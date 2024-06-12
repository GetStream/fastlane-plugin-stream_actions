module Fastlane
  module Actions
    class CheckFoundationAction < Action
      def self.run(params)
        errors = []
        Dir.glob("#{params[:path]}/**/*.swift") do |file|
          next if params[:ignore].any? { |path| file.include?(path) } || !File.file?(file)

          content = File.read(file)
          unless content.match?(/import (Foundation|SwiftUI|UIKit)/)
            detected_keywords = scan(content)
            unless detected_keywords.empty?
              UI.error("#{file} needs to `import Foundation`. Detected keywords: #{detected_keywords}")
              errors << { file: file, keywords: detected_keywords }
            end
          end
        end

        errors.empty? ? UI.success('Check passed ✅') : UI.user_error!('Check failed 🛑')
      end

      def self.scan(source_code)
        foundation_keywords = %w[
          Date
          URL
          Data
          JSONDecoder
          JSONEncoder
          URLSession
          DispatchQueue
          OperationQueue
          FileManager
          Bundle
          ProcessInfo
          Calendar
          DateFormatter Locale
          NotificationCenter
          NSCoder
          NSUserDefaults
          Operation
          Progress
          Timer
          URLRequest
          URLResponse
          RunLoop
          TimeZone
          FileHandle
          NSFileManager
          NSFileHandle
          NSFileVersion
          NSRunLoop
          NSTimeZone
          NSProgress
          NSTimer
          NSRegularExpression
          NSSortDescriptor
          NSString
          NSArray
          NSDictionary
          NSSet
          NSIndexSet
          NSCalendar
          NSDateFormatter
          NSLocale
          NSDate
          NSData
          NSURL
          NSError
          NSUUID
        ]

        space_prefix = ' ' # To reduce false positives
        found_keywords = []
        source_code.each_line do |line|
          next if line.include?('//') # To skip comments

          found_keywords += foundation_keywords.select { |keyword| line.include?("#{space_prefix}#{keyword}") }
        end

        found_keywords.uniq
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        'Check if a swift file requires importing the Foundation framework'
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :path,
            description: 'The path to the source code'
          ),
          FastlaneCore::ConfigItem.new(
            key: :ignore,
            description: 'An array of files or paths that should be ignored',
            is_string: false,
            default_value: []
          )
        ]
      end

      def self.supported?(_platform)
        [:ios].include?(platform)
      end
    end
  end
end
