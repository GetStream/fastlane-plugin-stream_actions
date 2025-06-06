module Fastlane
  module Actions
    class UpdateReleaseVersionToSnapshotAction < Action
      def self.run(params)
        content = File.read(params[:file_path])
        current_version = content.match(/String\s+=\s+"([\d.]+).*"/)[1]
        major, minor, _patch = current_version.split('.').map(&:to_i)
        minor += 1
        updated_version = "#{major}.#{minor}.0-SNAPSHOT"
        new_content = content.sub!(/"[^"]+"/, "\"#{updated_version}\"")
        File.open(params[:file_path], 'w') { |f| f.puts(new_content) }
        UI.important("Replaced #{current_version} with #{updated_version} 📝")
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        'Bump a release version and add a snapshot postfix'
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :file_path,
            description: 'File with a version that needs to be a snapshot'
          )
        ]
      end

      def self.is_supported?(platform)
        true
      end
    end
  end
end
