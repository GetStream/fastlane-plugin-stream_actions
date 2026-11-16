describe Fastlane do
  describe Fastlane::FastFile do
    describe 'Custom Match Action' do
      let(:export_methods) { ["development", "adhoc", "appstore"] }
      let(:text) { 'test' }

      it 'raises an error after providing a wrong type of app_identifier' do
        expect do
          described_class.new.parse("lane :test do
            custom_match(api_key: {a: 'b'}, app_identifier: '#{text}')
          end").runner.execute(:test)
        end.to raise_error('The bundle identifier(s) have to be specified')
      end

      it 'raises an error after skipping api_key' do
        expect do
          described_class.new.parse("lane :test do
            custom_match(app_identifier: ['#{text}'])
          end").runner.execute(:test)
        end.to raise_error('AppStore Connect API Key has to be specified')
      end

      it 'verifies match without registering device' do
        allow(Fastlane::Actions::MatchAction).to receive(:run).and_return(true)

        result = described_class.new.parse("lane :test do
          custom_match(api_key: {a: 'b'}, app_identifier: ['#{text}'])
        end").runner.execute(:test)
        expect(result).to eq(export_methods)
      end

      def match_auth(token: nil, github_actions: nil)
        auths = []
        allow(Fastlane::Actions::MatchAction).to receive(:run) { |params| auths << params[:git_basic_authorization] }
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('MATCH_GIT_TOKEN').and_return(nil)
        allow(ENV).to receive(:[]).with('GITHUB_ACTIONS').and_return(github_actions)
        token_arg = token ? ", git_token: '#{token}'" : ''
        described_class.new.parse("lane :test do
          custom_match(api_key: {a: 'b'}, app_identifier: ['#{text}']#{token_arg})
        end").runner.execute(:test)
        auths
      end

      it 'passes the git token to match as a basic auth header' do
        expect(match_auth(token: 'abc')).to eq([Base64.strict_encode64('x-access-token:abc')] * 3)
      end

      it 'leaves match auth alone without a git token' do
        expect(match_auth).to eq([nil] * 3)
      end

      it 'masks the header on GitHub Actions' do
        allow($stdout).to receive(:puts).and_call_original
        match_auth(token: 'abc', github_actions: 'true')

        expect($stdout).to have_received(:puts).with("::add-mask::#{Base64.strict_encode64('x-access-token:abc')}").once
      end

      it 'verifies device registration' do
        allow(Fastlane::Actions::MatchAction).to receive(:run).and_return(true)
        allow(Fastlane::Actions::PromptAction).to receive(:run).and_return(text)
        expect(Fastlane::Actions::RegisterDeviceAction).to receive(:run)

        described_class.new.parse("lane :test do
          custom_match(api_key: {a: 'b'}, app_identifier: ['#{text}'], register_device: true)
        end").runner.execute(:test)
      end
    end
  end
end
