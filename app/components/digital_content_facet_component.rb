# frozen_string_literal: true

# component for rendering a digital content facet
class DigitalContentFacetComponent < Blacklight::Facets::ListComponent
  def icon_with_popover
    render OnlineContentPopoverComponent.new
  end
end
