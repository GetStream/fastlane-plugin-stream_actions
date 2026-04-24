module Fastlane
  module Actions
    class IsCheckRequiredAction < Action
      def self.run(params)
        return true if params[:force_check] || params[:github_pr_num].nil? || params[:github_pr_num].strip.empty?

        UI.message("Checking if check is required for PR ##{params[:github_pr_num]}")

        changed_files = self.changed_file_paths(params)

        too_many_files = changed_files.size > 99 # TODO: https://github.com/cli/cli/issues/5368
        if too_many_files
          UI.important("Check is required because there were too many files changed.")
          return true
        end

        changed_files.select! do |path|
          params[:sources].any? { |required| path.start_with?(required) }
        end

        is_check_required = changed_files.size.positive?
        UI.important("Check is required: #{is_check_required}")
        is_check_required
      end

      # For pull_request: use full PR for `opened` (etc.); for `synchronize` pass
      # github_event_before/after (e.g. github.event.before/after) to scope to this push.
      def self.changed_file_paths(params)
        action = params[:github_event_action].to_s
        before = params[:github_event_before].to_s.strip
        after = params[:github_event_after].to_s.strip
        repo = (params[:github_repository] || ENV['GITHUB_REPOSITORY']).to_s

        if action == 'synchronize' && !before.empty? && !after.empty? && !repo.empty?
          if before.match?(/\A0+\z/) || !before.match?(/\A[0-9a-f]{7,40}\z/i) || !after.match?(/\A[0-9a-f]{7,40}\z/i)
            UI.important("Invalid before/after for compare; falling back to full PR file list")
          else
            out = self.compare_push_files(repo, before, after)
            return out unless out.nil?

            UI.important("Could not list push diff (e.g. fork/cross-repo); falling back to full PR file list")
          end
        end

        self.gh_path_lines(Actions.sh("gh pr view #{params[:github_pr_num]} --json files -q '.files[].path'"))
      end

      def self.compare_push_files(repo, before, after)
        self.gh_path_lines(Actions.sh(
                             "gh api \"repos/#{repo}/compare/#{before}...#{after}\" " \
                             "-H \"Accept: application/vnd.github.v3+json\" " \
                             "-q '.files[].filename'"
                           ))
      rescue StandardError
        nil
      end

      def self.gh_path_lines(output)
        output.to_s.split("\n", -1).map(&:strip).reject(&:empty?)
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        'Analyzes the impact of changes on PR'
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :sources,
            description: 'Array of paths to scan',
            is_string: false,
            verify_block: proc do |array|
              UI.user_error!("Sources have to be specified") unless array.kind_of?(Array) && array.size.positive?
            end
          ),
          FastlaneCore::ConfigItem.new(
            env_name: 'GITHUB_PR_NUM',
            key: :github_pr_num,
            description: 'GitHub PR number',
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :force_check,
            description: 'GitHub PR number',
            optional: true,
            is_string: false
          ),
          FastlaneCore::ConfigItem.new(
            env_name: 'GITHUB_EVENT_ACTION',
            key: :github_event_action,
            description: 'pull_request action: e.g. opened, synchronize. When synchronize and before/after ' \
                         'are set, only files in that push are considered',
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            env_name: 'GITHUB_EVENT_BEFORE',
            key: :github_event_before,
            description: 'github.event.before (head ref before the push) for pull_request',
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            env_name: 'GITHUB_EVENT_AFTER',
            key: :github_event_after,
            description: 'github.event.after (head ref after the push) for pull_request',
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            env_name: 'GITHUB_REPOSITORY',
            key: :github_repository,
            description: 'owner/repo; required for push-scoped file list (defaults to GITHUB_REPOSITORY in CI)',
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
