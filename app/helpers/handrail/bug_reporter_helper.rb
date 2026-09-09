require "json"

module Handrail
  module BugReporterHelper
    # Public, data-only API. Never turn a Factory/Configuration into JSON or
    # construct a request client here: credential resolution belongs to forwarding.
    OPTIONS = [:endpoint, :enabled, :mode, :launcher_id, :context, :show_history,
      :appearance, :label, :heading, :allow_screenshots, :load_policy_on_mount,
      :history_page_size].freeze
    CONTEXT = { :route => "route", :app_version => "appVersion",
      :build_number => "buildNumber", :commit_sha => "commitSha",
      :app_flavor => "appFlavor", :title => "title", :description => "description",
      :reproducer => "reproducer", :profile_key => "profileKey" }.freeze
    TOKENS = %w[accent accentText surface surfaceMuted text mutedText border overlay
      dangerSurface dangerText successSurface successText warningSurface warningText
      infoSurface infoText radius fontFamily].freeze
    STYLE_KEYS = TOKENS.map { |key| "--handrail-bug-" + key.gsub(/[A-Z]/) { |c| "-" + c.downcase } }.freeze
    JSON_ESCAPES = { "<" => '\u003c', ">" => '\u003e', "&" => '\u0026',
      "\u2028" => '\u2028', "\u2029" => '\u2029' }.freeze

    def handrail_bug_reporter(options = {})
      handrail_reporter_keys!(options, OPTIONS)
      handrail_reporter_boolean!(options[:enabled]) if options.key?(:enabled)
      return "".html_safe if options[:enabled] == false
      factory = Rails.application.config.handrail_bug_reporter_factory
      return "".html_safe unless factory && factory.configuration.enabled
      configuration = factory.configuration

      mode = options.fetch(:mode, "launcher").to_s
      raise ArgumentError, "Invalid reporter mode" unless ["launcher", "custom-launcher"].include?(mode)
      launcher_id = options[:launcher_id]
      if mode == "custom-launcher"
        unless launcher_id.is_a?(String) && launcher_id =~ /\A[A-Za-z][A-Za-z0-9_-]*\z/
          raise ArgumentError, "custom-launcher requires a launcher_id"
        end
      elsif launcher_id
        raise ArgumentError, "launcher_id requires custom-launcher mode"
      end

      config = { "transport" => "same-origin", "enabled" => true,
        "apiBaseUrl" => handrail_reporter_endpoint!(options[:endpoint]),
        "projectId" => handrail_reporter_string!(configuration.project_id),
        "environment" => handrail_reporter_string!(configuration.environment),
        "allowScreenshots" => handrail_reporter_boolean!(options.fetch(:allow_screenshots, false)) }
      context = options.fetch(:context, {})
      handrail_reporter_keys!(context, CONTEXT.keys)
      initial_form = context.each_with_object({}) do |(key, value), result|
        result[CONTEXT.fetch(key)] = handrail_reporter_string!(value)
      end
      payload = { "config" => config, "initialForm" => initial_form,
        "showHistory" => handrail_reporter_boolean!(options.fetch(:show_history, true)),
        "loadPolicyOnMount" => handrail_reporter_boolean!(options.fetch(:load_policy_on_mount, true)),
        "appearance" => handrail_reporter_appearance!(options.fetch(:appearance, {})) }
      [:label, :heading].each do |key|
        payload[key.to_s] = handrail_reporter_string!(options[key]) if options.key?(key)
      end
      if options.key?(:history_page_size)
        size = options[:history_page_size]
        raise ArgumentError, "history_page_size must be between 1 and 50" unless size.is_a?(Integer) && size.between?(1, 50)
        payload["historyPageSize"] = size
      end

      # JSON stays nonexecuting even if copied into a JSON script by a future
      # adapter. content_tag also escapes the surrounding HTML attribute context.
      json = JSON.generate(payload).gsub(/[<>&\u2028\u2029]/) { |character| JSON_ESCAPES.fetch(character) }
      data = { :handrail_bug_reporter => "1", :handrail_bug_reporter_mode => mode,
        :handrail_bug_reporter_options => json }
      data[:handrail_bug_reporter_launcher_id] = launcher_id if launcher_id
      safe_join([content_tag(:div, "", :data => data),
        javascript_include_tag("handrail_bug_reporter", :defer => true)])
    end

    private

    def handrail_reporter_keys!(value, allowed)
      unless value.is_a?(Hash) && (value.keys - allowed).empty?
        raise ArgumentError, "Unsupported reporter options"
      end
    end

    def handrail_reporter_string!(value)
      unless value.is_a?(String) && value.valid_encoding?
        raise ArgumentError, "Reporter values must be strings"
      end
      value
    end

    def handrail_reporter_boolean!(value)
      raise ArgumentError, "Reporter flag must be true or false" unless value == true || value == false
      value
    end

    def handrail_reporter_endpoint!(endpoint)
      # The upstream normalizer appends this suffix to other paths. Require the
      # complete intake path so the emitted URL is exactly the mounted endpoint.
      unless endpoint.is_a?(String) && endpoint.valid_encoding? &&
          endpoint =~ /\A\/(?:[A-Za-z0-9_~.-]+\/)*api\/mobile-bug-reports\z/ &&
          !(endpoint =~ /(?:\A|\/)\.{1,2}(?:\/|\z)/)
        raise ArgumentError, "Reporter endpoint must be a local complete intake path"
      end
      script_name = request.script_name.to_s
      local_path = endpoint
      unless script_name.empty?
        unless endpoint.start_with?(script_name + "/")
          raise ArgumentError, "Reporter endpoint must include the host script name"
        end
        local_path = endpoint[script_name.length..-1]
      end
      route = Rails.application.routes.recognize_path(local_path, :method => :post)
      unless route[:controller] == "handrail/bug_reporter/reports" && route[:action] == "create"
        raise ArgumentError, "Reporter endpoint must resolve to the mounted intake"
      end
      endpoint
    rescue ActionController::RoutingError
      raise ArgumentError, "Reporter endpoint must resolve to the mounted intake"
    end

    def handrail_reporter_appearance!(appearance)
      handrail_reporter_keys!(appearance, [:theme_mode, :tokens, :class_name, :style])
      result = {}
      if appearance.key?(:theme_mode)
        mode = appearance[:theme_mode].to_s
        raise ArgumentError, "Invalid reporter theme" unless %w[auto light dark].include?(mode)
        result["themeMode"] = mode
      end
      result["className"] = handrail_reporter_string!(appearance[:class_name]) if appearance.key?(:class_name)
      { :tokens => TOKENS, :style => STYLE_KEYS }.each do |key, allowed|
        next unless appearance.key?(key)
        values = appearance[key]
        unless values.is_a?(Hash) && values.keys.all? { |name| (name.is_a?(String) || name.is_a?(Symbol)) && allowed.include?(name.to_s) }
          raise ArgumentError, "Unsupported reporter appearance values"
        end
        result[key.to_s] = values.each_with_object({}) do |(name, value), output|
          numeric_style = key == :style && (value.is_a?(Integer) || (value.is_a?(Float) && value.finite?))
          output[name.to_s] = numeric_style ? value : handrail_reporter_string!(value)
        end
      end
      result
    end
  end
end
