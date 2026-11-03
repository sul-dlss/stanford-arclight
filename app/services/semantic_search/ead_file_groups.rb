# frozen_string_literal: true

require 'pathname'

module SemanticSearch
  # Groups EAD file paths by the Arclight repository they belong to, so a bulk
  # embedding pass can run each group under its own REPOSITORY_ID.
  #
  # This is not cosmetic. TextBuilder strips a document's OWN repository name out
  # of the embedded "Names:" list (see TextBuilder#access_terms), and the
  # repository comes from REPOSITORY_ID. Generating a repository's EAD under some
  # other slug therefore leaves that repository's name in the embed text, which
  # changes the SHA256 keying the embedding cache - so the vector generated for a
  # collection-level doc is never found again when the doc is indexed under its
  # real repository. Components are unaffected (they don't carry the
  # <repository> corpname), which is why this shows up as a collection-level-only
  # cache miss.
  #
  # The repository code is the immediate parent directory name - the same
  # convention IndexEadJob#arclight_repository_code uses (data/<repo>/<ead>.xml).
  module EadFileGroups
    module_function

    # @param files [Array<String>] EAD file paths
    # @return [Hash{String => Array<String>}] repository code => its files
    def call(files)
      files.group_by { |path| repository_code(path) }
    end

    # @param path [String] an EAD file path
    # @return [String] the Arclight repository code (parent directory name)
    def repository_code(path)
      Pathname.new(path).parent.basename.to_s
    end

    # @param code [String] a candidate repository code
    # @return [Boolean] whether config/repositories.yml configures it
    def configured?(code)
      !Arclight::Repository.find_by(slug: code).nil?
    end
  end
end
