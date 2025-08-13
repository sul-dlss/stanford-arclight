# frozen_string_literal: true

# Render various actions for a collection (e.g. requesting, download links, etc)
class CollectionContextComponent < ViewComponent::Base
  def initialize(presenter:, download_component:)
    super()

    @collection = presenter.document.collection
    @download_component = download_component
  end

  attr_reader :collection

  def title
    helpers.link_to_document(collection)
  end

  def unitid
    render CollectionUnitidPillComponent.new(document: collection)
  end

  def document_download
    render @download_component.new(downloads: collection.downloads) ||
           Arclight::DocumentDownloadComponent.new(downloads: collection.downloads)
  end

  def collection_info
    render CollectionInfoComponent.new(collection: collection)
  end
end
