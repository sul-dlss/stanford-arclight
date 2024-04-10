# frozen_string_literal: true

# Controller for downloading finding aid files
class DownloadController < ApplicationController
  def show
    doc = SolrDocument.find(params[:id])

    data_dir = Settings.data_dir
    repository_id = doc.repository_config.slug

    respond_to do |format|
      format.xml do
        send_file File.join(data_dir, repository_id, doc.ead_filename)
      end
    end
  end
end
