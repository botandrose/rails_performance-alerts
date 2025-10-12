module RailsPerformance
  module Alerts
    class Checker
      def self.check_all
        new.check_all
      end

      def check_all
        RailsPerformance.alert_rules.map do |rule_config|
          begin
            rule = Rule.new(rule_config)
            check_rule(rule)
          rescue => e
            RailsPerformance.log "Error checking alert rule: #{e.message}"
            notify_error e, rule_config
            nil
          end
        end.compact
      end

      def check_rule rule
        current_value, breaching = rule.evaluate

        # Only skip if value is nil AND not breaching (alert_on_missing_data: false)
        return nil if current_value.nil? && !breaching

        state = State.new(rule.id)

        if breaching
          state.record_breach
          duration_met = state.breaching_duration >= rule.duration

          if duration_met && !state.triggered?
            trigger_alert rule, current_value, state
            return { action: :triggered, rule: rule, value: current_value }
          end
        else
          if state.triggered?
            resolve_alert rule, current_value, state
            return { action: :resolved, rule: rule, value: current_value }
          end
          state.clear_breaches
        end

        nil
      end

      private

      def trigger_alert rule, current_value, state
        state.mark_triggered!

        RailsPerformance.alert_handler&.call({
          action: :triggered,
          name: rule.name,
          current_value: current_value,
          time_window: rule.time_window,
          duration: rule.duration,
          triggered_at: Time.now
        })
      end

      def resolve_alert rule, current_value, state
        state.mark_resolved!

        RailsPerformance.alert_handler&.call({
          action: :resolved,
          name: rule.name,
          current_value: current_value,
          resolved_at: Time.now,
          was_triggered_at: state.triggered_at
        })
      end

      def notify_error(exception, rule_config)
        RailsPerformance.alert_handler&.call({
          action: :error,
          error: exception,
          rule_config: rule_config
        })
      end
    end
  end
end
