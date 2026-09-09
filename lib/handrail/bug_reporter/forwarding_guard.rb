require "json"
require "stringio"
require "uri"

module Handrail
  module BugReporter
    class ForwardingGuard
      MAX_BODY_BYTES = 28 * 1024 * 1024
      PAYLOAD_KEY = "handrail.bug_reporter.forwarded_payload".freeze
      RESOURCE_KEY = "handrail.bug_reporter.history_resource".freeze
      QUERY_KEY = "handrail.bug_reporter.history_query".freeze
      HISTORY_QUERY_KEYS = %w[limit cursor search status_group sort visibility].freeze

      def initialize(app)
        @app = app
      end

      def call(env)
        path = env["PATH_INFO"].to_s
        # The host router collapses repeated slashes before dispatching a mount.
        # Retain rejection of empty IDs such as /bugs//archive after that step.
        original_path = env["ORIGINAL_FULLPATH"].to_s.split("?", 2).first.to_s
        return reject(404, "bug_history_not_found") if original_path.include?("//")
        method = env["REQUEST_METHOD"]
        allowed = { "" => "POST", "/" => "POST", "/policy" => "GET",
          "/mine" => "GET", "/mine/archive-closed" => "POST" }[path]
        resource = nil
        subscription = false
        if path == "/mine" || path == "/mine/archive-closed"
          resource = [:history, path == "/mine" ? "" : "/archive-closed"]
        elsif (match = /\A\/bugs\/([^\/]+)(\/archive|\/subscription)?\z/.match(path))
          segment = encoded_bug_id(match[1])
          return reject(404, "bug_history_not_found") unless segment
          allowed = match[2] ? "PUT, DELETE" : "GET"
          subscription = match[2] == "/subscription"
          allowed = "POST" if subscription
          resource = [:bugs, "/" + segment + match[2].to_s]
        end
        return reject(404, "bug_reporter_route_not_found") unless allowed
        return reject(405, "method_not_allowed", "allow" => allowed) unless allowed.split(", ").include?(method)
        env[RESOURCE_KEY] = resource
        env[QUERY_KEY] = path == "/mine" ? history_query(env["QUERY_STRING"].to_s) : {}
        request = ActionDispatch::Request.new(env)
        origin = env["HTTP_ORIGIN"]
        if env["HTTP_SEC_FETCH_SITE"].to_s.downcase == "cross-site" ||
            (origin && origin != request.base_url)
          return reject(403, "bug_reporter_cross_site_denied")
        end
        if method == "POST" && (path.empty? || path == "/" || subscription)
          length = env["CONTENT_LENGTH"].to_s
          return reject(400, "invalid_report") unless length.empty? || length =~ /\A[0-9]+\z/
          return reject(413, "report_too_large") if length.to_i > MAX_BODY_BYTES
          return reject(415, "invalid_report") unless env["CONTENT_TYPE"].to_s.split(";", 2).first.to_s.strip.downcase == "application/json"
          # Never trust CONTENT_LENGTH, including zero or an absent length. Each
          # read is bounded; stop after the first byte beyond the limit.
          bytes = String.new.force_encoding(Encoding::BINARY)
          input = env["rack.input"]
          while input && (chunk = input.read([16_384, MAX_BODY_BYTES + 1 - bytes.bytesize].min)) && !chunk.empty?
            bytes << chunk
            return reject(413, "report_too_large") if bytes.bytesize > MAX_BODY_BYTES
          end
          bytes.force_encoding(Encoding::UTF_8)
          return reject(400, "invalid_report") unless bytes.valid_encoding?
          payload = JSON.parse(bytes)
          return reject(400, "invalid_report") unless payload.is_a?(Hash)
          env[PAYLOAD_KEY] = payload
          env["rack.input"] = StringIO.new(bytes)
          env["CONTENT_LENGTH"] = bytes.bytesize.to_s
        end
        # The wire object is deliberately separate from controller params. This
        # also avoids reparsing/logging report data and requires CSRF via header.
        env["action_dispatch.request.request_parameters"] = {}
        env["action_dispatch.request.query_parameters"] = {}
        status, headers, body = @app.call(env)
        headers.delete("Cache-Control")
        headers["cache-control"] = "private, no-store"
        [status, headers, body]
      rescue JSON::ParserError, EncodingError, EOFError, IOError
        reject(400, "invalid_report")
      rescue StandardError
        reject(500, "bug_reporter_request_failed")
      end

      private

      def encoded_bug_id(raw)
        return nil if raw =~ /%(?![0-9a-f]{2})/i
        # PATH_INFO is still escaped here. Do not decode Rails' route params a
        # second time, or let format parsing truncate IDs containing a dot.
        id = URI::DEFAULT_PARSER.unescape(raw).force_encoding(Encoding::UTF_8)
        return nil unless id.valid_encoding?
        id = id.gsub(/\A[[:space:]\ufeff]+|[[:space:]\ufeff]+\z/, "")
        return nil if id.empty? || id == "." || id == ".." || id =~ /[\/\\%?#\x00-\x1f\x7f]/
        URI.encode_www_form_component(id).gsub("+", "%20")
      end

      def history_query(raw)
        # Parse flat pairs so duplicate values match URLSearchParams.get (first
        # wins, even if empty), without Rack's nested parameter interpretation.
        seen = {}
        URI.decode_www_form(raw).each_with_object({}) do |(key, value), result|
          next unless HISTORY_QUERY_KEYS.include?(key) && !seen[key]
          seen[key] = true
          result[key] = value unless value.empty?
        end
      end

      def reject(status, code, headers = {})
        [status, { "content-type" => "application/json", "cache-control" => "private, no-store" }.merge(headers),
          [JSON.generate("error" => code)]]
      end
    end
  end
end
