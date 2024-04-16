# frozen_string_literal: true

# Controller for downloading finding aid files
class DownloadController < ApplicationController
  def show
    doc = SolrDocument.find(params[:id])
    ead_file = File.join(Settings.data_dir, doc.repository_config.slug, doc.ead_filename)

    respond_to do |format|
      format.xml do
        send_file ead_file
      rescue ActionController::MissingFile => e
        Honeybadger.notify e
        raise ActionController::RoutingError, 'Not Found'
      end
    end
  end
end
