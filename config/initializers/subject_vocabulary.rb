# frozen_string_literal: true

# Loads the subject-vocabulary vectors (see scratchpad/embed_subject_vocabulary.rb)
# into memory once at boot, for the "related topics" suggestion in the results
# summary panel. Missing file is non-fatal - the panel just omits related
# topics (same defensive pattern as the rest of semantic search).
# SemanticSearch::* isn't autoloadable yet at top-level initializer time in
# this app (reproduces even for pre-existing classes, not just this one) -
# to_prepare defers until the app is fully loaded, same pattern already used
# for app/overrides in config/application.rb.
Rails.application.config.to_prepare do
  default_path = Rails.root.join('/opt/app/arclight/data/subject_vocabulary_vectors.marshal')
  subject_vocabulary_path = ENV.fetch('SEMANTIC_SEARCH_SUBJECT_VOCABULARY_PATH', default_path)

  if File.exist?(subject_vocabulary_path)
    SemanticSearch::SubjectVocabulary.vectors = Marshal.load(File.binread(subject_vocabulary_path)) # rubocop:disable Security/MarshalLoad
  else
    Rails.logger.warn(
      "[SemanticSearch] subject vocabulary file not found at #{subject_vocabulary_path}; related topics disabled"
    )
  end
end
