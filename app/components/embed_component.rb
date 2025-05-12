# frozen_string_literal: true

# Render digital object links for a document
class EmbedComponent < Arclight::EmbedComponent
  EMBEDDABLE_RESOURCE_PATTERN = %r{https://purl.stanford.edu/([a-z]{2})(\d{3})([a-z]{2})(\d{4})}

  def embeddable_resources
    resources.select { |object| embeddable?(object) }.first(1)
  end

  def linked_resources
    (resources - embeddable_resources).select { |object| linkable?(object) }
  end

  def embeddable?(object)
    object.href.match?(EMBEDDABLE_RESOURCE_PATTERN)
  end

  def linkable?(object)
    uri = URI.parse(object.href)
    uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    false
  end
end
