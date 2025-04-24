# frozen_string_literal: true

module LandingPage
  # Provide a library hours entry for a landing page access card
  class LibraryHoursComponent < ViewComponent::Base
    def initialize(key:)
      @key = key.to_s
      super
    end

    attr_reader :key

    def icon
      helpers.blacklight_icon('library_hours', classes: ['me-1', closed_icon_class])
    end

    def formatted_hours
      return link_to(hours_text, hours_link) if hours_link

      hours_text
    end

    delegate :seconds_until_next_half_hour, to: :TimeService

    def render?
      hours_location_config && hours.present?
    end

    private

    def hours_text
      return hours.closed_note if hours.closed_note

      return "Open until #{format_time(hours.hours_today.closes_at_time)}" if hours.open_now?

      return "Closed until #{format_time(hours.next_open_hours.opens_at_time)}" if hours.next_open_hours

      'Closed'
    end

    def hours_link
      hours_location_config&.url
    end

    def hours
      @hours ||= LibraryHours.from_config(hours_location_config)
    end

    def hours_location_config
      Settings.hours_locations.find { |entry| entry.library == key }
    end

    def closed_icon_class
      'library-closed' unless hours.open_now?
    end

    def format_time(time)
      hour = time.hour % 12
      hour = 12 if hour.zero?
      minute = time.min
      am_pm = time.hour >= 12 ? 'pm' : 'am'

      time_only = minute.zero? ? "#{hour}#{am_pm}" : "#{hour}:#{Kernel.format('%02d', minute)}#{am_pm}"
      return time_only if time.today? || time.tomorrow?

      "#{time_only} #{time.strftime('%A')}"
    end
  end
end
