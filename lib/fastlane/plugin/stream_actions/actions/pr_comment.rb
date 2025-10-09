module Fastlane
  module Actions
    class PrCommentAction < Action
      def self.run(params)
        if params[:pr_num].to_s.empty? || params[:github_repo].to_s.empty?
          UI.important('Skipping the PR comment because PR number or GitHub repo is not set.')
        else
          if params[:edit_last_comment_with_text]
            text = params[:edit_last_comment_with_text]
            UI.message("Checking last comment for required pattern: '#{text}'")
            comments = sh("gh api repos/#{params[:github_repo]}/issues/#{params[:pr_num]}/comments --jq " \
                          "'[.[] | select(.body | test(\"#{text}\"; \"i\")) | {id, user: .user.login, html_url}]'")

            JSON.parse(comments).each do |comment|
              sh("gh api --method DELETE repos/#{params[:github_repo]}/issues/comments/#{comment['id']}")
            end
          end
          sh("gh pr comment #{params[:pr_num]} -b '#{params[:text]}'")
          UI.success('PR comment has been added.')
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
            env_name: 'GITHUB_REPOSITORY',
            key: :github_repo,
            description: 'GitHub repo name',
            optional: true
          ),
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
            description: 'If last comment contains this text it will be edited or replaced',
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
