
module Stackato
  module RetryWithIncreasingIntervals    
    def retry(nats_connection_intervals)
      wait_interval = nats_connection_intervals.fetch(:initial_wait_interval, 0.5)
      wait_interval_increase_factor= nats_connection_intervals.fetch(:wait_interval_increase_factor, 1.2)
      max_wait_interval = nats_connection_intervals.fetch(:max_wait_interval, 60)
      max_total_wait_time = nats_connection_intervals.fetch(:max_total_wait_time, 600)
      max_wait_time = Time.now + max_total_wait_time
      iters = 1
      while Time.now < max_wait_time
        break if yield(iters, wait_interval)
        sleep(wait_interval)
        if wait_interval < max_wait_interval
          wait_interval *= wait_interval_increase_factor
          wait_interval = max_wait_interval if wait_interval > max_wait_interval
        end
        iters += 1
      end
    end
    module_function :retry
  end
end
