module Fastlane
  module Actions
    class SelectXcodeAction < Action
      def self.run(params)
        xcodes = sh('ls /Applications | grep Xcode')
        UI.user_error!("Xcode #{params[:version]} is not installed") unless xcodes.include?(params[:version])

        sh("sudo xcode-select -s /Applications/Xcode_#{params[:version]}.app")
        sh('xcodebuild -version')
        sh('xcrun simctl list runtimes | grep iOS')
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        'Select Xcode version'
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :version,
            env_name: 'GITHUB_REPOSITORY',
            description: 'Xcode version'
          )
        ]
      end

      def self.is_supported?(platform)
        [:ios].include?(platform)
      end
    end
  end
end
