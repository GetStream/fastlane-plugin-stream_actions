module Fastlane
  module Actions
    class WaitAndroidEmuIdleAction < Action
      def self.run(params)
        start_time = Time.now
        UI.important("Start waiting until emulator is idle (#{Time.now})")
        check_emu_uptime = 'adb shell uptime | cut -d , -f 3 | cut -f 2 -d :'
        current_uptime_value = `#{check_emu_uptime}`.strip.to_f

        end_time = start_time + params[:timeout]
        while current_uptime_value > params[:load_threshold] && Time.now < end_time
          UI.important("Current uptime value: #{current_uptime_value} 👀")

          not_responding_package = `adb shell dumpsys window | grep -E "mCurrentFocus.*Application Not Responding" | cut -f 2 -d : | sed -e "s/}//" -e "s/^ *//"`.strip
          if not_responding_package == 'com.android.systemui'
            UI.important("Trying to dismiss not responding #{not_responding_package} dialog")
            `adb shell input keyevent KEYCODE_ENTER`
            `adb shell input keyevent KEYCODE_DPAD_DOWN`
            `adb shell input keyevent KEYCODE_ENTER`
          end

          sleep(10)
          current_uptime_value = `#{check_emu_uptime}`.strip.to_f
        end

        UI.important('Reached timeout before emulator is idle 😕') if current_uptime_value > params[:load_threshold]
        UI.important("Waited until emulator is idle for #{(Time.now - start_time).to_i} seconds ⌛️")
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        'Adds environment variables to a test plan'
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :load_threshold,
            description: 'Load threshold to consider device idle',
            is_string: false,
            default_value: 1.0
          ),
          FastlaneCore::ConfigItem.new(
            key: :timeout,
            description: 'Timeout in seconds to wait for device to be idle',
            is_string: false,
            default_value: 1000
          )
        ]
      end

      def self.supported?(_platform)
        [:android].include?(platform)
      end
    end
  end
end
