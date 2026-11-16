require 'shellwords'

module Fastlane
  module Actions
    class CloneInternalMetricsAction < Action
      REPO = 'github.com/GetStream/stream-internal-metrics.git'.freeze

      def self.run(params)
        token = params[:github_token].to_s
        # Without a token, keep the SSH URL that local runs rely on.
        url = token.empty? ? "git@#{REPO.sub('/', ':')}" : "https://x-access-token:#{token}@#{REPO}"
        UI.message("Cloning #{REPO} into #{params[:path]}")
        # The URL can hold a token, so keep it out of the log and errors.
        sh(
          "git clone #{url.shellescape} #{params[:path].shellescape}",
          print_command: false,
          error_callback: ->(_) { UI.user_error!("Failed to clone #{REPO}") }
        )
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        'Clones GetStream/stream-internal-metrics, over HTTPS when a token is available'
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :path,
            description: 'Directory to clone into'
          ),
          FastlaneCore::ConfigItem.new(
            env_name: 'GITHUB_TOKEN',
            key: :github_token,
            description: 'Token with access to stream-internal-metrics. Without it, the SSH URL is used',
            sensitive: true,
            optional: true
          )
        ]
      end

      def self.is_supported?(platform)
        true
      end
    end
  end
end
