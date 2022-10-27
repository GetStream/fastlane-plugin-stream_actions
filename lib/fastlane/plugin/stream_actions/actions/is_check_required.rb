module Fastlane
  module Actions
    class IsCheckRequiredAction < Action
      def self.run(params)
        return true unless params[:github_pr_num]

        UI.message("Checking if check is required for PR ##{params[:github_pr_num]}")

        changed_files = sh("gh pr view #{params[:github_pr_num]} --json files -q '.files[].path'").split("\n")

        return true if changed_files.size == 100 # TODO: https://github.com/cli/cli/issues/5368

        changed_files.select! do |path|
          params[:sources].any? { |required| path.start_with?(required) }
        end

        changed_files.size.positive?
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        'Analyzes the impact of changes on PR'
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :sources,
            description: 'Array of paths to scan',
            is_string: false,
            verify_block: proc do |source|
              UI.user_error!("Sources have to be specified") unless source
            end
          ),
          FastlaneCore::ConfigItem.new(
            env_name: 'GITHUB_PR_NUM',
            key: :github_pr_num,
            description: 'GitHub PR number'
          )
        ]
      end

      def self.supported?(_platform)
        true
      end
    end
  end
end
