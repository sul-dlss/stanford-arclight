# frozen_string_literal: true

# Controller for downloading finding aid files
class DownloadController < ApplicationController
  def show
    doc = SolrDocument.find(params[:id])

    respond_to do |format|
      format.xml { handle_download { send_ead(DocumentLocalFileMapper.new(document: doc, format: :xml).path) } }
      format.pdf { handle_download { send_file(DocumentLocalFileMapper.new(document: doc, format: :pdf).path) } }
    end
  end

  private

  def handle_download
    yield
  rescue ActionController::MissingFile => e
    Honeybadger.notify e
    raise ActionController::RoutingError, 'Not Found'
  end

  def send_ead(ead_file)
    if params[:without_namespace] == 'true'
      send_data ead_without_namespace(ead_file)
    else
      send_file ead_file
    end
  end

  def ead_without_namespace(ead_file)
    doc = Nokogiri::XML(File.read(ead_file))
    xslt  = Nokogiri::XSLT(File.read(Rails.root.join('app/xslt/ead_remove_namespace.xsl').to_s))
    xslt.transform(doc).to_xml(indent: 2)
  end
end
