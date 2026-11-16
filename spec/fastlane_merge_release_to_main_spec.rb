describe Fastlane do
  describe 'Merge Release To Main Action' do
    describe '.ensure_author_is_repo_admin' do
      def check(permission, author: 'octocat', github_repo: 'GetStream/sdk')
        allow(Fastlane::Actions::MergeReleaseToMainAction).to receive(:sh).and_return("#{permission}\n")
        Fastlane::Actions::MergeReleaseToMainAction.ensure_author_is_repo_admin(author: author, github_repo: github_repo)
      end

      it 'passes for a repo admin' do
        expect { check('admin') }.not_to raise_error
        expect(Fastlane::Actions::MergeReleaseToMainAction).to have_received(:sh).with(
          'gh', 'api', 'repos/GetStream/sdk/collaborators/octocat/permission', '--jq', '.permission',
          hash_including(print_command_output: false)
        )
      end

      %w[write maintain read none].each do |permission|
        it "fails for #{permission} access" do
          expect { check(permission) }.to raise_error(FastlaneCore::Interface::FastlaneError, /needs admin access/)
        end
      end

      it 'fails when the API call fails' do
        expect { check('{"message":"Not Found","status":"404"}') }.to raise_error(FastlaneCore::Interface::FastlaneError, /needs admin access/)
      end

      it 'fails when the author is not set' do
        expect { check('admin', author: nil) }.to raise_error(FastlaneCore::Interface::FastlaneError, /author is not set/)
      end

      it 'fails when the repo is not set' do
        expect { check('admin', github_repo: '') }.to raise_error(FastlaneCore::Interface::FastlaneError, /repo is not set/)
      end
    end
  end
end
