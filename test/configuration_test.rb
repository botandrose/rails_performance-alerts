require "test_helper"

class ConfigurationTest < ActiveSupport::TestCase
  def setup
    @original_rules = RailsPerformance.alert_rules
    @original_handler = RailsPerformance.alert_handler
    RailsPerformance.alert_rules = []
    RailsPerformance.alert_handler = nil
  end

  def teardown
    RailsPerformance.alert_rules = @original_rules
    RailsPerformance.alert_handler = @original_handler
  end

  test "validates successfully with no alert rules configured" do
    assert_nothing_raised do
      RailsPerformance.setup do |config|
        config.alert_rules = []
        config.alert_handler = nil
      end
    end
  end

  test "validates successfully with alert rules and handler configured" do
    assert_nothing_raised do
      RailsPerformance.setup do |config|
        config.alert_rules = [
          {
            name: "Test Alert",
            report: RailsPerformance::Reports::ResponseTimeReport,
            threshold: ->(value) { value > 500 }
          }
        ]
        config.alert_handler = proc { |alert| }
      end
    end
  end

  test "raises error when alert rules configured without handler" do
    error = assert_raises(RailsPerformance::Alerts::ConfigurationError) do
      RailsPerformance.setup do |config|
        config.alert_rules = [
          {
            name: "Test Alert",
            report: RailsPerformance::Reports::ResponseTimeReport,
            threshold: ->(value) { value > 500 }
          }
        ]
        config.alert_handler = nil
      end
    end

    assert_match(/alert_rules are configured but alert_handler is not set/, error.message)
  end

  test "raises error when alert handler is not callable" do
    error = assert_raises(RailsPerformance::Alerts::ConfigurationError) do
      RailsPerformance.setup do |config|
        config.alert_rules = [
          {
            name: "Test Alert",
            report: RailsPerformance::Reports::ResponseTimeReport,
            threshold: ->(value) { value > 500 }
          }
        ]
        config.alert_handler = "not a proc"
      end
    end

    assert_match(/alert_handler must respond to :call/, error.message)
  end

  test "raises error when alert rule is invalid - missing report" do
    error = assert_raises(RailsPerformance::Alerts::ConfigurationError) do
      RailsPerformance.setup do |config|
        config.alert_rules = [
          {
            name: "Invalid Alert",
            threshold: ->(value) { value > 500 }
            # Missing report
          }
        ]
        config.alert_handler = proc { |alert| }
      end
    end

    assert_match(/Invalid alert rule at index 0/, error.message)
    assert_match(/Invalid report class name: nil/, error.message)
  end

  test "raises error when alert rule is invalid - missing threshold" do
    error = assert_raises(RailsPerformance::Alerts::ConfigurationError) do
      RailsPerformance.setup do |config|
        config.alert_rules = [
          {
            name: "Invalid Alert",
            report: RailsPerformance::Reports::ResponseTimeReport
            # Missing threshold
          }
        ]
        config.alert_handler = proc { |alert| }
      end
    end

    assert_match(/Invalid alert rule at index 0/, error.message)
    assert_match(/threshold lambda is required/, error.message)
  end

  test "raises error when alert rule is invalid - invalid report class" do
    error = assert_raises(RailsPerformance::Alerts::ConfigurationError) do
      RailsPerformance.setup do |config|
        config.alert_rules = [
          {
            name: "Invalid Alert",
            report: "NonExistentReport",
            threshold: ->(value) { value > 500 }
          }
        ]
        config.alert_handler = proc { |alert| }
      end
    end

    assert_match(/Invalid alert rule at index 0/, error.message)
    assert_match(/not found/, error.message)
  end

  test "identifies which rule is invalid when multiple rules configured" do
    error = assert_raises(RailsPerformance::Alerts::ConfigurationError) do
      RailsPerformance.setup do |config|
        config.alert_rules = [
          {
            name: "Valid Alert",
            report: RailsPerformance::Reports::ResponseTimeReport,
            threshold: ->(value) { value > 500 }
          },
          {
            name: "Invalid Alert",
            report: RailsPerformance::Reports::ResponseTimeReport
            # Missing threshold
          },
          {
            name: "Another Valid Alert",
            report: RailsPerformance::Reports::ThroughputReport,
            threshold: ->(value) { value < 10 }
          }
        ]
        config.alert_handler = proc { |alert| }
      end
    end

    assert_match(/Invalid alert rule at index 1/, error.message)
  end

  test "allows handler to be an object that responds to call" do
    # Create a callable object
    callable_handler = Class.new do
      def call(alert)
        # Do something
      end
    end.new

    assert_nothing_raised do
      RailsPerformance.setup do |config|
        config.alert_rules = [
          {
            name: "Test Alert",
            report: RailsPerformance::Reports::ResponseTimeReport,
            threshold: ->(value) { value > 500 }
          }
        ]
        config.alert_handler = callable_handler
      end
    end
  end
end
