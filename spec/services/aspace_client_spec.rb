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
    it 'fails without the url arg' do
      expect { described_class.new(url: nil, user: 'user', password: 'password') }.to raise_error(ArgumentError)
    end

    it 'fails without the user arg' do
      expect do
        described_class.new(url: 'http://example.com:8089', user: nil, password: 'password')
      end.to raise_error(ArgumentError)
    end

    it 'fails without the password arg' do
      expect do
        described_class.new(url: 'http://example.com:8089', user: 'user', password: nil)
      end.to raise_error(ArgumentError)
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
    it 'fails if you do not pass resource_uri' do
      expect { client.resource_description }.to raise_error(ArgumentError)
    end

    it 'sends an authenticated request with correct auth header to the resource_desriptions address' do
      stub_request(:get, "#{url}/repositories/2/resource_descriptions/10208.xml?include_daos=true")
      client.resource_description('repositories/2/resources/10208')
      expect(WebMock).to have_requested(:get,
                                        "#{url}/repositories/2/resource_descriptions/10208.xml?include_daos=true")
        .with(headers: { 'X-ArchivesSpace-Session' => 'token1' }).once
    end
  end

  describe '#published_resource_uris' do
    let(:aspace_query) { instance_double(AspaceClient::AspaceQuery) }

    before do
      allow(AspaceClient::AspaceQuery).to receive(:new).with(client:, repository_id: 11, updated_after: nil)
                                                       .and_return(aspace_query)
    end

    it 'fails if you do not pass repository_id' do
      expect { client.published_resource_uris }.to raise_error(ArgumentError)
    end

    it 'returns an instance of AspaceQuery' do
      expect(client.published_resource_uris(repository_id: 11)).to eq aspace_query
    end
  end

  describe '#authenticated_get' do
    it 'fails if you do not pass a path' do
      expect { client.resource_description }.to raise_error(ArgumentError)
    end

    it 'returns an error if the response is bad' do
      stub_request(:get, "#{url}/some_request").to_raise(Net::HTTPBadResponse)
      expect { client.authenticated_get('some_request') }.to raise_error(StandardError)
    end

    it 'sends an authenticated request with correct auth header to the specified address' do
      stub_request(:get, "#{url}/some_request")
      client.authenticated_get('some_request')
      expect(WebMock).to have_requested(:get,
                                        "#{url}/some_request")
        .with(headers: { 'X-ArchivesSpace-Session' => 'token1' }).once
    end
  end
end
