# frozen_string_literal: true

Blacklight::LayoutHelperBehavior.class_eval do
  # Class used for specifying main layout container classes. Can be
  # overwritten to return 'container-fluid' for Bootstrap full-width layout
  # @return [String]
  def container_classes
    # Use full-width layout on catalog#show and landing page
    if controller_name == 'catalog' && action_name == 'show' ||
       controller_name == 'landing_page' && action_name == 'index'
      return 'container-fluid'
    end

    'container'
  end
end
