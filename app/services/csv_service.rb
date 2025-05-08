# frozen_string_literal: true

# Service to generate a CSV from documents in a Solr response
class CsvService
  COLUMN_HEADERS = %w[id
                      repository
                      collection_id
                      ead_id
                      level
                      title
                      date
                      containers
                      description
                      extent].freeze

  def self.response_to_csv(response:)
    new(response: response).generate_csv
  end

  def self.filename(prefix: 'response')
    [prefix, '-', DateTime.now.strftime('%Y%m%d'), '.csv'].join
  end

  def initialize(response:)
    @response = response
  end

  def generate_csv # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
    CSV.generate do |csv|
      csv << COLUMN_HEADERS
      @response.documents.each do |doc|
        csv << [
          doc.id,
          doc.repository,
          doc.collection_unitid,
          doc.eadid,
          doc.level,
          ActionController::Base.helpers.strip_tags(doc.normalized_title),
          doc.normalized_date,
          doc.containers&.join('|'),
          ActionController::Base.helpers.strip_tags(doc.abstract_or_scope),
          doc.extent&.join('|')
        ]
      end
    end
  end
end
