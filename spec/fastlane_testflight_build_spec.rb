describe Fastlane do
  describe Fastlane::Actions::TestflightBuildAction do
    describe 'sanitize_changelog' do
      it 'removes emoji-presentation and text-presentation symbols from headings' do
        changelog =
          "### ⚡️ Performance\n" \
          "### ⚠ Deprecated\n" \
          "### ⚠️ Deprecated\n" \
          "### 🔄 Changed\n" \
          "### 🐞 Fixed\n" \
          '### ✅ Added'

        expect(described_class.sanitize_changelog(changelog)).to eq(
          " PERFORMANCE\n DEPRECATED\n DEPRECATED\n CHANGED\n FIXED\n ADDED"
        )
      end

      it 'removes skin tones, flags and keycap sequences from body text' do
        changelog = 'Thanks 👍🏽 to the 🇺🇸 team 1️⃣'

        expect(described_class.sanitize_changelog(changelog)).to eq('Thanks  to the  team 1')
      end

      it 'shortens markdown PR links to the PR number' do
        changelog = 'Fix a bug [#1234](https://github.com/GetStream/stream-chat-swiftui/pull/1234)'

        expect(described_class.sanitize_changelog(changelog)).to eq('Fix a bug (#1234)')
      end

      it 'leaves plain text untouched' do
        changelog = 'Fix crash on iPad (2x faster, 100% reliable) #1 * 5'

        expect(described_class.sanitize_changelog(changelog)).to eq(changelog)
      end
    end
  end
end
