# frozen_string_literal: true

# Finds the next half hour from now, but lead the clock by 30s.
class TimeService
  def self.next_half_hour
    now = Time.current
    now.at_beginning_of_hour + (now.min < 30 ? 30.minutes : 60.minutes)
  end

  def self.seconds_until_next_half_hour
    delta = next_half_hour - Time.current
    return 5.seconds if delta < 5.seconds

    return 30.minutes if delta > 30.minutes

    delta
  end
end
