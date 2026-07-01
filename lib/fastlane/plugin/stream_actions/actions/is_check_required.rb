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
        'Decides whether a CI check (tests, build, etc.) needs to run for the current pull request state'
      end

      def self.details
        <<~DETAILS
          Skips CI work that has nothing to verify, without ever skipping work that has not been verified yet.

          The action inspects which files changed and returns:
          - true  -> the caller should run the check
          - false -> the caller can safely skip it (usually via `next unless is_check_required(...)`)

          How the decision is made:
          1. If `force_check` is set, or no PR number is available (e.g. a push to a branch), it returns true.
          2. It collects the changed files. On a `synchronize` event with `github_event_before`/`after`, only
             the files in that single push are considered; otherwise the whole PR diff is used.
          3. If more than 99 files changed, it returns true (the GitHub CLI cannot reliably list more).
          4. If any changed file lives under one of `sources`, the check is relevant -> returns true.
          5. If no changed file touches `sources`:
             - With no `required_checks`, it returns false (nothing relevant changed in this push).
             - With `required_checks`, it confirms the sources were actually verified before skipping. It walks
               the PR commits newest-to-oldest: every commit newer than the last `sources` change shares the
               current source tree, so if all `required_checks` concluded `success` on any of them, the sources
               are proven and it returns false. The walk stops at the commit that changed `sources` (older
               commits carry different sources); if none of them passed, the sources are unverified -> true.
               If `sources` were never changed anywhere in the PR, there is nothing to test -> false.

          This is what prevents a docs-only follow-up commit (e.g. editing CHANGELOG.md) from skipping tests
          when the underlying source changes never passed CI.
        DETAILS
      end

      def self.return_value
        'Boolean. true when the check should run, false when it can be safely skipped for the current PR state.'
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :sources,
            description: 'Paths the check cares about. If a changed file path starts with any of these, the ' \
                         'check is relevant and must run. Non-empty array of path prefixes, e.g. ["Sources", "Tests"]',
            is_string: false,
            verify_block: proc do |array|
              UI.user_error!("Sources have to be specified") unless array.kind_of?(Array) && array.size.positive?
            end
          ),
          FastlaneCore::ConfigItem.new(
            env_name: 'GITHUB_PR_NUM',
            key: :github_pr_num,
            description: 'Pull request number to analyze. When empty or nil (e.g. not running for a PR), the ' \
                         'action always returns true',
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :required_checks,
            description: 'GitHub check-run names (exactly as shown on the PR, e.g. "Test (iOS 17)") that must ' \
                         'have concluded as success to prove the current sources were already verified. Only ' \
                         'consulted when the current push does not touch :sources: the check is skipped only if ' \
                         'all of these passed on a commit that has the current source tree. When empty, a push ' \
                         'that does not touch :sources is skipped immediately, without any verification',
            is_string: false,
            optional: true,
            default_value: []
          ),
          FastlaneCore::ConfigItem.new(
            key: :force_check,
            description: 'When truthy, bypass all analysis and always return true (force the check to run)',
            optional: true,
            is_string: false
          ),
          FastlaneCore::ConfigItem.new(
            env_name: 'GITHUB_EVENT_ACTION',
            key: :github_event_action,
            description: 'The pull_request event action, e.g. "opened" or "synchronize". When "synchronize" and ' \
                         'github_event_before/after are set, only the files in that push are considered; ' \
                         'otherwise the full PR diff is used',
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            env_name: 'GITHUB_EVENT_BEFORE',
            key: :github_event_before,
            description: 'github.event.before: the branch head SHA before the push. Combined with ' \
                         'github_event_after to scope the diff to a single push on synchronize',
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            env_name: 'GITHUB_EVENT_AFTER',
            key: :github_event_after,
            description: 'github.event.after: the branch head SHA after the push. Combined with ' \
                         'github_event_before to scope the diff to a single push on synchronize',
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            env_name: 'GITHUB_REPOSITORY',
            key: :github_repository,
            description: 'Repository in "owner/repo" form. Needed to scope the diff to a push and to look up ' \
                         'commit history and check runs. Defaults to the GITHUB_REPOSITORY env var set in CI',
            optional: true
          )
        ]
      end

      def self.example_code
        [
          'next unless is_check_required(sources: ["Sources", "Tests"])',
          'unless is_check_required(
            sources: ["Sources"],
            github_pr_num: ENV["GITHUB_PR_NUM"],
            required_checks: ["Test (iOS 17)", "Build"]
          )
            next
          end'
        ]
      end

      def self.category
        :testing
      end

      def self.is_supported?(platform)
        true
      end
    end
  end
end
