require "test_helper"

class MailerTest < ActiveSupport::TestCase
  test "triggered email has correct subject and recipient" do
    alert_data = {
      name: "High Response Time",
      current_value: 750.5,
      time_window: 300,
      duration: 180,
      triggered_at: Time.now
    }

    email = RailsPerformance::Alerts::Mailer.triggered(alert_data, to: "admin@example.com", from: "alerts@example.com", app_name: "MyApp")

    assert_equal ["admin@example.com"], email.to
    assert_equal "[MyApp] 🚨 Alert Triggered: High Response Time", email.subject
    assert_match(/High Response Time/, email.html_part.body.to_s)
    assert_match(/750\.5/, email.html_part.body.to_s)
    assert_match(/MyApp/, email.html_part.body.to_s)
    assert_match(/MyApp/, email.text_part.body.to_s)
  end

  test "resolved email has correct subject and recipient" do
    triggered_at = Time.now - 1.hour
    alert_data = {
      name: "High Response Time",
      current_value: 250.0,
      resolved_at: Time.now,
      was_triggered_at: triggered_at
    }

    email = RailsPerformance::Alerts::Mailer.resolved(alert_data, to: "admin@example.com", from: "alerts@example.com", app_name: "MyApp")

    assert_equal ["admin@example.com"], email.to
    assert_equal "[MyApp] ✅ Alert Resolved: High Response Time", email.subject
    assert_match(/High Response Time/, email.html_part.body.to_s)
    assert_match(/250\.0/, email.html_part.body.to_s)
    assert_match(/MyApp/, email.html_part.body.to_s)
    assert_match(/MyApp/, email.text_part.body.to_s)
  end

  test "mailer accepts from parameter" do
    alert_data = {
      name: "Test Alert",
      current_value: 100.0,
      time_window: 300,
      duration: 180,
      triggered_at: Time.now
    }

    email = RailsPerformance::Alerts::Mailer.triggered(alert_data, to: "admin@example.com", from: "custom@example.com", app_name: "MyApp")
    assert_equal ["custom@example.com"], email.from
  end

  test "can deliver triggered email" do
    alert_data = {
      name: "High CPU",
      current_value: 95.2,
      time_window: 300,
      duration: 180,
      triggered_at: Time.now
    }

    assert_nothing_raised do
      RailsPerformance::Alerts::Mailer.triggered(alert_data, to: "admin@example.com", from: "alerts@example.com", app_name: "MyApp").deliver_now
    end
  end

  test "can deliver resolved email" do
    triggered_at = Time.now - 30.minutes
    alert_data = {
      name: "High CPU",
      current_value: 45.0,
      resolved_at: Time.now,
      was_triggered_at: triggered_at
    }

    assert_nothing_raised do
      RailsPerformance::Alerts::Mailer.resolved(alert_data, to: "admin@example.com", from: "alerts@example.com", app_name: "MyApp").deliver_now
    end
  end

  test "formats durations under 60 seconds" do
    alert_data = {
      name: "Quick Alert",
      current_value: 100.0,
      time_window: 30,  # 30 seconds
      duration: 45,     # 45 seconds
      triggered_at: Time.now
    }

    email = RailsPerformance::Alerts::Mailer.triggered(alert_data, to: "admin@example.com", from: "alerts@example.com", app_name: "MyApp")
    assert_match(/30 seconds/, email.html_part.body.to_s)
    assert_match(/45 seconds/, email.html_part.body.to_s)
  end

  test "triggered email handles nil current_value (missing data)" do
    alert_data = {
      name: "Server Offline",
      current_value: nil,
      time_window: 300,
      duration: 180,
      triggered_at: Time.now
    }

    email = RailsPerformance::Alerts::Mailer.triggered(alert_data, to: "admin@example.com", from: "alerts@example.com", app_name: "MyApp")

    assert_equal ["admin@example.com"], email.to
    assert_equal "[MyApp] 🚨 Alert Triggered: Server Offline", email.subject
    assert_match(/Server Offline/, email.html_part.body.to_s)
  end

  test "resolved email handles nil current_value (missing data resolved)" do
    triggered_at = Time.now - 30.minutes
    alert_data = {
      name: "Server Offline",
      current_value: nil,
      resolved_at: Time.now,
      was_triggered_at: triggered_at
    }

    email = RailsPerformance::Alerts::Mailer.resolved(alert_data, to: "admin@example.com", from: "alerts@example.com", app_name: "MyApp")

    assert_equal ["admin@example.com"], email.to
    assert_equal "[MyApp] ✅ Alert Resolved: Server Offline", email.subject
    assert_match(/Server Offline/, email.html_part.body.to_s)
  end
end
