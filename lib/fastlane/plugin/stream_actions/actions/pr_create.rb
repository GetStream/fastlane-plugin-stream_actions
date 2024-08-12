module Fastlane
  module Actions
    class PrCreateAction < Action
      def self.run(params)
        params[:base_branch] ||= 'develop'
        sh("git checkout -b #{params[:head_branch]}")
        sh('git restore Brewfile.lock.json || true')
        sh('git add -A')
        sh("git commit -m '#{params[:title]}'")
        other_action.push_to_git_remote(tags: false)

        other_action.create_pull_request(
          api_token: ENV.fetch('GITHUB_TOKEN'),
          repo: params[:github_repo],
          title: params[:title],
          head: params[:head_branch],
          base: params[:base_branch],
          body: 'This PR was created automatically by CI.'
        )
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
            is_string: true
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
          )
        ]
      end

      def self.is_supported?(platform)
        true
      end
    end
  end
end