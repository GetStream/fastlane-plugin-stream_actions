require 'json'
require 'tmpdir'

describe Fastlane do
  describe 'Select Impacted Tests Action' do
    let(:action) { Fastlane::Actions::SelectImpactedTestsAction }
    let(:all_tests) do
      [
        'UITests/Messages_Tests/test_send',
        'UITests/Messages_Tests/test_edit',
        'UITests/Reactions_Tests/test_add',
        'UITests/New_Tests/test_new'
      ]
    end
    let(:root) { Dir.mktmpdir }
    let(:map_path) { File.join(root, 'map.json') }
    let(:generated_at) { Time.now.utc.iso8601 }

    before do
      sources = ['Sources/Client.swift', 'Sources/Message.swift', 'Sources/Reaction.swift', 'Sources/Unused.swift']
      tests = {
        'Messages_Tests/test_send' => [0, 1],
        'Messages_Tests/test_edit' => [0, 1],
        'Reactions_Tests/test_add' => [0, 2]
      }
      File.write(map_path, JSON.generate('version' => 1, 'generated_at' => generated_at, 'sources' => sources, 'tests' => tests))
    end

    after { FileUtils.remove_entry(root) }

    def select(changed_files, **options)
      action.run(
        FastlaneCore::Configuration.create(
          action.available_options,
          {
            all_tests: all_tests,
            coverage_map: map_path,
            changed_files: changed_files,
            source_paths: ['Sources'],
            test_paths: ['UITests/Tests'],
            run_all_paths: ['UITests/Robots', '**/*.pbxproj'],
            source_root: root
          }.merge(options)
        )
      )
    end

    it 'selects the tests that executed a changed file' do
      selection = select(['Sources/Reaction.swift'])

      expect(selection['run_all']).to be(false)
      expect(selection['tests']).to eq(['UITests/Reactions_Tests/test_add', 'UITests/New_Tests/test_new'])
    end

    it 'runs one test per class for a file most tests run when hot_test_ratio is set' do
      selection = select(['Sources/Client.swift'], hot_test_ratio: 0.9)

      expect(selection['run_all']).to be(false)
      expect(selection['tests']).to eq(['UITests/Messages_Tests/test_send', 'UITests/Reactions_Tests/test_add', 'UITests/New_Tests/test_new'])
    end

    it 'samples hot files only from the tests that run them' do
      selection = select(['Sources/Message.swift'], hot_test_ratio: 0.6)

      expect(selection['run_all']).to be(false)
      expect(selection['tests']).to eq(['UITests/Messages_Tests/test_send', 'UITests/New_Tests/test_new'])
    end

    it 'runs every test of a file most tests run without hot_test_ratio' do
      expect(select(['Sources/Client.swift'])['tests']).to eq(all_tests)
    end

    it 'always runs tests that are not in the map yet' do
      expect(select(['Sources/Unused.swift'])['tests']).to eq(['UITests/New_Tests/test_new'])
    end

    it 'ignores files outside every path' do
      expect(select(['README.md'])['tests']).to eq(['UITests/New_Tests/test_new'])
    end

    it 'runs every test of a changed test class' do
      FileUtils.mkdir_p(File.join(root, 'UITests/Tests'))
      File.write(File.join(root, 'UITests/Tests/Messages_Tests.swift'), "@MainActor final class Messages_Tests: StreamTestCase {}\n")

      selection = select(['UITests/Tests/Messages_Tests.swift'])

      expect(selection['tests']).to include('UITests/Messages_Tests/test_send', 'UITests/Messages_Tests/test_edit')
      expect(selection['tests']).not_to include('UITests/Reactions_Tests/test_add')
    end

    it 'runs every test of the class a test file extends' do
      FileUtils.mkdir_p(File.join(root, 'UITests/Tests'))
      File.write(File.join(root, 'UITests/Tests/Messages+Editing_Tests.swift'), "extension Messages_Tests {\n  func test_edit() {}\n}\n")

      expect(select(['UITests/Tests/Messages+Editing_Tests.swift'])['tests']).to include('UITests/Messages_Tests/test_send', 'UITests/Messages_Tests/test_edit')
    end

    it 'falls back to the file name for a deleted test class' do
      expect(select(['UITests/Tests/Reactions_Tests.swift'])['tests']).to include('UITests/Reactions_Tests/test_add')
    end

    it 'runs all tests for a run_all path even when ignore_paths also matches it' do
      expect(select(['.github/workflows/smoke.yml'], run_all_paths: ['.github/workflows/smoke.yml'], ignore_paths: ['**/*.yml'])['run_all']).to be(true)
    end

    it 'runs all tests when a run_all path changes' do
      expect(select(['UITests/Robots/UserRobot.swift'])['run_all']).to be(true)
      expect(select(['StreamChat.xcodeproj/project.pbxproj'])['run_all']).to be(true)
    end

    it 'runs all tests for an unmapped source file' do
      selection = select(['Sources/Resources/en.lproj/Localizable.strings'])

      expect(selection['run_all']).to be(true)
      expect(selection['tests']).to eq(all_tests)
    end

    it 'selects the tests of the files using the types of a declaration-only file' do
      FileUtils.mkdir_p(File.join(root, 'Sources'))
      File.write(File.join(root, 'Sources/Reaction.swift'), "func send() -> ReactionPayload { .init() }\n")
      File.write(File.join(root, 'Sources/ReactionPayload.swift'), "@available(iOS 13, *)\npublic struct ReactionPayload: Codable {}\n")

      selection = select(['Sources/ReactionPayload.swift'])

      expect(selection['run_all']).to be(false)
      expect(selection['tests']).to eq(['UITests/Reactions_Tests/test_add', 'UITests/New_Tests/test_new'])
    end

    it 'reads the names of Kotlin enum classes and fun interfaces' do
      FileUtils.mkdir_p(File.join(root, 'Sources'))
      File.write(File.join(root, 'Sources/Reaction.swift'), "val listener: ReactionListener = ReactionListener { ReactionType.LIKE }\n")
      File.write(File.join(root, 'Sources/ReactionType.kt'), "public enum class ReactionType { LIKE }\n\nfun interface ReactionListener {\n  fun onReaction()\n}\n")

      selection = select(['Sources/ReactionType.kt'])

      expect(selection['run_all']).to be(false)
      expect(selection['reasons'].first).to include('ReactionType, ReactionListener')
    end

    it 'reads the names of Dart class modifiers, mixins, typedefs and extension types' do
      FileUtils.mkdir_p(File.join(root, 'Sources'))
      File.write(File.join(root, 'Sources/Reaction.swift'), "ReactionTheme theme; OnReaction callback; ReactionId id; ReactionMixin mixin;\n")
      File.write(File.join(root, 'Sources/reaction_types.dart'), <<~DART)
        abstract interface class ReactionTheme {}
        abstract mixin class ReactionMixin {}
        typedef OnReaction = void Function(String type);
        extension type const ReactionId(String value) {}
      DART

      selection = select(['Sources/reaction_types.dart'])

      expect(selection['run_all']).to be(false)
      expect(selection['reasons'].first).to include('ReactionTheme, ReactionMixin, OnReaction, ReactionId')
    end

    it 'runs all tests for a declaration-only file that no mapped file uses' do
      FileUtils.mkdir_p(File.join(root, 'Sources'))
      File.write(File.join(root, 'Sources/Orphan.swift'), "struct OrphanPayload: Codable {}\n")

      selection = select(['Sources/Orphan.swift'])

      expect(selection['run_all']).to be(true)
      expect(selection['reasons'].first).to include('no mapped file uses OrphanPayload')
    end

    it 'runs all tests for an unmapped code file that declares no types' do
      FileUtils.mkdir_p(File.join(root, 'Sources'))
      File.write(File.join(root, 'Sources/Constants.swift'), "let timeout = 5\n")

      expect(select(['Sources/Constants.swift'])['run_all']).to be(true)
    end

    it 'skips ignore_paths' do
      expect(select(['Sources/.codegen.yml'], ignore_paths: ['**/*.yml'])['tests']).to eq(['UITests/New_Tests/test_new'])
    end

    it 'runs all tests without a map' do
      expect(select(['Sources/Reaction.swift'], coverage_map: File.join(root, 'missing.json'))['run_all']).to be(true)
    end

    context 'with a map without generated_at' do
      before { File.write(map_path, JSON.generate('version' => 1, 'sources' => [], 'tests' => {})) }

      it 'runs all tests' do
        selection = select(['Sources/Reaction.swift'])

        expect(selection['run_all']).to be(true)
        expect(selection['reasons']).to eq(['no coverage map'])
      end
    end

    context 'with a map whose generated_at is not a date' do
      let(:generated_at) { 'yesterday' }

      it 'runs all tests' do
        expect(select(['Sources/Reaction.swift'])['reasons']).to eq(['no coverage map'])
      end
    end

    context 'with a stale map' do
      let(:generated_at) { (Time.now.utc - (10 * 86_400)).iso8601 }

      it 'runs all tests' do
        expect(select(['Sources/Reaction.swift'])['run_all']).to be(true)
      end
    end

    context 'with git' do
      before do
        Dir.chdir(root) do
          system('git init -q && git config user.email a@b.c && git config user.name ci && git config commit.gpgsign false')
          FileUtils.mkdir_p('Sources')
          File.write('Sources/Reaction.swift', 'let a = 1')
          system('git add -A && git commit -qm base && git tag base')
          File.write('Sources/Reaction.swift', 'let a = 2')
          File.write('Sources/Brand_New.swift', 'let b = 1')
          system('git add -A && git commit -qm change')
        end
      end

      it 'ignores run_all files whose changed lines all match ignored_diff_lines' do
        Dir.chdir(root) do
          FileUtils.mkdir_p('App.xcodeproj')
          File.write('App.xcodeproj/project.pbxproj', "membershipExceptions = (\n);\n")
          system('git add -A && git commit -qm project && git tag project')
          File.write('App.xcodeproj/project.pbxproj', "membershipExceptions = (\n\tTests/A_Tests.swift,\n);\n")
          system('git add -A && git commit -qm membership && git tag membership')
          File.write('App.xcodeproj/project.pbxproj', "membershipExceptions = (\n\tTests/A_Tests.swift,\n);\nIPHONEOS_DEPLOYMENT_TARGET = 15.0;\n")
          system('git add -A && git commit -qm setting')
        end
        ignored = { '**/*.pbxproj' => ['^\\s*[^=]+\\.\\w+,$'] }

        expect(select(nil, diff_base: 'project', diff_head: 'membership', ignored_diff_lines: ignored)['run_all']).to be(false)
        expect(select(nil, diff_base: 'membership', ignored_diff_lines: ignored)['run_all']).to be(true)
        expect(select(nil, diff_base: 'project', diff_head: 'membership', ignored_diff_lines: ignored.transform_keys(&:to_sym))['run_all']).to be(false)
      end

      it 'runs all tests for a run_all file whose diff has no changed lines' do
        Dir.chdir(root) do
          FileUtils.mkdir_p('App.xcodeproj')
          File.write('App.xcodeproj/project.pbxproj', "files = (\n);\n")
          system('git add -A && git commit -qm project && git tag project')
          File.chmod(0o755, 'App.xcodeproj/project.pbxproj')
          system('git add -A && git commit -qm mode')
        end
        ignored = { '**/*.pbxproj' => ['^\\s*[^=]+\\.\\w+,$'] }

        expect(select(nil, diff_base: 'project', ignored_diff_lines: ignored)['run_all']).to be(true)
      end

      it 'does not mistake removed lines starting with -- for diff headers' do
        Dir.chdir(root) do
          FileUtils.mkdir_p('Scripts')
          File.write('Scripts/a.lua', "-- comment\n")
          system('git add -A && git commit -qm lua && git tag lua')
          File.write('Scripts/a.lua', "x = 1\n")
          system('git add -A && git commit -qm edit')
        end
        ignored = { 'Scripts/a.lua' => ['^x = \\d+$'] }

        expect(select(nil, diff_base: 'lua', run_all_paths: ['Scripts'], ignored_diff_lines: ignored)['run_all']).to be(true)
      end

      it 'ignores target membership edits in project.pbxproj by default' do
        project = "\t\tA1 /* Exceptions for \"Sources\" folder in \"App\" target */ = {\n" \
                  "\t\t\tisa = PBXFileSystemSynchronizedBuildFileExceptionSet;\n" \
                  "\t\t\tmembershipExceptions = (\n\t\t\t\tOld.swift,\n\t\t\t);\n\t\t\ttarget = B2 /* App */;\n\t\t};\n"
        Dir.chdir(root) do
          FileUtils.mkdir_p('App.xcodeproj')
          File.write('App.xcodeproj/project.pbxproj', "IPHONEOS_DEPLOYMENT_TARGET = 13.0;\n")
          system('git add -A && git commit -qm project && git tag project')
          File.write('App.xcodeproj/project.pbxproj', "IPHONEOS_DEPLOYMENT_TARGET = 13.0;\n#{project}")
          system('git add -A && git commit -qm membership && git tag membership')
          File.write('App.xcodeproj/project.pbxproj', "IPHONEOS_DEPLOYMENT_TARGET = 15.0;\n#{project}")
          system('git add -A && git commit -qm setting')
        end

        expect(select(nil, diff_base: 'project', diff_head: 'membership')['run_all']).to be(false)
        expect(select(nil, diff_base: 'membership')['run_all']).to be(true)
      end

      it 'looks for the users of a declaration-only file at diff_head' do
        Dir.chdir(root) do
          File.write('Sources/ReactionPayload.swift', "struct ReactionPayload {}\n")
          File.write('Sources/Reaction.swift', "let payload = ReactionPayload()\n")
          system('git add -A && git commit -qm payload && git tag payload')
          File.write('Sources/ReactionPayload.swift', "struct ReactionPayload { let type: String }\n")
          system('git add -A && git commit -qm field && git tag field')
          File.write('Sources/Reaction.swift', 'let a = 3')
        end

        selection = select(nil, diff_base: 'payload', diff_head: 'field')

        expect(selection['run_all']).to be(false)
        expect(selection['tests']).to eq(['UITests/Reactions_Tests/test_add', 'UITests/New_Tests/test_new'])
      end

      it 'selects the users of the existing types an added file extends' do
        Dir.chdir(root) do
          File.write('Sources/Reaction.swift', "struct Reaction {}\n")
          system('git add -A && git commit -qm reaction && git tag reaction')
          File.write('Sources/Reaction+Haptics.swift', "extension Reaction {\n  func buzz() {}\n}\n")
          File.write('Sources/Haptics.swift', "struct Haptics {}\nextension Haptics: Equatable {}\n")
          system('git add -A && git commit -qm haptics')
        end

        selection = select(nil, diff_base: 'reaction')

        expect(selection['run_all']).to be(false)
        expect(selection['tests']).to eq(['UITests/Reactions_Tests/test_add', 'UITests/New_Tests/test_new'])
      end

      it 'treats newly added code files as covered by the files that use them' do
        selection = select(nil, diff_base: 'base')

        expect(selection['run_all']).to be(false)
        expect(selection['tests']).to eq(['UITests/Reactions_Tests/test_add', 'UITests/New_Tests/test_new'])
      end
    end
  end
end
