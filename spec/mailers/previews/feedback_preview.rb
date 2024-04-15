# frozen_string_literal: true

# Preview all emails at http://localhost:3000/rails/mailers/feedback
class FeedbackPreview < ActionMailer::Preview
  def preview_email
    FeedbackMailer.submit_feedback(name: 'Testy Tester', email: 'testy@test.com', message: 'This is a test message')
  end
end
