# frozen_string_literal: true

# Service to find and delete old files that are no longer indexed in Solr.
class DeleteOldFilesService
  def initialize(repository_name:, repository_slug:, skip_delete_safeguard: false)
    @repository_name = repository_name
    @repository_slug = repository_slug
    @skip_delete_safeguard = skip_delete_safeguard
  end

  def delete_old_files!
    # Guard against insane delete counts here
    # unless skip_delete_safeguard
    #   DeleteSafeguard.check(delete_count: files_to_delete.count,
    #                         index_count: saved_files.count)
    # end
    files_to_delete.each do |file|
      if File.exist?(file)
        Rails.logger.info "Deleting #{file}"
        File.delete(file)
      else
        Rails.logger.info "File #{file} does not exist, skipping."
      end
    end
  end

  def files_to_delete
    @files_to_delete ||= saved_files.map(&:to_s) - indexed_files
  end

  def saved_files
    @saved_files ||= Dir.glob(saved_file_paths)
  end

  def indexed_files
    @indexed_files ||= indexed_file_names.map { |file| "#{Settings.data_dir}/#{@repository_slug}/#{file}" }
  end

  def saved_file_paths
    %w[*.xml *.pdf].map do |pattern|
      "#{Settings.data_dir}/#{@repository_slug}/#{pattern}"
    end
  end

  def indexed_file_names
    IndexedEads.new(repository_name: @repository_name).all.map { |file| ["#{file}.xml", "#{file}.pdf"] }.flatten
  end

  # TODO: This is bascially a copy of the IndexedEads class from delete_ead_job.rb.
  #      It should be refactored to avoid duplication.
  # Fetches all the indexed EAD files for an aspace repository
  class IndexedEads
    attr_reader :repository_id, :aspace_config_set

    PAGE_SIZE = 250

    def initialize(repository_name:)
      @repository_name = repository_name
    end

    # returns an array of SolrDocument IDs for the currently indexed EAD files
    def all
      each.to_a
    end

    private

    # rubocop:disable Metrics/MethodLength
    def each(&)
      return enum_for(:each) unless block_given?

      this_page = 0
      last_page = nil

      while last_page.nil? || this_page < last_page
        response = repository.search(
          rows: PAGE_SIZE,
          start: this_page,
          fl: 'id',
          fq: ["repository_ssim:\"#{@repository_name}\"", 'component_level_isim:0'],
          sort: 'id ASC',
          facet: false
        )

        this_page += PAGE_SIZE
        last_page = response.dig('response', 'numFound')

        response.dig('response', 'docs').pluck('id').to_a.each(&)
      end
    end
    # rubocop:enable Metrics/MethodLength

    delegate :repository, to: :blacklight_config

    def blacklight_config
      @blacklight_config ||= CatalogController.blacklight_config.configure
    end
  end
end
