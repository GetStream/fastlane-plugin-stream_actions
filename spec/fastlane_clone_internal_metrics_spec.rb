describe Fastlane do
  describe Fastlane::FastFile do
    describe 'Clone Internal Metrics Action' do
      let(:action) { Fastlane::Actions::CloneInternalMetricsAction }

      def clone(token, &callback)
        calls = []
        # Same keywords as Actions.sh_control_output, so a typo fails here.
        allow(action).to receive(:sh) do |command, print_command:, error_callback:|
          calls << { command: command, print_command: print_command }
          callback&.call(error_callback)
        end
        token_arg = token ? ", github_token: '#{token}'" : ''
        described_class.new.parse("lane :test do
          clone_internal_metrics(path: 'metrics'#{token_arg})
        end").runner.execute(:test)
        calls
      end

      before { ENV.delete('GITHUB_TOKEN') }

      it 'clones over HTTPS with the token and hides the command' do
        calls = clone('abc')

        expect(calls.first[:command]).to eq(
          'git clone https://x-access-token:abc@github.com/GetStream/stream-internal-metrics.git metrics'
        )
        expect(calls.first[:print_command]).to be(false)
      end

      it 'falls back to the SSH URL without a token' do
        calls = clone(nil)

        expect(calls.first[:command]).to eq('git clone git@github.com:GetStream/stream-internal-metrics.git metrics')
      end

      it 'fails without exposing the token' do
        expect { clone('abc') { |cb| cb.call('boom') } }.to raise_error(FastlaneCore::Interface::FastlaneError) { |e|
          expect(e.message).not_to include('abc')
        }
      end
    end
  end
end
