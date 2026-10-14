describe Fastlane do
  describe Fastlane::FastFile do
    describe 'Show SDK Size Action' do
      let(:benchmark) { { 'develop' => { 'js_bundle_size' => 2000.0 } } }

      before do
        allow(Fastlane::Actions).to receive(:sh)
        allow(FileUtils).to receive(:remove_dir)
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with('metrics/sdk-size.json').and_return(JSON.generate(benchmark))
        allow(Fastlane::Actions::CurrentBranchAction).to receive(:run).and_return('feature')
        allow(Fastlane::Actions::IsCiAction).to receive(:run).and_return(true)
        allow(Fastlane::Actions::PrCommentAction).to receive(:run)
      end

      def posted_table(branch_sizes)
        described_class.new.parse("lane :test do
          show_sdk_size(github_repo: 'GetStream/sdk', branch_sizes: #{branch_sizes}, size_ext: 'KB')
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
    end
  end
end
