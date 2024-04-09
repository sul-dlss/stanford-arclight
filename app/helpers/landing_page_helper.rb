# frozen_string_literal: true

# Landing Page helpers
module LandingPageHelper
  def format_hours(hours)
    return '' unless hours

    return hours.closed_note if hours.closed_note

    return "Open until #{format_time(hours.hours_today.closes_at_time)}" if hours.open_now?

    return "Closed until #{format_time(hours.next_open_hours.opens_at_time)}" if hours.next_open_hours

    'Closed'
  end

  def format_time(time)
    hour = time.hour % 12
    hour = 12 if hour.zero?
    minute = time.min
    am_pm = time.hour >= 12 ? 'pm' : 'am'

    time_only = minute.zero? ? "#{hour}#{am_pm}" : "#{hour}:#{format('%02d', minute)}#{am_pm}"
    return time_only if time.today? || time.tomorrow?

    "#{time_only} #{time.strftime('%A')}"
  end
end
