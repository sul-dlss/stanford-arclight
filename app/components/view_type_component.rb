# frozen_string_literal: true

# This is a subclass of the Blacklight::Response::ViewTypeComponent so we can use our
# own custom view type component
class ViewTypeComponent < Blacklight::Response::ViewTypeComponent
  renders_many :view_items, ViewTypeButtonComponent
  def initialize(response:, search_state:, views: {}, selected: nil)
    super
  end

  def with_view(...)
    with_view_item(...)
  end

  def render?
    !@response.empty?
  end
end
