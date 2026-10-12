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
      File.write(File.join(root, 'UITests/Tests/Messages_Tests.swift'), "final class Messages_Tests: StreamTestCase {}\n")

      selection = select(['UITests/Tests/Messages_Tests.swift'])

      expect(selection['tests']).to include('UITests/Messages_Tests/test_send', 'UITests/Messages_Tests/test_edit')
      expect(selection['tests']).not_to include('UITests/Reactions_Tests/test_add')
    end

    it 'falls back to the file name for a deleted test class' do
      expect(select(['UITests/Tests/Reactions_Tests.swift'])['tests']).to include('UITests/Reactions_Tests/test_add')
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
      end

      it 'treats newly added code files as covered by the files that use them' do
        selection = select(nil, diff_base: 'base')

        expect(selection['run_all']).to be(false)
        expect(selection['tests']).to eq(['UITests/Reactions_Tests/test_add', 'UITests/New_Tests/test_new'])
      end
    end
  end
end
