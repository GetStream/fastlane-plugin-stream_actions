module Fastlane
  module Actions
    class MergeMainToDevelopAction < Action
      def self.run(params)
        other_action.ensure_git_status_clean
        sh('git checkout main')
        sh('git pull origin main')
        sh('git checkout origin/develop')
        sh('git pull origin develop')
        sh('git log develop..main')
        sh('git merge main')
        sh('git push origin develop')
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        'Merge main branch to develop'
      end

      def self.available_options
        []
      end

      def self.is_supported?(platform)
        true
      end
    end
  end
end
