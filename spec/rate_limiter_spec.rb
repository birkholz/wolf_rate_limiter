require_relative '../rate_limiter'
require 'redis'

RSpec.describe RateLimiter do
  let(:time_window) { 30 }  # 30 seconds
  let(:max_requests) { 3 }
  let(:rate_limiter) { RateLimiter.new(time_window, max_requests) }
  let(:redis) { Redis.new(host: 'localhost', port: 6379) }

  # Clean up Redis before each test
  before(:each) do
    redis.flushdb
  end

  # Clean up Redis after each test
  after(:each) do
    redis.flushdb
  end

  # Ensure cleanup happens even if test is interrupted
  around(:each) do |example|
    begin
      example.run
    ensure
      redis.flushdb
    end
  end

  describe '#allow_request?' do
    context 'when requests are within rate limit' do
      let(:requests) do
        [
          { timestamp: 1700000010, user_id: 1 },
          { timestamp: 1700000011, user_id: 2 },
          { timestamp: 1700000020, user_id: 1 },
          { timestamp: 1700000035, user_id: 1 },
          { timestamp: 1700000040, user_id: 1 }
        ]
      end

      it 'allows all requests' do
        requests.each do |request|
          expect(rate_limiter.allow_request?(request[:timestamp], request[:user_id])).to be true
        end
      end
    end

    context 'when requests exceed rate limit' do
      let(:requests) do
        [
          { timestamp: 1700000010, user_id: 1 },
          { timestamp: 1700000011, user_id: 1 },
          { timestamp: 1700000012, user_id: 1 },
          { timestamp: 1700000013, user_id: 1 }  # This should be rejected
        ]
      end

      it 'rejects requests that exceed the rate limit' do
        requests.each do |request|
          result = rate_limiter.allow_request?(request[:timestamp], request[:user_id])
          if request[:timestamp] == 1700000013
            expect(result).to be false
          else
            expect(result).to be true
          end
        end
      end
    end

    context 'with complex request patterns' do
      let(:requests) do
        [
          # Initial requests from both users
          { timestamp: 1700000010, user_id: 1 },  # User 1 first request
          { timestamp: 1700000011, user_id: 2 },  # User 2 first request
          { timestamp: 1700000012, user_id: 2 },  # User 2 second request
          { timestamp: 1700000013, user_id: 2 },  # User 2 third request
          { timestamp: 1700000014, user_id: 2 },  # User 2 fourth request (should be rejected)

          # User 1 continues steady pace
          { timestamp: 1700000020, user_id: 1 },  # User 1 second request
          { timestamp: 1700000030, user_id: 1 },  # User 1 third request
          { timestamp: 1700000035, user_id: 1 },  # User 1 fourth request (should be rejected)

          # User 2 waits and tries again
          { timestamp: 1700000045, user_id: 2 },  # User 2 new first request
          { timestamp: 1700000046, user_id: 2 },  # User 2 new second request
          { timestamp: 1700000047, user_id: 2 },  # User 2 new third request

          # User 1 continues steady pace
          { timestamp: 1700000050, user_id: 1 },  # User 1 fifth request
          { timestamp: 1700000060, user_id: 1 }   # User 1 sixth request
        ]
      end

      it 'handles complex request patterns correctly' do
        results = requests.map do |request|
          rate_limiter.allow_request?(request[:timestamp], request[:user_id])
        end

        # First 3 requests from User 2 should be allowed
        expect(results[1..3]).to all(be true)

        # Fourth request from User 2 should be rejected
        expect(results[4]).to be false

        expect(results[0]).to be true  # First request
        expect(results[5..6]).to all(be true)  # Second and third requests
        expect(results[7]).to be false  # Fourth request (should be rejected)
        expect(results[11..12]).to all(be true)  # Fifth and sixth requests

        # User 2's new requests after waiting should all be allowed
        expect(results[8..10]).to all(be true)
      end
    end
  end
end
