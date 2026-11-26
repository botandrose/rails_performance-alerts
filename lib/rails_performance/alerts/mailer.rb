module RailsPerformance
  module Alerts
    class Mailer < ActionMailer::Base
      prepend_view_path File.expand_path("views", __dir__)
      layout "rails_performance/alerts/layouts/mailer"

      def triggered alert_data, to:, from:, app_name:
        @app_name = app_name
        @alert = alert_data
        @name = alert_data[:name]
        @current_value = alert_data[:current_value]
        @time_window = format_duration(alert_data[:time_window])
        @duration = format_duration(alert_data[:duration])
        @triggered_at = alert_data[:triggered_at]

        mail(
          to: to,
          from: from,
          subject: "[#{@app_name}] 🚨 Alert Triggered: #{@name}",
        )
      end

      def resolved alert_data, to:, from:, app_name:
        @app_name = app_name
        @alert = alert_data
        @name = alert_data[:name]
        @current_value = alert_data[:current_value]
        @resolved_at = alert_data[:resolved_at]
        @was_triggered_at = alert_data[:was_triggered_at]
        @duration_triggered = calculate_duration(@was_triggered_at, @resolved_at)

        mail(
          to: to,
          from: from,
          subject: "[#{@app_name}] ✅ Alert Resolved: #{@name}",
        )
      end

      private

      def format_duration seconds
        return "N/A" unless seconds

        if seconds < 60
          "#{seconds.to_i} seconds"
        elsif seconds < 3600
          "#{(seconds / 60).to_i} minutes"
        else
          "#{(seconds / 3600).to_i} hours"
        end
      end

      def calculate_duration start_time, end_time
        return "N/A" unless start_time && end_time
        format_duration(end_time - start_time)
      end
    end
  end
end
