$:.push File.expand_path("lib", __dir__)

require "rails_performance/alerts/version"

Gem::Specification.new do |spec|
  spec.name = "rails_performance-alerts"
  spec.version = RailsPerformance::Alerts::VERSION
  spec.authors = ["Micah"]
  spec.email = ["micah@example.com"]
  spec.homepage = "https://github.com/username/rails_performance-alerts"
  spec.summary = "Customizable alerts for rails_performance metrics"
  spec.description = "Add user-configurable alerts to rails_performance gem for monitoring response time, throughput, error rates, and system resources"
  spec.license = "MIT"

  spec.files = Dir["lib/**/*", "MIT-LICENSE", "Rakefile", "README.md"]

  spec.add_dependency "rails_performance", ">= 1.0"

  spec.add_development_dependency "minitest"
  spec.add_development_dependency "redis"
end
