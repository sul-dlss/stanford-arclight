# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # Adds a few additional behaviors into the application controller
  include Blacklight::Controller
  include Blacklight::LocalePicker::Concern
  layout :determine_layout if respond_to? :layout

  # Override Blacklight so that the "Login" link doesn't display
  def has_user_authentication_provider? # rubocop:disable Naming/PredicateName
    false
  end
end
