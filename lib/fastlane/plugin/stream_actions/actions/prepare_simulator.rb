module Fastlane
  module Actions
    class PrepareSimulatorAction < Action
      def self.run(params)
        version_set = params[:device].include?('(')
        sim = FastlaneCore::Simulator.all.detect do |d|
          params[:device] == (version_set ? "#{d.name} (#{d.os_version})" : d.name)
        end
        sim.reset if params[:reset]
        sh("xcrun simctl bootstatus #{sim.udid} -b")
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        'Prepares simulator for tests'
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :device,
            description: 'Simulator name or name with version',
            is_string: false
          ),
          FastlaneCore::ConfigItem.new(
            key: :reset,
            description: 'Reset simulator contents',
            optional: true,
            is_string: false
          )
        ]
      end

      def self.supported?(_platform)
        true
      end
    end
  end
end
