# frozen_string_literal: true

# Methods provided by blacklight and any overrides go here.
module BlacklightHelper
  include Blacklight::BlacklightHelperBehavior

  # This overrides a Blacklight provided method
  def container_classes
    unless (controller_name == 'catalog' && action_name == 'show') ||
           controller_name == 'landing_page'
      return 'container'
    end

    # Use full-width layout on catalog#show and landing page
    super
  end
end
