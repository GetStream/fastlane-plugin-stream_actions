module Fastlane
  module Actions
    class CoreVersionAction < Action
      def self.run(params)
        version = params[:version]
        return nil if version.nil? || version.to_s.strip.empty?

        m = version.to_s.match(/(\d+)\.(\d+)\.(\d+)/)
        UI.user_error!("Version must contain major.minor.patch (e.g. 1.2.3), got: #{version}") unless m

        "#{m[1]}.#{m[2]}.#{m[3]}"
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        'Returns major.minor.patch from a version string (e.g. 1.2.3-beta -> 1.2.3) for plist / CFBundleShortVersionString'
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :version,
            description: 'Version string to normalize; nil or empty returns nil',
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
