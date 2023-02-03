describe Fastlane do
  describe Fastlane::FastFile do
    describe 'Prepare Simulator Action' do
      let(:sim_name) { 'iPhone 14 Pro' }

      it 'verifies that simulator without version can be prepared' do
        result = described_class.new.parse("lane :test do
          prepare_simulator(device: '#{sim_name}')
        end").runner.execute(:test)
        expect(result).not_to be_empty
      end

      it 'verifies that simulator with version can be prepared' do
        sim = FastlaneCore::Simulator.all.detect { |d| sim_name == d.name }
        result = described_class.new.parse("lane :test do
          prepare_simulator(device: '#{sim_name} (#{sim.os_version})')
        end").runner.execute(:test)
        expect(result).not_to be_empty
      end

      it 'verifies that simulator can be reset' do
        expect_any_instance_of(FastlaneCore::DeviceManager::Device).to receive(:reset)

        described_class.new.parse("lane :test do
          prepare_simulator(device: '#{sim_name}', reset: true)
        end").runner.execute(:test)
      end
    end
  end
end
