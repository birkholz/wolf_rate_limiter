require 'redis'
require 'securerandom'

class RateLimiter
  def initialize(time_window, max_requests)
    @time_window = time_window
    @max_requests = max_requests
    @redis = Redis.new(host: 'localhost', port: 6379)
  end

  def allow_request?(timestamp, user_id)
    key = "rate_limit:#{user_id}"
    window_start = timestamp - @time_window

    # First transaction: remove expired requests and count requests in the window
    results = @redis.multi do |redis|
      # Remove requests older than window_start (inclusive)
      redis.zremrangebyscore(key, 0, window_start - 1)
      # Count requests in the window (inclusive of window_start, inclusive of current timestamp)
      redis.zcount(key, window_start, timestamp)
    end

    # If under the limit, add the new request
    if results[1] < @max_requests
      @redis.multi do |redis|
        # Add request with timestamp as score and a unique member to prevent timestamp collisions
        redis.zadd(key, timestamp, "#{timestamp}:#{SecureRandom.hex(4)}")
        # Set expiration, so absent users will be cleaned up automatically
        redis.expire(key, @time_window)
      end
      true
    else
      false
    end
  end
end
