[![Tests](https://github.com/birkholz/wolf_rate_limiter/actions/workflows/test.yml/badge.svg)](https://github.com/birkholz/wolf_rate_limiter/actions/workflows/test.yml)

# Redis-based Rate Limiter

A sliding window rate limiter implementation written in Ruby using Redis and Lua scripting. This implementation ensures atomic operations and consistent rate limiting across multiple instances.

## Features

- Sliding window rate limiting
- Atomic operations using Lua scripting
- O(1) time complexity
- Automatic cleanup of expired requests
- Support for multiple users
- Thread-safe and distributed-friendly

## Implementation Details

### Time Complexity: O(1)

All Redis operations in the Lua script are O(1):

- `ZREMRANGEBYSCORE`: O(1) amortized (uses a skip list internally)
- `ZCARD`: O(1) (maintains a counter)
- `ZADD`: O(1) amortized
- `EXPIRE`: O(1)

The script executes atomically in Redis's memory with no additional network round trips or loops.

### Space Complexity: O(1)

For each user:

- One Redis key (`rate_limit:{user_id}`)
- One sorted set containing at most `max_requests` entries
- Each entry is a timestamp + random hex string, since timestamp is in seconds and collisions are possible
  - A future change could be to use microseconds since epoch instead of seconds, which would remove the need for the random characters and dependence on securerandom

The space used is bounded by:

- Number of active users × max_requests × (timestamp_size + random_hex_size)
- Keys automatically expire after `time_window` seconds
- Old entries are automatically removed by `ZREMRANGEBYSCORE`

### Memory Efficiency

- Expired requests are automatically removed
- Keys expire after the time window
- Only active users consume memory

### CPU Efficiency

- All operations are O(1)
- No client-side processing
- Single atomic transaction

## Usage

```ruby
# Initialize with a 30-second window and max 3 requests
rate_limiter = RateLimiter.new(30, 3)

# Check if a request should be allowed
allowed = rate_limiter.allow_request?(Time.now.to_i, "user_123")
```

## Requirements

- Redis server
- Ruby 3+
- redis gem

## Setup

Install dependencies:

```bash
bundle install
```

## How It Works

1. Each user's requests are stored in a Redis sorted set
2. The score is the timestamp, and the member is a unique request ID
3. When a request comes in:
   - Expired requests are removed
   - Current request count is checked
   - If under the limit, the request is added
   - The key's expiration is set to the window size
4. All operations happen atomically in a single Lua script

## Testing

Run the test suite with:

```bash
bundle exec rspec
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
