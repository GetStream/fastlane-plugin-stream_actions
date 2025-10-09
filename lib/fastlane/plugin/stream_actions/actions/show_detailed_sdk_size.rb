module Fastlane
  module Actions
    class ShowDetailedSdkSizeAction < Action
      def self.run(params)
        metrics_dir = 'metrics'
        FileUtils.remove_dir(metrics_dir, force: true)
        sh("git clone git@github.com:GetStream/stream-internal-metrics.git #{metrics_dir}")

        params[:sdk_names].each do |sdk|
          old_linkmap = "metrics/linkmaps/#{sdk}-LinkMap.txt"
          new_linkmap = "linkmaps/#{sdk}-LinkMap.txt"
          details = other_action.xcsize_diff(
            old_linkmap: old_linkmap,
            new_linkmap: new_linkmap,
            threshold: 1
          )[:details]

          header = "## #{sdk} XCSize"
          content = "#{header}\nNo changes in SDK size."
          unless details.empty?
            table = "| `Object` | `Diff (bytes)` |\n| - | - |\n"
            details.each { |object, diff| table << "| #{object} | #{diff} |\n" }
            content = "#{header}\n#{table}"
          end

          if ENV['GITHUB_EVENT_NAME'].to_s == 'push' && other_action.current_branch == 'develop'
            File.write(old_linkmap, File.read(new_linkmap))
            Dir.chdir(metrics_dir) do
              if sh('git status -s').to_s.empty?
                UI.important('No changes in linkmap.')
              else
                sh('git add -A')
                sh("git commit -m 'Update #{sdk_size_path}'")
                sh('git push')
              end
            end
          end

          other_action.pr_comment(text: content, edit_last_comment_with_text: header) if other_action.is_ci
        end
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        'Show SDKs objects size'
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :sdk_names,
            description: 'SDK names to analyze',
            is_string: false,
            verify_block: proc do |sdks|
              UI.user_error!("SDK names array has to be specified") unless sdks.kind_of?(Array) && sdks.size.positive?
            end
          )
        ]
      end

      def self.is_supported?(platform)
        [:ios, :mac].include?(platform)
      end
    end
  end
end
