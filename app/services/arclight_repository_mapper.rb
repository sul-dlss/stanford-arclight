# frozen_string_literal: true

# Determines an EAD's arclight repository code
class ArclightRepositoryMapper
  class ArclightRepositoryMapperError < StandardError; end

  attr_reader :aspace_repository_code, :file_identifier

  def self.map_to_code(aspace_repository_code:, file_identifier:)
    new(aspace_repository_code:, file_identifier:).map_to_code
  end

  def initialize(aspace_repository_code:, file_identifier:)
    @aspace_repository_code = aspace_repository_code
    @file_identifier = file_identifier
  end

  def map_to_code
    code = if aspace_repository_code == 'speccoll'
             code_from_file_identifier
           else
             aspace_repository_code
           end

    unless repository_exists?(code)
      raise ArclightRepositoryMapperError,
            "Repository ID #{aspace_repository_code} and EAD ID #{file_identifier} could not be mapped."
    end

    code
  end

  private

  def repository_exists?(code)
    Arclight::Repository.all.map(&:slug).include?(code)
  end

  # a, f, pc, etc. are call number prefixes used to form EAD IDs
  # uarc and manuscripts are arclight repository codes
  def code_from_file_identifier
    case file_identifier[/^[A-Z]*/i].downcase
    when 'amernews', 'comics', 'macweek', 'pn', 'sanitary'
      'rarebooks'
    when 'a', 'f', 'pc', 'sc', 'scm', 'v'
      'uarc'
    # Fall back on manuscripts
    # if we can't determine the sub-category of speccoll from the syntax of the file_identifier
    else
      'manuscripts'
    end
  end
end
