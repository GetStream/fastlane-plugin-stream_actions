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

      it 'always requires the check when force_check is set, without inspecting files' do
        allow(Fastlane::Actions).to receive(:sh)

        result = described_class.new.parse("lane :test do
          is_check_required(sources: #{test_sources}, github_pr_num: '0', force_check: true)
        end").runner.execute(:test)

        expect(result).to be(true)
        expect(Fastlane::Actions).not_to have_received(:sh)
      end

      it 'requires the check when more than 99 files changed, regardless of sources' do
        allow(Fastlane::Actions).to receive(:sh).and_return((1..100).map { |i| "#{unexpected_path}#{i}" }.join("\n"))

        result = described_class.new.parse("lane :test do
          is_check_required(sources: #{test_sources}, github_pr_num: '0')
        end").runner.execute(:test)

        expect(result).to be(true)
      end

      it 'falls back to the full PR file list when before/after are not valid SHAs' do
        allow(Fastlane::Actions).to receive(:sh).and_return("test1/foo\n")

        described_class.new.parse("lane :test do
          is_check_required(
            sources: #{test_sources},
            github_pr_num: '0',
            github_event_action: 'synchronize',
            github_event_before: '#{'0' * 40}',
            github_event_after: '#{'b' * 40}',
            github_repository: 'o/r'
          )
        end").runner.execute(:test)

        expect(Fastlane::Actions).to have_received(:sh).once
        expect(Fastlane::Actions).to have_received(:sh).with(a_string_including('gh pr view'))
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

      it 'skips when a later same-source commit re-verified after the sources commit failed' do
        stub_history_sh(
          compare: "CHANGELOG.md\n",
          commits: "sourcessha\nchangelogsha\n",
          files: { 'changelogsha' => "CHANGELOG.md\n", 'sourcessha' => "test1/foo.swift\n" },
          checks: {
            # The sources commit failed, but the later CHANGELOG-only commit re-ran the same sources green.
            'sourcessha' => "Test\tfailure\t2024-01-01T00:00:00Z\nBuild\tsuccess\t2024-01-01T00:00:00Z\n",
            'changelogsha' => "Test\tsuccess\t2024-01-02T00:00:00Z\nBuild\tsuccess\t2024-01-02T00:00:00Z\n"
          }
        )

        expect(run_history_action).to be(false)
      end

      it 'runs when neither the sources commit nor any later commit passed' do
        stub_history_sh(
          compare: "CHANGELOG.md\n",
          commits: "sourcessha\nchangelogsha\n",
          files: { 'changelogsha' => "CHANGELOG.md\n", 'sourcessha' => "test1/foo.swift\n" },
          checks: {
            'sourcessha' => "Test\tfailure\t2024-01-01T00:00:00Z\nBuild\tsuccess\t2024-01-01T00:00:00Z\n",
            'changelogsha' => "Test\tfailure\t2024-01-02T00:00:00Z\nBuild\tsuccess\t2024-01-02T00:00:00Z\n"
          }
        )

        expect(run_history_action).to be(true)
      end

      it 'runs when the sources commit was cancelled' do
        stub_history_sh(
          compare: "CHANGELOG.md\n",
          commits: "sourcessha\nchangelogsha\n",
          files: { 'changelogsha' => "CHANGELOG.md\n", 'sourcessha' => "test1/foo.swift\n" },
          checks: {
            'sourcessha' => "Test\tcancelled\t2024-01-01T00:00:00Z\nBuild\tsuccess\t2024-01-01T00:00:00Z\n"
          }
        )

        expect(run_history_action).to be(true)
      end

      it 'runs when the sources commit and every later commit were cancelled' do
        stub_history_sh(
          compare: "CHANGELOG.md\n",
          commits: "sourcessha\nchangelogcancel\nchangelogsha\n",
          files: {
            'changelogsha' => "CHANGELOG.md\n",
            'changelogcancel' => "CHANGELOG.md\n",
            'sourcessha' => "test1/foo.swift\n"
          },
          checks: {
            'sourcessha' => "Test\tcancelled\t2024-01-01T00:00:00Z\nBuild\tsuccess\t2024-01-01T00:00:00Z\n",
            'changelogcancel' => "Test\tcancelled\t2024-01-02T00:00:00Z\nBuild\tsuccess\t2024-01-02T00:00:00Z\n"
          }
        )

        expect(run_history_action).to be(true)
      end

      it 'runs when the latest sources commit failed even though an older sources commit passed' do
        stub_history_sh(
          compare: "CHANGELOG.md\n",
          # oldest first: sources passed, then sources changed again and failed, then a CHANGELOG-only push.
          commits: "srcpass\nsrcfail\nchangelogsha\n",
          files: {
            'changelogsha' => "CHANGELOG.md\n",
            'srcfail' => "test1/foo.swift\n",
            'srcpass' => "test1/foo.swift\n"
          },
          checks: {
            # The older passing run verified different (superseded) sources, so it must be ignored.
            'srcpass' => "Test\tsuccess\t2024-01-01T00:00:00Z\nBuild\tsuccess\t2024-01-01T00:00:00Z\n",
            'srcfail' => "Test\tfailure\t2024-01-02T00:00:00Z\nBuild\tsuccess\t2024-01-02T00:00:00Z\n"
          }
        )

        expect(run_history_action).to be(true)
      end

      it 'runs when a required check never ran on the sources commit' do
        stub_history_sh(
          compare: "CHANGELOG.md\n",
          commits: "sourcessha\nchangelogsha\n",
          files: { 'changelogsha' => "CHANGELOG.md\n", 'sourcessha' => "test1/foo.swift\n" },
          checks: {
            # Only "Build" ran; the required "Test" check is absent, so the sources are not fully verified.
            'sourcessha' => "Build\tsuccess\t2024-01-01T00:00:00Z\n"
          }
        )

        expect(run_history_action).to be(true)
      end

      it 'runs when the repository is unknown so previous runs cannot be verified' do
        allow(Fastlane::Actions).to receive(:sh).and_return("CHANGELOG.md\n")
        # GitHub Actions always sets GITHUB_REPOSITORY, so force the "no repository" condition explicitly.
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('GITHUB_REPOSITORY').and_return(nil)

        result = described_class.new.parse("lane :test do
          is_check_required(
            sources: #{test_sources},
            github_pr_num: '0',
            required_checks: ['Test', 'Build']
          )
        end").runner.execute(:test)

        expect(result).to be(true)
      end

      it 'runs when the PR commit list cannot be read' do
        stub_history_sh(
          compare: "CHANGELOG.md\n",
          commits: "\n",
          files: {},
          checks: {}
        )

        expect(run_history_action).to be(true)
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
