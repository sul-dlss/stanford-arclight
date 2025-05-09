# frozen_string_literal: true

# Component for rendering information about using the collection
class UsingTheseMaterialsComponent < ViewComponent::Base
  attr_reader :document

  def initialize(document:)
    @document = document
    super
  end

  def repository_url
    document.repository_config.url
  end

  def restrictions
    document.collection.fetch('accessrestrict_html_tesm', ['']).first.html_safe # rubocop:disable Rails/OutputSafety
  end
end
