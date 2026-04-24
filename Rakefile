# frozen_string_literal: true

# Add your own tasks in files placed in lib/tasks ending in .rake,
# for example lib/tasks/capistrano.rake, and they will automatically be available to Rake.

require_relative 'config/application'

task(:default).clear
task default: :ci

Rails.application.load_tasks

unless Rails.env.production?
  begin
    require 'rubocop/rake_task'
    RuboCop::RakeTask.new(:rubocop) do |task|
      task.fail_on_error = true
    end
  rescue LoadError
    # this rescue block is here for deployment to production, where
    # certain dependencies are not expected, and that is OK
    warn 'WARNING: Rubocop was not found and could not be required.'
  end
end

unless Rails.env.production?
  begin
    require 'solr_wrapper/rake_task'
  rescue LoadError
    # this rescue block is here for deployment to production, where
    # certain dependencies are not expected, and that is OK
    warn 'solr_wrapper was not found and could not be required.'
  end
end

def with_solr(&block) # rubocop:disable Metrics/MethodLength
  if system('docker compose -f compose.yaml version', out: File::NULL, err: File::NULL)
    begin
      sh 'docker compose -f compose.yaml up -d --wait solr'
      yield
    ensure
      system 'docker compose -f compose.yaml stop solr'
    end
  else
    require 'solr_wrapper'
    SolrWrapper.wrap(port: '8983') do |solr|
      solr.with_collection(name: 'blacklight-core', dir: Rails.root.join('solr/conf'), &block)
    end
  end
end

desc 'Run tests in generated test Rails app with generated Solr instance running'
task ci: %i[rubocop environment] do
  ENV['environment'] = 'test'
  with_solr do
    Rake::Task['seed'].invoke
    Rake::Task['spec'].invoke
  end
end

desc 'Seed ArcLight fixture data'
task seed: :environment do
  # Read the repository configuration
  repo_config = YAML.safe_load_file('./config/repositories.yml')
  repo_config.keys.map do |repository|
    # Index all EAD fixtures in directories matching the configured repository codes
    Dir.glob(Rails.root.join('spec', 'fixtures', 'ead', repository, '*.xml').to_s).each do |file|
      IndexEadJob.perform_now(file_path: file, arclight_repository_code: repository)
    end
  end
end
