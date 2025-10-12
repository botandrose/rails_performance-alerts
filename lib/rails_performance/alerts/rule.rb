module RailsPerformance
  module Alerts
    class Rule
      attr_reader :name, :time_window, :duration, :report, :query, :threshold, :server, :alert_on_missing_data

      def initialize(options = {})
        @name = options[:name] || "Unnamed Alert"
        @time_window = options[:time_window] || 5.minutes
        @duration = options[:duration] || 5.minutes
        @report = options[:report]
        @query = options[:query] || {}
        @threshold = options[:threshold]
        @server = options[:server]
        @alert_on_missing_data = options.fetch(:alert_on_missing_data, true)

        validate!
      end

      def id
        @id ||= Digest::MD5.hexdigest("#{name}_#{report_class}_#{query}_#{server}_#{threshold.source_location}")
      end

      def evaluate
        data = fetch_data

        value = calculate_average_value(data)
        breaching = if value.nil?
          @alert_on_missing_data
        else
          @threshold.call(value)
        end

        [value, breaching]
      end

      def to_s
        "#{name} (#{report})"
      end

      def report_class
        return @report if @report.is_a?(Class)

        unless @report.is_a?(String)
          raise ArgumentError, "Invalid report class name: #{@report.inspect}"
        end

        # Try RailsPerformance::Reports namespace first
        if RailsPerformance::Reports.const_defined?(@report, false)
          return RailsPerformance::Reports.const_get(@report, false)
        end

        # Try RailsPerformance::SystemMonitor namespace
        if RailsPerformance::SystemMonitor.const_defined?(@report, false)
          return RailsPerformance::SystemMonitor.const_get(@report, false)
        end

        # Try top-level constant
        if Object.const_defined?(@report, false)
          return Object.const_get(@report, false)
        end

        raise ArgumentError, "Class #{@report} not found in RailsPerformance::Reports, RailsPerformance::SystemMonitor, or top level"
      end

      private

      def resource_chart?
        report_class.ancestors.include?(RailsPerformance::SystemMonitor::ResourceChart)
      end

      def fetch_data
        if resource_chart?
          fetch_resource_chart_data
        else
          fetch_report_data
        end
      end

      def fetch_resource_chart_data
        time_window_days = RailsPerformance::Utils.days(@time_window)
        query_params = @query.merge({on: Date.today})
        db = RailsPerformance::DataSource.new(type: :resources, q: query_params, days: time_window_days).db

        resources_report = RailsPerformance::Reports::ResourcesReport.new(db)

        target_server = if @server
          resources_report.servers.find { |s| s.key == @server }
        else
          resources_report.servers.first
        end

        return nil if target_server.nil?

        chart = report_class.new(target_server)
        chart.data
      end

      def fetch_report_data
        time_window_days = RailsPerformance::Utils.days(@time_window)
        query_params = @query.merge({on: Date.today})
        db = RailsPerformance::DataSource.new(type: :requests, q: query_params, days: time_window_days).db

        report = report_class.new(db)
        report.data
      end

      def calculate_average_value(data)
        window_start = (Time.now - @time_window).to_i * 1000
        recent_data = (data || []).select { |timestamp, value| timestamp >= window_start && value }
        values = recent_data.map { |_, value| value }.compact

        return nil if values.empty?

        (values.sum.to_f / values.size).round(2)
      end

      def validate!
        raise ArgumentError, "name is required" if @name.nil? || @name.empty?
        raise ArgumentError, "report class is required" unless report_class.is_a?(Class)
        raise ArgumentError, "threshold lambda is required" unless @threshold.is_a?(Proc)
        raise ArgumentError, "time_window must be positive" unless @time_window.to_i > 0
        raise ArgumentError, "duration must be positive" unless @duration.to_i > 0
      end
    end
  end
end
