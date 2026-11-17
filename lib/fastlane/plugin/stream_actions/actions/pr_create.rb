module Fastlane
  module Actions
    class PrCreateAction < Action
      def self.run(params)
        sh("git checkout -b #{params[:head_branch]}")
        sh('git restore Brewfile.lock.json || true')
        sh("git add #{params[:git_add]}")
        staged_files = sh('git diff --cached --name-only').split
        if staged_files.empty?
          unstaged_files = sh('git diff --name-only')
          UI.important("There is nothing to commit. See unstaged files for more details:\n#{unstaged_files}")
        else
          sh("git commit -m '#{params[:title]}'")
          other_action.push_to_git_remote(tags: false)

          run_url = "#{ENV['GITHUB_SERVER_URL']}/#{ENV['GITHUB_REPOSITORY']}/actions/runs/#{ENV['GITHUB_RUN_ID']}" if ENV['GITHUB_RUN_ID']
          body = 'This PR was created automatically by CI.'
          body += "\n\nTriggered by: #{run_url}" if run_url

          # `api_bearer`, because GitHub App tokens do not authenticate with the Basic scheme of `api_token`.
          pull_request = other_action.create_pull_request(
            api_bearer: ENV.fetch('GITHUB_TOKEN'),
            repo: params[:github_repo],
            title: params[:title],
            head: params[:head_branch],
            base: params[:base_branch],
            body: body
          )
          # `create_pull_request` only logs a failed request and returns nil.
          unless pull_request
            UI.user_error!("Failed to create the pull request. The branch #{params[:head_branch]} is already pushed.")
          end
        end
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        'Create PR'
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
            key: :base_branch,
            description: 'Base branch',
            is_string: true,
            default_value: 'develop'
          ),
          FastlaneCore::ConfigItem.new(
            key: :head_branch,
            description: 'Head branch',
            is_string: true,
            optional: false
          ),
          FastlaneCore::ConfigItem.new(
            key: :title,
            description: 'Title',
            is_string: true,
            optional: false
          ),
          FastlaneCore::ConfigItem.new(
            key: :git_add,
            description: 'Path that should be commited',
            is_string: true,
            default_value: '-A'
          )
        ]
      end

      def self.is_supported?(platform)
        true
      end
    end
  end
end
