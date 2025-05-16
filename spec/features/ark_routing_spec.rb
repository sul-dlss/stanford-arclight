# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ARK indexing and routing' do
  let(:valid_ark_id) { 'ark:/22236/s19f562efc-dc7f-4ca7-bc10-d8456c3451a0' }
  let(:missing_ark_id) { 'ark:/22236/s19f562efc-dc7f-4ca7-bc10-d8456c3451b3' }
  let(:invalid_ark_id) { 'ark:/22236/9f562efc-dc7f-4ca7-bc10-d8372c3451a0' } # This ARK has no shoulder (s1)

  context 'when a valid ARK is found in Solr' do
    before do
      visit "/findingaid/#{valid_ark_id}"
    end

    it 'redirects to the catalog page when ARK ID is found' do
      expect(page).to have_current_path('/catalog/sc0097')
    end
  end

  context 'when a valid ARK has no match in Solr' do
    before do
      visit "/findingaid/#{missing_ark_id}"
    end

    it 'shows not found message' do
      expect(page).to have_content('Finding aid not found')
      expect(page.status_code).to eq(404)
    end
  end

  context 'with an invalid ARK' do
    before do
      visit "/findingaid/#{invalid_ark_id}"
    end

    it 'shows not found message' do
      expect(page.status_code).to eq(404)
    end
  end
end
