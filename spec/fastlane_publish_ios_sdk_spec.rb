describe Fastlane do
  describe Fastlane::FastFile do
    describe 'Publish iOS SDK Action' do
      before do
        allow(Fastlane::Actions::GitTagExistsAction).to receive(:run).and_return(false)
        allow(Fastlane::Actions::CurrentBranchAction).to receive(:run).and_return('v4')
        allow(Fastlane::Actions::SetGithubReleaseAction).to receive(:run).and_return({ 'id' => 42 })
        allow(Fastlane::Actions::GithubApiAction).to receive(:run)
      end

      def publish(options = '')
        described_class.new.parse("lane :test do
          publish_ios_sdk(
            version: '4.103.0',
            github_repo: 'GetStream/sdk',
            github_token: 'token',
            changelog: 'changes',
            skip_pods: true,
            skip_branch_check: true,
            skip_git_status_check: true#{options}
          )
        end").runner.execute(:test)
      end

      def release_params
        params = nil
        expect(Fastlane::Actions::SetGithubReleaseAction).to have_received(:run) { |p| params = p }
        params
      end

      def api_params
        params = nil
        expect(Fastlane::Actions::GithubApiAction).to have_received(:run) { |p| params = p }
        params
      end

      it 'publishes the release right away by default' do
        publish

        expect(release_params[:is_draft]).to be(false)
        expect(Fastlane::Actions::GithubApiAction).not_to have_received(:run)
      end

      it 'publishes the release without marking it as Latest' do
        publish(', make_latest: false')

        expect(release_params[:is_draft]).to be(true)
        expect(api_params[:http_method]).to eq('PATCH')
        expect(api_params[:path]).to eq('repos/GetStream/sdk/releases/42')
        expect(api_params[:body]).to eq({ draft: false, make_latest: 'false' })
      end

      it 'fails when the draft release was not created' do
        allow(Fastlane::Actions::SetGithubReleaseAction).to receive(:run).and_return(nil)

        expect { publish(', make_latest: false') }.to raise_error(FastlaneCore::Interface::FastlaneError, /Failed to create the GitHub release/)
        expect(Fastlane::Actions::GithubApiAction).not_to have_received(:run)
      end
    end
  end
end
