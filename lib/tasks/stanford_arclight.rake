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

  desc 'Reindex all downloaded EAD files'
  task :reindex_all, %i[arclight_repository_code] => :environment do |_, args|
    repos_to_index = if args[:arclight_repository_code].blank?
                       Arclight::Repository.all.map(&:slug)
                     else
                       [args[:arclight_repository_code]]
                     end
    repos_to_index.each do |repo_slug|
      puts "Reindexing EAD files for repository: #{repo_slug}"
      Dir.glob("#{Settings.data_dir}/#{repo_slug}/*.xml").each_slice(100) do |files|
        IndexEadJob.perform_later(file_path: files.join(' '), arclight_repository_code: repo_slug)
      end
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
