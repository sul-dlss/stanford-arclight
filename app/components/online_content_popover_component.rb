# frozen_string_literal: true

# Component for rendering an online content popover
class OnlineContentPopoverComponent < ViewComponent::Base
  def icon_with_popover
    tag.button(class: 'al-online-content-icon btn',
               data: { 'bs-toggle': 'popover',
                       'bs-placement': 'top',
                       'bs-content': 'Includes digital content' },
               aria: { label: 'al-online-content-icon' }) do
      helpers.blacklight_icon(:online).to_s
    end
  end
end
