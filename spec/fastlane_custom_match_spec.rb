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
