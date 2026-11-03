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

  # Batched, resumable generation of the semantic-search embedding cache. Runs
  # the Traject extraction over the EAD (no Solr writes), batch-embeds each
  # collection/component doc via the gateway, and stores vectors in the SQLite
  # cache. Ship the resulting file read-only to the app hosts.
  #
  #   SEMANTIC_SEARCH_EMBEDDING_CACHE=/path.sqlite \
  #   SEMANTIC_SEARCH_EMBEDDING_API_KEY=... \
  #     bundle exec rake stanford_arclight:generate_embeddings[/path/to/data]
  #
  # Runs ONE Traject pass PER REPOSITORY, each under its own REPOSITORY_ID. The
  # repository is part of the embed text - TextBuilder strips a document's own
  # repository name from the "Names:" list - so generating under the wrong slug
  # produces a cache key that indexing will never look up (see
  # SemanticSearch::EadFileGroups). Directories with no entry in
  # config/repositories.yml are reported and skipped, because there is no correct
  # slug to embed them under.
  #
  # Single-process (one SQLite writer); resumable (already-cached texts are
  # skipped).
  #
  # Concurrency: the run is almost entirely waiting on the embedding gateway, so
  # it defaults to SEMANTIC_SEARCH_EMBED_THREADS=8 Traject worker threads (~4,800
  # docs/min measured, vs ~1,200 serial). 8 sits at roughly the key's 100 rpm
  # ceiling and within its max_parallel_requests of 10; 429s are expected and
  # ridden out by the retries below. Set it to 1 to go back to a serial run.
  # The rpm limit is per KEY, so don't run this alongside another generation
  # process - the threads here already consume the whole budget.
  desc 'Generate the semantic-search embedding cache from EAD (no Solr writes)'
  task :generate_embeddings, %i[data_dir] => :environment do |_task, args|
    cache_path = ENV.fetch('SEMANTIC_SEARCH_EMBEDDING_CACHE')
    ENV.fetch('SEMANTIC_SEARCH_EMBEDDING_API_KEY') # fail fast if unset
    data_dir = args[:data_dir] || Settings.data_dir
    files = Dir.glob(File.join(data_dir, '**', '*.xml'))
    raise "No EAD (*.xml) found under #{data_dir}" if files.empty?

    known, unknown = SemanticSearch::EadFileGroups.call(files)
                                                  .partition { |code, _| SemanticSearch::EadFileGroups.configured?(code) }
    unknown.each do |code, repo_files|
      warn "SKIPPING #{repo_files.size} file(s) in '#{code}': no matching slug in config/repositories.yml"
    end
    raise "No configured repository for any EAD under #{data_dir}" if known.empty?

    puts "Generating embeddings for #{known.sum { |_, repo_files| repo_files.size }} finding aids " \
         "across #{known.size} repositories under #{data_dir} -> #{cache_path}"

    threads = ENV.fetch('SEMANTIC_SEARCH_EMBED_THREADS', '8')
    puts "  using #{threads} embedding thread(s) per repository pass"

    env = { 'SEMANTIC_SEARCH_EMBEDDING_CACHE' => cache_path,
            'SEMANTIC_SEARCH_EMBEDDING_CACHE_GENERATE' => 'true',
            'SEMANTIC_SEARCH_EMBED_THREADS' => threads,
            # Ride out gateway rate limits during the batch run (fail-fast at query time).
            'SEMANTIC_SEARCH_EMBED_MAX_RETRIES' => ENV.fetch('SEMANTIC_SEARCH_EMBED_MAX_RETRIES', '8') }

    known.sort.each do |code, repo_files|
      puts "  #{code}: #{repo_files.size} finding aids"
      cmd = ['bundle', 'exec', 'traject', '-i', 'xml',
             '-c', Rails.root.join('lib/traject/sul_config.rb').to_s,
             '-w', 'Traject::JsonWriter', '-o', File::NULL, *repo_files]
      raise "Embedding generation failed for #{code}" unless system(env.merge('REPOSITORY_ID' => code), *cmd)
    end

    cache = SemanticSearch::EmbeddingCache::Sqlite.new(cache_path)
    puts "Done. Cache holds #{cache.size} vectors."
    cache.close
  end
end
