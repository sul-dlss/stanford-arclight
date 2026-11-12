# frozen_string_literal: true

# Service to find and delete old files that are no longer indexed in Solr.
class DeleteOldFilesService
  def initialize(repository_name:, repository_slug:, skip_delete_safeguard: false)
    @repository_name = repository_name
    @repository_slug = repository_slug
    @skip_delete_safeguard = skip_delete_safeguard
  end

  def delete_old_files!
    delete_safeguard_check

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

  private

  def delete_safeguard_check
    return if @skip_delete_safeguard

    DeleteSafeguard.check(delete_count: files_to_delete.count,
                          index_count: saved_files.count)
  end

  def saved_file_paths
    %w[*.xml *.pdf].map do |pattern|
      "#{Settings.data_dir}/#{@repository_slug}/#{pattern}"
    end
  end

  def indexed_file_names
    indexed_eads.map { |file| ["#{file}.xml", "#{file}.pdf"] }.flatten
  end

  def indexed_eads
    SolrPaginatedQuery.new(filter_queries: { repository_ssim: @repository_name,
                                             component_level_isim: 0 },
                           fields_to_return: %w[id]).all
  end
end
