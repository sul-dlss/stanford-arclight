# frozen_string_literal: true

# Many finding aids cite SearchWorks, OAC, DOI, etc. as plain-text URLs, or in an <extref>
# with no href, which Arclight renders as unclickable text. Give those an <extref href>
# first so Arclight's own format_links renders them like every other external link.
#
# Prepended, not class_eval'd like the other overrides, so it can add a step and call super
# instead of copying Arclight's transform_ead_to_html.
module EadFormatHelpersOverride
  # This file is re-loaded on every dev code reload; the guards avoid constant-redefinition warnings.
  # The elements Arclight's format_links turns into <a> when they have an href.
  LINK_ELEMENTS = 'extptr, extref, extrefloc, ptr, ref' unless defined?(LINK_ELEMENTS)
  # Trailing punctuation and quotes are almost always the sentence's, not part of the URL.
  BARE_URL = %r{https?://[^\s<>"]*[^\s<>".,;:)\]']} unless defined?(BARE_URL)
  # Retired library URLs, repeated in hundreds of finding aids, that now redirect to the library
  # home page; point them where the library's own redirects send the sibling URLs.
  unless defined?(RETIRED_URLS)
    RETIRED_URLS = {
      'http://library.stanford.edu/depts/spc/pubserv/permissions.html' =>
        'https://library.stanford.edu/special-collections-policies',
      'http://library.stanford.edu/depts/spc/spc.html' => 'https://library.stanford.edu/libraries/special-collections'
    }.freeze
  end

  private

  def transform_ead_to_html(value)
    super(link_bare_urls(value))
  end

  def link_bare_urls(value)
    return value unless value.include?('http')

    fragment = Loofah.xml_fragment(value)
    fragment.xpath('.//text()').each do |text|
      link = text.ancestors(LINK_ELEMENTS).first
      link ? add_missing_href(link) : link_urls_in(text)
    end
    fragment.css(LINK_ELEMENTS).each { |link| replace_retired_href(link) }
    fragment.to_xml
  end

  def replace_retired_href(link)
    link['href'] = RETIRED_URLS[link['href']] if RETIRED_URLS.key?(link['href'])
  end

  def add_missing_href(link)
    text = link.text.strip
    link['href'] = text if link['href'].blank? && text.match?(/\A#{BARE_URL}\z/o)
  end

  # Builds nodes rather than markup so text around the URL never needs escaping.
  def link_urls_in(text)
    return unless text.content.match?(BARE_URL)

    doc = text.document
    text.content.split(/(#{BARE_URL})/o).each_with_index do |part, index|
      node = index.odd? ? doc.create_element('extref', part, href: part) : doc.create_text_node(part)
      text.add_previous_sibling(node)
    end
    text.remove
  end
end

# Prepending again on a dev reload would add a second copy to classes that already include the helpers.
unless Arclight::EadFormatHelpers.include?(EadFormatHelpersOverride)
  Arclight::EadFormatHelpers.prepend(EadFormatHelpersOverride)
end
