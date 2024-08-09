module Fastlane
  module Actions
    class PrCommentAction < Action
      def self.run(params)
        if params[:pr_num]
          last_comment = sh("gh pr view #{params[:pr_num]} --json comments --jq '.comments | map(select(.author.login == \"Stream-SDK-Bot\")) | last'")
          edit_last_comment = params[:edit_last_comment_with_text] && last_comment.include?(params[:edit_last_comment_with_text]) ? '--edit-last' : ''
          sh("gh pr comment #{params[:pr_num]} #{edit_last_comment} -b '#{params[:text]}'")
        else
          UI.important('Skipping the PR comment because PR number has not been provided.')
        end
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        'Comment in the PR'
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            env_name: 'GITHUB_PR_NUM',
            key: :pr_num,
            description: 'GitHub PR number',
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :text,
            description: 'Comment text',
            is_string: true,
            verify_block: proc do |text|
              UI.user_error!("Text should not be empty") if text.to_s.empty?
            end
          ),
          FastlaneCore::ConfigItem.new(
            key: :edit_last_comment_with_text,
            description: 'If last comment contains this text it will be edited',
            is_string: true,
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
