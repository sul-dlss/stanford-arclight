# Add your own tasks in files placed in lib/tasks ending in .rake,
# for example lib/tasks/capistrano.rake, and they will automatically be available to Rake.

require_relative 'config/application'

task(:default).clear
task default: :ci

Rails.application.load_tasks

require 'solr_wrapper/rake_task' unless Rails.env.production?

desc 'Run tests in generated test Rails app with generated Solr instance running'
task ci: :environment do
  require 'solr_wrapper'
  ENV['environment'] = 'test'
  SolrWrapper.wrap(port: '8983') do |solr|
    solr.with_collection(name: 'blacklight-core', dir: Rails.root.join('solr', 'conf')) do
      # run the tests
      Rake::Task['spec'].invoke
    end
  end
end
