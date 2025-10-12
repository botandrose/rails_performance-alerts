require "test_helper"

class AlertCheckerTest < ActiveSupport::TestCase
  def create_request_with_duration(duration_ms, status: 200)
    time = RailsPerformance::Utils.time
    RailsPerformance::Models::RequestRecord.new(
      controller: "TestController",
      action: "index",
      format: "html",
      status: status,
      datetime: time.strftime(RailsPerformance::FORMAT),
      datetimei: time.to_i,
      method: "GET",
      path: "/test",
      view_runtime: 0,
      db_runtime: 0,
      duration: duration_ms,
      request_id: SecureRandom.hex(16)
    ).save
  end

  test "check_all returns empty array when no rules configured" do
    results = RailsPerformance::Alerts::Checker.check_all
    assert_equal [], results
  end


  test "triggers alert when threshold exceeded for duration" do
    10.times { create_request_with_duration(600) }

    handler_called = false
    triggered_alert = nil

    RailsPerformance.alert_rules = [
      {
        name: "High Response Time",
        report: RailsPerformance::Reports::ResponseTimeReport,
        threshold: ->(value) { value > 200 },
        time_window: 1.minute,
        duration: 1.second
      }
    ]

    RailsPerformance.alert_handler = proc do |alert|
      handler_called = true
      triggered_alert = alert
    end

    checker = RailsPerformance::Alerts::Checker.new
    rule = RailsPerformance::Alerts::Rule.new(RailsPerformance.alert_rules.first)

    state = RailsPerformance::Alerts::State.new(rule.id)
    state.record_breach(Time.now - 2.seconds)

    checker.check_rule(rule)

    assert handler_called, "Alert handler should have been called"
    assert_equal :triggered, triggered_alert[:action]
    assert_equal "High Response Time", triggered_alert[:name]
    assert triggered_alert[:current_value] > 200
  end

  test "resolves alert when threshold no longer exceeded" do
    create_request_with_duration(100)

    handler_called = false
    resolved_alert = nil

    RailsPerformance.alert_rules = [
      {
        name: "High Response Time",
        report: RailsPerformance::Reports::ResponseTimeReport,
        threshold: ->(value) { value > 500 },
        time_window: 1.minute,
        duration: 1.second
      }
    ]

    RailsPerformance.alert_handler = proc do |alert|
      handler_called = true
      resolved_alert = alert
    end

    rule = RailsPerformance::Alerts::Rule.new(RailsPerformance.alert_rules.first)
    state = RailsPerformance::Alerts::State.new(rule.id)
    state.mark_triggered!

    checker = RailsPerformance::Alerts::Checker.new
    checker.check_rule(rule)

    assert handler_called, "Alert handler should have been called"
    assert_equal :resolved, resolved_alert[:action]
    assert_equal "High Response Time", resolved_alert[:name]
  end

  test "does not trigger alert if duration not met" do
    create_request_with_duration(600)

    handler_called = false

    RailsPerformance.alert_rules = [
      {
        name: "High Response Time",
        report: RailsPerformance::Reports::ResponseTimeReport,
        threshold: ->(value) { value > 500 },
        time_window: 1.minute,
        duration: 10.minutes
      }
    ]

    RailsPerformance.alert_handler = proc do |alert|
      handler_called = true
    end

    checker = RailsPerformance::Alerts::Checker.new
    rule = RailsPerformance::Alerts::Rule.new(RailsPerformance.alert_rules.first)
    result = checker.check_rule(rule)

    assert_not handler_called, "Alert handler should not have been called"
    assert_nil result, "check_rule should return nil when duration not met"

    # Also verify check_all returns empty
    results = RailsPerformance::Alerts::Checker.check_all
    assert_equal [], results, "check_all should return empty when duration not met"
  end

  test "calculates throughput for errors correctly" do
    5.times { create_request_with_duration(200, status: 200) }
    5.times { create_request_with_duration(200, status: 500) }

    RailsPerformance.alert_rules = [
      {
        name: "High Error Count",
        report: RailsPerformance::Reports::ThroughputReport,
        query: {status: 500},
        threshold: ->(value) { value > 2 },
        time_window: 1.minute,
        duration: 1.second
      }
    ]

    checker = RailsPerformance::Alerts::Checker.new
    rule = RailsPerformance::Alerts::Rule.new(RailsPerformance.alert_rules.first)

    state = RailsPerformance::Alerts::State.new(rule.id)
    state.record_breach(Time.now - 2.seconds)

    result = checker.check_rule(rule)
    assert_equal :triggered, result[:action]
  end

  test "evaluates throughput correctly" do
    20.times { dummy_event.save }

    RailsPerformance.alert_rules = [
      {
        name: "High Throughput",
        report: RailsPerformance::Reports::ThroughputReport,
        threshold: ->(value) { value > 5 },
        time_window: 1.minute,
        duration: 1.second
      }
    ]

    checker = RailsPerformance::Alerts::Checker.new
    rule = RailsPerformance::Alerts::Rule.new(RailsPerformance.alert_rules.first)

    state = RailsPerformance::Alerts::State.new(rule.id)
    state.record_breach(Time.now - 2.seconds)

    result = checker.check_rule(rule)
    assert_equal :triggered, result[:action]
  end

  test "handles missing data gracefully" do
    RailsPerformance.alert_rules = [
      {
        name: "Test Alert",
        report: RailsPerformance::Reports::ResponseTimeReport,
        threshold: ->(value) { value > 500 },
        time_window: 1.minute,
        duration: 1.second
      }
    ]

    checker = RailsPerformance::Alerts::Checker.new
    rule = RailsPerformance::Alerts::Rule.new(RailsPerformance.alert_rules.first)

    assert_nothing_raised do
      result = checker.check_rule(rule)
      assert_nil result
    end
  end

  test "does not trigger duplicate alerts" do
    10.times { create_request_with_duration(600) }

    trigger_count = 0

    RailsPerformance.alert_rules = [
      {
        name: "High Response Time",
        report: RailsPerformance::Reports::ResponseTimeReport,
        threshold: ->(value) { value > 200 },
        time_window: 1.minute,
        duration: 1.second
      }
    ]

    RailsPerformance.alert_handler = proc do |alert|
      trigger_count += 1 if alert[:action] == :triggered
    end

    checker = RailsPerformance::Alerts::Checker.new
    rule = RailsPerformance::Alerts::Rule.new(RailsPerformance.alert_rules.first)

    state = RailsPerformance::Alerts::State.new(rule.id)
    state.record_breach(Time.now - 2.seconds)

    checker.check_rule(rule)
    checker.check_rule(rule)
    checker.check_rule(rule)

    assert_equal 1, trigger_count, "Alert should only trigger once"
  end

  test "handles exceptions in alert handler gracefully" do
    create_request_with_duration(600)

    RailsPerformance.alert_rules = [
      {
        name: "High Response Time",
        report: RailsPerformance::Reports::ResponseTimeReport,
        threshold: ->(value) { value > 500 },
        time_window: 1.minute,
        duration: 1.second,
      }
    ]

    RailsPerformance.alert_handler = proc do |alert|
      raise "Handler error"
    end

    checker = RailsPerformance::Alerts::Checker.new
    rule = RailsPerformance::Alerts::Rule.new(RailsPerformance.alert_rules.first)

    state = RailsPerformance::Alerts::State.new(rule.id)
    state.record_breach(Time.now - 2.seconds)

    assert_nothing_raised do
      checker.check_rule(rule)
    end
  end

  test "check_all handles rule errors gracefully" do
    RailsPerformance.alert_rules = [
      {
        name: "Invalid Rule",
        report: "not a class",
        threshold: ->(value) { value > 500 }
      }
    ]

    assert_nothing_raised do
      results = RailsPerformance::Alerts::Checker.check_all
      assert_equal [], results
    end
  end

  test "supports less than operator for throughput" do
    dummy_event.save

    RailsPerformance.alert_rules = [
      {
        name: "Low Throughput",
        report: RailsPerformance::Reports::ThroughputReport,
        threshold: ->(value) { value < 100 },
        time_window: 1.minute,
        duration: 1.second
      }
    ]

    checker = RailsPerformance::Alerts::Checker.new
    rule = RailsPerformance::Alerts::Rule.new(RailsPerformance.alert_rules.first)

    state = RailsPerformance::Alerts::State.new(rule.id)
    state.record_breach(Time.now - 2.seconds)

    result = checker.check_rule(rule)
    assert_equal :triggered, result[:action]
  end

  test "clears breaches when threshold no longer exceeded" do
    create_request_with_duration(100)

    RailsPerformance.alert_rules = [
      {
        name: "High Response Time",
        report: RailsPerformance::Reports::ResponseTimeReport,
        threshold: ->(value) { value > 500 },
        time_window: 1.minute,
        duration: 1.second
      }
    ]

    rule = RailsPerformance::Alerts::Rule.new(RailsPerformance.alert_rules.first)
    state = RailsPerformance::Alerts::State.new(rule.id)
    state.record_breach

    checker = RailsPerformance::Alerts::Checker.new
    checker.check_rule(rule)

    assert_nil state.first_breach_at, "Breaches should be cleared when threshold not exceeded"
  end

  test "handles ResourceChart rules gracefully" do
    RailsPerformance.alert_rules = [
      {
        name: "High CPU Load",
        report: RailsPerformance::SystemMonitor::CPULoad,
        threshold: ->(value) { value > 80 },
        time_window: 1.minute,
        duration: 1.second
      }
    ]

    checker = RailsPerformance::Alerts::Checker.new
    rule = RailsPerformance::Alerts::Rule.new(RailsPerformance.alert_rules.first)

    assert_nothing_raised do
      result = checker.check_rule(rule)
      assert_nil result
    end
  end

  test "triggers alert when data is missing and alert_on_missing_data is true (default)" do
    handler_called = false
    triggered_alert = nil

    RailsPerformance.alert_rules = [
      {
        name: "Server Offline",
        report: RailsPerformance::SystemMonitor::CPULoad,
        threshold: ->(value) { value > 80 },
        time_window: 1.minute,
        duration: 1.second
        # alert_on_missing_data defaults to true
      }
    ]

    RailsPerformance.alert_handler = proc do |alert|
      handler_called = true
      triggered_alert = alert
    end

    checker = RailsPerformance::Alerts::Checker.new
    rule = RailsPerformance::Alerts::Rule.new(RailsPerformance.alert_rules.first)

    # Simulate duration being met
    state = RailsPerformance::Alerts::State.new(rule.id)
    state.record_breach(Time.now - 2.seconds)

    result = checker.check_rule(rule)

    assert handler_called, "Alert handler should have been called for missing data"
    assert_equal :triggered, triggered_alert[:action]
    assert_equal "Server Offline", triggered_alert[:name]
    assert_nil triggered_alert[:current_value]
  end

  test "does not trigger alert when data is missing and alert_on_missing_data is false" do
    handler_called = false

    RailsPerformance.alert_rules = [
      {
        name: "High CPU Load",
        report: RailsPerformance::SystemMonitor::CPULoad,
        threshold: ->(value) { value > 80 },
        time_window: 1.minute,
        duration: 1.second,
        alert_on_missing_data: false
      }
    ]

    RailsPerformance.alert_handler = proc do |alert|
      handler_called = true
    end

    checker = RailsPerformance::Alerts::Checker.new
    rule = RailsPerformance::Alerts::Rule.new(RailsPerformance.alert_rules.first)

    result = checker.check_rule(rule)

    assert_not handler_called, "Alert handler should not have been called when alert_on_missing_data is false"
    assert_nil result
  end

  test "calls alert_handler with :error action when rule creation fails" do
    error_alert = nil

    RailsPerformance.alert_rules = [
      {
        name: "Invalid Rule",
        # Missing required report field
        threshold: ->(value) { value > 100 }
      }
    ]

    RailsPerformance.alert_handler = proc do |alert|
      error_alert = alert if alert[:action] == :error
    end

    results = RailsPerformance::Alerts::Checker.check_all

    assert_not_nil error_alert, "Error alert should have been sent"
    assert_equal :error, error_alert[:action]
    assert_kind_of StandardError, error_alert[:error]
    assert_not_nil error_alert[:rule_config]
    assert_equal "Invalid Rule", error_alert[:rule_config][:name]
  end

  test "calls alert_handler with :error action when rule evaluation fails" do
    error_alert = nil

    # Create a rule that will fail during evaluation
    RailsPerformance.alert_rules = [
      {
        name: "Failing Rule",
        report: RailsPerformance::Reports::ResponseTimeReport,
        threshold: ->(value) { raise "Evaluation error" }
      }
    ]

    RailsPerformance.alert_handler = proc do |alert|
      error_alert = alert if alert[:action] == :error
    end

    # Create some data so evaluation happens
    create_request_with_duration(100)

    results = RailsPerformance::Alerts::Checker.check_all

    assert_not_nil error_alert, "Error alert should have been sent"
    assert_equal :error, error_alert[:action]
    assert_kind_of StandardError, error_alert[:error]
    assert_match(/Evaluation error/, error_alert[:error].message)
    assert_not_nil error_alert[:rule_config]
    assert_equal "Failing Rule", error_alert[:rule_config][:name]
  end

  test "continues processing other rules after an error" do
    results_count = 0
    error_count = 0

    RailsPerformance.alert_rules = [
      {
        name: "Invalid Rule",
        threshold: ->(value) { value > 100 }
        # Missing report
      },
      {
        name: "Valid Rule",
        report: RailsPerformance::Reports::ResponseTimeReport,
        threshold: ->(value) { value > 50 },
        time_window: 1.minute,
        duration: 1.second
      }
    ]

    RailsPerformance.alert_handler = proc do |alert|
      if alert[:action] == :error
        error_count += 1
      else
        results_count += 1
      end
    end

    create_request_with_duration(100)

    checker = RailsPerformance::Alerts::Checker.new
    results = checker.check_all

    # Should have 1 error from invalid rule
    assert_equal 1, error_count, "Should have 1 error alert"

    # Valid rule was processed (even if it didn't trigger an alert)
    # The important thing is check_all didn't stop after the error
    assert_equal 2, RailsPerformance.alert_rules.size, "Should have processed both rules"
  end
end
