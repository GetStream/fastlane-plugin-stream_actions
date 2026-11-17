describe Fastlane do
  describe Fastlane::FastFile do
    describe 'Release iOS SDK Action' do
      # Stands in for the action of fastlane-plugin-versioning, which the consumer repos install.
      let(:increment_version_action) do
        Class.new(Fastlane::Action) do
          def self.run(params)
            params[:version_number]
          end

          def self.available_options
            %i[target version_number bump_type].map do |key|
              FastlaneCore::ConfigItem.new(key: key, description: key.to_s, optional: true)
            end
          end

          def self.is_supported?(platform)
            true
          end
        end
      end

      before do
        stub_const('Fastlane::Actions::IncrementVersionNumberInPlistAction', increment_version_action)
        allow(Fastlane::Actions::ReleaseIosSdkAction).to receive(:sh)
        allow(Fastlane::Actions::GitTagExistsAction).to receive(:run).and_return(false)
        allow(Fastlane::Actions::PushToGitRemoteAction).to receive(:run)
        allow(Fastlane::Actions::CreatePullRequestAction).to receive(:run).and_return('https://github.com/GetStream/sdk/pull/1')
      end

      def release(options = '')
        described_class.new.parse("lane :test do
          release_ios_sdk(
            version: '1.2.3',
            sdk_names: ['Sdk'],
            github_repo: 'GetStream/sdk',
            github_token: 'token',
            skip_git_status_check: true,
            use_changelog: false#{options}
          )
        end").runner.execute(:test)
      end

      def pull_request_params
        params = nil
        expect(Fastlane::Actions::CreatePullRequestAction).to have_received(:run) { |p| params = p }
        params
      end

      it 'does not create a pull request by default' do
        expect(release).to eq('1.2.3')
        expect(Fastlane::Actions::CreatePullRequestAction).not_to have_received(:run)
      end

      it 'creates the release pull request to main' do
        release(', create_pull_request: true')

        expect(pull_request_params[:title]).to eq('1.2.3 Release')
        expect(pull_request_params[:head]).to eq('release/1.2.3')
        expect(pull_request_params[:base]).to eq('main')
      end

      # GitHub App tokens do not authenticate with the Basic scheme of `api_token`.
      it 'sends the token as a Bearer token' do
        release(', create_pull_request: true')

        expect(pull_request_params[:api_bearer]).to eq('token')
        expect(pull_request_params._values).not_to have_key(:api_token)
      end

      it 'fails when the pull request was not created' do
        allow(Fastlane::Actions::CreatePullRequestAction).to receive(:run).and_return(nil)

        expect { release(', create_pull_request: true') }.to raise_error(
          FastlaneCore::Interface::FastlaneError, %r{Failed to create the release pull request.*release/1\.2\.3}
        )
      end
    end
  end
end
