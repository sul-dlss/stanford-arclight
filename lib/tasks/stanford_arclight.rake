# frozen_string_literal: true

namespace :stanford_arclight do
  desc 'Delete a collection and its components from Solr by EAD ID'
  task :delete_by_ead_id, %i[ead_id] => :environment do |_task, args|
    puts "Are you sure you want to delete #{args[:ead_id]} from ArcLight?\nEnter YES to proceed:"
    input = $stdin.gets.chomp
    raise "#{args[:ead_id]} will NOT be deleted." unless input == 'YES'

    puts "Deleting #{args[:ead_id]} from the index..."
    Blacklight.default_index.connection.delete_by_query("id:#{args[:ead_id]}")
    Blacklight.default_index.connection.commit
  end
end
