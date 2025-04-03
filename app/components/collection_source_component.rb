# frozen_string_literal: true

# Component for rendering information about the collection source
class CollectionSourceComponent < ViewComponent::Base
  attr_reader :document

  def initialize(document:)
    @document = document
    super
  end

  def source_message
    I18n.t("collection_source.#{source_translation_key}", last_indexed:).html_safe
  end

  def render?
    Settings.display_collection_source
  end

  private

  def source_translation_key
    return 'oac_html' unless from_aspace?

    Settings.aspace[:default].url.include?('prod') ? 'aspace.prod' : 'aspace.stage'
  end

  def last_indexed
    document.last_indexed&.strftime('%B %-d, %Y')
  end

  def from_aspace?
    document['repository_uri_ssi'] || document.collection['repository_uri_ssi']
  end
end
