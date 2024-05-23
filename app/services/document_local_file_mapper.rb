# frozen_string_literal: true

# Class to handle logic for mapping a document's downloadable EAD files to a local file system.
class DocumentLocalFileMapper
  class UnsupportedFormatError < StandardError; end

  attr_reader :document, :format

  # @param document [SolrDocument] The EAD document
  # @param format [Symbol] The file format (:ead, :xml, :pdf)
  def initialize(document:, format: :ead)
    @document = document
    @format = format
  end

  def path
    case format
    when :ead, :xml
      ead_file_path
    when :pdf
      ead_file_path&.sub(/(xml)?$/i, 'pdf')
    else
      raise UnsupportedFormatError, "Unsupported format: #{format}"
    end
  end

  def size
    return nil unless path

    return nil unless File.exist?(path)

    File.size(path)
  end

  private

  def ead_file_path
    return nil unless path_components?

    File.join(Settings.data_dir, document.repository_config.slug, document.ead_filename)
  end

  def path_components?
    document.repository_config.slug.present? && document.ead_filename.present?
  end
end
