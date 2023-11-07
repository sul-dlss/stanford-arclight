# frozen_string_literal: true

require 'English'

# Queue up an indexing job
class IndexEadJob
  include Sidekiq::Job

  class IndexEadError < StandardError; end

  def perform(path, repo_id)
    env = { 'REPOSITORY_ID' => repo_id }
    # Calling the traject command directly here instead of
    # the arclight:index rake task because the latter
    # doesn't return the exit code for the traject command.
    solr_url = ENV.fetch('SOLR_URL', Blacklight.default_index.connection.base_uri)
    # solr_url = 'http://localhost:8080/solr/arclight-prod-2020'
    cmd = %W[ bundle exec traject
              -u #{solr_url}
              -i xml
              -c ./lib/traject/sul_config.rb
              #{path} ]

    output = IO.popen(env, cmd, chdir: Rails.root, err: %i[child out], &:read)

    raise IndexEadError, output unless $CHILD_STATUS.success?

    Rails.logger.debug output
  end
end
