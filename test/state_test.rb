require "test_helper"

class AlertStateTest < ActiveSupport::TestCase
  def setup
    super
    @rule_id = "test_rule_123"
    @state = RailsPerformance::Alerts::State.new(@rule_id)
  end

  test "initializes with rule_id" do
    assert_equal @rule_id, @state.rule_id
  end

  test "returns false for triggered? when not triggered" do
    assert_not @state.triggered?
  end

  test "marks alert as triggered" do
    @state.mark_triggered!
    assert @state.triggered?
  end

  test "marks alert as resolved" do
    @state.mark_triggered!
    assert @state.triggered?

    @state.mark_resolved!
    assert_not @state.triggered?
  end

  test "records triggered_at timestamp" do
    before_time = Time.now - 1
    @state.mark_triggered!
    after_time = Time.now + 1

    triggered_at = @state.triggered_at
    assert_not_nil triggered_at
    assert triggered_at >= before_time
    assert triggered_at <= after_time
  end

  test "records resolved_at timestamp" do
    @state.mark_triggered!

    before_time = Time.now - 1
    @state.mark_resolved!
    after_time = Time.now + 1

    resolved_at = @state.resolved_at
    assert_not_nil resolved_at
    assert resolved_at >= before_time
    assert resolved_at <= after_time
  end

  test "records breach timestamp" do
    before_time = Time.now - 1
    @state.record_breach
    after_time = Time.now + 1

    first_breach_at = @state.first_breach_at
    assert_not_nil first_breach_at
    assert first_breach_at >= before_time
    assert first_breach_at <= after_time
  end

  test "does not update first_breach_at on subsequent breaches" do
    @state.record_breach
    first_breach_time = @state.first_breach_at

    sleep 0.1
    @state.record_breach
    second_breach_time = @state.first_breach_at

    assert_equal first_breach_time.to_i, second_breach_time.to_i
  end

  test "clears breaches" do
    @state.record_breach
    assert_not_nil @state.first_breach_at

    @state.clear_breaches
    assert_nil @state.first_breach_at
  end

  test "calculates breaching duration" do
    @state.record_breach
    sleep 0.1
    duration = @state.breaching_duration

    assert duration >= 0.05, "Duration should be at least 0.05 seconds, was #{duration}"
    assert duration < 2, "Duration should be less than 2 seconds, was #{duration}"
  end

  test "returns zero duration when no breaches recorded" do
    assert_equal 0, @state.breaching_duration
  end

  test "persists state in Redis" do
    @state.mark_triggered!

    new_state = RailsPerformance::Alerts::State.new(@rule_id)
    assert new_state.triggered?
  end

  test "maintains separate state for different rule ids" do
    rule1_id = "rule_1"
    rule2_id = "rule_2"

    state1 = RailsPerformance::Alerts::State.new(rule1_id)
    state2 = RailsPerformance::Alerts::State.new(rule2_id)

    state1.mark_triggered!

    assert state1.triggered?
    assert_not state2.triggered?
  end

  test "triggered_at returns nil when never triggered" do
    assert_nil @state.triggered_at
  end

  test "resolved_at returns nil when never resolved" do
    assert_nil @state.resolved_at
  end

  test "first_breach_at returns nil when no breaches" do
    assert_nil @state.first_breach_at
  end

  test "can mark triggered with custom timestamp" do
    custom_time = Time.now - 1.hour
    @state.mark_triggered!(custom_time)

    assert @state.triggered?
    assert_equal custom_time.to_i, @state.triggered_at.to_i
  end

  test "can mark resolved with custom timestamp" do
    @state.mark_triggered!
    custom_time = Time.now - 30.minutes
    @state.mark_resolved!(custom_time)

    assert_not @state.triggered?
    assert_equal custom_time.to_i, @state.resolved_at.to_i
  end

  test "can record breach with custom timestamp" do
    custom_time = Time.now - 10.minutes
    @state.record_breach(custom_time)

    assert_equal custom_time.to_i, @state.first_breach_at.to_i
  end
end
