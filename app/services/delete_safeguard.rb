# frozen_string_literal: true

# Service to prevent excessive deletes from the Solr index.
# Prevents deletes exceeding 100 records per repository. If the repository has 100
# or fewer records, it prevents deletes that would remove all records.
class DeleteSafeguard
  class DeleteSafeguardError < StandardError; end

  MAX_AUTOMATED_DELETES = 100

  def self.check(delete_count:, index_count:)
    new(delete_count:, index_count:).check
  end

  def initialize(delete_count:, index_count:)
    @delete_count = delete_count
    @index_count = index_count
  end

  def check
    check_if_delete_count_exceeds_max_allowed
    check_if_delete_removes_all_records
  end

  private

  def check_if_delete_count_exceeds_max_allowed
    return unless @delete_count > MAX_AUTOMATED_DELETES

    raise DeleteSafeguardError, "Attempting to delete #{@delete_count} records. " \
                                "This exceeds the limit of #{MAX_AUTOMATED_DELETES}."
  end

  def check_if_delete_removes_all_records
    return unless @delete_count >= @index_count

    raise DeleteSafeguardError, "Attempting to delete #{@delete_count} records. " \
                                "This would remove all #{@index_count} records."
  end
end
