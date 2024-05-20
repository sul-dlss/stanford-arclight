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

  def landing_page?
    controller_name == 'landing_page' && action_name == 'index'
  end

  def render_using_these_materials(args)
    render partial: 'catalog/using_these_materials', locals: { repository: args[:document].repository_config }
  end
end
