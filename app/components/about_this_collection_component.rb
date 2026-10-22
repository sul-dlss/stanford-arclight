# frozen_string_literal: true

# Summary facts about a collection, read from its EAD file when the page renders,
# and the AI summary that script/collection_summaries/generate.rb wrote for it.
class AboutThisCollectionComponent < ViewComponent::Base
  attr_reader :document

  def initialize(document:)
    @document = document
    super()
  end

  def render?
    document.collection? && organization.present?
  end

  def organization_text
    case organization.arrangement
    when :none then t('about_this_collection.organization.none')
    when :flat then t('about_this_collection.organization.flat', components: components(organization.component_count))
    else grouped_text
    end
  end

  def ai_summary
    ai_record['summary']
  end

  def ai_problems
    ai_record['problems'].to_a
  end

  # Superscript links to the components an entry cites, numbered in page order
  # and listed in ascending order.
  def citations(entry)
    links = Array(entry['cites']).filter_map { |number| citation(number) }.sort_by(&:first).map(&:last)
    tag.sup(safe_join(links, ', ')) if links.any?
  end

  def render_deterministic?
    false
  end

  private

  def citation(number)
    cited = ai_record.dig('refs', number.to_s)
    return unless cited&.dig('ref')

    label = footnote(number)
    [label, link_to(label, helpers.solr_document_path("#{document.id}_#{cited['ref']}"), title: cited['title'])]
  end

  def footnote(number)
    @footnotes ||= {}
    @footnotes[number] ||= @footnotes.size + 1
  end

  def ai_record
    @ai_record ||= begin
      path = ai_summary_path
      path && File.exist?(path) ? JSON.parse(File.read(path)) : {}
    end
  end

  def ai_summary_path
    return unless document.repository_config&.slug.present? && document.ead_filename.present?

    File.join(Settings.collection_summaries_dir, document.repository_config.slug,
              document.ead_filename.sub(/\.xml\z/i, '.json'))
  end

  def organization
    return @organization if defined?(@organization)

    path = DocumentLocalFileMapper.new(document:).path
    @organization = (CollectionSummary::Organization.from_file(path) if path && File.exist?(path))
  end

  def grouped_text
    groups = organization.groups
    text = t('about_this_collection.organization.grouped', components: components(organization.component_count),
                                                           groups: groups_label(groups))
    groups.one? ? text : safe_join([text, largest_text], ' ')
  end

  def largest_text
    largest = organization.largest_group
    t('about_this_collection.organization.largest_html', title: group_link(largest),
                                                         components: components(largest.component_count))
  end

  def group_link(group)
    return group.title unless group.ref

    link_to group.title, helpers.solr_document_path("#{document.id}_#{group.ref}")
  end

  def groups_label(groups)
    key = groups.all? { |group| group.level == 'series' } ? 'series' : 'groups'
    t("about_this_collection.#{key}", count: groups.size, formatted: number_with_delimiter(groups.size))
  end

  def components(count)
    t('about_this_collection.components', count:, formatted: number_with_delimiter(count))
  end
end
