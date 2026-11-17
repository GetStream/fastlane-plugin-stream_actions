describe Fastlane do
  describe Fastlane::FastFile do
    describe 'Show SDK Size Action' do
      let(:benchmark) { { 'develop' => { 'js_bundle_size' => 2000.0 } } }

      before do
        allow(Fastlane::Actions).to receive(:sh)
        allow(FileUtils).to receive(:remove_dir)
        allow(Fastlane::Actions::CloneInternalMetricsAction).to receive(:run)
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with('metrics/sdk-size.json').and_return(JSON.generate(benchmark))
        allow(Fastlane::Actions::CurrentBranchAction).to receive(:run).and_return('feature')
        allow(Fastlane::Actions::IsCiAction).to receive(:run).and_return(true)
        allow(Fastlane::Actions::PrCommentAction).to receive(:run)
      end

      def posted_table(branch_sizes, options = '')
        described_class.new.parse("lane :test do
          show_sdk_size(github_repo: 'GetStream/sdk', branch_sizes: #{branch_sizes}, size_ext: 'KB'#{options})
        end").runner.execute(:test)

        table = nil
        expect(Fastlane::Actions::PrCommentAction).to have_received(:run) { |params| table = params[:text] }
        table
      end

      it 'compares a tracked size against the benchmark' do
        table = posted_table({ js_bundle_size: 2001.0 })

        expect(table).to include('|js_bundle_size|2000 KB|2001 KB|+1024 B|🟢|')
      end

      it 'shows a size without a benchmark as new instead of failing' do
        table = posted_table({ js_bundle_size: 2000.0, ai_size: 130.0 })

        expect(table).to include('|js_bundle_size|2000 KB|2000 KB|0 B|🟢|')
        expect(table).to include('|ai_size|n/a|130 KB|n/a|🆕|')
      end

      it 'applies the tolerances passed by the caller' do
        table = posted_table({ js_bundle_size: 2001.0 }, ', max_tolerance: 500, fine_tolerance: 100')

        expect(table).to include('|js_bundle_size|2000 KB|2001 KB|+1024 B|🔴|')
      end

      it 'shows a base branch without a benchmark as new when there is no fallback' do
        table = posted_table({ js_bundle_size: 2001.0 }, ", base_branch: 'feature/x'")

        expect(table).to include('| `title` | `feature/x` | `branch` |')
        expect(table).to include('|js_bundle_size|n/a|2001 KB|n/a|🆕|')
      end

      it 'compares against the fallback branch when the base branch has no benchmark' do
        table = posted_table({ js_bundle_size: 2001.0 }, ", base_branch: 'feature/x', fallback_branch: 'develop'")

        expect(table).to include('| `title` | `develop` | `branch` |')
        expect(table).to include('|js_bundle_size|2000 KB|2001 KB|+1024 B|🟢|')
      end

      it 'prefers the base branch benchmark over the fallback' do
        benchmark['v2'] = { 'js_bundle_size' => 1000.0 }
        allow(File).to receive(:read).with('metrics/sdk-size.json').and_return(JSON.generate(benchmark))
        table = posted_table({ js_bundle_size: 1001.0 }, ", base_branch: 'v2', fallback_branch: 'develop'")

        expect(table).to include('| `title` | `v2` | `branch` |')
        expect(table).to include('|js_bundle_size|1000 KB|1001 KB|+1024 B|🟢|')
      end

      it 'stores a new base branch benchmark under the base branch, not the fallback' do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('GITHUB_EVENT_NAME').and_return('push')
        allow(Fastlane::Actions::CurrentBranchAction).to receive(:run).and_return('v2')
        written = nil
        allow(File).to receive(:write) { |_path, content| written = JSON.parse(content) }
        allow(Dir).to receive(:chdir).and_yield
        allow(Fastlane::Actions::ShowSdkSizeAction).to receive(:sh) { |command, *| command == 'git status -s' ? ' M sdk-size.json' : '' }
        allow(Fastlane::Helper::MetricsHelper).to receive(:push)

        posted_table({ js_bundle_size: 2001.0 }, ", base_branch: 'v2', fallback_branch: 'develop'")

        expect(written).to eq('develop' => { 'js_bundle_size' => 2000.0 }, 'v2' => { 'js_bundle_size' => 2001.0 })
      end

      it 'stores the benchmark through the metrics helper on a push to the base branch' do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('GITHUB_EVENT_NAME').and_return('push')
        allow(Fastlane::Actions::CurrentBranchAction).to receive(:run).and_return('develop')
        allow(File).to receive(:write)
        allow(Dir).to receive(:chdir).and_yield
        allow(Fastlane::Actions::ShowSdkSizeAction).to receive(:sh) { |command, *| command == 'git status -s' ? ' M sdk-size.json' : '' }
        allow(Fastlane::Helper::MetricsHelper).to receive(:push)

        posted_table({ js_bundle_size: 2001.0 })

        expect(Fastlane::Helper::MetricsHelper).to have_received(:push)
      end
    end
  end
end
