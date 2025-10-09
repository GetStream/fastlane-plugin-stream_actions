lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'fastlane/plugin/stream_actions/version'

Gem::Specification.new do |spec|
  spec.name          = 'fastlane-plugin-stream_actions'
  spec.version       = Fastlane::StreamActions::VERSION
  spec.author        = 'GetStream'
  spec.email         = 'alexey.alterpesotskiy@getstream.io'
  spec.summary       = 'stream custom actions'
  spec.homepage      = 'https://github.com/GetStream/fastlane-plugin-stream_actions'
  spec.files         = Dir["lib/**/*"] + %w(README.md)
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 2.4'
  spec.add_dependency('xctest_list', '1.2.1')
  spec.add_development_dependency('bundler')
  spec.add_development_dependency('fasterer', '0.9.0')
  spec.add_development_dependency('fastlane', '>= 2.182.0')
  spec.add_development_dependency('plist')
  spec.add_development_dependency('pry')
  spec.add_development_dependency('rake')
  spec.add_development_dependency('rspec')
  spec.add_development_dependency('rspec_junit_formatter')
  spec.add_development_dependency('rubocop', '1.38')
  spec.add_development_dependency('rubocop-performance')
  spec.add_development_dependency('rubocop-rake', '0.6.0')
  spec.add_development_dependency('rubocop-require_tools')
  spec.add_development_dependency('rubocop-rspec', '2.15.0')
  spec.add_development_dependency('simplecov')
  spec.metadata['rubygems_mfa_required'] = 'true'
end
