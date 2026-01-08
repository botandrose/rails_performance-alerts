require "test_helper"

class AlertRuleTest < ActiveSupport::TestCase
  def dummy_resource_event(time: RailsPerformance::Utils.time, server: "localhost", cpu: 50.0, memory: 1000000, disk: 5000000000)
    RailsPerformance::Models::ResourceRecord.new(
      server: server,
      context: "production",
      role: "web",
      datetime: time.strftime(RailsPerformance::FORMAT),
      datetimei: time.to_i,
      json: {
        cpu: {one_min: cpu, five_min: cpu, fifteen_min: cpu},
        memory: memory,
        disk: {available: disk, total: 10000000000, used: 5000000000}
      }
    )
  end

  test "creates alert rule with valid parameters" do
    threshold_lambda = ->(value) { value > 500 }

    rule = RailsPerformance::Alerts::Rule.new(
      name: "High Response Time",
      report: RailsPerformance::Reports::ResponseTimeReport,
      query: { controller: "UsersController", action: "index" },
      threshold: threshold_lambda,
      time_window: 5.minutes,
      duration: 5.minutes
    )

    assert_equal "High Response Time", rule.name
    assert_equal RailsPerformance::Reports::ResponseTimeReport, rule.report_class
    assert_equal ({ controller: "UsersController", action: "index" }), rule.query
    assert_equal threshold_lambda, rule.threshold
    assert_equal 5.minutes, rule.time_window
    assert_equal 5.minutes, rule.duration
  end

  test "evaluate returns value for resource chart with data" do
    3.times do |i|
      time = Time.now - (i * 10).seconds
      event = dummy_resource_event(time: time, cpu: 75.5 + i)
      event.save
    end

    rule = RailsPerformance::Alerts::Rule.new(
      name: "High CPU",
      report: RailsPerformance::Widgets::CPULoad,
      threshold: ->(value) { value > 80 },
      time_window: 1.minute
    )

    value, breaching = rule.evaluate
    assert_equal value, 76.5
    assert_equal false, breaching
  end

  test "evaluate returns value for resource chart when breaching threshold" do
    # Create resource data with high CPU
    3.times do |i|
      time = Time.now - (i * 10).seconds
      event = dummy_resource_event(time: time, cpu: 85.0 + i)
      event.save
    end

    rule = RailsPerformance::Alerts::Rule.new(
      name: "High CPU",
      report: RailsPerformance::Widgets::CPULoad,
      threshold: ->(value) { value > 80 },
      time_window: 1.minute
    )

    value, breaching = rule.evaluate
    assert value > 80
    assert_equal true, breaching
  end

  test "evaluate returns nil and true when no resource servers found (ResourceChart, default alert_on_missing_data)" do
    rule = RailsPerformance::Alerts::Rule.new(
      name: "High CPU",
      report: RailsPerformance::Widgets::CPULoad,
      threshold: ->(value) { value > 80 },
      time_window: 1.minute
    )

    value, breaching = rule.evaluate
    assert_nil value
    assert_equal true, breaching
  end

  test "evaluate returns nil and false when no resource servers found and alert_on_missing_data is false" do
    rule = RailsPerformance::Alerts::Rule.new(
      name: "High CPU",
      report: RailsPerformance::Widgets::CPULoad,
      threshold: ->(value) { value > 80 },
      time_window: 1.minute,
      alert_on_missing_data: false
    )

    value, breaching = rule.evaluate
    assert_nil value
    assert_equal false, breaching
  end

  test "evaluate returns 0.0 and false when no request data (regular Report)" do
    rule = RailsPerformance::Alerts::Rule.new(
      name: "Test",
      report: RailsPerformance::Reports::ResponseTimeReport,
      threshold: ->(value) { value > 500 },
      time_window: 1.minute
    )

    value, breaching = rule.evaluate
    assert_equal 0.0, value
    assert_equal false, breaching
  end

  test "alert_on_missing_data defaults to true" do
    rule = RailsPerformance::Alerts::Rule.new(
      name: "Test",
      report: RailsPerformance::Reports::ResponseTimeReport,
      threshold: ->(value) { value > 500 }
    )

    assert_equal true, rule.alert_on_missing_data
  end

  test "alert_on_missing_data can be set to false" do
    rule = RailsPerformance::Alerts::Rule.new(
      name: "Test",
      report: RailsPerformance::Reports::ResponseTimeReport,
      threshold: ->(value) { value > 500 },
      alert_on_missing_data: false
    )

    assert_equal false, rule.alert_on_missing_data
  end

  test "to_s returns readable description" do
    rule = RailsPerformance::Alerts::Rule.new(
      name: "High Response Time",
      report: "ResponseTimeReport",
      threshold: ->(value) { value > 500 }
    )

    assert_equal "High Response Time (ResponseTimeReport)", rule.to_s
  end

  test "accepts ResourceChart classes" do
    rule = RailsPerformance::Alerts::Rule.new(
      name: "High CPU",
      report: RailsPerformance::Widgets::CPULoad,
      threshold: ->(value) { value > 80 },
      time_window: 5.minutes,
      duration: 2.minutes
    )

    assert_equal "High CPU", rule.name
    assert_equal RailsPerformance::Widgets::CPULoad, rule.report_class
  end

  test "accepts optional server parameter for ResourceChart" do
    rule = RailsPerformance::Alerts::Rule.new(
      name: "High Memory on Server1",
      report: RailsPerformance::Widgets::MemoryUsage,
      threshold: ->(value) { value > 1000000000 },
      server: "server1///production///web"
    )

    assert_equal "server1///production///web", rule.server
  end

  test "evaluate returns value for specific server when server parameter is specified" do
    # Create resource data for server1
    3.times do |i|
      time = Time.now - (i * 10).seconds
      event = dummy_resource_event(time: time, server: "server1", cpu: 85.0 + i)
      event.save
    end

    # Create resource data for server2
    3.times do |i|
      time = Time.now - (i * 10).seconds
      event = dummy_resource_event(time: time, server: "server2", cpu: 45.0 + i)
      event.save
    end

    rule = RailsPerformance::Alerts::Rule.new(
      name: "High CPU on Server1",
      report: RailsPerformance::Widgets::CPULoad,
      threshold: ->(value) { value > 80 },
      time_window: 1.minute,
      server: "server1///production///web"
    )

    value, breaching = rule.evaluate
    assert value > 80
    assert_equal true, breaching
  end

  test "generates consistent id for same configuration" do
    threshold_lambda = ->(value) { value > 500 }

    rule1 = RailsPerformance::Alerts::Rule.new(
      name: "Test",
      report: RailsPerformance::Reports::ResponseTimeReport,
      threshold: threshold_lambda
    )

    rule2 = RailsPerformance::Alerts::Rule.new(
      name: "Test",
      report: RailsPerformance::Reports::ResponseTimeReport,
      threshold: threshold_lambda
    )

    assert_equal rule1.id, rule2.id
  end

  test "accepts string report name from Reports namespace" do
    rule = RailsPerformance::Alerts::Rule.new(
      name: "Test",
      report: "ResponseTimeReport",
      threshold: ->(value) { value > 500 }
    )

    assert_equal RailsPerformance::Reports::ResponseTimeReport, rule.report_class
  end

  test "accepts string report name from Widgets namespace" do
    rule = RailsPerformance::Alerts::Rule.new(
      name: "Test",
      report: "CPULoad",
      threshold: ->(value) { value > 80 }
    )

    assert_equal RailsPerformance::Widgets::CPULoad, rule.report_class
  end

  test "accepts string report name from top level" do
    # Create a test class at top level
    Object.const_set(:TestReport, Class.new(RailsPerformance::Reports::BaseReport))

    rule = RailsPerformance::Alerts::Rule.new(
      name: "Test",
      report: "TestReport",
      threshold: ->(value) { value > 500 }
    )

    assert_equal TestReport, rule.report_class

    # Cleanup
    Object.send(:remove_const, :TestReport)
  end

  test "raises error for non-existent string report name" do
    error = assert_raises(ArgumentError) do
      RailsPerformance::Alerts::Rule.new(
        name: "Test",
        report: "NonExistentReport",
        threshold: ->(value) { value > 500 }
      )
    end

    assert_match(/not found/, error.message)
  end

  test "raises error for invalid report type (not string or class)" do
    error = assert_raises(ArgumentError) do
      RailsPerformance::Alerts::Rule.new(
        name: "Test",
        report: 123,
        threshold: ->(value) { value > 500 }
      )
    end

    assert_match(/Invalid report class name/, error.message)
  end

  test "string report name works with evaluation" do
    dummy_event.save

    rule = RailsPerformance::Alerts::Rule.new(
      name: "Test",
      report: "ResponseTimeReport",
      threshold: ->(value) { value > 500 },
      time_window: 1.minute
    )

    value, _breaching = rule.evaluate
    refute_nil value
  end

  test "raises error when report is missing" do
    assert_raises(ArgumentError) do
      RailsPerformance::Alerts::Rule.new(
        name: "Test",
        threshold: ->(value) { value > 500 }
      )
    end
  end

  test "raises error when threshold is missing" do
    assert_raises(ArgumentError) do
      RailsPerformance::Alerts::Rule.new(
        name: "Test",
        report: RailsPerformance::Reports::ResponseTimeReport
      )
    end
  end

  test "raises error for invalid report class name" do
    assert_raises(NameError) do
      RailsPerformance::Alerts::Rule.new(
        name: "Test",
        report: "not a class",
        threshold: ->(value) { value > 500 }
      )
    end
  end

  test "raises error for invalid threshold" do
    assert_raises(ArgumentError) do
      RailsPerformance::Alerts::Rule.new(
        name: "Test",
        report: RailsPerformance::Reports::ResponseTimeReport,
        threshold: "not a proc"
      )
    end
  end

end
