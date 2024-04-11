# frozen_string_literal: true

# Controller for downloading finding aid files
class DownloadController < ApplicationController
  def show
    doc = SolrDocument.find(params[:id])
    ead_file = File.join(Settings.data_dir, doc.repository_config.slug, doc.ead_filename)

    respond_to do |format|
      format.xml do
        send_ead(ead_file)
      rescue ActionController::MissingFile => e
        Honeybadger.notify e
        raise ActionController::RoutingError, 'Not Found'
      end
    end
  end

  private

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
