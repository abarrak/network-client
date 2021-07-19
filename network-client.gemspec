# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'network/version'
require 'date'

Gem::Specification.new do |spec|
  spec.name          = "network-client"
  spec.version       = Network::VERSION
  spec.date          = Date.today.to_s
  spec.authors       = ["Abdullah Barrak (abarrak)"]
  spec.email         = ["abdullah@abarrak.com"]

  spec.summary       = "A thin resilient JSON web client built around Net::HTTP"
  spec.description   = "network-client is a drop-in thin layer on top of Net::HTTP classes for \
                        JSON web requests with retry functionality and simple error handling"
  spec.homepage      = "https://github.com/abarrak/network-client"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end

  spec.require_paths = %w(lib)

  spec.add_development_dependency "bundler", "~> 1.14"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.6"
  spec.add_development_dependency "factory_girl", "~> 4.5"
  spec.add_development_dependency "simplecov", "~> 0.14.1"
  spec.add_development_dependency "codeclimate-test-reporter", "~> 1.0"
  spec.add_development_dependency "dotenv", "~> 2.2"
end
