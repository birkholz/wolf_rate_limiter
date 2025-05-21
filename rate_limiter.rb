require 'redis'

class RateLimiter
  def initialize(time_window, max_requests)
    @time_window = time_window
    @max_requests = max_requests
    @redis = Redis.new(host: 'localhost', port: 6379)
  end

  def allow_request?(timestamp, user_id)
    key = "rate_limit:#{user_id}"
    window_start = timestamp - @time_window

    # First transaction: remove expired requests and count current requests
    results = @redis.multi do |redis|
      redis.zremrangebyscore(key, 0, window_start)
      redis.zcard(key)
    end

    # If under the limit, add the new request
    if results[1] < @max_requests
      @redis.multi do |redis|
        redis.zadd(key, timestamp, timestamp.to_s)
        redis.expire(key, @time_window)
      end
      true
    else
      false
    end
  end
end
