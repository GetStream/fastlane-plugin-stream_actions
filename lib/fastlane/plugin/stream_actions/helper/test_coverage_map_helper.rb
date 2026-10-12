require 'json'
require 'open3'
require 'tmpdir'

module Fastlane
  module Helper
    # Reads, writes and downloads the per-test coverage maps of build_test_coverage_map and select_impacted_tests.
    class TestCoverageMapHelper
      MAP_VERSION = 1

      # Downloads the newest unexpired artifact with this name produced on coverage_map_branch.
      def self.download_map(params)
        repo = params[:github_repository]
        query = ".artifacts | map(select(.expired | not) | select(.workflow_run.head_branch == \"#{params[:coverage_map_branch]}\")) " \
                '| sort_by(.created_at) | last | .workflow_run.id // empty'
        run_id = command('gh', 'api', "repos/#{repo}/actions/artifacts?name=#{params[:coverage_map_artifact]}&per_page=100", '-q', query).strip
        return nil if run_id.empty?

        dir = Dir.mktmpdir('coverage-map')
        command('gh', 'run', 'download', run_id, '--repo', repo, '--name', params[:coverage_map_artifact], '--dir', dir)
        Dir.glob(File.join(dir, '**', '*.json')).first
      rescue StandardError => e
        UI.important("Could not download the coverage map: #{e.message}")
        nil
      end

      def self.command(*args)
        output, status = Open3.capture2e(*args)
        raise "`#{args.join(' ')}` failed: #{output}" unless status.success?

        output
      end

      def self.read_map(path)
        map = JSON.parse(File.read(path))
        UI.user_error!("Unsupported coverage map version #{map['version']}") unless map['version'] == MAP_VERSION

        sources = map['sources']
        map.merge('tests' => map['tests'].transform_values { |indices| indices.map { |i| sources.fetch(i) } })
      end
    end
  end
end
