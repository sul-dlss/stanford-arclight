# frozen_string_literal: true

# Search tips link for the catalog navbar
class SearchTipsLinkComponent < ViewComponent::Base
  def initialize(custom_classes: '')
    default_classes = 'searchtips-link ms-lg-2 mt-2 mt-lg-0'
    @classes = [default_classes, custom_classes].join(' ').strip
    super
  end
end
