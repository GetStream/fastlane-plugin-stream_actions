module Fastlane
  module Actions
    class ReleaseIosSdkAction < Action
      def self.run(params)
        ensure_everything_is_set_up(params)

        version_number = ''
        params[:sdk_names].each do |target|
          version_number = other_action.increment_version_number_in_plist(
            target: target,
            version_number: params[:version],
            bump_type: params[:bump_type]
          )
        end

        ensure_release_tag_is_new(version_number)

        changes = other_action.read_changelog(version: version_number, changelog_path: params[:changelog_path])

        podspecs = []
        params[:sdk_names].each { |sdk| podspecs << "#{sdk}.podspec" }

        podspecs.each do |podspec|
          UI.user_error!("Podspec #{podspec} does not exist!") unless File.exist?(podspec)
          other_action.pod_lib_lint(podspec: podspec, allow_warnings: true) unless params[:skip_pod_list]
          other_action.version_bump_podspec(path: podspec, version_number: version_number)
        end

        commit_changes(version_number)

        release_details = other_action.set_github_release(
          repository_name: params[:github_repo],
          api_token: params[:github_token],
          name: version_number,
          tag_name: version_number,
          description: changes,
          commitish: ENV['BRANCH_NAME'] || other_action.git_branch
        )

        podspecs.each { |podspec| other_action.pod_push_safely(podspec: podspec, sync: params[:pod_sync] & true) }

        UI.success("Github release v#{version_number} was created, please visit #{release_details['html_url']} to see it! 🚢")
      end

      def self.ensure_everything_is_set_up(params)
        other_action.ensure_git_branch(branch: 'main') if params[:check_release_branch]
        other_action.ensure_git_status_clean if params[:check_git_status]

        if params[:version].nil? && !["patch", "minor", "major"].include?(params[:bump_type])
          UI.user_error!("Please use type parameter with one of the options: type:patch, type:minor, type:major")
        end
      end

      def self.ensure_release_tag_is_new(version_number)
        if other_action.git_tag_exists(tag: version_number)
          UI.user_error!("Tag for version #{version_number} already exists!")
        else
          UI.success("Ignore the red warning above. Tag for version #{version_number} is alright!")
        end
      end

      def self.commit_changes(version_number)
        sh("git add -A")
        UI.user_error!("Not committing changes") unless other_action.prompt(text: "Will commit changes. All looking good?", boolean: true)

        sh("git commit -m 'Bump #{version_number}'")
        UI.user_error!("Not pushing changes") unless other_action.prompt(text: "Will push changes. All looking good?", boolean: true)

        other_action.push_to_git_remote(tags: true)
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        'Releases iOS SDKs to GitHub and CocoaPods'
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :version,
            description: 'Release version (not required if release type is set)',
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :bump_type,
            description: 'Release type (not required if release version is set)',
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
            key: :check_release_branch,
            description: 'Ensure git branch is main',
            is_string: false,
            default_value: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :skip_pod_list,
            description: 'Skip pod lib lint action',
            is_string: false,
            default_value: false
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
