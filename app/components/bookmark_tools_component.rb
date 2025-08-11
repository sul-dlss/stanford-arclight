# frozen_string_literal: true

# Component for rendering bookmark tools and related alerts.
class BookmarkToolsComponent < ViewComponent::Base
  def initialize(response:, params:)
    @params = Blacklight::Parameters.sanitize(params.to_unsafe_h)
    @response = response
    super()
  end

  def disclaimer_alert
    return unless current_page == 1

    render AlertComponent.new(message: t('bookmarks.disclaimer_html'), type: :info)
  end

  def export_info_alert
    return unless bookmarks_total_count > bookmarks_shown_count

    render AlertComponent.new(message: t('bookmarks.export_info_html',
                                         bookmarks_total_count: number_with_delimiter(bookmarks_total_count),
                                         bookmarks_shown_count: bookmarks_shown_count),
                              type: :info)
  end

  def export_link
    link_to url_for(params:, format: 'csv'), download: csv_download do
      helpers.blacklight_icon('export') + t('bookmarks.export_csv')
    end
  end

  def email_link
    link_to '#modal-bookmarks-email', data: { bs_toggle: 'modal', bs_target: '#modal-bookmarks-email' } do
      helpers.blacklight_icon('email') + t('bookmarks.email_link')
    end
  end

  def render?
    bookmarks_total_count.positive?
  end

  private

  attr_reader :params, :response

  delegate :current_page, to: :response

  def bookmarks_shown_count
    response.documents.count
  end

  def bookmarks_total_count
    response.total
  end

  def csv_download
    CsvService.filename(prefix: 'bookmarks')
  end
end
