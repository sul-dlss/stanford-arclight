# frozen_string_literal: true

# Finds the next half hour from now, but lead the clock by 30s.
class TimeService
  def self.next_half_hour
    now = Time.current
    next30 = now.at_beginning_of_hour + (now.min < 30 ? 30.minutes : 60.minutes)

    return next30 + 5.seconds if next30 - now < 5.seconds

    next30
  end
end
