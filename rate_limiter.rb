require 'redis'
require 'securerandom'

class RateLimiter
  # Using Lua script for atomic operations:
  # 1. Ensures all Redis operations (removing expired requests, counting current requests,
  #    and adding new requests) happen in a single atomic transaction
  # 2. Eliminates race conditions that could occur with separate Redis commands
  # 3. Reduces network round trips by executing all operations in Redis's memory
  # 4. Maintains O(1) time complexity while guaranteeing consistency
  LUA_SCRIPT = <<~LUA
    local key = KEYS[1]
    local timestamp = tonumber(ARGV[1])
    local window_start = timestamp - tonumber(ARGV[2])
    local max_requests = tonumber(ARGV[3])
    local request_id = ARGV[4]

    -- Remove expired requests (using exclusive boundary)
    redis.call('ZREMRANGEBYSCORE', key, 0, '(' .. window_start)

    -- Count requests in the window
    local request_count = redis.call('ZCARD', key)

    -- If under the limit, add the request
    if request_count < max_requests then
        redis.call('ZADD', key, timestamp, request_id)
        redis.call('EXPIRE', key, ARGV[2])
        return 1
    end
    return 0
  LUA

  def initialize(time_window, max_requests)
    @time_window = time_window
    @max_requests = max_requests
    @redis = Redis.new(host: 'localhost', port: 6379)
    @script = @redis.script(:load, LUA_SCRIPT)
  end

  def allow_request?(timestamp, user_id)
    key = "rate_limit:#{user_id}"
    # Timestamps are in seconds, so we add a random 4-character hex string to avoid collisions
    request_id = "#{timestamp}:#{SecureRandom.hex(4)}"

    # Execute the Lua script atomically
    result = @redis.evalsha(
      @script,
      keys: [key],
      argv: [timestamp, @time_window, @max_requests, request_id]
    )

    # 1 means allowed, 0 means rejected
    result == 1
  end
end
