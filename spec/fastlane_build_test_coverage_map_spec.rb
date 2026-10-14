require 'json'
require 'tmpdir'

describe Fastlane do
  describe 'Build Test Coverage Map Action' do
    let(:action) { Fastlane::Actions::BuildTestCoverageMapAction }
    let(:root) { Dir.mktmpdir }
    let(:previous_map) { File.join(root, 'previous.json') }
    let(:tests) { { 'Messages_Tests/test_send' => ['Sources/Client.swift'] } }
    let(:sources) { ['Sources/Client.swift'] }

    after { FileUtils.remove_entry(root) }

    def carry_over
      action.carry_over_failed_tests(tests, sources, previous_map: previous_map, failed_tests: ['UITests/Messages_Tests/test_send'])
    end

    it 'keeps the previous coverage of a failed test' do
      File.write(previous_map, JSON.generate('version' => 1, 'generated_at' => Time.now.utc.iso8601,
                                             'sources' => ['Sources/Client.swift', 'Sources/Message.swift'],
                                             'tests' => { 'Messages_Tests/test_send' => [0, 1] }))

      carry_over

      expect(tests['Messages_Tests/test_send']).to eq(['Sources/Client.swift', 'Sources/Message.swift'])
      expect(sources).to eq(['Sources/Client.swift', 'Sources/Message.swift'])
    end

    it 'drops a failed test from the map when the previous map is unreadable' do
      File.write(previous_map, JSON.generate('version' => 1, 'generated_at' => 'yesterday', 'sources' => [], 'tests' => {}))

      expect { carry_over }.not_to raise_error
      expect(tests).to be_empty
      expect(sources).to eq(['Sources/Client.swift'])
    end

    it 'drops a failed test from the map when the previous map is missing' do
      carry_over

      expect(tests).to be_empty
    end

    it 'drops a failed test the previous map does not have' do
      File.write(previous_map, JSON.generate('version' => 1, 'generated_at' => Time.now.utc.iso8601, 'sources' => [], 'tests' => {}))

      carry_over

      expect(tests).to be_empty
    end
  end
end
