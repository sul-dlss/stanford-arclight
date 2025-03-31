# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AspaceClient do
  let(:uri) { 'http://aspace_user:aspace_password@example.com:8089' }
  let(:client) { described_class.new(uri:) }

  before do
    # Authentication request
    stub_request(:post,
                 'http://example.com:8089/users/aspace_user/login').to_return(body: { session: 'token1' }.to_json)
  end

  describe '#initialize' do
    context 'without a complete uri argument' do
      it 'raises an error' do
        expect { described_class.new(uri: 'http://example.com:8089') }.to raise_error(ArgumentError)
      end
    end
  end

  describe '#repositories' do
    it 'sends an authenticated request with correct auth header to the repositories address' do
      stub_request(:get, 'http://example.com:8089/repositories').to_return(body: {}.to_json)
      client.repositories
      expect(WebMock).to have_requested(:get, 'http://example.com:8089/repositories')
                     .with(headers: { 'X-ArchivesSpace-Session' => 'token1' }).once
    end
  end

  describe '#resource_description' do
    it 'sends an authenticated request with correct auth header to the resource_desriptions address' do
      request_url = 'http://example.com:8089/repositories/2/resource_descriptions/10208.xml?include_daos=true&numbered_cs=true'
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
    let(:aspace_query) { instance_double(AspaceQuery) }

    before do
      allow(AspaceQuery).to receive(:new).with(client:, repository_id: 11, updated_after: nil,
                                               options: { published: true, suppressed: false })
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
      allow(AspaceQuery).to receive(:new).with(client:, repository_id: 3, updated_after: nil,
                                               options: { published: true, suppressed: false })
                                         .and_return(published_resource_uris)
    end

    it 'returns an array of published resource uris' do
      expect(client.all_published_resource_uris_by(repository_id: 3)).to eq(
        ['/repositories/3/resources/2', '/repositories/3/resources/4']
      )
    end
  end

  describe '#published_resource_with_updated_component_uris' do
    let(:aspace_query) { instance_double(AspaceQuery) }

    before do
      allow(AspaceQuery).to receive(:new)
        .with(client:, repository_id: 11, updated_after: '2024-05-06', primary_type: nil,
              options: { contains_fields: ['resource'], select_fields: ['resource'],
                         exclude_field_values: { 'resource' => nil } })
        .and_return(aspace_query)
      allow(AspaceQuery).to receive(:new)
        .with(client:, repository_id: 11,
              options: { published: true, suppressed: false, limit_results_to_uris: [] }).and_return(aspace_query)
      allow(aspace_query).to receive(:each).and_return([])
    end

    it 'returns an instance of AspaceQuery' do
      expect(client.published_resource_with_updated_component_uris(repository_id: 11,
                                                                   updated_after: '2024-05-06')).to eq aspace_query
    end

    context 'without a repository_id argument' do
      it 'raises an error' do
        expect do
          client.published_resource_with_updated_component_uris(updated_after: '2024-05-06')
        end.to raise_error(ArgumentError)
      end
    end

    context 'without an updated_after argument' do
      it 'raises an error' do
        expect do
          client.published_resource_with_updated_component_uris(repository_id: 11)
        end.to raise_error(ArgumentError)
      end
    end
  end

  describe '#published_resource_with_linked_agent_uris' do
    context 'without a repository_id argument' do
      it 'raises an error' do
        expect do
          client.published_resource_with_linked_agent_uris(updated_after: '2024-05-10')
        end.to raise_error(ArgumentError)
      end
    end

    context 'without an updated_after argument' do
      it 'raises an error' do
        expect do
          client.published_resource_with_linked_agent_uris(repository_id: 11)
        end.to raise_error(ArgumentError)
      end
    end
  end

  describe '#updated_agents' do
    let(:aspace_query) { instance_double(AspaceQuery) }

    before do
      allow(AspaceQuery).to receive(:new).with(client:, repository_id: 11, updated_after: '2024-05-06',
                                               primary_type: nil,
                                               options: { contains_fields: [], contains_type: 'agent' })
                                         .and_return(aspace_query)
    end

    it 'returns an instance of AspaceQuery' do
      expect(client.updated_agents(repository_id: 11, updated_after: '2024-05-06')).to eq aspace_query
    end

    context 'without a repository_id argument' do
      it 'raises an error' do
        expect do
          client.updated_agents(updated_after: '2024-05-06')
        end.to raise_error(ArgumentError)
      end
    end

    context 'without an updated_after argument' do
      it 'raises an error' do
        expect do
          client.updated_agents(repository_id: 11)
        end.to raise_error(ArgumentError)
      end
    end
  end

  describe '#resources_with_linked_agents' do
    let(:agent_uris) { ['/agents/people/1', '/agents/corporate_entities/2'] }
    let(:aspace_query) { instance_double(AspaceQuery) }
    let(:repository_id) { 2 }

    before do
      allow(client).to receive(:record_uris_from_linked_agent_uris)
        .with(repository_id:, agent_uris:)
        .and_return(['/repositories/2/resources/4335', '/repositories/2/archival_objects/20'])
      allow(client).to receive(:resource_uris_from_record_uris)
        .with(repository_id:, record_uris: ['/repositories/2/archival_objects/20'])
        .and_return(['/repositories/2/resources/101'])
      allow(AspaceQuery).to receive(:new)
        .with(client:, repository_id:,
              options: { published: true, suppressed: false,
                         limit_results_to_uris: ['/repositories/2/resources/4335', '/repositories/2/resources/101'] })
        .and_return(aspace_query)
    end

    it 'returns an instance of AspaceQuery for resources linked with given agent URIs' do
      expect(client.resources_with_linked_agents(repository_id:, agent_uris:)).to eq(aspace_query)
    end

    context 'without a repository_id argument' do
      it 'raises an error' do
        expect do
          client.resources_with_linked_agents(agent_uris: ['/agents/people/1', '/agents/corporate_entities/2'])
        end.to raise_error(ArgumentError)
      end
    end

    context 'without an agent_uris argument' do
      it 'raises an error' do
        expect do
          client.resources_with_linked_agents(repository_id:)
        end.to raise_error(ArgumentError)
      end
    end
  end

  describe '#authenticated_get' do
    it 'sends an authenticated request with correct auth header to the specified address' do
      stub_request(:get, 'http://example.com:8089/some_request')
      client.authenticated_get('some_request')
      expect(WebMock).to have_requested(:get,
                                        'http://example.com:8089/some_request')
        .with(headers: { 'X-ArchivesSpace-Session' => 'token1' }).once
    end

    context 'without a path argument' do
      it 'raises an error' do
        expect { client.resource_description }.to raise_error(ArgumentError)
      end
    end

    context 'when the HTTP response is bad' do
      it 'raises an error' do
        stub_request(:get, 'http://example.com:8089/some_request').to_raise(Net::HTTPBadResponse)
        expect { client.authenticated_get('some_request') }.to raise_error(StandardError)
      end
    end
  end

  describe '#authenticated_post' do
    it 'sends an authenticated request with correct auth header to the specified address' do
      stub_request(:post, 'http://example.com:8089/some_request')
      client.authenticated_post('some_request')
      expect(WebMock).to have_requested(:post,
                                        'http://example.com:8089/some_request')
        .with(headers: { 'X-ArchivesSpace-Session' => 'token1' }).once
    end

    context 'without a path argument' do
      it 'raises an error' do
        expect { client.resource_description }.to raise_error(ArgumentError)
      end
    end

    context 'when the HTTP response is bad' do
      it 'raises an error' do
        stub_request(:post, 'http://example.com:8089/some_request').to_raise(Net::HTTPBadResponse)
        expect { client.authenticated_post('some_request') }.to raise_error(StandardError)
      end
    end
  end
end
