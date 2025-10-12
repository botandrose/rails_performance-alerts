namespace :rails_performance do
  namespace :alerts do
    desc "Check all configured alerts"
    task check: :environment do
      unless RailsPerformance.enabled
        puts "RailsPerformance is disabled. Skipping alert checks."
        next
      end

      if RailsPerformance.alert_rules.empty?
        puts "No alert rules configured. Skipping alert checks."
        next
      end

      puts "Checking #{RailsPerformance.alert_rules.size} alert rule(s)..."

      results = RailsPerformance::Alerts::Checker.check_all

      if results.empty?
        puts "All metrics are within normal thresholds."
      else
        results.each do |result|
          case result[:action]
          when :triggered
            puts "ALERT TRIGGERED: #{result[:rule].name} - #{result[:rule].metric} is #{result[:value]} (threshold: #{result[:rule].threshold})"
          when :resolved
            puts "ALERT RESOLVED: #{result[:rule].name} - #{result[:rule].metric} is now #{result[:value]}"
          end
        end
      end
    end

    desc "Run alert checker continuously (for background process)"
    task monitor: :environment do
      unless RailsPerformance.enabled
        puts "RailsPerformance is disabled. Exiting."
        exit
      end

      if RailsPerformance.alert_rules.empty?
        puts "No alert rules configured. Exiting."
        exit
      end

      puts "Starting alert monitor (checking every minute)..."
      puts "Monitoring #{RailsPerformance.alert_rules.size} alert rule(s)"
      puts "Press Ctrl+C to stop"

      trap("INT") do
        puts "\nStopping alert monitor..."
        exit
      end

      loop do
        begin
          results = RailsPerformance::Alerts::Checker.check_all

          results.each do |result|
            case result[:action]
            when :triggered
              puts "[#{Time.now}] ALERT TRIGGERED: #{result[:rule].name}"
            when :resolved
              puts "[#{Time.now}] ALERT RESOLVED: #{result[:rule].name}"
            end
          end
        rescue => e
          puts "[#{Time.now}] Error checking alerts: #{e.message}"
          puts e.backtrace.first(5).join("\n") if RailsPerformance.debug
        end

        sleep 1.minute
      end
    end
  end
end
