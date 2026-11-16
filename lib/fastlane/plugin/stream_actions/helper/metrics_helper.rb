module Fastlane
  module Helper
    # Pushes commits to GetStream/stream-internal-metrics, which other repositories push to as well.
    class MetricsHelper
      # Rebases onto the latest metrics and pushes, retrying when another push got there first. Run it inside the
      # metrics clone, after committing.
      def self.push(attempts: 3)
        1.upto(attempts) do |attempt|
          rebase
          begin
            return Actions.sh('git push')
          rescue FastlaneCore::Interface::FastlaneShellError
            raise if attempt == attempts

            UI.important("Pushing to stream-internal-metrics was rejected, retrying (#{attempt}/#{attempts}).")
            sleep(attempt * 5)
          end
        end
      end

      # A conflict isn't retried: it would fail again on the unfinished rebase and hide the conflict.
      def self.rebase
        Actions.sh('git pull --rebase')
      rescue FastlaneCore::Interface::FastlaneShellError
        Actions.sh('git rebase --abort', error_callback: ->(_) {})
        raise
      end
    end
  end
end
