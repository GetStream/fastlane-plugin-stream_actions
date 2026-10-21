require 'json'
require 'open3'
require 'set'
require 'time'
require 'tmpdir'

module Fastlane
  module Actions
    class BuildTestCoverageMapAction < Action
      def self.run(params)
        source_root = File.expand_path(params[:source_root] || Dir.pwd)
        sources, tests =
          if params[:class_dirs]
            jacoco_coverage(params, source_root)
          elsif params[:binaries]
            llvm_coverage(params, source_root)
          else
            lcov_coverage(params, source_root)
          end

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

      # iOS: one folder of .profraw files per test, `<coverage_dir>/<TestClass>/<testMethod>/`.
      def self.llvm_coverage(params, source_root)
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
        [sources, tests]
      end

      # Android: one JaCoCo `.ec` file per test, named `<package>.<TestClass>#<testMethod>.ec` by the test orchestrator.
      def self.jacoco_coverage(params, source_root)
        exec_files = Dir.glob(File.join(params[:coverage_dir], '**', '*.ec'))
        UI.user_error!("No per-test coverage found in '#{params[:coverage_dir]}'") if exec_files.empty?

        class_dirs = params[:class_dirs].select { |dir| File.directory?(dir) }
        UI.user_error!('None of the class_dirs exist') if class_dirs.empty?

        UI.message("Building the coverage map of #{exec_files.size} tests ⌛️")
        cli = params[:jacoco_cli] || download_jacoco_cli
        paths = kotlin_and_java_paths(source_root)
        source_of_class = jacoco_class_sources(cli, class_dirs).transform_values { |key| paths[key] }.compact

        tests = {}
        jacoco_executed_classes(cli, exec_files).each do |file, classes|
          test_class, method = File.basename(file, '.ec').split('#', 2)
          next UI.important("#{File.basename(file)} is not named <TestClass>#<testMethod>.ec, skipping") if method.nil?

          tests["#{test_class.split('.').last}/#{method}"] = classes.flat_map { |name| source_of_class[name].to_a }.uniq
        end
        [source_of_class.values.flatten.uniq, tests]
      end

      # Flutter: one folder of lcov files per test, `<coverage_dir>/<TestFile>/<test description>/`, e.g. from
      # `flutter test --coverage --coverage-path <dir>/lcov.info --name <test>`. lcov lists every library the app loaded,
      # so a file counts as executed when one of its lines has hits.
      def self.lcov_coverage(params, source_root)
        reports = Helper::TestCoverageMapHelper.lcov_reports(params[:coverage_dir])
        UI.user_error!("No per-test coverage found in '#{params[:coverage_dir]}'") if reports.empty?

        UI.message("Building the coverage map of #{reports.size} tests ⌛️")
        base_dir = File.expand_path(params[:lcov_base_dir] || source_root)
        sources = []
        tests = reports.transform_values do |files|
          files = files.map { |file, executed| [relative_path(File.expand_path(file, base_dir), source_root), executed] }.reject { |file, _| file.nil? }
          sources |= files.map(&:first)
          files.select(&:last).map(&:first).uniq
        end
        [sources, tests]
      end

      # Class name => `<package path>/<source file name>`, from an XML report of the class files without execution data.
      # Classes without code (interfaces, annotations, constants) are empty `<class/>` elements and stay out, like
      # declaration-only files in llvm-cov. One report per folder, as JaCoCo fails on a class name that two folders
      # define differently (e.g. a stale build).
      def self.jacoco_class_sources(cli, class_dirs)
        Dir.mktmpdir('jacoco') do |dir|
          xml = File.join(dir, 'classes.xml')
          class_dirs.each_with_object({}) do |class_dir, sources|
            Helper::TestCoverageMapHelper.command('java', '-jar', cli, 'report', '--classfiles', class_dir, '--xml', xml, '--quiet')
            File.read(xml).scan(/<class name="([^"]+)" sourcefilename="([^"]+)">/).each do |name, source|
              sources[name] ||= "#{File.dirname(name)}/#{source}"
            end
          end
        end
      end

      # Exec file => names of the classes with at least one executed probe.
      def self.jacoco_executed_classes(cli, exec_files)
        exec_files.each_slice(100).with_object({}) do |slice, result|
          current = nil
          Helper::TestCoverageMapHelper.command('java', '-jar', cli, 'execinfo', *slice).each_line do |line|
            if (loaded = line[/\[INFO\] Loading exec file (.+)\.$/, 1])
              current = result[loaded] = []
            elsif current && (hit = line.match(/^\h+\s+(\d+) of\s+\d+\s+(\S+)$/)) && hit[1].to_i.positive?
              current << hit[2]
            end
          end
        end
      end

      # `<package path>/<file name>` => repository paths of the tracked Kotlin and Java files. The package comes from the
      # file, as a Kotlin file does not have to sit in the folder of its package.
      def self.kotlin_and_java_paths(source_root)
        files = Helper::TestCoverageMapHelper.command('git', '-C', source_root, 'ls-files', '*.kt', '*.java').split("\n")
        files.each_with_object({}) do |file, paths|
          package = File.foreach(File.join(source_root, file)).lazy.map { |line| line[/^\s*package\s+([\w.]+)/, 1] }.find(&:itself)
          (paths["#{package.to_s.tr('.', '/')}/#{File.basename(file)}".delete_prefix('/')] ||= []) << file
        end
      end

      def self.download_jacoco_cli
        version = '0.8.13'
        path = File.join(Dir.tmpdir, "jacococli-#{version}.jar")
        return path if File.exist?(path)

        url = "https://repo1.maven.org/maven2/org/jacoco/org.jacoco.cli/#{version}/org.jacoco.cli-#{version}-nodeps.jar"
        Helper::TestCoverageMapHelper.command('curl', '-sSfL', '-o', "#{path}.part", url)
        File.rename("#{path}.part", path)
        path
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
        'Builds a map of which source files every test executes, from per-test LLVM, JaCoCo or lcov coverage'
      end

      def self.details
        <<~DETAILS
          iOS: expects one folder per test, `<coverage_dir>/<TestClass>/<testMethod>/`, holding the `.profraw` files
          the app wrote while that test ran (e.g. via `LLVM_PROFILE_FILE=<dir>/<TestClass>/<testMethod>/%m_%p%c.profraw`
          in the app's launch environment). Each folder is merged with `llvm-profdata` and exported with `llvm-cov`
          against the instrumented `binaries`.

          Android: pass `class_dirs` instead of `binaries`, and a `coverage_dir` holding one JaCoCo `.ec` file per test,
          `<package>.<TestClass>#<testMethod>.ec`, which the test orchestrator writes with `-e coverage true
          -e coverageFilePath <dir>/`. A source file counts as executed when one of its classes ran a probe.

          Flutter: pass neither, and a `coverage_dir` with one folder of lcov `.info` files per test, `<TestFile>/<test>/`,
          e.g. from `flutter test --coverage --name <test>`. A source file counts as executed when one of its lines has hits.

          The resulting JSON map feeds `select_impacted_tests`.
        DETAILS
      end

      def self.return_value
        'Hash with `version`, `generated_at`, `commit`, `sources` (every instrumented file) and `tests` (`Class/test` => covered files).'
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :coverage_dir,
            description: 'Folder with per-test coverage: <TestClass>/<testMethod>/*.profraw (iOS), *.ec files (Android) ' \
                         'or <TestFile>/<test>/*.info (Flutter)',
            verify_block: proc { |path| UI.user_error!("Coverage folder '#{path}' does not exist") unless File.directory?(path) }
          ),
          FastlaneCore::ConfigItem.new(
            key: :binaries,
            description: 'Instrumented binaries the profiles belong to, e.g. the app executable (or its .debug.dylib) and every SDK framework',
            type: Array,
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :class_dirs,
            description: 'Android: folders with the compiled classes of the app and its modules. Switches to JaCoCo coverage',
            type: Array,
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :jacoco_cli,
            description: 'Android: path to the JaCoCo CLI jar (org.jacoco.cli nodeps). Downloaded when not set',
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :lcov_base_dir,
            description: 'Flutter: folder that relative lcov SF paths start from (the package that ran the tests), source_root by default',
            optional: true
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
          )',
          'build_test_coverage_map(
            coverage_dir: "coverage",
            class_dirs: Dir.glob("*/build/intermediates/classes/debug/**/dirs"),
            output_path: "e2e_coverage_map.json"
          )'
        ]
      end

      def self.category
        :testing
      end

      def self.is_supported?(platform)
        [:ios, :mac, :android].include?(platform)
      end
    end
  end
end
