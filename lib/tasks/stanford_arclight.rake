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

  desc 'Delete EAD files (and their associated PDFs) from the filesystem that are no longer indexed in Solr'
  task delete_old_files: :environment do
    Arclight::Repository.all.to_h { |repo| [repo.name, repo.slug] }.each do |repository_name, repository_slug|
      service = DeleteOldFilesService.new(repository_name:, repository_slug:)
      if service.files_to_delete.empty?
        puts "No old files to delete for #{repository_name} (#{repository_slug})."
        next
      end
      puts "Deleting the following files for #{repository_name} (#{repository_slug}):"
      puts service.files_to_delete
      service.delete_old_files!
    end
  end

  desc 'Prune guest users without bookmarks from the database'
  task :prune_guest_user_data, %i[months_old] => :environment do |_, args|
    updated_at = User.arel_table[:updated_at]
    User.includes(:bookmarks)
        .where(guest: true)
        .where(bookmarks: { user_id: nil })
        .where(updated_at.lt(args[:months_old].to_i.months.ago)).in_batches do |users|
      users.delete_all
      sleep(10) # Throttle the delete queries
    end
  end

  desc 'Prune search data from the database'
  task :prune_search_data, %i[days_old] => :environment do |_, args|
    updated_at = Search.arel_table[:updated_at]
    Search.where(updated_at.lt(args[:days_old].to_i.days.ago)).in_batches do |searches|
      searches.delete_all
      sleep(10) # Throttle the delete queries
    end
  end
end
