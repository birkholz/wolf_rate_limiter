require 'rspec'
require_relative '../rate_limiter'

RSpec.describe RateLimiter do
  let(:time_window) { 30 }  # 30 seconds
  let(:max_requests) { 3 }  # 3 requests per window
  let(:rate_limiter) { RateLimiter.new(time_window, max_requests) }
  let(:user_id) { "user1" }

  before(:each) do
    # Clear Redis before each test
    Redis.new(host: 'localhost', port: 6379).flushall
  end

  describe '#allow_request?' do
    it 'allows requests within the rate limit' do
      # Simulate rapid requests
      current_time = Time.now.to_i

      # First request should be allowed
      expect(rate_limiter.allow_request?(current_time, user_id)).to be true

      # Second request 1 second later
      expect(rate_limiter.allow_request?(current_time + 1, user_id)).to be true

      # Third request 2 seconds later
      expect(rate_limiter.allow_request?(current_time + 2, user_id)).to be true

      # Fourth request 3 seconds later should be rejected
      expect(rate_limiter.allow_request?(current_time + 3, user_id)).to be false
    end

    it 'allows new requests after the time window expires' do
      current_time = Time.now.to_i

      # Make max_requests
      max_requests.times do |i|
        expect(rate_limiter.allow_request?(current_time + i, user_id)).to be true
      end

      # Next request should be rejected
      expect(rate_limiter.allow_request?(current_time + max_requests, user_id)).to be false

      # Request after time window should be allowed
      expect(rate_limiter.allow_request?(current_time + time_window + 1, user_id)).to be true
    end

    it 'handles multiple users independently' do
      current_time = Time.now.to_i
      user2 = "user2"

      # User 1 makes max_requests
      max_requests.times do |i|
        expect(rate_limiter.allow_request?(current_time + i, user_id)).to be true
      end

      # User 1's next request should be rejected
      expect(rate_limiter.allow_request?(current_time + max_requests, user_id)).to be false

      # User 2 should still be able to make requests
      expect(rate_limiter.allow_request?(current_time + max_requests, user2)).to be true
    end

    it 'handles complex request patterns' do
      current_time = Time.now.to_i

      # First request
      expect(rate_limiter.allow_request?(current_time, user_id)).to be true

      # Second request 5 seconds later
      expect(rate_limiter.allow_request?(current_time + 5, user_id)).to be true

      # Third request 10 seconds later
      expect(rate_limiter.allow_request?(current_time + 10, user_id)).to be true

      # Fourth request 15 seconds later (should be rejected)
      expect(rate_limiter.allow_request?(current_time + 15, user_id)).to be false

      # Fifth request 35 seconds later (should be allowed as first request expired)
      expect(rate_limiter.allow_request?(current_time + 35, user_id)).to be true
    end

    it 'coordinates rate limiting across multiple instances' do
      current_time = Time.now.to_i
      # Create a second instance of RateLimiter
      rate_limiter2 = RateLimiter.new(time_window, max_requests)

      # First instance makes 2 requests
      expect(rate_limiter.allow_request?(current_time, user_id)).to be true
      expect(rate_limiter.allow_request?(current_time + 1, user_id)).to be true

      # Second instance makes the third request
      expect(rate_limiter2.allow_request?(current_time + 2, user_id)).to be true

      # First instance tries to make a fourth request (should be rejected)
      expect(rate_limiter.allow_request?(current_time + 3, user_id)).to be false

      # Second instance also tries to make a fourth request (should be rejected)
      expect(rate_limiter2.allow_request?(current_time + 4, user_id)).to be false

      # After window expires, second instance should be able to make a new request
      expect(rate_limiter2.allow_request?(current_time + time_window + 1, user_id)).to be true
    end

    it 'handles requests at exactly the same timestamp' do
      current_time = Time.now.to_i

      # Make max_requests at exactly the same timestamp
      max_requests.times do
        expect(rate_limiter.allow_request?(current_time, user_id)).to be true
      end

      # Next request at same timestamp should be rejected
      expect(rate_limiter.allow_request?(current_time, user_id)).to be false
    end

    it 'handles requests exactly at window boundaries' do
      current_time = Time.now.to_i

      # Make a request at the start of the window
      expect(rate_limiter.allow_request?(current_time, user_id)).to be true

      # Make a request exactly at the end of the window
      expect(rate_limiter.allow_request?(current_time + time_window, user_id)).to be true

      # Make a request just after the window
      expect(rate_limiter.allow_request?(current_time + time_window + 1, user_id)).to be true
    end

    it 'handles rapid concurrent requests' do
      current_time = Time.now.to_i
      rate_limiter2 = RateLimiter.new(time_window, max_requests)
      rate_limiter3 = RateLimiter.new(time_window, max_requests)

      # Simulate concurrent requests from different instances
      results = [
        rate_limiter.allow_request?(current_time, user_id),
        rate_limiter2.allow_request?(current_time, user_id),
        rate_limiter3.allow_request?(current_time, user_id)
      ]

      # Only max_requests should be allowed
      expect(results.count(true)).to eq(max_requests)
    end

    it 'handles many users with different request patterns' do
      current_time = Time.now.to_i
      users = (1..10).map { |i| "user#{i}" }

      # Each user makes requests at different intervals
      users.each_with_index do |user, index|
        # First request
        expect(rate_limiter.allow_request?(current_time + index, user)).to be true

        # Second request after a delay
        expect(rate_limiter.allow_request?(current_time + index + 5, user)).to be true

        # Third request after another delay
        expect(rate_limiter.allow_request?(current_time + index + 10, user)).to be true

        # Fourth request should be rejected
        expect(rate_limiter.allow_request?(current_time + index + 15, user)).to be false
      end
    end

    it 'handles requests with very long time windows' do
      long_window = 3600  # 1 hour
      long_limiter = RateLimiter.new(long_window, max_requests)
      current_time = Time.now.to_i

      # Make requests spread across the long window
      expect(long_limiter.allow_request?(current_time, user_id)).to be true
      expect(long_limiter.allow_request?(current_time + 1800, user_id)).to be true  # 30 minutes later
      expect(long_limiter.allow_request?(current_time + 3500, user_id)).to be true  # ~58 minutes later
      expect(long_limiter.allow_request?(current_time + 3600, user_id)).to be false # 1 hour later
    end

    it 'handles requests with very short time windows' do
      short_window = 1  # 1 second
      short_limiter = RateLimiter.new(short_window, max_requests)
      current_time = Time.now.to_i

      # Make requests within the short window
      expect(short_limiter.allow_request?(current_time, user_id)).to be true
      expect(short_limiter.allow_request?(current_time + 0.1, user_id)).to be true
      expect(short_limiter.allow_request?(current_time + 0.2, user_id)).to be true
      expect(short_limiter.allow_request?(current_time + 0.3, user_id)).to be false

      # Wait for window to expire
      expect(short_limiter.allow_request?(current_time + 1.1, user_id)).to be true
    end

    it 'consistently rejects requests after reaching the limit' do
      current_time = Time.now.to_i

      # Make max_requests to reach the limit
      max_requests.times do |i|
        expect(rate_limiter.allow_request?(current_time + i, user_id)).to be true
      end

      # Try multiple requests in quick succession - all should be rejected
      5.times do |i|
        expect(rate_limiter.allow_request?(current_time + max_requests + i, user_id)).to be false
      end

      # Try requests at different intervals within the window - all should be rejected
      expect(rate_limiter.allow_request?(current_time + 10, user_id)).to be false
      expect(rate_limiter.allow_request?(current_time + 15, user_id)).to be false
      expect(rate_limiter.allow_request?(current_time + 20, user_id)).to be false

      # Only after the window expires should new requests be allowed
      expect(rate_limiter.allow_request?(current_time + time_window + 1, user_id)).to be true
    end
  end
end
