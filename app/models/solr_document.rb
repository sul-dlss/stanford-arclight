# frozen_string_literal: true

# Represents a single document returned from Solr
class SolrDocument
  include Blacklight::Solr::Document
  include Arclight::SolrDocument

  # Override Arclight::SolrDocument.digital_objects to use
  # local DigitalObject class that adds the Purl URL
  # Demo data href only contains the ID
  def digital_objects
    digital_objects_field = fetch('digital_objects_ssm', []).reject(&:empty?)
    return [] if digital_objects_field.blank?

    digital_objects_field.map do |object|
      DigitalObject.from_json(object)
    end
  end

  # NOTE: Override of method from ArcLight core to guard against cases where
  # lower level components are set to Collection and lack an EAD ID.
  # We have requested data remediation, but this is needed until that is complete.
  # You can check for occurences in the data with this Solr query:
  # select?fl=id&fq=component_level_isim%3A[1 TO *]&fq=level_ssm%3ACollection OR level_ssm%3Acollection&
  #   indent=true&q.op=OR&q=*%3A*&rows=100
  def collection?
    level&.parameterize == 'collection' && component_level.zero?
  end

  # self.unique_key = 'id'

  # DublinCore uses the semantic field mappings below to assemble an OAI-compliant Dublin Core document
  # Semantic mappings of solr stored fields. Fields may be multi or
  # single valued. See Blacklight::Document::SemanticFields#field_semantics
  # and Blacklight::Document::SemanticFields#to_semantic_values
  # Recommendation: Use field names from Dublin Core
  use_extension(Blacklight::Document::DublinCore)
end
