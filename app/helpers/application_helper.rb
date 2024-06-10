# frozen_string_literal: true

module ApplicationHelper
  include Blacklight::LocalePicker::LocaleHelper

  def additional_locale_routing_scopes
    [blacklight, arclight_engine]
  end

  # Disables display of icons from Dashlane password manager
  # See https://github.com/sul-dlss/vt-arclight/issues/495
  def dashlane_ignore
    { 'form-type' => 'other' }
  end

  # This overrides a Blacklight provided method
  def container_classes
    unless controller_name == 'catalog' && action_name == 'show' ||
           controller_name == 'landing_page'
      return 'container'
    end

    # Use full-width layout on catalog#show and landing page
    super
  end
end
