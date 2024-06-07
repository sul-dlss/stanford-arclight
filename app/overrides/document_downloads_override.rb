# frozen_string_literal: true

module Arclight
  # Monkey patch DocumentDownloads to limit files to those that exist and have content
  class DocumentDownloads
    # rubocop:disable Metrics/AbcSize
    def files
      data = self.class.config[id] || self.class.config['default']
      disabled = data.delete('disabled')
      return [] if disabled

      files ||= data.filter_map do |file_type, file_data|
        self.class.file_class.new(type: file_type, data: file_data, document:)
      end

      files.select! do |file|
        file.size&.positive?
      end
      @files = files
    end
    # rubocop:enable Metrics/AbcSize
  end
end
