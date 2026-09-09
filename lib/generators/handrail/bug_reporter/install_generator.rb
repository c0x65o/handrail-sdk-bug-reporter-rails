require "rails/generators"

module Handrail
  module BugReporter
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", File.dirname(__FILE__))
      namespace "handrail:bug_reporter:install"
      desc "Install server configuration; optionally mount the Handrail reporter engine."
      class_option :mount, :type => :boolean, :default => false,
        :desc => "Add an explicit, named local reporter engine mount"

      def create_initializer
        return unless behavior == :invoke
        path = "config/initializers/handrail_bug_reporter.rb"
        destination = File.join(destination_root, path)
        # Check before Thor's conflict handling: --force must never replace host
        # configuration. Also preserve symlinks, including dangling symlinks.
        if File.exist?(destination) || File.symlink?(destination)
          say_status :skip, "#{path} already exists; preserving it even with --force"
        else
          copy_file "initializer.rb.tt", path
        end
      end

      def mount_engine
        return unless behavior == :invoke && options[:mount]
        # Be conservative about customized/multiline mounts and routes loaded
        # through draw/require. Even a commented reference calls for host review.
        references = Dir[File.join(destination_root, "config/**/*.rb")].any? do |path|
          File.file?(path) && File.read(path) =~ /Handrail\s*::\s*BugReporter\s*::\s*Engine|handrail_bug_reporter_path|["':]handrail_bug_reporter["'\s,)]|\/api\/mobile-bug-reports/
        end
        if references
          say_status :skip, "Existing reporter route reference found; preserve and review its mount/path helper."
        else
          route 'mount Handrail::BugReporter::Engine => "/handrail/api/mobile-bug-reports", :as => "handrail_bug_reporter"'
        end
      end

      def installation_instructions
        say File.read(File.join(self.class.source_root, "instructions.txt")) if behavior == :invoke
      end
    end
  end
end
