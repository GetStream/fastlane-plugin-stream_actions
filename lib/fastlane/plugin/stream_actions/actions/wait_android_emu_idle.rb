module Fastlane
  module Actions
    class WaitAndroidEmuIdle < Action
      def self.run(params)
        start_time = Time.now
        load_threshold = 1.0
        UI.important("Start waiting until device is idle (#{Time.now})")
        adb_command = 'adb shell uptime | cut -d , -f 3 | cut -f 2 -d :'
        load = `#{adb_command}`.strip.to_f

        end_time = start_time + 1800
        while load > load_threshold && Time.now < end_time
          if load < 4
            `adb shell dumpsys window | grep -E "mCurrentFocus.*Application Not Responding" || echo`
            anr_package = `adb shell dumpsys window | grep -E "mCurrentFocus.*Application Not Responding" | cut -f 2 -d : | sed -e "s/}//" -e "s/^ *//"`.strip
            unless anr_package.empty?
              UI.important("ANR on screen for: #{anr_package}. Restarting it.")
              begin
                `adb shell su 0 killall #{anr_package}`
              rescue StandardError => e
                UI.error(e)
                # Fallback to click if kill didn't work. This location is for a 1080x1920 screen
                `adb shell input tap 540 935 || echo`
              end

              if anr_package == 'com.android.systemui'
                `adb shell am start-service -n com.android.systemui/.SystemUIService || echo`
              end
            end
          end

          sleep(10)
          load = `#{adb_command}`.strip.to_f
        end

        UI.important('Reached timeout before device is idle 😕') if load > load_threshold
        UI.important("Waited until device is idle for #{(Time.now - start_time).to_i} seconds ⌛️")
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        'Adds environment variables to a test plan'
      end

      def self.available_options
        []
      end

      def self.supported?(_platform)
        [:android].include?(platform)
      end
    end
  end
end
