require "test_helper"

class CheckerJobTest < ActiveSupport::TestCase
  test "performs check_all" do
    RailsPerformance.alert_rules = [
      {
        name: "Test Alert",
        report: RailsPerformance::Reports::ThroughputReport,
        threshold: ->(value) { value > 100 },
        time_window: 5.minutes,
        duration: 1.minute
      }
    ]

    # Setup some data so the alert can evaluate
    dummy_event.save

    job = RailsPerformance::Alerts::CheckerJob.new
    result = job.perform

    assert_equal result, []
  end
end
