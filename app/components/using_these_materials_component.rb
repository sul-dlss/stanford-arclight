# frozen_string_literal: true

# Component for rendering information about using the collection
class UsingTheseMaterialsComponent < ViewComponent::Base
  attr_reader :document

  def initialize(document:)
    @document = document
    super()
  end

  def repository_url
    document.repository_config.url
  end

  def restrictions
    text = document.collection.fetch('accessrestrict_tesim', ['']).join(' ')

    if text.length > 250
      truncated = truncate(text, length: 250, omission: '', separator: ' ')
      text_with_link = "#{truncated} #{link_to('[...]', '#access-and-use')}"
      text_with_link.html_safe # rubocop:disable Rails/OutputSafety
    else
      text
    end
  end
end
