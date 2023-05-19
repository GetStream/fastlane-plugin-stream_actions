module Fastlane
  module Actions
    class ReleaseIosSdkAction < Action
      def self.run(params)
        podspecs = []
        params[:sdk_names].each { |sdk| podspecs << "#{sdk}.podspec" }

        if params[:update_version_numbers]
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

          changes = other_action.touch_changelog(
            release_version: version_number,
            github_repo: params[:github_repo],
            changelog_path: params[:changelog_path]
          )

          podspecs.each do |podspec|
            UI.user_error!("Podspec #{podspec} does not exist!") unless File.exist?(podspec)
            other_action.version_bump_podspec(path: podspec, version_number: version_number)
          end

          sh("git checkout -b release/#{version_number}") if params[:create_pull_request]

          commit_changes(version_number)
        end

        if params[:create_pull_request]
          create_pull_request(
            api_token: params[:github_token],
            repo: params[:github_repo],
            title: "#{version_number} Release",
            head: "release/#{version_number}",
            base: 'main',
            body: changes.to_s
          )
          UI.success("Successfully started release #{version_number}! 🚢")
        elsif params[:publish_release]
          version_number ||= params[:version]

          ensure_everything_is_set_up(params)
          ensure_release_tag_is_new(version_number)

          changes ||= other_action.read_changelog(
            version: version_number,
            changelog_path: params[:changelog_path]
          )

          release_details = other_action.set_github_release(
            repository_name: params[:github_repo],
            api_token: params[:github_token],
            name: version_number,
            tag_name: version_number,
            description: changes,
            commitish: ENV['BRANCH_NAME'] || other_action.git_branch
          )

          podspecs.each { |podspec| other_action.pod_push_safely(podspec: podspec) }

          UI.success("Github release v#{version_number} was created, please visit #{release_details['html_url']} to see it! 🚢")
        end
      end

      def self.ensure_everything_is_set_up(params)
        other_action.ensure_git_branch(branch: 'main') if params[:publish_release]
        other_action.ensure_git_status_clean

        UI.user_error!('Please set GITHUB_TOKEN environment value.') if params[:github_token].nil?

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

        other_action.push_to_git_remote(tags: false)
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        'Releases iOS SDKs'
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
            key: :changelog_path,
            env_name: 'FL_CHANGELOG_PATH',
            description: 'The path to your project CHANGELOG.md',
            is_string: true,
            default_value: './CHANGELOG.md'
          ),
          FastlaneCore::ConfigItem.new(
            key: :create_pull_request,
            description: 'Create pull request from release branch to main',
            is_string: false,
            default_value: false
          ),
          FastlaneCore::ConfigItem.new(
            key: :update_version_numbers,
            description: 'Update release version numbers in podspecs and plist files',
            is_string: false,
            default_value: false
          ),
          FastlaneCore::ConfigItem.new(
            key: :publish_release,
            description: 'Publish release to GitHub and CocoaPods',
            is_string: false,
            default_value: false
          )
        ]
      end

      def self.supported?(_platform)
        [:ios].include?(platform)
      end
    end
  end
end
