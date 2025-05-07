# frozen_string_literal: true

# This is a subclass of the Blacklight::Response::ViewTypeButtonComponent so we can use our
# set our own classes on the buttons
class ViewTypeButtonComponent < Blacklight::Response::ViewTypeButtonComponent
  def initialize(view:, key: nil, selected: false, search_state: nil, classes: 'btn btn-outline-primary btn-icon')
    super
  end
end
