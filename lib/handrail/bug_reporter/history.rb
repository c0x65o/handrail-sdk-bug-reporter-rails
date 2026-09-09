require "handrail/bug_reporter/transport"
require "handrail/bug_reporter/payload"

module Handrail
  module BugReporter
    # JS v0.4.49 history projections, exposed as deeply frozen symbol-keyed
    # hashes (including query[:status_group]). Ownership stays on the server.
    module History
      STAGES = %w[submitted verifying verified fixing fixed deployed closed not_reproduced wont_fix needs_attention].map(&:freeze).freeze
      STATUS_GROUPS = %w[needs_attention in_progress closed not_reproduced].map(&:freeze).freeze
      SORTS = %w[newest oldest].map(&:freeze).freeze
      VISIBILITIES = %w[active archived all].map(&:freeze).freeze
      MILESTONE_KEYS = %w[reported confirmed corrected checked released confirmed_resolved].map(&:freeze).freeze
      MILESTONE_STATES = %w[complete current upcoming stopped].map(&:freeze).freeze
      MISSING = Object.new.freeze
      TRIM = /\A[\u0009-\u000d\u0020\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]+|[\u0009-\u000d\u0020\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]+\z/.freeze

      class << self
        def list(client, options = {})
          ready!(client)
          reject! unless options.is_a?(Hash)
          # Never forward arbitrary caller keys, especially project/environment.
          query = {}
          %w[limit cursor search status_group sort visibility].each do |key|
            value = options.key?(key.to_sym) ? options[key.to_sym] : options[key]
            query[key] = value unless value.nil? || value == ""
          end
          if query.key?("search")
            reject! unless query["search"].is_a?(String) && query["search"].valid_encoding?
            query["search"] = clean(query["search"])
            reject! if query["search"] && search_length(query["search"]) > 200
          end
          { "status_group" => STATUS_GROUPS, "sort" => SORTS, "visibility" => VISIBILITIES }.each do |key, allowed|
            reject! if query.key?(key) && !allowed.include?(query[key])
          end
          if query.key?("limit")
            limit = query["limit"]
            # Like JS, let the server default/cap requested limits. Returned
            # page limits are always validated as integers in 1..50 below.
            reject! unless limit.is_a?(Integer) || (limit.is_a?(Float) && limit.finite?)
          end
          if query.key?("cursor")
            reject! unless query["cursor"].is_a?(String) && query["cursor"].valid_encoding?
          end
          url = query_url(client, client.configuration.endpoints[:history], query)
          request(client, url) { |body| page(body) }
        rescue EncodingError, ArgumentError
          reject!
        end

        def get(client, bug_id)
          ready!(client)
          id = normalized_id(bug_id)
          segment = URI.encode_www_form_component(id).gsub("+", "%20")
          url = query_url(client, client.configuration.endpoints[:bugs] + "/" + segment)
          request(client, url) do |body|
            record(body["bug"]) if body.is_a?(Hash) && body["contract_version"] == "v1"
          end
        rescue EncodingError, ArgumentError
          reject!
        end

        def change_archive_state(client, bug_id, archived)
          ready!(client)
          id = normalized_id(bug_id)
          segment = URI.encode_www_form_component(id).gsub("+", "%20")
          url = query_url(client, client.configuration.endpoints[:bugs] + "/" + segment + "/archive")
          request(client, url, archived ? "PUT" : "DELETE") do |body|
            result = archive_result(body)
            result if result && result[:bug_id] == id && result[:archived] == archived
          end
        rescue EncodingError, ArgumentError
          reject!
        end

        def archive_closed(client)
          ready!(client)
          url = query_url(client, client.configuration.endpoints[:history] + "/archive-closed")
          request(client, url, "POST") { |body| archive_closed_result(body) }
        end

        private

        def normalized_id(bug_id)
          reject! if bug_id.is_a?(String) && bug_id.valid_encoding? &&
            bug_id.encode(Encoding::UTF_8) =~ /[\x00-\x1f\x7f]/
          id = clean(bug_id)
          # Reject separators, escapes (including nested escapes), dot segments,
          # and controls before encoding. Keep Transport's containment checks.
          reject! unless id && id != "." && id != ".." &&
            !(id =~ /[\/\\%\x00-\x1f\x7f]/)
          id
        end

        def ready!(client)
          raise Error.new(:invalid_configuration), :cause => nil unless client.configuration.status == :ready
        end

        def reject!(response = nil)
          raise Error.new(:tracking_rejected, response && response.status_code,
            :request_id => response && response.request_id), :cause => nil
        end

        def query_url(client, endpoint, options = {})
          values = { :project_id => client.configuration.project_id,
            :environment => client.configuration.environment }.merge(options)
          endpoint + "?" + URI.encode_www_form(values.reject { |_, value| value.nil? || value == "" })
        end

        def request(client, url, method = "GET")
          response = client.request(:method => method, :url => url)
          begin
            bytes = response.body
            bytes = bytes.dup.force_encoding(Encoding::UTF_8) if bytes.is_a?(String)
            reject!(response) unless bytes.is_a?(String) && bytes.valid_encoding?
            result = yield JSON.parse(bytes)
            reject!(response) unless result
            deep_freeze(result)
          rescue JSON::ParserError, EncodingError, ArgumentError
            reject!(response)
          end
        rescue Error => error
          if error.code == :request_failed
            code = error.status_code ? :tracking_rejected : :tracking_unavailable
            raise Error.new(code, error.status_code, :code => error.upstream_code,
              :message => error.upstream_message, :request_id => error.request_id), :cause => nil
          end
          raise error, :cause => nil
        end

        def clean(value)
          return nil unless value.is_a?(String) && value.valid_encoding?
          value = value.encode(Encoding::UTF_8).gsub(TRIM, "")
          value.empty? ? nil : value
        end

        def search_length(value)
          # JS bounds UTF-16 code units, not Ruby codepoints or UTF-8 bytes.
          value.encode(Encoding::UTF_16LE).bytesize / 2
        end

        def boolean?(value)
          value == true || value == false
        end

        def strings(source, keys)
          keys.each_with_object({}) { |key, result| result[key.to_sym] = clean(source[key]) }
        end

        # Match JS Number() for JSON values. Missing and null differ: optional
        # occurrence counts default to 1 when absent, while explicit null is 0.
        def number(value)
          case value
          when nil, false then 0.0
          when true then 1.0
          when Integer, Float then value.to_f
          when Array then number(array_string(value))
          when String
            text = clean(value)
            return 0.0 unless text
            if text =~ /\A(?:0[xX][0-9a-fA-F]+|0[bB][01]+|0[oO][0-7]+)\z/
              Integer(text).to_f
            elsif text =~ /\A[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?\z/
              text.to_f
            end
          end
        end

        def array_string(values)
          values.map do |value|
            value.is_a?(Array) ? array_string(value) : (value.is_a?(Hash) ? "[object Object]" : value.to_s)
          end.join(",")
        end

        def non_negative(value, fallback = nil)
          numeric = number(value)
          numeric && numeric.finite? && numeric >= 0 ? numeric : fallback
        end

        def integer(value)
          numeric = non_negative(value)
          numeric && numeric == numeric.to_i ? numeric.to_i : nil
        end

        def archive_result(input)
          return nil unless input.is_a?(Hash) && input["contract_version"] == "v1" &&
            boolean?(input["archived"])
          id = clean(input["bug_id"])
          archived_at = clean(input["archived_at"])
          return nil unless id
          return nil if (input["archived"] && !archived_at) || (!input["archived"] && archived_at)
          { :contract_version => "v1", :bug_id => id,
            :archived => input["archived"], :archived_at => archived_at }
        end

        def archive_closed_result(input)
          return nil unless input.is_a?(Hash) && input["contract_version"] == "v1"
          count = integer(input.fetch("archived_count", MISSING))
          return nil unless count
          { :contract_version => "v1", :archived_count => count }
        end

        def record(input)
          return nil unless input.is_a?(Hash) && input["status_rollup"].is_a?(Hash)
          rollup = input["status_rollup"]
          result = strings(input, %w[id title severity environment status])
          status = strings(rollup, %w[stage label raw_status])
          return nil if result.values.any?(&:nil?) || status.values.any?(&:nil?) ||
            !STAGES.include?(status[:stage]) || !boolean?(rollup["terminal"])
          impact = clean(input["canonical_impact"].nil? ? result[:severity] : input["canonical_impact"])
          impact = impact && Payload::IMPACTS[impact.downcase]
          return nil unless impact
          group = if %w[needs_attention not_reproduced].include?(status[:stage])
            status[:stage]
          else
            rollup["terminal"] ? "closed" : "in_progress"
          end
          provided_group = clean(input["status_group"])
          return nil if provided_group && provided_group != group
          return nil if input.key?("archived") && !boolean?(input["archived"])
          archived = input["archived"] == true
          archived_at = clean(input["archived_at"])
          return nil if (archived && !archived_at) || (!archived && archived_at)
          status.merge!(strings(rollup, %w[workflow_state environment fixed_version version updated_at]))
          reverification = clean(rollup["reverification_status"])
          status[:reverification_status] = %w[in_progress passed failed].include?(reverification) ? reverification : nil
          status[:terminal] = rollup["terminal"]
          result.merge!(strings(input, %w[reported_app_version reported_route reported_app_flavor first_reported_at last_reported_at created_at updated_at fixed_at closed_at]))
          result.merge(:impact => impact, :status_group => group, :status_rollup => status,
            :resolution_journey => journey(input["resolution_journey"]),
            :archived => archived, :archived_at => archived_at,
            :occurrence_count => non_negative(input.fetch("occurrence_count", MISSING), 1),
            :reporter_occurrence_count => non_negative(input.fetch("reporter_occurrence_count", MISSING), 1))
        end

        def summary(input)
          return nil unless input.is_a?(Hash)
          result = (["total"] + STATUS_GROUPS).each_with_object({}) do |key, output|
            output[key.to_sym] = integer(input.fetch(key, MISSING))
          end
          return nil if result.values.any?(&:nil?) || result[:total] !=
            STATUS_GROUPS.inject(0) { |sum, key| sum + result[key.to_sym] }
          result
        end

        def query(input)
          return nil unless input.is_a?(Hash)
          result = strings(input, %w[search status_group sort visibility])
          return nil unless input.key?("search") && input.key?("status_group")
          return nil if !input["search"].nil? && (!result[:search] || search_length(result[:search]) > 200)
          return nil if !input["status_group"].nil? && !STATUS_GROUPS.include?(result[:status_group])
          result[:visibility] = "active" unless input.key?("visibility")
          return nil unless SORTS.include?(result[:sort]) && VISIBILITIES.include?(result[:visibility])
          result
        end

        def page(input)
          return nil unless input.is_a?(Hash) && input["contract_version"] == "v1" &&
            input["bugs"].is_a?(Array) && input["pagination"].is_a?(Hash)
          pagination = input["pagination"]
          return nil unless boolean?(pagination["has_more"])
          bugs = input["bugs"].map { |bug| record(bug) }
          return nil if bugs.any?(&:nil?)
          limit = integer(pagination.fetch("limit", MISSING))
          return nil unless limit && limit.between?(1, 50)
          cursor = clean(pagination["next_cursor"])
          return nil if pagination["has_more"] && !cursor
          discovery = input.key?("summary") || input.key?("query")
          counts = discovery ? summary(input["summary"]) : nil
          filters = discovery ? query(input["query"]) : nil
          filtered_count = integer(pagination.fetch("filtered_count", MISSING))
          if discovery
            return nil unless counts && filters && filtered_count &&
              filtered_count == counts[(filters[:status_group] || "total").to_sym]
          end
          { :contract_version => "v1", :bugs => bugs, :summary => counts, :query => filters,
            :pagination => { :limit => limit, :filtered_count => filtered_count,
              :has_more => pagination["has_more"], :next_cursor => cursor } }
        end

        def journey(input)
          return nil unless input.is_a?(Hash) && input["schema_version"] == 1
          result = strings(input, %w[headline outcome handling])
          return nil unless result[:headline] &&
            %w[in_progress resolved needs_attention not_reproduced closed].include?(result[:outcome]) &&
            %w[automatic team_review unknown].include?(result[:handling]) && input["milestones"].is_a?(Array)
          %w[automatic_fix_authorized automatic_delivery_authorized approval_required].each do |key|
            return nil unless boolean?(input[key])
            result[key.to_sym] = input[key]
          end
          seen = []
          milestones = input["milestones"].map do |item|
            return nil unless item.is_a?(Hash)
            milestone = strings(item, %w[key label state started_at completed_at])
            key = milestone[:key]
            return nil unless MILESTONE_KEYS.include?(key) && !seen.include?(key) &&
              milestone[:label] && MILESTONE_STATES.include?(milestone[:state])
            seen << key
            duration = non_negative(item.fetch("duration_ms", MISSING))
            return nil if !item.key?("duration_ms") || (!item["duration_ms"].nil? && duration.nil?)
            milestone[:duration_ms] = item["duration_ms"].nil? ? nil : duration
            milestone
          end
          return nil unless seen.length == MILESTONE_KEYS.length
          duration = non_negative(input.fetch("total_duration_ms", MISSING))
          return nil if !input.key?("total_duration_ms") || (!input["total_duration_ms"].nil? && duration.nil?)
          next_step = input["next_step"]
          next_step = next_step.is_a?(Hash) ? strings(next_step, %w[kind label summary]) : nil
          unless next_step && next_step[:label] && next_step[:summary] &&
            %w[read_only_runtime_diagnosis scoped_diagnosis owner_decision].include?(next_step[:kind])
            next_step = nil
          end
          result.merge!(strings(input, %w[started_at completed_at verification_method verification_label release_environment fixed_version released_version]))
          result.merge(:schema_version => 1, :next_step => next_step,
            :total_duration_ms => input["total_duration_ms"].nil? ? nil : duration, :milestones => milestones)
        end

        def deep_freeze(value)
          case value
          when Hash then value.each { |key, child| key.freeze; deep_freeze(child) }
          when Array then value.each { |child| deep_freeze(child) }
          end
          value.freeze
        end
      end
    end
  end
end
