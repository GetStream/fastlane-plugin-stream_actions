require 'json'
require 'tmpdir'

describe Fastlane do
  describe 'Build Test Coverage Map Action' do
    let(:action) { Fastlane::Actions::BuildTestCoverageMapAction }
    let(:root) { Dir.mktmpdir }
    let(:previous_map) { File.join(root, 'previous.json') }
    let(:tests) { { 'Messages_Tests/test_send' => ['Sources/Client.swift'] } }
    let(:sources) { ['Sources/Client.swift'] }

    after { FileUtils.remove_entry(root) }

    def carry_over
      action.carry_over_failed_tests(tests, sources, previous_map: previous_map, failed_tests: ['UITests/Messages_Tests/test_send'])
    end

    it 'keeps the previous coverage of a failed test' do
      File.write(previous_map, JSON.generate('version' => 1, 'generated_at' => Time.now.utc.iso8601,
                                             'sources' => ['Sources/Client.swift', 'Sources/Message.swift'],
                                             'tests' => { 'Messages_Tests/test_send' => [0, 1] }))

      carry_over

      expect(tests['Messages_Tests/test_send']).to eq(['Sources/Client.swift', 'Sources/Message.swift'])
      expect(sources).to eq(['Sources/Client.swift', 'Sources/Message.swift'])
    end

    it 'drops a failed test from the map when the previous map is unreadable' do
      File.write(previous_map, JSON.generate('version' => 1, 'generated_at' => 'yesterday', 'sources' => [], 'tests' => {}))

      expect { carry_over }.not_to raise_error
      expect(tests).to be_empty
      expect(sources).to eq(['Sources/Client.swift'])
    end

    it 'drops a failed test from the map when the previous map is missing' do
      carry_over

      expect(tests).to be_empty
    end

    describe 'JaCoCo coverage' do
      let(:helper) { Fastlane::Helper::TestCoverageMapHelper }
      let(:coverage_dir) { File.join(root, 'coverage') }
      let(:class_dir) { File.join(root, 'classes') }

      before do
        FileUtils.mkdir_p([coverage_dir, class_dir, File.join(root, 'sdk/src/main/java/io/sdk')])
        File.write(File.join(root, 'sdk/src/main/java/io/sdk/Client.kt'), "package io.sdk\n\nclass Client\n")
        File.write(File.join(root, 'sdk/src/main/java/io/sdk/Models.kt'), "// Moved out of io/sdk/models\npackage io.sdk.models\n\ndata class Message(val id: String)\n")
        File.write(File.join(root, 'sdk/src/main/java/io/sdk/Ui.kt'), "package io.sdk\n\nfun render() = Unit\n")
        File.write(File.join(coverage_dir, 'io.app.tests.MessagesTests#test_send.ec'), '')
        File.write(File.join(coverage_dir, 'io.app.tests.MessagesTests#test_edit.ec'), '')
        File.write(File.join(coverage_dir, 'merged.ec'), '')

        allow(helper).to receive(:command).and_call_original
        allow(helper).to receive(:command).with('git', '-C', root, 'ls-files', '*.kt', '*.java')
                                          .and_return("sdk/src/main/java/io/sdk/Client.kt\nsdk/src/main/java/io/sdk/Models.kt\nsdk/src/main/java/io/sdk/Ui.kt\n")
        allow(helper).to receive(:command).with('java', '-jar', 'cli.jar', 'report', '--classfiles', class_dir, '--xml', anything, '--quiet') do |*args|
          File.write(args[-2], '<report><package name="io/sdk"><class name="io/sdk/Client" sourcefilename="Client.kt"><method/></class>' \
                               '<class name="io/sdk/Client$Companion" sourcefilename="Client.kt"><method/></class>' \
                               '<class name="io/sdk/UiKt" sourcefilename="Ui.kt"><method/></class>' \
                               '<class name="io/sdk/Generated" sourcefilename="Generated.kt"><method/></class>' \
                               '<class name="io/sdk/Listener" sourcefilename="Client.kt"/></package>' \
                               '<package name="io/sdk/models"><class name="io/sdk/models/Message" sourcefilename="Models.kt"><method/></class></package></report>')
          ''
        end
        allow(helper).to receive(:command).with('java', '-jar', 'cli.jar', 'execinfo', *Dir.glob(File.join(coverage_dir, '**', '*.ec'))) do |*args|
          args.drop(4).map do |file|
            classes =
              case File.basename(file)
              when /test_send/ then ['1db3754e97473fbe   12 of  47   io/sdk/Client$Companion', '7b2dc122b6180c11    3 of  27   io/sdk/models/Message']
              when /test_edit/ then ['1db3754e97473fbe    0 of  47   io/sdk/Client', 'a6c1f0095dd1912a  139 of 165   io/sdk/UiKt']
              else []
              end
            ["[INFO] Loading exec file #{file}.", 'CLASS ID         HITS/PROBES   CLASS NAME', 'Session "host": Tue Oct 20 - Tue Oct 20', *classes].join("\n")
          end.join("\n")
        end
      end

      def build
        action.run(FastlaneCore::Configuration.create(action.available_options, {
          coverage_dir: coverage_dir, class_dirs: [class_dir, File.join(root, 'missing')], jacoco_cli: 'cli.jar',
          source_root: root, output_path: File.join(root, 'map.json'), commit: 'abc'
        }))
      end

      it 'maps every test to the tracked source files of the classes it executed' do
        map = build

        expect(map['tests']).to eq(
          'MessagesTests/test_edit' => ['sdk/src/main/java/io/sdk/Ui.kt'],
          'MessagesTests/test_send' => ['sdk/src/main/java/io/sdk/Client.kt', 'sdk/src/main/java/io/sdk/Models.kt']
        )
        expect(map['sources']).to eq(['sdk/src/main/java/io/sdk/Client.kt', 'sdk/src/main/java/io/sdk/Models.kt', 'sdk/src/main/java/io/sdk/Ui.kt'])
      end

      it 'writes a map select_impacted_tests reads' do
        build

        expect(helper.read_map(File.join(root, 'map.json'))['tests']['MessagesTests/test_edit']).to eq(['sdk/src/main/java/io/sdk/Ui.kt'])
      end
    end

    describe 'lcov coverage' do
      let(:helper) { Fastlane::Helper::TestCoverageMapHelper }
      let(:coverage_dir) { File.join(root, 'build/e2e-coverage') }

      before do
        send_dir = File.join(coverage_dir, 'messages_test', 'user sends a message')
        react_dir = File.join(coverage_dir, 'reactions_test', 'user adds a reaction')
        FileUtils.mkdir_p([send_dir, react_dir, File.join(coverage_dir, 'reactions_test', 'skipped')])
        File.write(File.join(send_dir, 'lcov.info'), <<~LCOV)
          SF:lib/app.dart
          DA:3,1
          end_of_record
          SF:../packages/sdk/lib/client.dart
          DA:10,0
          DA:11,4
          end_of_record
          SF:../packages/sdk/lib/reaction.dart
          DA:7,0
          end_of_record
          SF:/elsewhere/pub-cache/http.dart
          DA:1,9
          end_of_record
        LCOV
        File.write(File.join(react_dir, 'lcov.info'), "SF:lib/app.dart\nDA:3,2\nend_of_record\nSF:../packages/sdk/lib/reaction.dart\nDA:7,1\nend_of_record\n")

        allow(helper).to receive(:command).and_call_original
        allow(helper).to receive(:command).with('git', '-C', root, 'ls-files')
                                          .and_return("sample_app/lib/app.dart\npackages/sdk/lib/client.dart\npackages/sdk/lib/reaction.dart\n")
      end

      def build
        action.run(FastlaneCore::Configuration.create(action.available_options, {
          coverage_dir: coverage_dir, lcov_base_dir: File.join(root, 'sample_app'),
          source_root: root, output_path: File.join(root, 'map.json'), commit: 'abc'
        }))
      end

      it 'maps every test to the repository files with executed lines' do
        map = build

        expect(map['tests']).to eq(
          'messages_test/user sends a message' => ['sample_app/lib/app.dart', 'packages/sdk/lib/client.dart'],
          'reactions_test/user adds a reaction' => ['sample_app/lib/app.dart', 'packages/sdk/lib/reaction.dart']
        )
        expect(map['sources']).to eq(['packages/sdk/lib/client.dart', 'packages/sdk/lib/reaction.dart', 'sample_app/lib/app.dart'])
      end
    end

    it 'drops a failed test the previous map does not have' do
      File.write(previous_map, JSON.generate('version' => 1, 'generated_at' => Time.now.utc.iso8601, 'sources' => [], 'tests' => {}))

      carry_over

      expect(tests).to be_empty
    end
  end
end
