describe Fastlane do
  describe Fastlane::Helper::MetricsHelper do
    describe '.push' do
      let(:commands) { [] }

      before { allow(described_class).to receive(:sleep) }

      # Stubs the git commands: the first `rejected` pushes fail, and so does the pull when `conflict` is set.
      def stub_git(rejected: 0, conflict: false)
        allow(Fastlane::Actions).to receive(:sh) do |command, *|
          commands << command
          failed = (command == 'git push' && commands.count('git push') <= rejected) ||
                   (command == 'git pull --rebase' && conflict)
          raise FastlaneCore::Interface::FastlaneShellError if failed
        end
      end

      it 'rebases before pushing' do
        stub_git

        described_class.push

        expect(commands).to eq(['git pull --rebase', 'git push'])
      end

      it 'waits, rebases and pushes again when another push got there first' do
        stub_git(rejected: 1)

        described_class.push

        expect(commands).to eq(['git pull --rebase', 'git push', 'git pull --rebase', 'git push'])
        expect(described_class).to have_received(:sleep).with(5).once
      end

      it 'fails after three rejected pushes' do
        stub_git(rejected: 3)

        expect { described_class.push }.to raise_error(FastlaneCore::Interface::FastlaneShellError)
        expect(commands.count('git push')).to eq(3)
        expect(described_class).to have_received(:sleep).twice
      end

      it 'aborts a conflicting rebase and fails without pushing' do
        stub_git(conflict: true)

        expect { described_class.push }.to raise_error(FastlaneCore::Interface::FastlaneShellError)
        expect(commands).to eq(['git pull --rebase', 'git rebase --abort'])
      end
    end
  end
end
