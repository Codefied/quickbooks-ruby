$:.unshift File.expand_path("../lib", __FILE__)
require "quickbooks/version"

Gem::Specification.new do |gem|
  gem.name     = "quickbooks-ruby"
  gem.version  = Quickbooks::VERSION

  gem.author   = "Cody Caughlan"
  gem.email    = "toolbag@gmail.com"
  gem.homepage = "http://github.com/ruckus/quickbooks-ruby"
  gem.summary  = "REST API to Quickbooks Online"
  gem.license  = 'MIT'
  gem.description = "QBO V3 REST API to Quickbooks Online"

  gem.files = Dir['lib/**/*']

  # Faraday 2 requires Ruby >= 3.0; a Rails 8 host additionally requires >= 3.2.
  gem.required_ruby_version = '>= 3.0'

  gem.add_dependency 'oauth2', '~> 2.0'
  gem.add_dependency 'roxml', '~> 4.2'
  gem.add_dependency 'activemodel', '> 4.0' # unpinned upper bound → allows Rails 8 (activemodel 8.x)
  gem.add_dependency 'faraday-net_http_persistent', '~> 2.0' # Faraday 2 :net_http_persistent adapter (replaces the raw net-http-persistent gem)
  gem.add_dependency 'nokogiri'  # promiscuous mode
  gem.add_dependency 'multipart-post' # promiscuous mode
  gem.add_dependency 'faraday', '~> 2.0'
  gem.add_dependency 'faraday-multipart', '~> 1.0' # Faraday 2 extracted :multipart + UploadIO into this gem

  gem.add_development_dependency 'rake'
  gem.add_development_dependency 'simplecov'
  gem.add_development_dependency 'rr'
  gem.add_development_dependency 'rspec'
  gem.add_development_dependency "webmock"
  gem.add_development_dependency 'dotenv'
end
