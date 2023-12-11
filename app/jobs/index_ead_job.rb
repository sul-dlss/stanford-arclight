# frozen_string_literal: true

require 'open3'
require 'pathname'

##
# Background job to index an EAD XML file in Solr
class IndexEadJob < ApplicationJob
  class IndexEadError < StandardError; end

  def perform(file_path:,
              arclight_repo_code: nil,
              solr_url: ENV.fetch('SOLR_URL', Blacklight.default_index.connection.base_uri),
              app_dir: Rails.root)
    env = { 'REPOSITORY_ID' => arclight_repo_code || arclight_repository_code(file_path) }
    cmd = "bundle exec traject -u #{solr_url} -i xml -c ./lib/traject/sul_config.rb #{file_path}"

    output, status = Open3.capture2(env, cmd, chdir: app_dir)

    raise IndexEadError, output unless status.success?

    Rails.logger.debug output
  end

  private

  # Infer the arclight repository code from the file_path as
  # the name of the immediate parent directory of the file
  def arclight_repository_code(file_path)
    Pathname.new(file_path).parent.split.last.to_s
  end
end
