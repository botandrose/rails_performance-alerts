module RailsPerformance
  module Alerts
    class State
      REDIS_KEY_PREFIX = "rails_performance:alerts:state"
      STATE_TTL = 7.days.to_i

      attr_reader :rule_id

      def initialize(rule_id)
        @rule_id = rule_id
      end

      def triggered?
        redis.get(triggered_key) == "true"
      end

      def mark_triggered!(timestamp = Time.now)
        redis.setex(triggered_key, STATE_TTL, "true")
        redis.setex(triggered_at_key, STATE_TTL, timestamp.to_i.to_s)
      end

      def mark_resolved!(timestamp = Time.now)
        redis.del(triggered_key)
        redis.setex(resolved_at_key, STATE_TTL, timestamp.to_i.to_s)
      end

      def triggered_at
        timestamp = redis.get(triggered_at_key)
        timestamp ? Time.at(timestamp.to_i) : nil
      end

      def resolved_at
        timestamp = redis.get(resolved_at_key)
        timestamp ? Time.at(timestamp.to_i) : nil
      end

      def first_breach_at
        timestamp = redis.get(first_breach_key)
        timestamp ? Time.at(timestamp.to_i) : nil
      end

      def record_breach(timestamp = Time.now)
        unless first_breach_at
          redis.setex(first_breach_key, STATE_TTL, timestamp.to_i.to_s)
        end
      end

      def clear_breaches
        redis.del(first_breach_key)
      end

      def breaching_duration
        return 0 unless first_breach_at
        Time.now - first_breach_at
      end

      private

      def redis
        RailsPerformance.redis
      end

      def triggered_key
        "#{REDIS_KEY_PREFIX}:#{rule_id}:triggered"
      end

      def triggered_at_key
        "#{REDIS_KEY_PREFIX}:#{rule_id}:triggered_at"
      end

      def resolved_at_key
        "#{REDIS_KEY_PREFIX}:#{rule_id}:resolved_at"
      end

      def first_breach_key
        "#{REDIS_KEY_PREFIX}:#{rule_id}:first_breach_at"
      end
    end
  end
end
