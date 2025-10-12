require_relative "mailer"

module RailsPerformance
  module Alerts
    class EmailNotifier < Data.define(:recipients, :from, :smtp_settings)
      def initialize recipients:, from:, smtp_settings: ::Rails.application.config.action_mailer.smtp_settings
        recipients = Array(recipients)
        super
      end

      def call alert
        configure_mailer
        deliver_emails alert
      end

      private

      def deliver_emails alert
        case alert[:action]
        when :triggered
          recipients.each do |recipient|
            Mailer.triggered(alert, to: recipient, from: from).deliver_now
          end
        when :resolved
          recipients.each do |recipient|
            Mailer.resolved(alert, to: recipient, from: from).deliver_now
          end
        end
      end

      def configure_mailer
        Mailer.smtp_settings = smtp_settings
      end
    end
  end
end
