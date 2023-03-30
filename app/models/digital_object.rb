# frozen_string_literal: true

##
# Override Arclight::DigitalObject to add Purl URL
# Demo data href only contains the ID
class DigitalObject
  attr_reader :label, :href

  def initialize(label:, href:)
    @label = label.presence || href
    @href = href
  end

  def self.from_json(json)
    object_data = JSON.parse(json)
    new(label: object_data['label'], href: "https://purl.stanford.edu/#{object_data['href']}")
  end
end
