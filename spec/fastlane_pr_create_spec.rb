describe Fastlane do
  describe Fastlane::FastFile do
    describe 'PR Create Action' do
      let(:action) { Fastlane::Actions::PrCreateAction }

      before do
        allow(action).to receive(:sh) { |command, *| command.include?('--cached') ? "file.rb\n" : '' }
        allow(Fastlane::Actions::PushToGitRemoteAction).to receive(:run)
        allow(Fastlane::Actions::CreatePullRequestAction).to receive(:run).and_return('https://github.com/GetStream/sdk/pull/1')
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with('GITHUB_TOKEN').and_return('token')
      end

      def create
        described_class.new.parse("lane :test do
          pr_create(github_repo: 'GetStream/sdk', head_branch: 'ci/update', title: 'Update')
        end").runner.execute(:test)
      end

      def pull_request_params
        params = nil
        expect(Fastlane::Actions::CreatePullRequestAction).to have_received(:run) { |p| params = p }
        params
      end

      # GitHub App tokens do not authenticate with the Basic scheme of `api_token`.
      it 'sends the token as a Bearer token' do
        create

        expect(pull_request_params[:api_bearer]).to eq('token')
        expect(pull_request_params._values).not_to have_key(:api_token)
      end

      it 'fails when the pull request was not created' do
        allow(Fastlane::Actions::CreatePullRequestAction).to receive(:run).and_return(nil)

        expect { create }.to raise_error(FastlaneCore::Interface::FastlaneError, %r{Failed to create the pull request.*ci/update})
      end

      it 'does not create a pull request when there is nothing to commit' do
        allow(action).to receive(:sh).and_return('')

        create

        expect(Fastlane::Actions::CreatePullRequestAction).not_to have_received(:run)
      end
    end
  end
end
