# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Download finding aid file' do
  it 'downloads the file' do
    get '/download/ars-0043_ambassador-auditorium-collection.xml'

    expect(response).to have_http_status(:ok)
    expect(Nokogiri::XML::Document.parse(response.body).at_css('ead').namespaces).to(
      eq({ 'xmlns' => 'urn:isbn:1-931666-22-9',
           'xmlns:xlink' => 'http://www.w3.org/1999/xlink',
           'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance' })
    )
  end

  context 'when an EAD without namespaces is requested' do
    it 'downloads an EAD without namespaces' do
      get '/download/ars-0043_ambassador-auditorium-collection.xml?without_namespace=true'

      expect(response).to have_http_status(:ok)
      expect(Nokogiri::XML::Document.parse(response.body).at_css('ead').namespaces).to be_empty
    end
  end

  context 'when the document does not exist in the Solr index' do
    it 'returns not found' do
      get '/download/does_not_exist.xml'

      expect(response).to have_http_status(:not_found)
    end
  end

  context 'when the finding aid file does not exist on the file system' do
    let(:blacklight_config) { CatalogController.blacklight_config }
    let(:solr_conn) { blacklight_config.repository_class.new(blacklight_config).connection }

    before do
      solr_conn.add({
                      id: 'abc123',
                      ead_filename_ssi: 'abc123.xml',
                      repository_ssm: 'Archive of Recorded Sound'
                    })
      solr_conn.commit
    end

    it 'returns not found' do
      get '/download/abc123.xml'

      expect(response).to have_http_status(:not_found)
    end
  end
end
