# frozen_string_literal: true

# Overrides of Blacklight's MetadataFieldLayoutComponent
# Here we change the label and value classes to match our designs
class AccessMetadataLayoutComponent < Blacklight::MetadataFieldLayoutComponent
  def initialize(field:, label_class: 'col-12', value_class: 'col-12')
    super
  end
end
