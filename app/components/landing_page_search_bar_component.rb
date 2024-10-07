# frozen_string_literal: true

# A version of the ArcLight/Blacklight search bar that only shows the text input.
class LandingPageSearchBarComponent < Arclight::SearchBarComponent
  def initialize(**kwargs)
    super

    # Default to grouping search results by collection.
    @params = @params.merge(@params, group: true)
  end

  def search_button
    render SearchButtonComponent.new(id: "#{@prefix}search", text: scoped_t('submit'))
  end
end
