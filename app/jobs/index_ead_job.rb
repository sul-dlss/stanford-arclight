# frozen_string_literal: true

require 'open3'

##
# Background job to index an EAD XML file in Solr
class IndexEadJob < ApplicationJob
  class IndexEadError < StandardError; end

  def perform(file_path:,
              repo_code:,
              solr_url: ENV.fetch('SOLR_URL', Blacklight.default_index.connection.base_uri),
              app_dir: Rails.root)
    env = { 'REPOSITORY_ID' => repo_code }
    cmd = "bundle exec traject -u #{solr_url} -i xml -c ./lib/traject/sul_config.rb #{file_path}"

    output, status = Open3.capture2(env, cmd, chdir: app_dir)

    raise IndexEadError, output unless status.success?

    Rails.logger.debug output
  end
end
