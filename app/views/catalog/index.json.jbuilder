# frozen_string_literal: true

# Override from Blacklight to render grouped (group=true) results, which have no flat list of documents

json.links do
  json.self url_for(search_state.to_h.merge(only_path: false))
  json.prev url_for(search_state.to_h.merge(only_path: false, page: @response.prev_page.to_s)) if @response.prev_page
  json.next url_for(search_state.to_h.merge(only_path: false, page: @response.next_page.to_s)) if @response.next_page
  json.last url_for(search_state.to_h.merge(only_path: false, page: @response.total_pages.to_s))
end

json.meta do
  json.pages @presenter.pagination_info
end

json.data do
  if render_grouped_response?
    json.array! @response.groups do |group|
      json.partial! 'document', document: group.docs.first.collection
      json.parts group.docs.reject(&:collection?) do |document|
        json.partial! 'document', document: document
      end
      json.match_count group.total
    end
  else
    json.array! @presenter.documents do |document|
      json.partial! 'document', document: document
    end
  end
end

json.included do
  json.array! @presenter.search_facets do |facet|
    json.type 'facet'
    json.id facet.name
    json.attributes do
      facet_config = facet_configuration_for_field(facet.name)
      json.label facet_field_label(facet_config.key)
      json.items do
        json.array! facet.items do |item|
          json.id
          json.attributes do
            json.label item.label
            json.value item.value
            json.hits item.hits
          end
          json.links do
            if search_state.filter(facet_config).include?(facet_value_for_facet_item(item.value))
              json.remove search_action_path(search_state.filter(facet.name).remove(item.value))
            else
              json.self facet_item_presenter(facet_config, item.value, facet.name).href(only_path: false)
            end
          end
        end
      end
    end
    json.links do
      json.self search_facet_path(id: facet.name, only_path: false)
    end
  end

  search_fields = blacklight_config.search_fields
                                   .values
                                   .select { |field_def| should_render_field?(field_def) }
                                   .collect { |field_def| [label_for_search_field(field_def.key), field_def.key] }

  json.array! search_fields do |(label, key)|
    json.type 'search_field'
    json.id key
    json.attributes do
      json.label label
    end
    json.links do
      json.self url_for(search_state.to_h.merge(search_field: key, only_path: false))
    end
  end

  json.array! active_sort_fields do |key, field|
    json.type 'sort'
    json.id key
    json.attributes do
      json.label field.label
    end
    json.links do
      json.self url_for(search_state.to_h.merge(sort: key, only_path: false))
    end
  end
end
