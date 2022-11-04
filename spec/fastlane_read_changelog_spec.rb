describe Fastlane do
  describe Fastlane::FastFile do
    describe 'Read Changelog Action' do
      let(:changelog) { 'CHANGELOG.md' }
      let(:new_version) { '4.23.0' }
      let(:new_date) { '_October 27, 2022_' }
      let(:old_version) { '4.0.0' }
      let(:old_date) { '_January 1, 2022_' }
      let(:non_existent_version) { '33.22.11' }
      let(:link) { 'https://getstream.io/' }
      let(:text) { 'testme' }
      let(:first_product) { 'StreamChat' }
      let(:second_product) { 'StreamChatUI' }

      before do
        File.write(changelog, initial_changelog)
      end

      after do
        File.delete(changelog)
      end

      def initial_changelog
        <<~TEXT
        # SAMPLE CHANGELOG

        The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

        # Upcoming

        ### 🔄 Changed

        # [#{new_version}](#{link})
        #{new_date}

        ## #{first_product}
        ### 🐞 Fixed
        - #{text}
        - [#{text}](#{link})

        ## #{second_product}
        ### ✅ Added
        - #{text}
        - [#{text}](#{link})

        # [#{old_version}](#{link})
        #{old_date}

        ## #{first_product}
        ### ✅ Added
        - #{text}
        - [#{text}](#{link})
        TEXT
      end

      it 'reads changelog for a new release version' do
        result = described_class.new.parse("lane :test do
          read_changelog(changelog_path: '../#{changelog}', version: '#{new_version}')
        end").runner.execute(:test)

        expected_result = "#{new_date}\n\n## #{first_product}\n### 🐞 Fixed\n- #{text}\n- [#{text}](#{link})\n\n## #{second_product}\n### ✅ Added\n- #{text}\n- [#{text}](#{link})\n\n"
        expect(result).to eq(expected_result)
      end

      it 'reads changelog for an old release version' do
        result = described_class.new.parse("lane :test do
          read_changelog(changelog_path: '../#{changelog}', version: '#{old_version}')
        end").runner.execute(:test)

        expected_result = "#{old_date}\n\n## #{first_product}\n### ✅ Added\n- #{text}\n- [#{text}](#{link})\n"
        expect(result).to eq(expected_result)
      end

      it 'raises an error after providing a non-existent release version' do
        expect do
          described_class.new.parse("lane :test do
            read_changelog(changelog_path: '../#{changelog}', version: '#{non_existent_version}')
          end").runner.execute(:test)
        end.to raise_error("No changelog found for #{non_existent_version}")
      end

      it 'raises an error after skipping the version' do
        expect do
          described_class.new.parse("lane :test do
            read_changelog(changelog_path: '../#{changelog}')
          end").runner.execute(:test)
        end.to raise_error('You need to pass the version of the release you want to obtain the changelog from')
      end
    end
  end
end
