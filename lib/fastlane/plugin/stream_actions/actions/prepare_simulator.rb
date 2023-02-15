module Fastlane
  module Actions
    class PrepareSimulatorAction < Action
      def self.run(params)
        simulators = FastlaneCore::Simulator.all
        version_regex = /\((\d+\.)?(\d+\.)?(\*|\d+)\)/
        ios_version = params[:device][version_regex]

        if ios_version.nil?
          sim = simulators.filter { |d| d.name == params[:device] }.max_by(&:os_version)
        else
          sim = simulators.detect { |d| "#{d.name} (#{d.os_version})" == params[:device] }
          if sim.nil?
            device_name = params[:device].sub(version_regex, '').strip
            sh("xcrun simctl create '#{device_name}' '#{device_name}' 'iOS#{ios_version.delete('()')}'")
            sim = simulators.detect { |d| "#{d.name} (#{d.os_version})" == params[:device] }
          end
        end

        if sim.nil?
          simulators.map! { |d| "#{d.name} (#{d.os_version})" }.join("\n")
          UI.user_error!("Simulator #{params[:device]} not found \nAvailable simulators: \n#{simulators}")
        end

        sim.reset if params[:reset]
        sh("xcrun simctl bootstatus #{sim.udid} -b")
        UI.success("Simulator #{sim.name} (#{sim.os_version}) is ready")
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
