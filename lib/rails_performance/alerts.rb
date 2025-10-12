require "rails_performance"
require "active_support/core_ext/integer"
require_relative "alerts/version"
require_relative "alerts/rule"
require_relative "alerts/state"
require_relative "alerts/checker"
require_relative "alerts/checker_job" if defined?(ActiveJob)
require_relative "alerts/mailer" if defined?(ActionMailer)
require_relative "alerts/email_notifier" if defined?(ActionMailer)
require_relative "alerts/railtie" if defined?(Rails::Railtie)

module RailsPerformance
  module Alerts
    class ConfigurationError < StandardError; end

    class << self
      def validate_configuration!
        # Check if alert_rules exist without handler
        if RailsPerformance.alert_rules.any? && RailsPerformance.alert_handler.nil?
          raise ConfigurationError, "alert_rules are configured but alert_handler is not set"
        end

        # Validate handler is callable
        if RailsPerformance.alert_handler && !RailsPerformance.alert_handler.respond_to?(:call)
          raise ConfigurationError, "alert_handler must respond to :call"
        end

        # Validate each rule can be instantiated
        RailsPerformance.alert_rules.each_with_index do |rule_config, index|
          begin
            Rule.new(rule_config)
          rescue => e
            raise ConfigurationError, "Invalid alert rule at index #{index}: #{e.message}"
          end
        end
      end
    end
  end

  mattr_accessor :alert_rules
  @@alert_rules = []

  mattr_accessor :alert_handler
  @@alert_handler = nil

  singleton_class.prepend Module.new {
    def setup
      super
      RailsPerformance::Alerts.validate_configuration!
    end
  }
end
