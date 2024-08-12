module Fastlane
  module Actions
    class UpdateSdkSizeInReadmeAction < Action
      def self.run(params)
        readme_content = File.read(params[:readme_path])

        params[:sizes].each do |key, value|
          framework_size_kb = value
          framework_size_mb = (framework_size_kb / 1024).round(2)
          readme_content.gsub!(%r{(https://img.shields.io/badge/#{key}-)(.*?)(-blue)}, "\\1#{framework_size_mb}\\3")
        end

        File.write(params[:readme_path], readme_content)
        UI.success('Successfully updated the SDK size labels in README.md!')

        other_action.pr_create(title: '[CI] Update SDK Size', head_branch: "ci/sdk-size-update-#{Time.now.to_i}") if params[:open_pr]
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        'Update SDKs size in README.md'
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :readme_path,
            description: 'Path to README.md',
            verify_block: proc do |name|
              UI.user_error!("Path to README.md should not be empty") if name.to_s.empty?
            end
          ),
          FastlaneCore::ConfigItem.new(
            key: :sizes,
            description: 'SDK sizes',
            is_string: false
          ),
          FastlaneCore::ConfigItem.new(
            key: :open_pr,
            description: 'Should a PR be opened',
            is_string: false
          )
        ]
      end

      def self.is_supported?(platform)
        true
      end
    end
  end
end
