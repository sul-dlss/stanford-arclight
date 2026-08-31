# frozen_string_literal: true

module StanfordArclightMcp
  # Stable semantic vocabulary and existing Solr fields exposed by the archival record projection.
  module ArchivalRecordFields
    Definition = Struct.new(:section, :name, :label, :solr_fields, keyword_init: true)

    def self.field(section, name, label, *solr_fields)
      Definition.new(section:, name:, label:, solr_fields:).freeze
    end

    FIELDS = [
      field('description', 'abstract', 'Abstract', 'abstract_html_tesm'),
      field('description', 'scope_and_contents', 'Scope and Contents', 'scopecontent_html_tesm'),
      field('description', 'biographical_historical', 'Biographical/Historical', 'bioghist_html_tesm'),
      field('description', 'arrangement', 'Arrangement', 'arrangement_html_tesm'),
      field('description', 'other_descriptive_data', 'Other Descriptive Data', 'odd_html_tesm'),
      field('physical_description', 'extent', 'Extent', 'extent_ssm'),
      field('physical_description', 'languages', 'Languages', 'language_ssim'),
      field('physical_description', 'physical_description', 'Physical Description', 'physdesc_tesim'),
      field('physical_description', 'physical_details', 'Physical Details', 'physfacet_tesim'),
      field('physical_description', 'dimensions', 'Dimensions', 'dimensions_tesim'),
      field('physical_description', 'material_specific_details', 'Material-Specific Details', 'materialspec_html_tesm'),
      field('physical_description', 'physical_location', 'Physical Location', 'physloc_html_tesm'),
      field('physical_description', 'technical_requirements', 'Technical Requirements', 'phystech_html_tesm'),
      field('administrative', 'acquisition_information', 'Acquisition Information', 'acqinfo_ssim'),
      field('administrative', 'appraisal', 'Appraisal', 'appraisal_html_tesm'),
      field('administrative', 'custodial_history', 'Custodial History', 'custodhist_html_tesm'),
      field('administrative', 'processing_information', 'Processing Information', 'processinfo_html_tesm'),
      field('administrative', 'accruals', 'Accruals', 'accruals_html_tesm'),
      field('administrative', 'file_plan', 'File Plan', 'fileplan_html_tesm'),
      field('administrative', 'description_rules', 'Description Rules', 'descrules_ssm'),
      field('administrative', 'general_notes', 'General Notes', 'note_html_tesm'),
      field('related_materials', 'related_materials', 'Related Materials', 'relatedmaterial_html_tesm'),
      field('related_materials', 'separated_materials', 'Separated Materials', 'separatedmaterial_html_tesm'),
      field('related_materials', 'other_finding_aids', 'Other Finding Aids', 'otherfindaid_html_tesm'),
      field('related_materials', 'alternate_formats', 'Alternate Formats', 'altformavail_html_tesm'),
      field('related_materials', 'originals_location', 'Originals Location', 'originalsloc_html_tesm'),
      field('citation', 'preferred_citation', 'Preferred Citation', 'prefercite_html_tesm'),
      field('indexed_terms', 'subjects', 'Subjects', 'access_subjects_ssim'),
      field('indexed_terms', 'names', 'Names', 'names_coll_ssim', 'names_ssim'),
      field('indexed_terms', 'places', 'Places', 'places_ssim'),
      field('indexed_terms', 'indexes', 'Indexes', 'indexes_html_tesm')
    ].freeze
  end
end
