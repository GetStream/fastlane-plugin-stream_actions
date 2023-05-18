module Fastlane
  module Actions
    class PublishIosSdkReleaseAction < Action
      def self.run(params)
        ensure_everything_is_set_up(params)
        ensure_release_tag_is_new(params[:version])

        changes = other_action.read_changelog(
          version: params[:version],
          changelog_path: params[:changelog_path]
        )

        podspecs = []
        params[:sdk_names].each { |sdk| podspecs << "#{sdk}.podspec" }

        release_details = other_action.set_github_release(
          repository_name: params[:github_repo],
          api_token: params[:github_token],
          name: params[:version],
          tag_name: params[:version],
          description: changes,
          commitish: ENV['BRANCH_NAME'] || other_action.git_branch
        )

        podspecs.each { |podspec| other_action.pod_push_safely(podspec: podspec, sync: params[:pod_sync] & true) }

        UI.success("Github release v#{params[:version]} was created, please visit #{release_details['html_url']} to see it! 🚢")
      end

      def self.ensure_everything_is_set_up(params)
        other_action.ensure_git_branch(branch: 'main') if params[:check_branch]
        other_action.ensure_git_status_clean if params[:check_git_status]
      end

      def self.ensure_release_tag_is_new(version_number)
        if other_action.git_tag_exists(tag: version_number)
          UI.user_error!("Tag for version #{version_number} already exists!")
        else
          UI.success("Ignore the red warning above. Tag for version #{version_number} is alright!")
        end
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        'Publishes iOS SDKs to GitHub and CocoaPods'
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :version,
            description: 'Release version',
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :sdk_names,
            description: 'SDK names to release',
            is_string: false,
            verify_block: proc do |sdks|
              UI.user_error!("SDK names array has to be specified") unless sdks.kind_of?(Array) && sdks.size.positive?
            end
          ),
          FastlaneCore::ConfigItem.new(
            env_name: 'GITHUB_REPOSITORY',
            key: :github_repo,
            description: 'Github repository name'
          ),
          FastlaneCore::ConfigItem.new(
            env_name: 'GITHUB_TOKEN',
            key: :github_token,
            description: 'GITHUB_TOKEN environment variable'
          ),
          FastlaneCore::ConfigItem.new(
            key: :check_git_status,
            description: 'Ensure git status is clean',
            is_string: false,
            default_value: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :check_branch,
            description: 'Ensure git branch is main',
            is_string: false,
            default_value: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :pod_sync,
            description: 'If validation depends on other recently pushed pods, synchronize',
            is_string: false,
            default_value: false
          ),
          FastlaneCore::ConfigItem.new(
            key: :changelog_path,
            env_name: 'FL_CHANGELOG_PATH',
            description: 'The path to your project CHANGELOG.md',
            is_string: true,
            default_value: './CHANGELOG.md'
          )
        ]
      end

      def self.supported?(_platform)
        [:ios].include?(platform)
      end
    end
  end
end
