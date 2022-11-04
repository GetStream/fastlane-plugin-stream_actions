describe Fastlane do
  describe Fastlane::FastFile do
    describe 'Is Check Required Action' do
      let(:test_sources) { ['test1', 'test2'] }
      let(:happy_path) { "#{test_sources.first}/some_path" }
      let(:unexpected_path) { "some/path/" }

      it 'passes an empty string instead of github_pr_num' do
        result = described_class.new.parse("lane :test do
          is_check_required(sources: #{test_sources}, github_pr_num: '')
        end").runner.execute(:test)

        expect(result).to be(true)
      end

      it 'passes a nil instead of github_pr_num' do
        result = described_class.new.parse("lane :test do
          is_check_required(sources: #{test_sources}, github_pr_num: nil)
        end").runner.execute(:test)

        expect(result).to be(true)
      end

      it 'raises an error after providing an empty array instead of list of sources' do
        expect do
          described_class.new.parse("lane :test do
            is_check_required(sources: [], github_pr_num: '0')
          end").runner.execute(:test)
        end.to raise_error('Sources have to be specified')
      end

      it 'expects that checks are required' do
        allow(Fastlane::Actions).to receive(:sh).and_return(happy_path)

        result = described_class.new.parse("lane :test do
          is_check_required(sources: #{test_sources}, github_pr_num: '0')
        end").runner.execute(:test)

        expect(result).to be(true)
      end

      it 'expects that checks are not required' do
        allow(Fastlane::Actions).to receive(:sh).and_return(unexpected_path)

        result = described_class.new.parse("lane :test do
          is_check_required(sources: #{test_sources}, github_pr_num: '0')
        end").runner.execute(:test)

        expect(result).to be(false)
      end
    end
  end
end
