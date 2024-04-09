# frozen_string_literal: true

# Contains our overrides for the BlacklightHelpers
module BlacklightHelper
  include Blacklight::BlacklightHelperBehavior

  # The landing page defines its own container classes
  def container_classes
    return 'landing-page-container' if controller_name == 'landing_page' && action_name == 'index'

    super
  end
end
