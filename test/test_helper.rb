ENV["RAILS_ENV"] = "test"

require "simplecov"
SimpleCov.start do
  add_filter "/test/"
  add_filter "lib/rails_performance/alerts/railtie.rb"
end

require "minitest/autorun"
require "active_support/all"
require "rails/railtie"
require "action_mailer"
require "logger"

ActionMailer::Base.delivery_method = :test
ActionMailer::Base.perform_deliveries = true
ActionMailer::Base.deliveries = []

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "rails_performance-alerts"

RailsPerformance.redis = Redis.new(db: 15) # Use separate test database
Rails.logger = Logger.new(IO::NULL)

def dummy_event(
  time: RailsPerformance::Utils.time,
  controller: "Home",
  action: "index",
  status: 200,
  path: "/",
  method: "GET",
  request_id: SecureRandom.hex(16))

  RailsPerformance::Models::RequestRecord.new(
    controller: controller,
    action: action,
    format: "html",
    status: status,
    datetime: time.strftime(RailsPerformance::FORMAT),
    datetimei: time.to_i,
    method: method,
    path: path,
    view_runtime: rand(100.0),
    db_runtime: rand(100.0),
    duration: 100 + rand(100.0),
    request_id: request_id
  )
end

class ActiveSupport::TestCase < Minitest::Test
  def setup
    RailsPerformance.redis.flushdb
    RailsPerformance.alert_rules = []
    RailsPerformance.alert_handler = nil
  end
end
