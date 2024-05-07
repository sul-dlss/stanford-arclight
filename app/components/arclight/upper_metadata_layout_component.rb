# frozen_string_literal: true

module Arclight
  # Overrides Arclight's override of Blacklight's MetadataFieldLayoutComponent
  # Here we change the label and value classes to match our designs
  class UpperMetadataLayoutComponent < Blacklight::MetadataFieldLayoutComponent
    def initialize(field:, label_class: 'col-md-3 ps-md-4', value_class: 'col-md-9')
      super
    end
  end
end
