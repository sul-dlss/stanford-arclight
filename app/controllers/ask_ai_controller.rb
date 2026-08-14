# frozen_string_literal: true

# Controller for the prototype "Ask AI" chat page
class AskAiController < ApplicationController
  def index
    @question = params[:q].presence || t('ask_ai.fallback_question')
  end
end
