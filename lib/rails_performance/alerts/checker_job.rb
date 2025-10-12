module RailsPerformance
  module Alerts
    class CheckerJob < ActiveJob::Base
      queue_as :default

      def perform
        Checker.check_all
      end
    end
  end
end
