# frozen_string_literal: true

# this is overriding the default button classes set in Blacklight
class DropdownComponent < Blacklight::System::DropdownComponent
  def before_render
    # (we want to use btn-outline-primary for Arclight instead of btn-outline-secondary)
    with_button(label: button_label, classes: %w[btn btn-outline-primary dropdown-toggle])
    super
  end
end
