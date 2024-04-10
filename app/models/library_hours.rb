# frozen_string_literal: true

# Uses LibraryHoursAPI to fetch library hours
class LibraryHours
  attr_reader :closed_note, :label, :library_slug, :location_slug, :url

  def self.from_config(config)
    new(label: config['label'],
        library_slug: config['library'],
        location_slug: config['location'],
        url: config['url'],
        closed_note: config['closed_note'])
  end

  def initialize(label:, library_slug:, location_slug:, url:, closed_note: nil)
    @label = label
    @library_slug = library_slug
    @location_slug = location_slug
    @closed_note = closed_note
    @url = url
  end

  def open_now?
    return false if closed_note

    hours_today && hours_today.opens_at_time <= now && hours_today.closes_at_time >= now
  end

  def next_open_hours
    return nil if closed_note

    weekly_library_hours.find { |hours| hours.open? && hours.opens_at_time > now && hours.closes_at_time > now }
  end

  def hours_today
    return nil if closed_note

    weekly_library_hours.first
  end

  private

  def weekly_library_hours
    range = { from: Time.zone.today, to: Time.zone.today + 7.days }
    @weekly_library_hours ||= LibraryHoursApi::Request.new(library_slug, location_slug, range).get.hours
  end

  def now
    Time.zone.now
  end
end
