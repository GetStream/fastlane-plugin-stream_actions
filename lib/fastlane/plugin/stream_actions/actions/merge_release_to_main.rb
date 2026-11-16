module Fastlane
  module Actions
    class MergeReleaseToMainAction < Action
      def self.run(params)
        other_action.ensure_git_status_clean

        release_branch =
          if other_action.is_ci
            ensure_author_is_repo_admin(author: params[:author], github_repo: params[:github_repo])

            other_action.current_branch
          else
            release_branches = sh(command: 'git branch -a').delete(' ').split("\n").grep(%r(origin/.*release/))
            UI.user_error!("Expected 1 release branch, found #{release_branches.size}") if release_branches.size != 1

            release_branches.first
          end

        UI.user_error!("`#{release_branch}`` branch does not match the release branch pattern: `release/*`") unless release_branch.start_with?('release/')

        sh('git config pull.ff only')
        sh('git fetch --all --tags --prune')
        sh("git checkout #{release_branch}")
        sh("git pull origin #{release_branch} --ff-only")
        sh('git checkout main')
        sh('git pull origin main --ff-only')
        sh("git merge #{release_branch} --ff-only")
        sh('git push origin main')

        comment = "Publication of the release has been launched 👍"
        UI.important(comment)
        other_action.pr_comment(text: comment)
      end

      # Admin access to the repo is what separates the iOS team from the rest of the org (which only has write).
      # Unlike listing org team members, this endpoint works with the workflow's built-in GITHUB_TOKEN.
      def self.ensure_author_is_repo_admin(author:, github_repo:)
        UI.user_error!('Release author is not set') if author.to_s.empty?
        UI.user_error!('GitHub repo is not set') if github_repo.to_s.empty?

        permission = sh(
          'gh', 'api', "repos/#{github_repo}/collaborators/#{author}/permission", '--jq', '.permission',
          print_command_output: false,
          error_callback: ->(_) {}
        ).to_s.strip
        UI.user_error!("#{author} needs admin access to #{github_repo} to merge a release (has: #{permission})") unless permission == 'admin'
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        'Merge release branch to main'
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            env_name: 'USER_LOGIN',
            key: :author,
            description: 'Github user name',
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            env_name: 'GITHUB_REPOSITORY',
            key: :github_repo,
            description: 'GitHub repo name (owner/name)',
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
