require 'tempfile'

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
            comments = sh('gh', 'api', "repos/#{params[:github_repo]}/issues/#{params[:pr_num]}/comments", log: false)

            JSON.parse(comments).select { |comment| comment['body'].downcase.include?(text.downcase) }.each do |comment|
              sh("gh api --method DELETE repos/#{params[:github_repo]}/issues/comments/#{comment['id']}")
            end
          end
          Tempfile.create('pr_comment') do |file|
            file.write(comment_body(params))
            file.close
            sh('gh', 'pr', 'comment', params[:pr_num].to_s, '--body-file', file.path)
          end
          UI.success('PR comment has been added.')
        end
      end

      def self.comment_body(params)
        text = params[:text]
        return text if text.length <= 65_536

        UI.important("PR comment has #{text.length} characters, more than GitHub allows (65536). Full text:")
        UI.message(text)
        # Leave room for the closing fence and the footer
        body = text[0, 60_000]
        # Cut at a line break so a fence marker is never split
        body = body[0, body.rindex("\n")] if body.include?("\n")
        fence = open_fence(body)
        body += "\n#{fence}" if fence
        run_url = "https://github.com/#{params[:github_repo]}/actions/runs/#{ENV['GITHUB_RUN_ID']}"
        "#{body}\n\n⚠️ Truncated to fit GitHub's comment limit. The full text is in the [job log](#{run_url})."
      end

      def self.open_fence(body)
        fence = nil
        body.each_line do |line|
          marker = line[/\A {0,3}(`{3,})/, 1]
          next unless marker

          if fence.nil?
            fence = marker
          elsif marker.length >= fence.length && line.strip == marker
            fence = nil
          end
        end
        fence
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
