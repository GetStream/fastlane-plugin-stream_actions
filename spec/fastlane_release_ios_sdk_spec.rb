describe Fastlane do
  describe Fastlane::FastFile do
    describe 'Release iOS SDK Action' do
      before do
        allow(Fastlane::Actions::ReleaseIosSdkAction).to receive(:sh)
        allow(Fastlane::Actions::GitTagExistsAction).to receive(:run).and_return(false)
        allow(Fastlane::Actions::PushToGitRemoteAction).to receive(:run)
      end

      def release(options)
        described_class.new.parse("lane :test do
          release_ios_sdk(
            github_repo: 'GetStream/sdk',
            github_token: 'token',
            use_changelog: false,
            skip_git_status_check: true#{options}
          )
        end").runner.execute(:test)
      end

      it 'releases without bumping plists when sdk names are not set' do
        expect(release(", version: '1.2.3-beta'")).to eq('1.2.3-beta')
        expect(Fastlane::Actions::ReleaseIosSdkAction).to have_received(:sh).with("git commit -m 'Bump 1.2.3-beta'")
      end

      it 'requires a version when sdk names are not set' do
        expect { release(", bump_type: 'minor'") }.to raise_error(FastlaneCore::Interface::FastlaneError, /version/)
        expect(Fastlane::Actions::ReleaseIosSdkAction).not_to have_received(:sh)
      end
    end
  end
end
