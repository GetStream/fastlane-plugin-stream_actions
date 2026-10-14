require 'json'
require 'open3'
require 'set'
require 'time'

module Fastlane
  module Actions
    class BuildTestCoverageMapAction < Action
      def self.run(params)
        source_root = File.expand_path(params[:source_root] || Dir.pwd)
        test_dirs = Dir.glob(File.join(params[:coverage_dir], '*', '*')).select { |dir| File.directory?(dir) }
        UI.user_error!("No per-test coverage found in '#{params[:coverage_dir]}'") if test_dirs.empty?

        binaries = params[:binaries].select { |binary| File.exist?(binary) }
        UI.user_error!('None of the instrumented binaries exist') if binaries.empty?

        UI.message("Building the coverage map of #{test_dirs.size} tests ⌛️")
        sources = []
        tests = {}
        lock = Mutex.new
        queue = Queue.new
        test_dirs.each { |dir| queue << dir }

        workers = Array.new([params[:jobs], test_dirs.size].min) do
          Thread.new do
            until queue.empty?
              dir = begin
                queue.pop(true)
              rescue ThreadError
                break
              end
              test = dir.split('/').last(2).join('/')
              report = coverage_report(dir, binaries)
              next if report.nil?

              lock.synchronize do
                sources |= report[:all].map { |file| relative_path(file, source_root) }.compact
                tests[test] = report[:covered].map { |file| relative_path(file, source_root) }.compact
              end
            end
          end
        end
        workers.each(&:join)

        carry_over_failed_tests(tests, sources, params) unless params[:failed_tests].to_a.empty?
        drop_untracked(tests, sources, source_root)

        map = {
          'version' => Helper::TestCoverageMapHelper::MAP_VERSION,
          'generated_at' => Time.now.utc.iso8601,
          'commit' => params[:commit],
          'sources' => sources.sort,
          'tests' => tests.sort.to_h
        }
        write(map, params[:output_path])
        UI.success("Coverage map of #{tests.size} tests and #{map['sources'].size} sources saved to #{params[:output_path]}")
        map
      end

      # Returns the instrumented files (`all`) and the files with at least one executed line (`covered`).
      def self.coverage_report(dir, binaries)
        profiles = Dir.glob(File.join(dir, '**', '*.profraw'))
        if profiles.empty?
          UI.important("No profiles in #{dir}, skipping")
          return nil
        end

        profdata = File.join(dir, 'merged.profdata')
        _, err, status = Open3.capture3('xcrun', 'llvm-profdata', 'merge', '-sparse', *profiles, '-o', profdata)
        unless status.success?
          UI.important("Could not merge the profiles in #{dir}: #{err}")
          return nil
        end

        objects = binaries.drop(1).flat_map { |binary| ['-object', binary] }
        out, err, status = Open3.capture3(
          'xcrun', 'llvm-cov', 'export', '-format=text', '-summary-only',
          "-instr-profile=#{profdata}", binaries.first, *objects
        )
        unless status.success?
          UI.important("Could not export the coverage of #{dir}: #{err}")
          return nil
        end

        files = JSON.parse(out).fetch('data').flat_map { |data| data.fetch('files') }
        {
          all: files.map { |file| file['filename'] },
          covered: files.select { |file| file.dig('summary', 'lines', 'covered').to_i.positive? }.map { |file| file['filename'] }
        }
      end

      # A failed test stops early, so its fresh coverage can miss code it normally runs. Without its previous
      # coverage the test leaves the map, and select_impacted_tests runs tests that are not in the map every time.
      def self.carry_over_failed_tests(tests, sources, params)
        previous = previous_map(params)
        params[:failed_tests].to_a.each do |failed_test|
          test = failed_test.split('/').last(2).join('/')
          previous_files = previous && previous['tests'][test]
          if previous_files.nil?
            tests.delete(test)
            UI.important("No previous coverage of the failed #{test}, so it runs on every pull request until it passes")
            next
          end

          tests[test] = (tests[test].to_a | previous_files)
          sources.concat(previous_files - sources)
          UI.message("Kept the previous coverage of the failed #{test}")
        end
      end

      def self.previous_map(params)
        path = params[:previous_map]
        if path.nil? && params[:previous_map_artifact]
          path = Helper::TestCoverageMapHelper.download_map(
            coverage_map_artifact: params[:previous_map_artifact],
            coverage_map_branch: params[:previous_map_branch],
            github_repository: params[:github_repository]
          )
        end
        return nil if path.nil? || !File.exist?(path)

        Helper::TestCoverageMapHelper.read_map(path)
      rescue StandardError => e
        UI.important("Could not read the previous coverage map: #{e.message}")
        nil
      end

      # Keeps sources the repository tracks, dropping e.g. package checkouts cloned inside it.
      def self.drop_untracked(tests, sources, source_root)
        tracked = Helper::TestCoverageMapHelper.command('git', '-C', source_root, 'ls-files').split("\n").to_set
        sources.select! { |file| tracked.include?(file) }
        tests.each_value { |files| files.select! { |file| tracked.include?(file) } }
      rescue StandardError => e
        UI.important("Could not list the tracked files, keeping every source: #{e.message}")
      end

      def self.relative_path(file, source_root)
        return nil unless file.start_with?("#{source_root}/")

        file.delete_prefix("#{source_root}/")
      end

      # Stores file indices instead of paths, which keeps the map an order of magnitude smaller.
      def self.write(map, path)
        index = map['sources'].each_with_index.to_h
        compact = map.merge('tests' => map['tests'].transform_values { |files| files.map { |file| index.fetch(file) }.sort })
        File.write(path, JSON.generate(compact))
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        'Builds a map of which source files every test executes, from per-test LLVM coverage profiles'
      end

      def self.details
        <<~DETAILS
          Expects one folder per test, `<coverage_dir>/<TestClass>/<testMethod>/`, holding the `.profraw` files
          the app wrote while that test ran (e.g. via `LLVM_PROFILE_FILE=<dir>/<TestClass>/<testMethod>/%m_%p%c.profraw`
          in the app's launch environment). Each folder is merged with `llvm-profdata` and exported with `llvm-cov`
          against the instrumented `binaries`. The resulting JSON map feeds `select_impacted_tests`.
        DETAILS
      end

      def self.return_value
        'Hash with `version`, `generated_at`, `commit`, `sources` (every instrumented file) and `tests` (`Class/test` => covered files).'
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :coverage_dir,
            description: 'Folder with per-test profiles, laid out as <TestClass>/<testMethod>/*.profraw',
            verify_block: proc { |path| UI.user_error!("Coverage folder '#{path}' does not exist") unless File.directory?(path) }
          ),
          FastlaneCore::ConfigItem.new(
            key: :binaries,
            description: 'Instrumented binaries the profiles belong to, e.g. the app executable (or its .debug.dylib) and every SDK framework',
            type: Array
          ),
          FastlaneCore::ConfigItem.new(
            key: :source_root,
            description: 'Repository root, the current directory by default (fastlane runs actions from the repository root). ' \
                         'Paths in the map are relative to it, and files outside it (e.g. SPM checkouts) are dropped',
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :output_path,
            description: 'Where to write the JSON map'
          ),
          FastlaneCore::ConfigItem.new(
            key: :commit,
            description: 'Commit the map was built from',
            optional: true,
            default_value: ENV['GITHUB_SHA']
          ),
          FastlaneCore::ConfigItem.new(
            key: :previous_map,
            description: 'Previous map to take the coverage of failed_tests from, as a failed test stops before running all of its code',
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :previous_map_artifact,
            description: 'GitHub Actions artifact to download the previous map from when previous_map is not set',
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :previous_map_branch,
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
            key: :failed_tests,
            description: 'Tests that failed in this run, as Class/test or Target/Class/test. Each takes its previous coverage, ' \
                         'or leaves the map when there is none',
            type: Array,
            optional: true,
            default_value: []
          ),
          FastlaneCore::ConfigItem.new(
            key: :jobs,
            description: 'How many tests to process in parallel',
            type: Integer,
            default_value: 8
          )
        ]
      end

      def self.example_code
        [
          'build_test_coverage_map(
            coverage_dir: "test_output/coverage",
            binaries: ["App.app/App.debug.dylib", "App.app/Frameworks/SDK.framework/SDK"],
            output_path: "test_output/e2e_coverage_map.json"
          )'
        ]
      end

      def self.category
        :testing
      end

      def self.is_supported?(platform)
        [:ios, :mac].include?(platform)
      end
    end
  end
end
