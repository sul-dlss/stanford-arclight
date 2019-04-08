# frozen_string_literal: true

# Add your own tasks in files placed in lib/tasks ending in .rake,
# for example lib/tasks/capistrano.rake, and they will automatically be available to Rake.

require_relative 'config/application'

task(:default).clear
task default: :ci

Rails.application.load_tasks

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

unless Rails.env.production?
  begin
    require 'solr_wrapper/rake_task'
  rescue LoadError
    # this rescue block is here for deployment to production, where
    # certain dependencies are not expected, and that is OK
    warn 'solr_wrapper was not found and could not be required.'
  end
end

desc 'Run tests in generated test Rails app with generated Solr instance running'
task ci: %i[rubocop environment] do
  require 'solr_wrapper'
  ENV['environment'] = 'test'
  SolrWrapper.wrap(port: '8983') do |solr|
    solr.with_collection(name: 'blacklight-core', dir: Rails.root.join('solr', 'conf')) do
      # run the tests
      Rake::Task['spec'].invoke
    end
  end
end
