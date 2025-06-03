# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ARK indexing and routing' do
  let(:valid_ark_id) { "ark:/#{Settings.ark_naan}/s19f562efc-dc7f-4ca7-bc10-d8456c3451a0" }
  let(:no_hyphen_ark_id) { "ark:/#{Settings.ark_naan}/s19f562efcdc7f4ca7bc10d8456c3451a0" }
  let(:missing_ark_id) { "ark:/#{Settings.ark_naan}/s19f562efc-dc7f-4ca7-bc10-d8456c3451b3" }
  # This ARK has no shoulder (s1)
  let(:invalid_ark_id) do
    "ark:/#{Settings.ark_naan}/9f562efc-dc7f-4ca7-bc10-d8372c3451a0"
  end

  context 'when a valid ARK is found in Solr' do
    before do
      visit "/findingaid/#{valid_ark_id}"
    end

    it 'redirects to the catalog page when ARK ID is found' do
      expect(page).to have_current_path('/catalog/sc0097')
    end

    it 'does not index extra ARK fields in the unitid' do
      expect(page).to have_no_content('Archival Resource Key')
      expect(page).to have_no_content('Previous Archival Resource Key')
    end
  end

  context 'when a component has an ARK' do
    before { visit 'sc0097_aspace_ref128_jpj' }

    it 'does not index extra ARK fields in the unitid' do
      expect(page).to have_no_content('Archival Resource Key')
      expect(page).to have_no_content('Previous Archival Resource Key')
    end
  end

  context 'when the route requests an ARK with no hyphens' do
    before do
      visit "/findingaid/#{no_hyphen_ark_id}"
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
