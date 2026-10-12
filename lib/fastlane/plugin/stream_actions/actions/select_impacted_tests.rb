require 'json'
require 'set'
require 'time'

module Fastlane
  module Actions
    class SelectImpactedTestsAction < Action
      CODE_EXTENSIONS = %w[.swift .m .mm .h .kt .java .dart .js .jsx .ts .tsx].freeze
      MODIFIERS = '(?:(?:public|open|internal|fileprivate|private|final|indirect|nonisolated|data|sealed|abstract|export|default)\\s+)*'
      DECLARATION = /^\s*(?:@\w+(?:\([^)\n]*\))?\s+)*#{MODIFIERS}(?:class|struct|enum|protocol|actor|typealias|extension|interface|object)\s+([A-Za-z_]\w*)/.freeze

      def self.run(params)
        source_root = File.expand_path(params[:source_root] || Dir.pwd)
        all_tests = params[:all_tests]
        selection = Dir.chdir(source_root) { select(params, all_tests, source_root) }

        if selection['run_all']
          UI.important("Running all #{all_tests.size} tests: #{selection['reasons'].join('; ')}")
        else
          UI.important("Running #{selection['tests'].size} of #{all_tests.size} tests")
          selection['reasons'].each { |reason| UI.message("  #{reason}") }
        end
        File.write(params[:output_path], JSON.pretty_generate(selection)) if params[:output_path]
        selection
      end

      def self.select(params, all_tests, source_root)
        changes = changed_files(params)
        return run_all(all_tests, 'the changed files are unknown') if changes.nil?
        return selection(all_tests, [], ['no changed files']) if changes.empty?

        forcing = changes.keys.find { |file| matches_any?(file, params[:run_all_paths]) && !only_ignored_lines?(file, params) }
        return run_all(all_tests, "#{forcing} affects every test") if forcing

        map = load_map(params)
        return run_all(all_tests, 'no coverage map') if map.nil?

        age_days = (Time.now.utc - Time.parse(map['generated_at'])) / 86_400
        return run_all(all_tests, "the coverage map is #{age_days.round(1)} days old") if age_days > params[:max_map_age_days]

        tests_by_file = Hash.new { |hash, key| hash[key] = [] }
        map['tests'].each { |test, files| files.each { |file| tests_by_file[file] << test } }
        known_sources = map['sources'].to_set
        mapped_count = map['tests'].size

        selected = []
        reasons = []
        changes.each do |file, status|
          if matches_any?(file, params[:ignore_paths])
            next
          elsif matches_any?(file, params[:test_paths])
            classes = test_classes(file, source_root)
            tests = all_tests.select { |id| classes.include?(test_key(id).split('/').first) }
            selected.concat(tests)
            reasons << "#{file}: #{tests.size} tests of #{classes.join(', ')}"
          elsif known_sources.include?(file)
            tests = tests_by_file[file]
            selected.concat(impacted(tests, all_tests, mapped_count, params))
            reasons << "#{file}: #{describe(tests, mapped_count, params)}"
          elsif matches_any?(file, params[:source_paths])
            return run_all(all_tests, "#{file} is not in the coverage map") unless CODE_EXTENSIONS.include?(File.extname(file))

            if status == 'A' || status == 'D'
              reasons << "#{file}: #{status == 'A' ? 'added' : 'deleted'}, so the files using it changed too"
              next
            end

            # Declaration-only files (models, protocols, constants) have no executable regions, so coverage
            # never lists them. Their declarations still matter, e.g. a Codable key, so run the tests of the
            # mapped files that reference the declared types.
            names = declared_names(file, source_root, params)
            return run_all(all_tests, "#{file} is not in the coverage map and declares no types") if names.empty?

            users = referencing_files(names, known_sources - [file], source_root)
            tests = users.flat_map { |user| tests_by_file[user] }.uniq
            selected.concat(impacted(tests, all_tests, mapped_count, params))
            reasons << "#{file}: #{describe(tests, mapped_count, params)} of the #{users.size} mapped files using #{names.join(', ')}"
          end
        end

        mapped = map['tests'].keys.to_set
        unmapped = all_tests.reject { |id| mapped.include?(test_key(id)) }
        unless unmapped.empty?
          selected.concat(unmapped)
          reasons << "#{unmapped.size} tests that are not in the coverage map yet"
        end

        selection(all_tests, selected.uniq, reasons)
      end

      # Returns { path => git status letter }, or nil when the diff cannot be computed.
      def self.changed_files(params)
        return params[:changed_files].map { |file| [file, 'M'] }.to_h if params[:changed_files]

        range = diff_range(params)
        if range.nil?
          UI.important('Pass changed_files or diff_base, or run on a pull request merge commit')
          return nil
        end

        output = Helper::TestCoverageMapHelper.command('git', 'diff', '--name-status', '--no-renames', range)
        output.split("\n").map do |line|
          status, path = line.split("\t", 2)
          [path, status[0]]
        end.to_h
      rescue StandardError => e
        UI.important("Could not list the changed files: #{e.message}")
        nil
      end

      def self.diff_range(params)
        base = params[:diff_base]
        if base.nil?
          parents = Helper::TestCoverageMapHelper.command('git', 'rev-list', '--parents', '-n', '1', 'HEAD').split
          # GitHub checks out pull requests as a merge commit whose first parent is the base branch tip.
          base = 'HEAD^1' if parents.size == 3
        end
        base.nil? ? nil : "#{base}...#{params[:diff_head]}"
      end

      # True when every added or removed line of the file matches one of its ignored_diff_lines patterns.
      def self.only_ignored_lines?(file, params)
        patterns = params[:ignored_diff_lines].to_h.find { |path, _| matches_any?(file, [path]) }&.last
        return false if patterns.nil? || params[:changed_files]

        regexes = patterns.map { |pattern| Regexp.new(pattern) }
        lines = Helper::TestCoverageMapHelper.command('git', 'diff', '-U0', diff_range(params), '--', file).lines.map(&:chomp)
        changed = lines.select { |line| line.match?(/^[+-]/) && !line.match?(/^(\+\+\+|---) /) }.map { |line| line[1..-1] }
        changed.all? { |line| regexes.any? { |regex| line.match?(regex) } }
      rescue StandardError => e
        UI.important("Could not read the diff of #{file}: #{e.message}")
        false
      end

      def self.load_map(params)
        path = params[:coverage_map]
        path = Helper::TestCoverageMapHelper.download_map(params) if (path.nil? || !File.exist?(path)) && params[:coverage_map_artifact]
        return nil if path.nil? || !File.exist?(path)

        Helper::TestCoverageMapHelper.read_map(path)
      rescue StandardError => e
        UI.important("Could not read the coverage map: #{e.message}")
        nil
      end

      def self.test_classes(file, source_root)
        path = File.join(source_root, file)
        classes = File.exist?(path) ? File.read(path).scan(/^\s*(?:(?:public|open|final|internal)\s+)*class\s+(\w+)/).flatten : []
        classes.empty? ? [File.basename(file, '.*')] : classes
      end

      # Code nearly every test runs (app start, login, the main screen) would select everything. With
      # hot_test_ratio such a change runs one test per class instead, leaving the rest to the full nightly run.
      def self.impacted(tests, all_tests, mapped_count, params)
        return smoke_tests(all_tests) if hot?(tests, mapped_count, params)

        all_tests.select { |id| tests.include?(test_key(id)) }
      end

      def self.hot?(tests, mapped_count, params)
        params[:hot_test_ratio] && mapped_count.positive? && tests.size >= params[:hot_test_ratio] * mapped_count
      end

      def self.smoke_tests(all_tests)
        all_tests.group_by { |id| test_key(id).split('/').first }.values.map(&:first)
      end

      def self.describe(tests, mapped_count, params)
        hot?(tests, mapped_count, params) ? "run by #{tests.size} tests, so one test per class" : "#{tests.size} tests"
      end

      def self.declared_names(file, source_root, params)
        content = begin
          params[:changed_files] ? File.read(File.join(source_root, file)) : Helper::TestCoverageMapHelper.command('git', 'show', "#{params[:diff_head]}:#{file}")
        rescue StandardError
          ''
        end
        content.scan(DECLARATION).flatten.uniq
      end

      def self.referencing_files(names, files, source_root)
        pattern = /\b(?:#{names.map { |name| Regexp.escape(name) }.join('|')})\b/
        files.select do |file|
          path = File.join(source_root, file)
          File.exist?(path) && File.read(path).match?(pattern)
        end
      end

      def self.matches_any?(file, patterns)
        patterns.to_a.any? do |pattern|
          if pattern.include?('*')
            File.fnmatch?(pattern, file, File::FNM_PATHNAME | File::FNM_EXTGLOB | File::FNM_DOTMATCH)
          else
            file == pattern || file.start_with?(pattern.end_with?('/') ? pattern : "#{pattern}/")
          end
        end
      end

      # Target/Class/test -> Class/test, the key the coverage map uses.
      def self.test_key(id)
        id.split('/').last(2).join('/')
      end

      def self.run_all(all_tests, reason)
        selection(all_tests, all_tests, [reason], run_all: true)
      end

      def self.selection(all_tests, tests, reasons, run_all: false)
        order = all_tests.each_with_index.to_h
        { 'run_all' => run_all, 'tests' => tests.sort_by { |id| order.fetch(id) }, 'reasons' => reasons }
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        'Selects the tests a change can affect, using a per-test coverage map'
      end

      def self.details
        <<~DETAILS
          Intersects the changed files with a coverage map from `build_test_coverage_map` (or any producer that
          writes the same JSON) and returns the tests that executed any of them. Falls back to all tests whenever
          it cannot prove a test is unaffected:
          - the changed files or the map are unavailable, or the map is older than `max_map_age_days`;
          - a changed file matches `run_all_paths` (test infrastructure, build settings, CI config);
          - a changed file under `source_paths` is not in the map and is not code (e.g. resources).
          A changed code file that is not in the map and was not added or deleted is declaration-only (coverage
          lists only files with executable code): it selects the tests of the mapped files that reference the
          types it declares.
          A changed file under `test_paths` selects every test of the classes it declares, and tests that are not
          in the map yet (added after it was built) always run. Files outside all paths are ignored.
          With `hot_test_ratio`, a file that (nearly) every test runs selects one test per class instead of all tests;
          use it only when a full run on the base branch catches what that sample misses.
        DETAILS
      end

      def self.return_value
        'Hash with `run_all` (Boolean), `tests` (subset of all_tests, in their order) and `reasons` (Array of String).'
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :all_tests,
            description: 'Every test identifier that could run, e.g. Target/Class/test from retrieve_xctest_names',
            type: Array
          ),
          FastlaneCore::ConfigItem.new(
            key: :coverage_map,
            description: 'Path to the coverage map JSON',
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :coverage_map_artifact,
            description: 'GitHub Actions artifact to download the map from when coverage_map does not exist',
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :coverage_map_branch,
            description: 'Branch whose artifact to download',
            default_value: 'develop'
          ),
          FastlaneCore::ConfigItem.new(
            env_name: 'GITHUB_REPOSITORY',
            key: :github_repository,
            description: 'Repository in "owner/repo" form, for downloading the artifact',
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :changed_files,
            description: 'Changed file paths relative to source_root. When nil, they come from `git diff diff_base...diff_head`',
            type: Array,
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :diff_base,
            description: 'Git revision to diff against. Defaults to the first parent of a pull request merge commit',
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :diff_head,
            description: 'Git revision with the changes',
            default_value: 'HEAD'
          ),
          FastlaneCore::ConfigItem.new(
            key: :source_paths,
            description: 'Path prefixes or globs of the code under test. Unmapped changes here run all tests',
            type: Array,
            default_value: []
          ),
          FastlaneCore::ConfigItem.new(
            key: :test_paths,
            description: 'Path prefixes or globs of the test classes. A change here runs the tests of the classes in the file',
            type: Array,
            default_value: []
          ),
          FastlaneCore::ConfigItem.new(
            key: :ignore_paths,
            description: 'Path prefixes or globs that never affect tests, e.g. code generation configs inside source_paths',
            type: Array,
            default_value: []
          ),
          FastlaneCore::ConfigItem.new(
            key: :run_all_paths,
            description: 'Path prefixes or globs whose change runs all tests, e.g. test helpers, project files, CI config',
            type: Array,
            default_value: []
          ),
          FastlaneCore::ConfigItem.new(
            key: :ignored_diff_lines,
            description: 'Per run_all path or glob, regexes of changed lines that do not affect tests, ' \
                         'e.g. file membership in project.pbxproj. The path runs all tests only if another line changed. ' \
                         'Needs the git diff, so it does not apply to changed_files',
            type: Hash,
            default_value: {}
          ),
          FastlaneCore::ConfigItem.new(
            key: :hot_test_ratio,
            description: 'When a changed file is run by at least this share of the mapped tests (e.g. 0.9), select one ' \
                         'test per class for it instead of all of them. nil selects every test that runs the file',
            type: Float,
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :max_map_age_days,
            description: 'Run all tests when the map is older than this',
            type: Float,
            default_value: 7.0
          ),
          FastlaneCore::ConfigItem.new(
            key: :source_root,
            description: 'Repository root that changed file paths are relative to, the current directory by default ' \
                         '(fastlane runs actions from the repository root)',
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :output_path,
            description: 'Where to write the selection as JSON',
            optional: true
          )
        ]
      end

      def self.example_code
        [
          'selection = select_impacted_tests(
            all_tests: retrieve_xctest_names(xctestrun: xctestrun).values.flatten,
            coverage_map_artifact: "e2e-coverage-map",
            source_paths: ["Sources"],
            test_paths: ["UITests/Tests"],
            run_all_paths: ["UITests/Robots", "Package.swift", ".github/workflows"]
          )
          scan(only_testing: selection["tests"]) unless selection["tests"].empty?'
        ]
      end

      def self.category
        :testing
      end

      def self.is_supported?(platform)
        true
      end
    end
  end
end
