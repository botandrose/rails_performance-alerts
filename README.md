# RailsPerformance::Alerts

Customizable alerts for [rails_performance](https://github.com/igorkasyanchuk/rails_performance) metrics.

Monitor your Rails application and receive alerts when metrics exceed configured thresholds.

## Setup

Assuming you already have rails_performance set up, follow these steps:

1. Add to your Gemfile and run `bundle install`:

```ruby
gem "rails_performance-alerts"
```

2. Update `config/initializers/rails_performance.rb`:

```ruby
RailsPerformance.setup do |config|
  # ... existing rails_performance config ...

  # example alerts:
  config.alert_rules = [
    # Request-based alerts
    {
      name: "High Response Time",
      report: "ResponseTimeReport",          # RailsPerformance::Reports::ResponseTimeReport
      threshold: ->(value) { value > 500 },  # Alert when > 500ms
      time_window: 5.minutes,                # Calculate average from last 5 minutes
      duration: 3.minutes                    # Alert if breached for 3 consecutive minutes
    },
    {
      name: "Low Throughput",
      report: "ThroughputReport",
      threshold: ->(value) { value < 10 },   # Alert when < 10 requests/min
      time_window: 3.minutes,
      duration: 2.minutes
    },
    {
      name: "High Error Count",
      report: "ThroughputReport",
      query: { status: 500 },                # Filter to 500 errors only
      threshold: ->(value) { value > 5 },
      time_window: 5.minutes,
      duration: 1.minute
    },
    # System resource alerts (requires rails_performance's system monitoring to be enabled)
    {
      name: "High CPU Load",
      report: "CPULoad",                     # RailsPerformance::Widgets::CPULoad
      threshold: ->(value) { value > 80 },   # Alert when CPU > 80%
      time_window: 5.minutes,
      duration: 3.minutes
    },
    {
      name: "High Memory Usage",
      report: "MemoryUsage",
      threshold: ->(value) { value > 1.gigabyte },  # Alert when > 1GB
      time_window: 5.minutes,
      duration: 2.minutes
    },
    {
      name: "Disk Space Exhaustion",
      report: "DiskUsage",
      threshold: ->(value) { value < 5.gigabytes }, # Alert when < 5GB free
      time_window: 10.minutes,
      duration: 5.minutes,
    },
  ]

  config.alert_handler = RailsPerformance::Alerts::EmailNotifier.new(
    recipients: ["team@yourapp.com", "ops@yourapp.com"],
    from: "alerts@yourapp.com",
    app_name: "YourApp", # shown in subject and body; defaults to your Rails application's name
    smtp_settings: { ... } # defaults to Rails ActionMailer config if omitted
  )
end
```

3. Run the checks periodically using either ActiveJob, cron, or a standalone daemon:

* ActiveJob: `RailsPerformance::Alerts::CheckerJob`
* Rake task for cron: `rails_performance:alerts:check`
* Rake task for daemon: `rails_performance:alerts:monitor`

## How It Works

Alerts can be configured for two types of metrics:

### Request-Based Reports

Any report class from `RailsPerformance::Reports::*`:
- `ResponseTimeReport` - Average response time in milliseconds
- `ThroughputReport` - Requests per minute
- `PercentileReport` - P50, P90, P95, P99 response times
- Any custom report you create

### System Resource Charts

Monitor system resources with `RailsPerformance::Widgets::*` classes:
- `CPULoad` - CPU load average
- `MemoryUsage` - Application memory usage (in bytes)
- `DiskUsage` - Available disk space (in bytes)
- Any custom system monitor you create

The `threshold` parameter accepts a lambda that receives the calculated metric value and returns true when the threshold is breached.

## Understanding `time_window` vs `duration`

- **`time_window`**: Period of historical data to analyze (lookback period)
- **`duration`**: How long the threshold must be exceeded before alerting

Example: `time_window: 5.minutes, duration: 3.minutes` means:
> "Calculate the average over the last 5 minutes of data. If that average exceeds the threshold for 3 consecutive checks, trigger the alert."

This prevents false alarms from brief spikes while still detecting sustained problems.

## Running Alert Checks

### With ActiveJob (recommended)

Schedule with your preferred job scheduler:

#### With Solid Queue (config/recurring.yml):

```yaml
rails_performance_alerts:
  class: RailsPerformance::Alerts::CheckerJob
  schedule: every minute
```

#### With whenever gem (config/schedule.rb):

```ruby
every 1.minute do
  runner "RailsPerformance::Alerts::CheckerJob.perform_later"
end
```

### With cron and rake

Add to your crontab:
```bash
* * * * * cd /app && bundle exec rake rails_performance:alerts:check
```

### Run as its own process

You can run the alert monitor continuously as a daemon process. It will check alerts every minute.
```bash
bundle exec rake rails_performance:alerts:monitor
```

## Filtering Alerts by Query Parameters

You can scope alerts to specific controllers, actions, status codes, or any other attribute:

```ruby
{
  name: "Slow API Endpoint",
  report: RailsPerformance::Reports::ResponseTimeReport,
  query: {
    controller: "Api::UsersController",
    action: "index"
  },
  threshold: ->(value) { value > 1000 },
  time_window: 3.minutes,
  duration: 2.minutes
}
```

The `query` parameter is passed directly to the RailsPerformance DataSource, so you can filter by any attribute available in your performance data.

## Monitoring Specific Servers

For system resource alerts, you can monitor a specific server by providing the `server` parameter:

```ruby
{
  name: "High Memory on Production Web Server",
  report: RailsPerformance::Widgets::MemoryUsage,
  server: "web-server-1///production///web",  # Format: hostname///context///role
  threshold: ->(value) { value > 2_000_000_000 },
  time_window: 5.minutes,
  duration: 2.minutes
}
```

If no `server` is specified, the alert will monitor the first available server in the ResourcesReport.

## Alerting on Missing Data

By default, alerts will trigger when metric data is missing (e.g., no server reporting resource metrics). This is useful for detecting when servers go offline or stop reporting data.

```ruby
{
  name: "Server Offline",
  report: RailsPerformance::Widgets::CPULoad,
  threshold: ->(value) { value > 80 },
  time_window: 5.minutes,
  duration: 2.minutes,
  alert_on_missing_data: true  # Default: true
}
```

If you want to ignore missing data and only alert on threshold breaches:

```ruby
{
  name: "High CPU (ignore missing data)",
  report: RailsPerformance::Widgets::CPULoad,
  threshold: ->(value) { value > 80 },
  time_window: 5.minutes,
  duration: 2.minutes,
  alert_on_missing_data: false  # Don't alert when data is missing
}
```

**Note**: For request-based reports, missing data typically means no requests were recorded, which returns a value of `0.0` rather than `nil`.

## Custom Alert Handlers

While the built-in `EmailNotifier` (shown in the configuration example above) handles most use cases, you can create custom alert handlers for other notification systems.

### Post to Slack

```ruby
config.alert_handler = proc do |alert|
  slack = Slack::Notifier.new(ENV['SLACK_WEBHOOK_URL'])

  case alert[:action]
  when :triggered
    slack.ping("🚨 *Alert Triggered*: #{alert[:name]}\n" \
               "Current value: #{alert[:current_value]}")
  when :resolved
    slack.ping("✅ *Alert Resolved*: #{alert[:name]}")
  when :error
    slack.ping("⚠️ *Alert System Error*: #{alert[:error].message}")
  end
end
```

### Create PagerDuty Incident

```ruby
config.alert_handler = proc do |alert|
  pagerduty = Pagerduty.build(
    integration_key: ENV['PAGERDUTY_INTEGRATION_KEY']
  )

  case alert[:action]
  when :triggered
    pagerduty.trigger(
      summary: "#{alert[:name]}: value is #{alert[:current_value]}",
      severity: 'error',
      custom_details: alert
    )
  when :resolved
    pagerduty.resolve
  when :error
    pagerduty.trigger(
      summary: "Alert system error: #{alert[:error].message}",
      severity: 'critical',
      custom_details: alert
    )
  end
end
```

### Custom Email Mailer

```ruby
config.alert_handler = proc do |alert|
  case alert[:action]
  when :triggered
    MyAlertMailer.alert_triggered(alert).deliver_later
  when :resolved
    MyAlertMailer.alert_resolved(alert).deliver_later
  when :error
    MyAlertMailer.alert_error(alert).deliver_later
  end
end
```

### Alert Handler Actions

Your alert handler will receive alerts with three possible actions:

- **`:triggered`** - An alert threshold has been exceeded
  - Contains: `:name`, `:current_value`, `:time_window`, `:duration`, `:triggered_at`
- **`:resolved`** - An alert has returned to normal
  - Contains: `:name`, `:current_value`, `:resolved_at`, `:was_triggered_at`
- **`:error`** - An error occurred while checking alerts
  - Contains: `:error` (exception object), `:rule_config` (may be nil)

## Rake Tasks

```bash
# Check alerts once
rake rails_performance:alerts:check

# Run alert monitor continuously as a daemon
rake rails_performance:alerts:monitor
```

## License

The gem is available as open source under the terms of the MIT License.
