describe Fastlane do
  describe Fastlane::FastFile do
    describe 'Update Testplan Action' do
      let(:xctestplan) { 'Sample.xctestplan' }
      let(:env_var) { { 'key' => 'CI', 'value' => 'TRUE' } }

      before do
        File.write(xctestplan, initial_xctestplan)
      end

      after do
        File.delete(xctestplan)
      end

      def initial_xctestplan
        <<~TEXT
        {
          "configurations": [
            {
              "id": "52D2F0B8-32A4-4C72-A8CE-D2AE40A4C18F",
              "name": "Configuration 1",
              "options": {
              }
            }
          ],
          "defaultOptions": {
          },
          "testTargets": [
            {
              "target": {
                "containerPath": "container:Sample.xcodeproj",
                "identifier": "84F737F3287C13AD00A363F4",
                "name": "SampleTests"
              }
            }
          ],
          "version": 1
        }
        TEXT
      end

      it 'adds one env var' do
        described_class.new.parse("lane :test do
          update_testplan(path: '../#{xctestplan}', env_vars: #{env_var})
        end").runner.execute(:test)

        xctestplan_json = JSON.parse(File.read(xctestplan))
        actual_env_vars = xctestplan_json['defaultOptions']['environmentVariableEntries']
        expect(actual_env_vars).to include(env_var)
      end

      it 'adds multiple env vars' do
        described_class.new.parse("lane :test do
          update_testplan(path: '../#{xctestplan}', env_vars: [#{env_var}, #{env_var}])
        end").runner.execute(:test)

        xctestplan_json = JSON.parse(File.read(xctestplan))
        actual_env_vars = xctestplan_json['defaultOptions']['environmentVariableEntries']
        expect(actual_env_vars.size).to eq(2)
      end

      it 'raises an error after providing an empty array of env vars' do
        expect do
          described_class.new.parse("lane :test do
            update_testplan(path: '../#{xctestplan}', env_vars: [])
          end").runner.execute(:test)
        end.to raise_error('The environment variables array should not be empty')
      end

      it 'raises an error after providing a non-existent xctestplan' do
        wrong_path = "wrong/path/#{xctestplan}"
        expect do
          described_class.new.parse("lane :test do
            update_testplan(path: '#{wrong_path}', env_vars: #{env_var})
          end").runner.execute(:test)
        end.to raise_error("Cannot find the testplan file '#{wrong_path}'")
      end
    end
  end
end
