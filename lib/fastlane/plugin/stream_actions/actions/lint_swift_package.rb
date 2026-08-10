module Fastlane
  module Actions
    class LintSwiftPackageAction < Action
      def self.run(params)
        path = params[:swift_package_path]
        UI.user_error!("Package.swift not found at path: #{path}") unless File.exist?(path)

        dependencies = package_declarations(File.read(path))
        violations = dependencies.flat_map { |dependency| dependency_violations(dependency) }
        violations += duplicate_violations(dependencies)

        if violations.any?
          UI.user_error!("Package.swift contains #{violations.size} dependency issue(s):\n#{violations.join("\n")}")
        end

        UI.success("Package.swift dependencies look good 🚀")
      end

      def self.dependency_violations(dependency)
        body = dependency[:body]
        violations = []
        if body =~ /\bbranch:/ || body.include?('.branch(')
          violations << violation(dependency, 'branch-based dependency — pin it with `from:` or `exact:` instead')
        end
        if body =~ /\brevision:/ || body.include?('.revision(')
          violations << violation(dependency, 'revision-pinned dependency — pin it with `from:` or `exact:` instead')
        end
        if body.include?('..<') || body =~ /"\s*\.\.\.\s*"/ || body.include?('.upToNextMinor(')
          violations << violation(dependency, 'version-range dependency — pin it with `from:` or `exact:` instead')
        end
        if body =~ /\bpath:/
          violations << violation(dependency, 'local path dependency — it will not resolve for package consumers')
        end
        if dependency[:url] && dependency[:url] !~ %r{\Ahttps://}
          violations << violation(dependency, 'insecure or non-https url — use `https://`')
        end
        if violations.empty? && body !~ /\b(from|exact):/ && !body.include?('.exact(') && !body.include?('.upToNextMajor(')
          violations << violation(dependency, 'missing version requirement — pin it with `from:` or `exact:`')
        end
        violations
      end

      def self.duplicate_violations(dependencies)
        dependencies
          .select { |dependency| dependency[:url] }
          .group_by { |dependency| dependency[:url].downcase.sub(/\.git\z/, '') }
          .values
          .select { |group| group.size > 1 }
          .map do |group|
            lines = group.map { |dependency| dependency[:line] }.join(', ')
            "- #{group.first[:url]} (lines #{lines}): duplicate dependency"
          end
      end

      def self.violation(dependency, message)
        location = dependency[:url] ? "#{dependency[:url]} (line #{dependency[:line]})" : "line #{dependency[:line]}"
        "- #{location}: #{message}"
      end

      def self.package_declarations(content)
        declarations = []
        offset = 0
        while (start = content.index('.package(', offset))
          body_start = start + 9 # '.package('.length
          index = body_start
          depth = 1
          in_string = false
          while index < content.length && depth > 0
            char = content[index]
            if in_string
              in_string = false if char == '"' && content[index - 1] != '\\'
            else
              case char
              when '"' then in_string = true
              when '(' then depth += 1
              when ')' then depth -= 1
              end
            end
            index += 1
          end
          body = content[body_start...(index - 1)]
          declarations << {
            body: body,
            url: body[/url:\s*"([^"]+)"/, 1],
            line: content[0..start].count("\n") + 1
          }
          offset = index
        end
        declarations
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        'Scans Package.swift for common mistakes in dependency declarations'
      end

      def self.details
        'Fails if any dependency is declared via branch, revision, version range, local path, ' \
          'insecure url, or is duplicated. All dependencies should be pinned with `from:` or `exact:`.'
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :swift_package_path,
            description: 'The path to your project Package.swift',
            is_string: true,
            default_value: './Package.swift',
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
