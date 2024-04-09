# frozen_string_literal: true

# Controller for downloading finding aid files
class DownloadController < ApplicationController
  def show
    doc = SolrDocument.find(params[:id])

    data_dir = Settings.data_dir
    repository_id = doc.repository_config.slug

    respond_to do |format|
      ead_file = File.join(data_dir, repository_id, doc.ead_filename)
      format.xml do
        if remove_namespace?
          send_data ead_without_namespace(ead_file)
        else
          send_file ead_file
        end
      end
    end
  end

  private

  def ead_without_namespace(ead_file)
    doc = Nokogiri::XML(File.read(ead_file))
    xslt  = Nokogiri::XSLT(File.read(Rails.root.join('app/xslt/ead_remove_namespace.xsl').to_s))
    xslt.transform(doc).to_xml(indent: 2)
  end

  def remove_namespace?
    params[:without_namespace] == 'true'
  end
end
