# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RecaptchaComponent, type: :component do
  subject(:component) { described_class.new(action: 'email_form') }

  before do
    render_inline(component)
  end

  it 'renders the recaptcha info and script' do
    expect(page).to have_text('window.executeRecaptchaForEmailFormAsync()')
    expect(page).to have_text('setInputWithRecaptchaResponseTokenForEmailForm')
    expect(page).to have_text('g-recaptcha-response-data-email-form')
    expect(page).to have_text('This site is protected by reCAPTCHA and the Google Privacy Policy')
  end
end
