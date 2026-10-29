describe Fastlane do
  describe Fastlane::FastFile do
    describe 'PR Comment Action' do
      def posted_body(text)
        body = nil
        allow(Fastlane::Actions::PrCommentAction).to receive(:sh) do |*args|
          body = File.read(args[args.index('--body-file') + 1]) if args.include?('--body-file')
        end

        described_class.new.parse("lane :test do
          pr_comment(github_repo: 'GetStream/sdk', pr_num: '1', text: #{text.inspect})
        end").runner.execute(:test)

        body
      end

      it 'posts text with shell metacharacters verbatim' do
        text = "## Header\nThe team's `value` is $(whoami)"

        expect(posted_body(text)).to eq(text)
      end

      it 'truncates text over the GitHub limit and closes the open code block' do
        body = posted_body("## Header\n```diff\n#{"+ line\n" * 15_000}```")

        expect(body.length).to be <= 65_536
        expect(body).to start_with("## Header\n```diff\n")
        expect(body.scan('```').size).to be_even
        expect(body).to include('https://github.com/GetStream/sdk/actions/runs/')
      end
    end
  end
end
