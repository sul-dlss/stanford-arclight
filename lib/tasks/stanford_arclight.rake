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

  desc 'Search ArchivesSpace for resources matching a query, such as an EAD ID'
  task :find_resource, %i[query] => :environment do |_task, args|
    AspaceRepositories.all_harvestable.each do |repository|
      client = AspaceClient.new(aspace_config_set: repository.aspace_config_set)
      client.search_resources(repository_id: repository.id, query: args[:query]).each do |result|
        puts "#{result['uri']}  #{repository.code} (#{repository.aspace_config_set})"
        puts "  title:     #{result['title']}"
        puts "  ead_id:    #{result['ead_id'].inspect}  identifier: #{result['identifier'].inspect}"
        puts "  published: #{result['publish']}  suppressed: #{result['suppressed']}  ark: #{result['ark_name']&.first}"
        task_args = "#{result['uri']},#{repository.aspace_config_set}"
        puts %(  fetch:     bin/rails "stanford_arclight:fetch_resource[#{task_args}]")
        puts
      end
    end
  end

  desc 'Download an ArchivesSpace resource by URI and queue indexing and PDF generation'
  task :fetch_resource, %i[uri aspace_config_set] => :environment do |_task, args|
    aspace_config_set = args[:aspace_config_set] || 'default'
    repository = AspaceRepositories.all.find do |repo|
      repo.aspace_config_set.to_s == aspace_config_set && args[:uri].start_with?("#{repo.uri}/")
    end
    raise "No #{aspace_config_set} ArchivesSpace repository found for #{args[:uri]}" unless repository

    client = AspaceClient.new(aspace_config_set: repository.aspace_config_set)
    result = client.published_resource(repository_id: repository.id, uri: args[:uri])
    raise "#{args[:uri]} is not a published, unsuppressed resource" unless result

    resource = Aspace::Resource.new(**result.symbolize_keys, repository_code: repository.code)
    file_dir = "#{Settings.data_dir}/#{resource.arclight_repository_code}"
    DownloadEadJob.perform_now(resource_uri: resource.uri, aspace_config_set: repository.aspace_config_set,
                               file_name: resource.file_name, file_dir:, index: true, generate_pdf: true)
    puts "Downloaded #{file_dir}/#{resource.file_name}.xml"
  end

  desc 'Prune guest users without bookmarks from the database'
  task :prune_guest_user_data, %i[months_old] => :environment do |_, args|
    months_old = args[:months_old].to_i
    raise ArgumentError, 'months_old is expected to be greater than 0' if months_old <= 0

    # Guests that own bookmarks are kept.
    bookmarked_user_ids = Bookmark.where(user_type: 'User').distinct.pluck(:user_id)

    User.where(guest: true)
        .where.not(id: bookmarked_user_ids)
        .where(User.arel_table[:updated_at].lt(months_old.months.ago)).in_batches do |users|
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
