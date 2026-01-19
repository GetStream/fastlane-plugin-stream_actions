module Fastlane
  module Actions
    class ShowDetailedSdkSizeAction < Action
      def self.run(params)
        chat_v5_branch = 'v5'
        is_chat_repo = params[:github_repo].include?('stream-chat-swift')
        is_pr_to_chat_v5 = is_chat_repo && ENV.fetch('GITHUB_BASE_REF', nil).to_s.include?(chat_v5_branch)
        is_push_to_chat_v5 = is_chat_repo && ENV['GITHUB_EVENT_NAME'].to_s == 'push' && other_action.current_branch == chat_v5_branch
        UI.important("TODO: Base branch workaround for StreamChat v5 on iOS. It should be removed when v5 is released.") if is_pr_to_chat_v5 || is_push_to_chat_v5

        is_release = other_action.current_branch.include?('release/')
        is_push_to_develop = ENV['GITHUB_EVENT_NAME'].to_s == 'push' && other_action.current_branch == 'develop'
        metrics_dir = 'metrics'
        FileUtils.remove_dir(metrics_dir, force: true)
        sh("git clone git@github.com:GetStream/stream-internal-metrics.git #{metrics_dir}")

        params[:sdk_names].each do |sdk|
          metrics_path = "metrics/linkmaps/#{sdk}.json"
          metrics_branch = is_release ? 'release' : is_pr_to_chat_v5 ? chat_v5_branch : 'develop'
          metrics = JSON.parse(File.read(metrics_path))
          old_details = metrics[metrics_branch] || {}
          new_details = other_action.xcsize(
            linkmap: "linkmaps/#{sdk}-arm64-LinkMap.txt",
            threshold: 0 # Threshold is set to 0 to show all objects
          )[:details]

          # Compare old linkmap and new linkmap objects sizes
          differences = {}

          # Handle old linkmap objects
          old_details.each do |object, value|
            new_value = new_details[object] || 0
            diff = new_value - value
            if diff.abs >= params[:threshold]
              differences[object] = diff > 0 ? "+#{diff}" : diff.to_s
            end
          end

          # Handle objects that are present only in new linkmap
          new_details.each do |object, value|
            if value >= params[:threshold] && !old_details.key?(object)
              differences[object] = "+#{value}"
            end
          end

          header = "## #{sdk} XCSize"
          content = "#{header}\nNo changes in SDK size."
          unless differences.empty?
            sorted_differences = differences.sort_by { |_, diff| -diff.to_s.gsub(/[+\-]/, '').to_i }
            content = "#{header}\n#{build_collapsible_table(sorted_differences.to_h)}"
          end
          UI.important(content)

          # Update metrics json with the new details
          metrics[metrics_branch] = new_details
          File.write(metrics_path, JSON.pretty_generate(metrics))

          next unless other_action.is_ci

          if is_release || is_push_to_develop || is_push_to_chat_v5
            Dir.chdir(metrics_dir) do
              if sh('git status -s').to_s.empty?
                UI.important('No changes in linkmap.')
              else
                sh('git add -A')
                sh("git commit -m 'Update #{metrics_path}'")
                sh('git push')
              end
            end
          end

          other_action.pr_comment(text: content, edit_last_comment_with_text: header) unless differences.empty?
        end
      end

      def self.build_collapsible_table(differences)
        differences_list = differences.to_a
        visible_count = differences_list.length > 10 ? 5 : differences_list.length
        hidden_count = differences_list.length - visible_count

        table = "| `Object` | `Diff (bytes)` |\n| - | - |\n"
        differences_list.first(visible_count).each do |object, diff|
          table << "| #{object} | #{diff} |\n"
        end

        if hidden_count > 0
          table << "\n<details>\n<summary>Show #{hidden_count} more objects</summary>\n\n"
          table << "| `Object` | `Diff (bytes)` |\n| - | - |\n"
          differences_list[visible_count..-1].each do |object, diff|
            table << "| #{object} | #{diff} |\n"
          end
          table << "</details>"
        end

        table
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        'Show SDK objects size'
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            env_name: 'GITHUB_REPOSITORY',
            key: :github_repo,
            description: 'GitHub repo name',
            verify_block: proc do |name|
              UI.user_error!("GITHUB_REPOSITORY should not be empty") if name.to_s.empty?
            end
          ),
          FastlaneCore::ConfigItem.new(
            key: :sdk_names,
            description: 'SDK names to analyze',
            is_string: false,
            verify_block: proc do |sdks|
              UI.user_error!("SDK names array has to be specified") unless sdks.kind_of?(Array) && sdks.size.positive?
            end
          ),
          FastlaneCore::ConfigItem.new(
            key: :threshold,
            description: 'Set minimum size threshold in bytes',
            optional: true,
            is_string: false,
            default_value: 1
          )
        ]
      end

      def self.is_supported?(platform)
        [:ios, :mac].include?(platform)
      end
    end
  end
end
