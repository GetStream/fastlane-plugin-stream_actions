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

      it 'truncates at a line break so a fence marker is not split' do
        body = posted_body("#{'a' * 59_997}\n```diff\n#{"+ line\n" * 2000}```")

        expect(body).to start_with("#{'a' * 59_997}\n\n⚠️ Truncated")
      end

      it 'closes an open fence with as many backticks as it was opened with' do
        body = posted_body("````md\n#{"```swift\nx\n```\n" * 5000}````")

        expect(body.split("\n\n⚠️ Truncated").first).to end_with("\n````")
      end

      it 'deletes earlier comments containing the text to edit' do
        header = %(## It's "quoted" (x))
        commands = []
        # Same keywords as Actions.sh_control_output, which an action's `sh` delegates to
        allow(Fastlane::Actions::PrCommentAction).to receive(:sh) do |*args, print_command: true, print_command_output: true|
          commands << args
          [{ id: 1, body: "#{header.upcase}\nold" }, { id: 2, body: 'other' }].to_json if args[1] == 'api'
        end

        described_class.new.parse("lane :test do
          pr_comment(github_repo: 'GetStream/sdk', pr_num: '1', text: 'new', edit_last_comment_with_text: #{header.inspect})
        end").runner.execute(:test)

        expect(commands).to include(['gh', 'api', 'repos/GetStream/sdk/issues/1/comments'])
        expect(commands.flatten.grep(/DELETE/)).to eq(['gh api --method DELETE repos/GetStream/sdk/issues/comments/1'])
      end
    end
  end
end
