# frozen_string_literal: true

# Service to prevent excessive deletes from the Solr index
# based on information from the ASpace repository
# and the number of records to delete
class DeleteSafeguard
  class DeleteSafeguardError < StandardError; end

  def self.check(delete_count:, index_count:, max_deletes: Settings.max_automated_deletes)
    new(delete_count:, index_count:, max_deletes:).check
  end

  def initialize(delete_count:, index_count:, max_deletes:)
    @delete_count = delete_count
    @index_count = index_count
    @max_deletes = max_deletes
  end

  def check
    check_if_delete_count_exceeds_max_deletes_setting
    check_if_delete_count_matches_current_index_count
  end

  private

  def check_if_delete_count_exceeds_max_deletes_setting
    return unless @delete_count > @max_deletes

    raise DeleteSafeguardError, "Attempting to delete #{@delete_count} records. " \
                                "This exceeds the limit of #{@max_deletes}."
  end

  def check_if_delete_count_matches_current_index_count
    return unless @delete_count >= @index_count

    raise DeleteSafeguardError, "Attempting to delete #{@delete_count} records. " \
                                "This would remove all #{@index_count} records."
  end
end
