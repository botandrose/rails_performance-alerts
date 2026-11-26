require "test_helper"

module NotifierTestApp
  class Application; end
end

class EmailNotifierTest < ActiveSupport::TestCase
  test "initializes with recipients and from" do
    notifier = RailsPerformance::Alerts::EmailNotifier.new(
      recipients: ["admin@example.com", "ops@example.com"],
      from: "alerts@example.com",
      smtp_settings: nil
    )

    assert_equal ["admin@example.com", "ops@example.com"], notifier.recipients
    assert_equal "alerts@example.com", notifier.from
  end

  test "converts single recipient to array" do
    notifier = RailsPerformance::Alerts::EmailNotifier.new(
      recipients: "admin@example.com",
      from: "alerts@example.com",
      smtp_settings: nil
    )

    assert_equal ["admin@example.com"], notifier.recipients
  end

  test "sends triggered emails to all recipients" do
    notifier = RailsPerformance::Alerts::EmailNotifier.new(
      recipients: ["admin@example.com", "ops@example.com"],
      from: "alerts@example.com",
      smtp_settings: nil
    )

    alert_data = {
      action: :triggered,
      name: "High Response Time",
      current_value: 750.5,
      time_window: 300,
      duration: 180,
      triggered_at: Time.now
    }

    ActionMailer::Base.deliveries.clear
    notifier.call(alert_data)

    assert_equal 2, ActionMailer::Base.deliveries.size
    assert_equal ["admin@example.com"], ActionMailer::Base.deliveries[0].to
    assert_equal ["ops@example.com"], ActionMailer::Base.deliveries[1].to
    assert_equal ["alerts@example.com"], ActionMailer::Base.deliveries[0].from
  end

  test "sends resolved emails to all recipients" do
    notifier = RailsPerformance::Alerts::EmailNotifier.new(
      recipients: ["admin@example.com"],
      from: "alerts@example.com",
      smtp_settings: nil
    )

    alert_data = {
      action: :resolved,
      name: "High Response Time",
      current_value: 250.0,
      resolved_at: Time.now,
      was_triggered_at: Time.now - 1.hour
    }

    ActionMailer::Base.deliveries.clear
    notifier.call(alert_data)

    assert_equal 1, ActionMailer::Base.deliveries.size
    assert_equal ["admin@example.com"], ActionMailer::Base.deliveries[0].to
    assert_match(/Alert Resolved/, ActionMailer::Base.deliveries[0].subject)
  end

  test "includes app name in email subject" do
    notifier = RailsPerformance::Alerts::EmailNotifier.new(
      recipients: "admin@example.com",
      from: "alerts@example.com",
      app_name: "MyApp",
      smtp_settings: nil
    )

    ActionMailer::Base.deliveries.clear
    notifier.call(action: :triggered, name: "High Response Time", current_value: 750.5, time_window: 300, duration: 180, triggered_at: Time.now)

    assert_equal "[MyApp] 🚨 Alert Triggered: High Response Time", ActionMailer::Base.deliveries[0].subject
  end

  test "defaults app name to the Rails application name" do
    Rails.application = NotifierTestApp::Application.new

    notifier = RailsPerformance::Alerts::EmailNotifier.new(
      recipients: "admin@example.com",
      from: "alerts@example.com",
      smtp_settings: nil
    )

    assert_equal "NotifierTestApp", notifier.app_name
  ensure
    Rails.application = nil
  end

  test "configures smtp settings when provided" do
    smtp_config = {
      address: "smtp.example.com",
      port: 587,
      user_name: "user",
      password: "pass"
    }

    notifier = RailsPerformance::Alerts::EmailNotifier.new(
      recipients: "admin@example.com",
      from: "alerts@example.com",
      smtp_settings: smtp_config
    )

    assert_equal smtp_config, notifier.smtp_settings

    # Call to trigger configuration
    alert_data = {
      action: :triggered,
      name: "Test Alert",
      current_value: 100,
      time_window: 300,
      duration: 180,
      triggered_at: Time.now
    }

    notifier.call(alert_data)
    assert_equal smtp_config, RailsPerformance::Alerts::Mailer.smtp_settings
  end
end
