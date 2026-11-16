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

      # Runs as a push to the base branch, which stores the benchmark, and
      # returns the commands the action ran, also collecting them into
      # `commands`. The first `rejected` pushes fail.
      def push_benchmark(rejected:, commands: [])
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('GITHUB_EVENT_NAME').and_return('push')
        allow(Fastlane::Actions::CurrentBranchAction).to receive(:run).and_return('develop')
        allow(File).to receive(:write)
        allow(Dir).to receive(:chdir).and_yield

        allow(Fastlane::Actions::ShowSdkSizeAction).to receive(:sh) do |command, *|
          commands << command
          raise FastlaneCore::Interface::FastlaneShellError if command == 'git push' && commands.count('git push') <= rejected

          command == 'git status -s' ? ' M sdk-size.json' : ''
        end

        posted_table({ js_bundle_size: 2001.0 })
        commands
      end

      it 'rebases the benchmark before pushing it' do
        expect(push_benchmark(rejected: 0).last(2)).to eq(['git pull --rebase', 'git push'])
      end

      it 'rebases and pushes again when another push got there first' do
        commands = push_benchmark(rejected: 1)

        expect(commands.last(4)).to eq(['git pull --rebase', 'git push', 'git pull --rebase', 'git push'])
      end

      it 'fails after three rejected pushes' do
        commands = []

        expect { push_benchmark(rejected: 3, commands: commands) }.to raise_error(FastlaneCore::Interface::FastlaneShellError)
        expect(commands.count('git push')).to eq(3)
      end
    end
  end
end
