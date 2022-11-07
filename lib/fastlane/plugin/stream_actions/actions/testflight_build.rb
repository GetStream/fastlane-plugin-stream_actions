module Fastlane
  module Actions
    class TestflightBuildAction < Action
      def self.run(params)
        build_number = other_action.latest_testflight_build_number(
          app_identifier: params[:app_identifier],
          api_key: params[:api_key]
        ) + 1
        other_action.increment_build_number(build_number: build_number.to_s)

        other_action.gym(
          project: params[:xcode_project],
          scheme: params[:app_target],
          configuration: 'Release',
          export_method: 'app-store',
          export_options: params[:testflight_export_options],
          clean: true,
          include_symbols: true,
          output_directory: params[:output_directory]
        )

        current_branch = ENV['BRANCH_NAME'] || other_action.git_branch
        external_groups = current_branch == 'main' ? ['Public Link'] : []
        other_action.pilot(
          api_key: params[:api_key],
          team_id: '118902954',
          app_identifier: params[:app_identifier],
          app_platform: 'ios',
          ipa: lane_context[SharedValues::IPA_OUTPUT_PATH],
          groups: external_groups,
          distribute_external: external_groups.any?,
          notify_external_testers: external_groups.any?,
          reject_build_waiting_for_review: true,
          changelog: testflight_instructions(params)
        )

        if params[:github_pr_num] && !params[:github_pr_num].strip.empty?
          message = "Build for regression testing №#{build_number} has been uploaded to TestFlight 🎁"
          sh("gh pr comment #{params[:github_pr_num]} -b '#{message}'")
        end
      end

      def self.testflight_instructions(params)
        version_number = other_action.get_version_number(target: params[:sdk_target])[/\d+\.\d+\.\d/]
        if ENV['GITHUB_EVENT_NAME'] == 'pull_request'
          sha = ENV['GITHUB_SHA'] ? ENV['GITHUB_SHA'][0..8] : sh('git rev-parse --short HEAD')
          "This is the build for Regression testing on release candidate v#{version_number} (sha: #{sha})."
        else
          "This is the official sample app built with iOS #{params[:sdk_target]} SDK v#{version_number}. It's designed " \
            'to highlight engaging features and new improvements to the SDK, but remember that this is just one ' \
            'possible implementation. You can start your own by borrowing and customizing the code from this ' \
            "sample, or build something completely different using Stream's components."
        end
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        'Builds a DemoApp and uploads it to TestFlight'
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :api_key,
            description: 'AppStore Connect API Key',
            is_string: false,
            verify_block: proc do |api_key|
              UI.user_error!('AppStore Connect API Key has to be specified') if api_key.nil? || api_key.empty?
            end
          ),
          FastlaneCore::ConfigItem.new(
            key: :xcode_project,
            description: 'Path to the Xcode project',
            verify_block: proc do |path|
              UI.user_error!('Path to the Xcode project has to be specified') if path.nil? || path.empty?
            end
          ),
          FastlaneCore::ConfigItem.new(
            key: :sdk_target,
            description: 'SDK target name',
            verify_block: proc do |target|
              UI.user_error!('SDK target name has to be specified') if target.nil? || target.empty?
            end
          ),
          FastlaneCore::ConfigItem.new(
            key: :app_target,
            description: 'DemoApp target name',
            verify_block: proc do |target|
              UI.user_error!('DemoApp target name has to be specified') if target.nil? || target.empty?
            end
          ),
          FastlaneCore::ConfigItem.new(
            key: :app_identifier,
            description: 'DemoApp bundle identifier',
            verify_block: proc do |id|
              UI.user_error!('DemoApp bundle identifier has to be specified') if id.nil? || id.empty?
            end
          ),
          FastlaneCore::ConfigItem.new(
            key: :testflight_export_options,
            description: 'We have to pass manually since `gym` detects profiles from `match` and that breaks it',
            default_value: './fastlane/testflight_export_options.plist'
          ),
          FastlaneCore::ConfigItem.new(
            key: :output_directory,
            description: 'Output directory for the build',
            default_value: 'archives'
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
