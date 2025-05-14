# frozen_string_literal: true

# # This is a subclass of Arclight::ExpandHierarchyButtonComponent so we can use our
# set our own classes on the buttons
class ExpandHierarchyButtonComponent < Arclight::ExpandHierarchyButtonComponent
  def initialize(path:, classes: 'btn btn-outline-primary btn-sm mb-3')
    super
  end
end
