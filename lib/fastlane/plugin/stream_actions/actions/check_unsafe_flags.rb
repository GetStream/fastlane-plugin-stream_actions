module Fastlane
  module Actions
    class CheckUnsafeFlagsAction < Action
      def self.run(params)
        if File.read(params[:swift_package_path]).include?('unsafe')
          UI.user_error!('Package.swift contains unsafe flags.')
        end
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        'Checks if Package.swift contains unsafe flags'
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :swift_package_path,
            description: 'The path to your project Package.swift',
            is_string: true,
            default_value: './Package.swift',
            optional: false
          )
        ]
      end

      def self.is_supported?(platform)
        true
      end
    end
  end
end
