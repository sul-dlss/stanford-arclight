# frozen_string_literal: true

# This require seems to be needed in order for ViewComponent::VERSION
# to be available in CI:
# https://github.com/projectblacklight/blacklight/blob/b1249e0e5947ea146e5dfcc903f70e5647da29e3/lib/blacklight/component.rb#L14
require 'view_component/version'

# Overrides of Blacklight's MetadataFieldLayoutComponent
# Here we change the label and value classes to match our designs
class AccessMetadataLayoutComponent < Blacklight::MetadataFieldLayoutComponent
  def initialize(field:, label_class: 'col-12', value_class: 'col-12')
    super
  end
end
