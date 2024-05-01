# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AspaceClient do
  let(:url) { 'http://example.com:8089' }
  let(:user) { 'aspace_user' }
  let(:password) { 'aspace_password' }
  let(:client) { described_class.new(url:, user:, password:) }

  before do
    # Authentication request
    stub_request(:post,
                 "#{url}/users/#{user}/login?password=#{password}").to_return(body: { session: 'token1' }.to_json)
  end

  describe '#initialize' do
    context 'without a url argument' do
      it 'raises an error' do
        expect { described_class.new(url: nil, user: 'user', password: 'password') }.to raise_error(ArgumentError)
      end
    end
  end

  describe '#repositories' do
    it 'sends an authenticated request with correct auth header to the repositories address' do
      stub_request(:get, "#{url}/repositories").to_return(body: {}.to_json)
      client.repositories
      expect(WebMock).to have_requested(:get, "#{url}/repositories")
                     .with(headers: { 'X-ArchivesSpace-Session' => 'token1' }).once
    end
  end

  describe '#resource_description' do
    it 'sends an authenticated request with correct auth header to the resource_desriptions address' do
      request_url = "#{url}/repositories/2/resource_descriptions/10208.xml?include_daos=true&numbered_cs=true"
      stub_request(:get, request_url)
      client.resource_description('repositories/2/resources/10208')
      expect(WebMock).to have_requested(:get, request_url)
        .with(headers: { 'X-ArchivesSpace-Session' => 'token1' }).once
    end

    context 'without a resource_uri argument' do
      it 'raises an error' do
        expect { client.resource_description }.to raise_error(ArgumentError)
      end
    end
  end

  describe '#published_resource_uris' do
    let(:aspace_query) { instance_double(AspaceClient::AspaceQuery) }

    before do
      allow(AspaceClient::AspaceQuery).to receive(:new).with(client:, repository_id: 11, updated_after: nil)
                                                       .and_return(aspace_query)
    end

    it 'returns an instance of AspaceQuery' do
      expect(client.published_resource_uris(repository_id: 11)).to eq aspace_query
    end

    context 'without a repository_id argument' do
      it 'raises an error' do
        expect { client.published_resource_uris }.to raise_error(ArgumentError)
      end
    end
  end

  describe '#all_published_resource_uris_by' do
    let(:published_resource_uris) do
      [{ 'ead_id' => 'abc123', 'uri' => '/repositories/3/resources/2' },
       { 'ead_id' => 'abc456', 'uri' => '/repositories/3/resources/4' }]
    end

    before do
      allow(AspaceClient::AspaceQuery).to receive(:new).with(client:, repository_id: 3, updated_after: nil)
                                                       .and_return(published_resource_uris)
    end

    it 'returns an array of published resource uris' do
      expect(client.all_published_resource_uris_by(repository_id: 3)).to eq(
        ['/repositories/3/resources/2', '/repositories/3/resources/4']
      )
    end
  end

  describe '#authenticated_get' do
    it 'sends an authenticated request with correct auth header to the specified address' do
      stub_request(:get, "#{url}/some_request")
      client.authenticated_get('some_request')
      expect(WebMock).to have_requested(:get,
                                        "#{url}/some_request")
        .with(headers: { 'X-ArchivesSpace-Session' => 'token1' }).once
    end

    context 'without a path argument' do
      it 'raises an error' do
        expect { client.resource_description }.to raise_error(ArgumentError)
      end
    end

    context 'when the HTTP response is bad' do
      it 'raises an error' do
        stub_request(:get, "#{url}/some_request").to_raise(Net::HTTPBadResponse)
        expect { client.authenticated_get('some_request') }.to raise_error(StandardError)
      end
    end
  end
end
