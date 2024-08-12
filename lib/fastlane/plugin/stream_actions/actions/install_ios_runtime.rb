module Fastlane
  module Actions
    class InstallIosRuntimeAction < Action
      def self.run(params)
        runtimes = `xcrun simctl runtime list -j`
        UI.message("👉 Runtime list:\n#{runtimes}")
        simulators = JSON.parse(runtimes).select do |_, sim|
          sim['platformIdentifier'].end_with?('iphonesimulator') && sim['version'] == params[:version] && sim['state'] == 'Ready'
        end

        if simulators.empty?
          Dir.chdir('..') do
            sh("echo 'iOS #{params[:version]} Simulator' | ipsw download xcode --sim") if Dir['*.dmg'].first.nil?
            sh("sh #{params[:custom_script]} #{Dir['*.dmg'].first}")
            UI.success("iOS #{params[:version]} Runtime successfuly installed")
          end
        else
          UI.important("iOS #{params[:version]} Runtime already exists")
        end
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        'Install iOS Runtime'
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :version,
            description: 'iOS Version'
          ),
          FastlaneCore::ConfigItem.new(
            key: :custom_script,
            description: 'Path to custom script to install the runtime'
          )
        ]
      end

      def self.is_supported?(platform)
        [:ios].include?(platform)
      end
    end
  end
end
