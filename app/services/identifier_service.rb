# frozen_string_literal: true

require 'arclight/exceptions'

# A utility class to normalize identifiers
class IdentifierService
  def initialize(identifiers)
    @identifiers = Array(identifiers)
  end

  def to_s
    normalized_id = @identifiers.compact.reject(&:empty?).map do |string|
      string.sub(/(\.xml)?$/i, '').split.map(&:parameterize).reject(&:empty?).take(5).join('-')
    end.compact_blank.uniq.first

    raise Arclight::Exceptions::IDNotFound if normalized_id.blank?

    normalized_id
  end
end
