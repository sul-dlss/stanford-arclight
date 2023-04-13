# frozen_string_literal: true

##
# Override Arclight::DigitalObject to add Purl URL
# Demo data href sometimes only contains the ID
class DigitalObject
  attr_reader :label, :href

  def initialize(label:, href:)
    @label = label.presence || href
    @href = href
  end

  def self.from_json(json)
    object_data = JSON.parse(json)
    new(label: object_data['label'], href: normalize_href(object_data['href']))
  end

  # Make a usable Purl URL from whatever happens to be in
  # the DigitalObject href in the sample data.
  # Ideally, this value would be consistent, but it is not currently.
  def self.normalize_href(href)
    # Some complete Purl URLs do not use https, convert them
    return href.gsub('http://', 'https://') if href.match?(%r{https?://purl.stanford.edu})
    # Some hrefs contain only a druid, convert them to a complete Purl URL
    return "https://purl.stanford.edu/#{href}" if href.match?(/^([a-z]{2})(\d{3})([a-z]{2})(\d{4})$/)

    href
  end
end
