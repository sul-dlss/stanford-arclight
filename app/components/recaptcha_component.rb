# frozen_string_literal: true

# Component for rendering the recaptcha message and script
class RecaptchaComponent < ViewComponent::Base
  def initialize(action:)
    @action = action
    super
  end

  attr_reader :action

  def form_id
    "#{action}_form"
  end

  def execute_recaptcha_method_name
    "executeRecaptchaFor#{action.camelize}Async"
  end

  def set_input_method_name
    "setInputWithRecaptchaResponseTokenFor#{action.camelize}"
  end

  def data_attribute
    "g-recaptcha-response-data-#{action.dasherize}"
  end
end
