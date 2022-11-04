describe Fastlane do
  describe Fastlane::FastFile do
    describe 'Touch Changelog Action' do
      let(:changelog) { 'CHANGELOG.md' }
      let(:new_version) { '4.23.0' }
      let(:new_date) { '_October 27, 2022_' }
      let(:old_version) { '4.22.0' }
      let(:old_date) { '_January 1, 2022_' }
      let(:link) { 'https://getstream.io/' }
      let(:text) { 'testme' }
      let(:first_product) { 'StreamChat' }
      let(:second_product) { 'StreamChatUI' }
      let(:github_repo) { 'GetStream/stream-chat-swift' }

      before do
        File.write(changelog, initial_changelog)
      end

      after do
        File.delete(changelog)
      end

      def initial_changelog
        changelog_header + upcoming_changelog + old_version_changelog
      end

      def changelog_header
        <<~TEXT
        # SAMPLE CHANGELOG

        The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

        TEXT
      end

      def upcoming_changelog
        <<~TEXT
        # Upcoming

        #{release_changes}

        TEXT
      end

      def upcoming_template
        <<~TEXT
        # Upcoming

        ### 🔄 Changed

        TEXT
      end

      def release_changes
        <<~TEXT
        ## #{first_product}
        ### 🐞 Fixed
        - #{text}
        - [#{text}](#{link})

        ## #{second_product}
        ### ✅ Added
        - #{text}
        - [#{text}](#{link})

        TEXT
      end

      def old_version_changelog
        <<~TEXT
        # [#{old_version}](#{link})
        #{old_date}

        ## #{first_product}
        ### ✅ Added
        - #{text}
        - [#{text}](#{link})
        TEXT
      end

      def new_version_changelog
        <<~TEXT
        # [#{new_version}](https://github.com/#{github_repo}/releases/tag/#{new_version})
        _#{Time.now.strftime('%B %d, %Y')}_

        #{release_changes}

        TEXT
      end

      it 'shows changes provided in upcoming release' do
        result = described_class.new.parse("lane :test do
          touch_changelog(
            changelog_path: '../#{changelog}',
            release_version: '#{new_version}',
            github_repo: '#{github_repo}'
          )
        end").runner.execute(:test)

        expect(result).to eq("\n#{release_changes}\n\n")
      end

      it 'updates file' do
        described_class.new.parse("lane :test do
          touch_changelog(
            changelog_path: '../#{changelog}',
            release_version: '#{new_version}',
            github_repo: '#{github_repo}'
          )
        end").runner.execute(:test)

        expected_result = changelog_header + upcoming_template + new_version_changelog + old_version_changelog
        expect(File.read(changelog)).to eq(expected_result)
      end
    end
  end
end
