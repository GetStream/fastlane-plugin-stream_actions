module Fastlane
  module Actions
    class NextPrNumberAction < Action
      def self.run(params)
        uri = URI('https://api.github.com/repos')
        uri.path += "/#{params[:github_repo]}/issues"
        uri.query = URI.encode_www_form('state' => 'all', 'sort' => 'created', 'direction' => 'desc', 'per_page' => 1)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        request = Net::HTTP::Get.new(uri.request_uri)
        token = ENV.fetch('GITHUB_TOKEN', nil)
        token = ENV.fetch('GH_TOKEN', nil) if token.to_s.empty?
        request['Authorization'] = "Bearer #{token}" unless token.to_s.empty?

        response = http.request(request)
        UI.user_error!("GitHub API request failed: #{response.code} #{response.message} — body: #{response.body}") if response.code != '200'

        list = JSON.parse(response.body)
        max_num = list.empty? ? 0 : list[0]['number'].to_i
        next_num = max_num + 1
        UI.important("Next pull request number: #{next_num}")
        next_num
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        'Get next pull request number'
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :github_repo,
            env_name: 'GITHUB_REPOSITORY',
            description: 'GitHub repo name'
          )
        ]
      end

      def self.is_supported?(platform)
        [:ios].include?(platform)
      end
    end
  end
end
