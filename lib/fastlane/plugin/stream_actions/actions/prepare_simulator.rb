module Fastlane
  module Actions
    class PrepareSimulatorAction < Action
      def self.run(params)
        simulators = FastlaneCore::Simulator.all
        version_provided = params[:device] =~ /\((\d+\.)?(\d+\.)?(\*|\d+)\)/
        sim = if version_provided
                simulators.detect { |d| "#{d.name} (#{d.os_version})" == params[:device] }
              else
                simulators.filter { |d| d.name == params[:device] }.max_by(&:os_version)
              end

        if sim.nil?
          simulators.map! { |d| version_provided ? "#{d.name} (#{d.os_version})" : d.name }
          UI.user_error!("Simulator #{params[:device]} not found \nAvailable simulators: \n#{simulators.join("\n")}")
        else
          sim.reset if params[:reset]
          sh("xcrun simctl bootstatus #{sim.udid} -b")
          UI.success("Simulator #{sim.name} (#{sim.os_version}) is ready")
        end
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
