# frozen_string_literal: true

# Creates feedback emails
class FeedbackMailer < ApplicationMailer
  def submit_feedback(name:, email:, reporting_from:, message:)
    @name = name
    @email = email
    @message = message
    @reporting_from = reporting_from
    mail(to: ENV.fetch('FEEDBACK_EMAIL', 'blackhole@stanford.edu'),
         from: 'no-reply@library.stanford.edu')
  end
end
