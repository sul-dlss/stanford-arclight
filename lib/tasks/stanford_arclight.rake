# frozen_string_literal: true

namespace :stanford_arclight do
  desc 'Delete a collection and its components from Solr by document ID'
  task :delete_by_id, %i[id] => :environment do |_task, args|
    puts "Are you sure you want to delete #{args[:id]} from ArcLight?\nEnter YES to proceed:"
    input = $stdin.gets.chomp
    raise "#{args[:id]} will NOT be deleted." unless input == 'YES'

    puts "Deleting #{args[:id]} from the index..."
    Blacklight.default_index.connection.delete_by_id(args[:id])
    Blacklight.default_index.connection.commit
  end
end
