module Fastlane
  module Actions
    class UpdateTestplanAction < Action
      def self.run(params)
        data_hash = JSON.parse(File.read(params[:path]))

        # Create the `environmentVariableEntries` array if it doesn't exist
        data_hash['defaultOptions']['environmentVariableEntries'] ||= []

        data_hash['defaultOptions']['environmentVariableEntries'] << params[:env_vars]
        File.write(params[:path], JSON.pretty_generate(data_hash))

        UI.success("✅ `#{params[:env_vars]}` ENV variables have been added to #{params[:path]}")
        UI.message("👀 #{params[:path]} ENV variables:\n#{data_hash['defaultOptions']['environmentVariableEntries']}")
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        'Adds environment variables to a test plan'
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :path,
            description: 'The test plan file path',
            verify_block: proc do |path|
              UI.user_error!("Cannot find the testplan file '#{path}'") unless File.exist?(path)
            end
          ),
          FastlaneCore::ConfigItem.new(
            key: :env_vars,
            description: 'The environment variables to add to test plan',
            is_string: false,
            verify_block: proc do |array|
              UI.user_error!("The environment variables array should not be empty") if array.empty?
            end
          )
        ]
      end

      def self.supported?(_platform)
        [:ios].include?(platform)
      end
    end
  end
end
