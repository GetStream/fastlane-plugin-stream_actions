describe Fastlane do
  describe Fastlane::FastFile do
    describe 'Is Check Required Action' do
      let(:test_sources) { ['test1', 'test2'] }
      let(:happy_path) { "#{test_sources.first}/some_path" }
      let(:unexpected_path) { "some/path/" }

      it 'passes an empty string instead of github_pr_num' do
        result = described_class.new.parse("lane :test do
          is_check_required(sources: #{test_sources}, github_pr_num: '')
        end").runner.execute(:test)

        expect(result).to be(true)
      end

      it 'passes a nil instead of github_pr_num' do
        result = described_class.new.parse("lane :test do
          is_check_required(sources: #{test_sources}, github_pr_num: nil)
        end").runner.execute(:test)

        expect(result).to be(true)
      end

      it 'raises an error after providing an empty array instead of list of sources' do
        expect do
          described_class.new.parse("lane :test do
            is_check_required(sources: [], github_pr_num: '0')
          end").runner.execute(:test)
        end.to raise_error('Sources have to be specified')
      end

      it 'expects that checks are required' do
        allow(Fastlane::Actions).to receive(:sh).and_return(happy_path)

        result = described_class.new.parse("lane :test do
          is_check_required(sources: #{test_sources}, github_pr_num: '0')
        end").runner.execute(:test)

        expect(result).to be(true)
      end

      it 'expects that checks are not required' do
        allow(Fastlane::Actions).to receive(:sh).and_return(unexpected_path)

        result = described_class.new.parse("lane :test do
          is_check_required(sources: #{test_sources}, github_pr_num: '0')
        end").runner.execute(:test)

        expect(result).to be(false)
      end

      it 'on synchronize, lists files from compare between before and after' do
        b = "a" * 40
        c = "b" * 40
        allow(Fastlane::Actions).to receive(:sh).and_return("test1/foo\n")

        described_class.new.parse("lane :test do
          is_check_required(
            sources: #{test_sources},
            github_pr_num: '0',
            github_event_action: 'synchronize',
            github_event_before: '#{b}',
            github_event_after: '#{c}',
            github_repository: 'o/r'
          )
        end").runner.execute(:test)

        expect(Fastlane::Actions).to have_received(:sh).once
        expect(Fastlane::Actions).to have_received(:sh).with(
          a_string_including("repos/o/r/compare/#{b}...#{c}")
        )
      end

      def stub_history_sh(compare:, commits:, files:, checks:)
        allow(Fastlane::Actions).to receive(:sh) do |cmd|
          if cmd.include?('compare')
            compare
          elsif cmd.include?('pr view')
            commits
          elsif cmd.include?('check-runs')
            checks[files.keys.find { |s| cmd.include?(s) }].to_s
          elsif cmd.include?('/commits/')
            files[files.keys.find { |s| cmd.include?(s) }].to_s
          else
            ''
          end
        end
      end

      def run_history_action
        described_class.new.parse("lane :test do
          is_check_required(
            sources: #{test_sources},
            github_pr_num: '0',
            required_checks: ['Test', 'Build'],
            github_event_action: 'synchronize',
            github_event_before: '#{'a' * 40}',
            github_event_after: '#{'d' * 40}',
            github_repository: 'o/r'
          )
        end").runner.execute(:test)
      end

      it 'skips when the last sources commit passed all required checks' do
        stub_history_sh(
          compare: "CHANGELOG.md\n",
          commits: "sourcessha\nchangelogsha\n", # gh returns oldest first
          files: { 'changelogsha' => "CHANGELOG.md\n", 'sourcessha' => "test1/foo.swift\n" },
          checks: {
            'sourcessha' => "Test\tsuccess\t2024-01-02T00:00:00Z\nBuild\tsuccess\t2024-01-02T00:00:00Z\n"
          }
        )

        expect(run_history_action).to be(false)
      end

      it 'runs when the last sources commit failed a required check' do
        stub_history_sh(
          compare: "CHANGELOG.md\n",
          commits: "sourcessha\nchangelogsha\n",
          files: { 'changelogsha' => "CHANGELOG.md\n", 'sourcessha' => "test1/foo.swift\n" },
          checks: {
            'sourcessha' => "Test\tfailure\t2024-01-02T00:00:00Z\nBuild\tsuccess\t2024-01-02T00:00:00Z\n"
          }
        )

        expect(run_history_action).to be(true)
      end

      it 'runs when a required check was skipped on the last sources commit' do
        stub_history_sh(
          compare: "CHANGELOG.md\n",
          commits: "sourcessha\nchangelogsha\n",
          files: { 'changelogsha' => "CHANGELOG.md\n", 'sourcessha' => "test1/foo.swift\n" },
          checks: {
            'sourcessha' => "Test\tskipped\t2024-01-02T00:00:00Z\nBuild\tsuccess\t2024-01-02T00:00:00Z\n"
          }
        )

        expect(run_history_action).to be(true)
      end

      it 'uses the latest run of a re-run check' do
        stub_history_sh(
          compare: "CHANGELOG.md\n",
          commits: "sourcessha\nchangelogsha\n",
          files: { 'changelogsha' => "CHANGELOG.md\n", 'sourcessha' => "test1/foo.swift\n" },
          checks: {
            'sourcessha' => "Test\tfailure\t2024-01-01T00:00:00Z\nTest\tsuccess\t2024-01-02T00:00:00Z\n" \
                            "Build\tsuccess\t2024-01-02T00:00:00Z\n"
          }
        )

        expect(run_history_action).to be(false)
      end

      it 'skips when no commit in the PR changed sources' do
        stub_history_sh(
          compare: "CHANGELOG.md\n",
          commits: "readmesha\nchangelogsha\n",
          files: { 'changelogsha' => "CHANGELOG.md\n", 'readmesha' => "README.md\n" },
          checks: {}
        )

        expect(run_history_action).to be(false)
      end
    end
  end
end
