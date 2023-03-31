# frozen_string_literal: true

# Customized oEmbed viewer that can pass extra parameters to sul-embed
class OembedViewerComponent < Arclight::OembedViewerComponent
  # Rendered as data-* attributes on the viewer element, passed to sul-embed
  def viewer_attrs
    {
      controller: 'sul-embed',
      sul_embed_hide_title_value: true,
      sul_embed_url_value: @resource.href
    }
  end
end
