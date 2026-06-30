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

        if self.touches_sources?(changed_files, params[:sources])
          UI.important("Check is required: true")
          return true
        end

        required_checks = params[:required_checks].to_a
        if required_checks.empty?
          UI.important("Check is required: false")
          return false
        end

        # The current push does not touch :sources. It is only safe to skip if :sources were already
        # verified, i.e. all required checks passed on some commit that has the current :sources tree.
        is_check_required = self.required_due_to_history(params, required_checks)
        UI.important("Check is required: #{is_check_required}")
        is_check_required
      end

      def self.touches_sources?(files, sources)
        files.any? { |path| sources.any? { |required| path.start_with?(required) } }
      end

      # Walks the PR commits from newest to oldest. Every commit newer than the last :sources change
      # has the current :sources tree, so a passing run on any of them means :sources were verified.
      # The walk stops at the commit that changed :sources, since older commits have different sources.
      def self.required_due_to_history(params, required_checks)
        repo = (params[:github_repository] || ENV['GITHUB_REPOSITORY']).to_s
        if repo.empty?
          UI.important("No repository provided; cannot verify previous runs, running check")
          return true
        end

        shas = self.pr_commit_shas(params[:github_pr_num])
        if shas.empty?
          UI.important("Could not list PR commits; running check")
          return true
        end

        shas.each do |sha|
          short = sha[0, 7]
          if self.required_checks_passed?(repo, sha, required_checks)
            UI.message("Commit #{short} passed required checks for the current sources; safe to skip")
            return false
          end

          next unless self.touches_sources?(self.commit_files(repo, sha), params[:sources])

          UI.important("Last sources commit #{short} was not verified by a passing run; running check")
          return true
        end

        UI.message("No commit in this PR changed sources; nothing to test")
        false
      end

      # PR commits, newest first (gh returns them oldest first).
      def self.pr_commit_shas(pr_num)
        self.gh_path_lines(Actions.sh("gh pr view #{pr_num} --json commits -q '.commits[].oid'")).reverse
      rescue StandardError
        []
      end

      # Files changed by a single commit (relative to its first parent).
      def self.commit_files(repo, sha)
        self.gh_path_lines(Actions.sh("gh api repos/#{repo}/commits/#{sha} --paginate -q '.files[].filename'"))
      rescue StandardError
        []
      end

      # True only if every required check has its latest run concluded as 'success' on the commit.
      def self.required_checks_passed?(repo, sha, required_checks)
        out = Actions.sh(
          "gh api \"repos/#{repo}/commits/#{sha}/check-runs?per_page=100\" --paginate " \
          "-H \"Accept: application/vnd.github.v3+json\" " \
          "-q '.check_runs[] | \"\\(.name)\\t\\(.conclusion)\\t\\(.completed_at)\"'"
        )
        latest = self.latest_conclusions(out)
        required_checks.all? { |name| latest[name] == 'success' }
      rescue StandardError
        false
      end

      # Reduces "name\tconclusion\tcompleted_at" lines to the latest conclusion per check name,
      # so re-runs of the same check supersede earlier attempts.
      def self.latest_conclusions(output)
        latest = {}
        seen_at = {}
        output.to_s.split("\n", -1).each do |line|
          name, conclusion, completed_at = line.split("\t", -1)
          next if name.nil? || name.strip.empty?

          completed_at = completed_at.to_s
          next if seen_at.key?(name) && completed_at < seen_at[name]

          seen_at[name] = completed_at
          latest[name] = conclusion.to_s
        end
        latest
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
            key: :required_checks,
            description: 'Names of GitHub check runs that must have concluded as success on the last commit ' \
                         'that changed :sources for the check to be skipped when the current push does not ' \
                         'touch :sources. When empty, the check is skipped as soon as the current push does ' \
                         'not touch :sources',
            is_string: false,
            optional: true,
            default_value: []
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
