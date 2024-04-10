# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Download finding aid file' do
  it 'downloads the file' do
    get '/download/ARS-0043.xml'

    expect(response).to have_http_status(:ok)
  end

  context 'when the finding aid does not exist' do
    it 'returns not found' do
      get '/download/does_not_exist.xml'

      expect(response).to have_http_status(:not_found)
    end
  end
end
