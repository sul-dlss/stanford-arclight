# frozen_string_literal: true

require 'open3'
require 'pathname'

# Background job to generate a PDF from EAD metadata
class GeneratePdfJob < ApplicationJob
  class GeneratePdfError < StandardError; end

  # There are very few situations where a PDF generation job would fail but then
  # succeed in a subsequent retry.
  sidekiq_options retry: 1

  # Generate PDFs for all XML files contained within a directory (deeply).
  # PDF files will be created in the same directory as the XML and will share the same name.
  # For example `ead123.xml` would result in `ead123.pdf`.
  # @param data_dir [String] the path to the directory containing the XML files
  # @param skip_existing [Boolean] if true, XML files that have existing corresponding PDFs will be skipped
  def self.enqueue_all(data_dir: Settings.data_dir, skip_existing: false)
    Dir.glob("#{data_dir}/**/*.xml") do |file_path|
      file_dir = File.dirname(file_path)
      file_name = File.basename(file_path)
      GeneratePdfJob.perform_later(file_path:, file_name:, data_dir: file_dir, skip_existing:)
    end
  end

  # Enqueue a PDF generation job for all XML files in data_dir, skipping those having an existing valid PDF.
  def self.enqueue_all_missing_and_invalid(data_dir: Settings.data_dir)
    enqueue_all(data_dir:, skip_existing: true)
  end

  # Generates a PDF for a given EAD XML file. Will overwrite any existing PDFs with the same name.
  # @param file_path [String] the path of the XML file, such as '/opt/app/arclight/data/ars/ars0001.xml'
  # @param file_name [String] the name of the PDF file to be created, such as 'ead1234'
  # @param data_dir [String] the path where the file should be saved, such as '/opt/app/arclight/data/ars'
  # @param skip_existing [Boolean] if true, an existing valid PDF will not be replaced
  def perform(file_path:, file_name:, data_dir:, skip_existing:)
    pdf_file_path = pdf_path(data_dir:, file_name:)
    return if skip_existing && valid_pdf?(pdf_file_path:)

    stderr_output = nil
    Open3.popen3("#{xml_to_fo_cmd} | #{fo_to_pdf_cmd(pdf_file_path:)}") do |stdin, _stdout, stderr|
      stdin.write(ead_xml(file_path:))
      stdin.close
      stderr_output = stderr.read
    end

    raise GeneratePdfError, error_message(file_path:, output: stderr_output) unless valid_pdf?(pdf_file_path:)
  end

  private

  def error_message(file_path:, output:)
    severe_errors = output.split("\n").grep(/^SEVERE:/)
    ["Failed to generate PDF for #{file_path}."].concat(severe_errors).join("\n")
  end

  def xml_to_fo_cmd
    "java -jar #{Settings.pdf_generation.saxon_path} -s:- "\
    "-xsl:#{Settings.pdf_generation.ead_to_fo_xsl_path} " \
    "pdf_image=#{Settings.pdf_generation.logo_path}"
  end

  def fo_to_pdf_cmd(pdf_file_path:)
    "#{Settings.pdf_generation.fop_path} -q -c #{Settings.pdf_generation.fop_config_path} " \
    "- -pdf #{pdf_file_path}"
  end

  def ead_xml(file_path:)
    doc = Nokogiri::XML(File.read(file_path))

    # OAC strips the default EAD namespace and our XSLT expects it
    doc.root.add_namespace_definition(nil, 'urn:isbn:1-931666-22-9') unless doc.root.namespace
    # Some EADs from OAC use a ns2 namespace but the declaration has been stripped, which causes Saxon to fail.
    doc.root.add_namespace_definition('ns2', 'http://example.com/ns2') unless doc.namespaces.include?('xmlns:ns2')
    doc.to_xml
  end

  def pdf_path(data_dir:, file_name:)
    File.join(data_dir, pdf_file_name(file_name:))
  end

  def pdf_file_name(file_name:)
    file_name.sub(/(\.xml|\.pdf)?$/i, '').concat('.pdf').to_s
  end

  def valid_pdf?(pdf_file_path:)
    return false unless File.exist?(pdf_file_path)

    PDF::Reader.new(pdf_file_path).pages.any?
  rescue PDF::Reader::MalformedPDFError, ArgumentError
    false
  rescue PDF::Reader::UnsupportedFeatureError
    # If a feature is unsupported pdf-reader has still checked for the structure/EOF marker,
    # which raises MalformedPDFError.
    true
  end
end
