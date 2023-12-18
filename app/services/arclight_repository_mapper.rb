# frozen_string_literal: true

# Determines an EAD's arclight repository code
class ArclightRepositoryMapper
  class ArclightRepositoryMapperError < StandardError; end

  attr_reader :aspace_repository_code, :ead_id

  def self.map_to_code(aspace_repository_code:, ead_id:)
    new(aspace_repository_code:, ead_id:).map_to_code
  end

  def initialize(aspace_repository_code:, ead_id:)
    @aspace_repository_code = aspace_repository_code
    @ead_id = ead_id
  end

  def map_to_code
    code = if aspace_repository_code == 'speccoll'
             code_from_ead_id
           else
             aspace_repository_code
           end

    unless repository_exists?(code)
      raise ArclightRepositoryMapperError,
            "Repository ID #{aspace_repository_code} and EAD ID #{ead_id} could not be mapped."
    end

    code
  end

  private

  def repository_exists?(code)
    Arclight::Repository.all.map(&:slug).include?(code)
  end

  # a, f, pc, etc. are call number prefixes used to form EAD IDs
  # uarc and speccoll are arclight repository codes
  def code_from_ead_id
    case ead_id[/^[A-Z]*/i]
    when 'a', 'f', 'pc', 'sc', 'scm', 'v'
      'uarc'
    else
      'speccoll'
    end
  end
end
