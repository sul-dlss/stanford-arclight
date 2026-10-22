# frozen_string_literal: true

require 'nokogiri'

module CollectionSummary
  # rubocop:disable Metrics/ClassLength
  # The text a model reads to summarize one collection: the collection-level
  # notes, facts that code counts, then every component in order. Each
  # component line starts with a number the model cites; #ref maps that number
  # back to the component's ref.
  #
  # Numbers stand in for refs because ArchivesSpace refs are long and easy to
  # garble. This class is Rails-free so it can run inside the standalone Traject process.
  class Evidence
    COMPONENT = Organization::COMPONENT
    COLLECTION_NOTES = {
      'abstract' => 'Abstract', 'scopecontent' => 'Scope and content', 'bioghist' => 'Biographical or historical',
      'arrangement' => 'Arrangement', 'accessrestrict' => 'Access', 'userestrict' => 'Use',
      'acqinfo' => 'Acquisition', 'processinfo' => 'Processing', 'relatedmaterial' => 'Related material',
      'separatedmaterial' => 'Separated material', 'otherfindaid' => 'Other finding aids'
    }.freeze
    DID_FIELDS = {
      'unitdate' => 'Dates', 'physdesc' => 'Extent', 'origination' => 'Creator', 'langmaterial' => 'Language'
    }.freeze
    COMPONENT_NOTES = {
      'scopecontent' => 'scope', 'odd' => 'note', 'bioghist' => 'history', 'arrangement' => 'arrangement',
      'accessrestrict' => 'access', 'userestrict' => 'use', 'phystech' => 'physical', 'acqinfo' => 'acquisition'
    }.freeze
    INDEX_TERMS = %w[persname famname corpname subject geogname genreform occupation function title].freeze
    RESTRICTED = /\b(closed|restricted|sealed|unavailable)\b/i
    NAME_WORD = /\b[[:upper:]][[:lower:]]{2,}\b/

    def self.from_file(path)
      doc = Nokogiri::XML(File.read(path), &:huge)
      doc.remove_namespaces!
      new(doc)
    end

    def initialize(doc)
      @archdesc = doc.at_xpath('/ead/archdesc')
      @refs = []
      @lines = []
      @titles = []
      @groups = []
      @restricted_lines = []
      @open_lines = []
    end

    def text
      @text ||= begin
        contents = contents_lines
        (collection_lines + ['', 'FACTS'] + fact_lines + ['', 'CONTENTS'] + contents).join("\n")
      end
    end

    # @param number [Integer] a component number as it appears in #text
    def ref(number)
      text
      @refs[number - 1] if number.positive?
    end

    # @return [String, nil] the component's line and notes, or the collection notes for 0
    def line(number)
      text
      return collection_lines.join("\n") if number.zero?

      @lines[number - 1] if number.positive?
    end

    def title(number)
      text
      @titles[number - 1] if number.positive?
    end

    # The counts in the FACTS section, the only numbers a summary may state
    # besides years.
    def facts
      text
      [@refs.size, @groups.size] + @groups.map(&:last)
    end

    # Capitalized words that appear only in restricted components, such as the
    # names of people in closed files.
    def private_words
      text
      @private_words ||= words(@restricted_lines) - words(@open_lines + collection_lines)
    end

    private

    def collection_lines
      @collection_lines ||= begin
        did = @archdesc.at_xpath('./did')
        lines = ['COLLECTION', "Title: #{clean(did&.at_xpath('./unittitle'))}"]
        lines += DID_FIELDS.map { |name, label| labeled(label, did&.xpath("./#{name}")) }
        lines += COLLECTION_NOTES.map { |name, label| labeled(label, @archdesc.xpath("./#{name} | ./did/#{name}")) }
        (lines + index_lines).compact
      end
    end

    def index_lines
      INDEX_TERMS.filter_map do |type|
        terms = @archdesc.xpath("./controlaccess//#{type}").map { |node| clean(node) }.uniq
        "Index (#{type}): #{terms.join('; ')}" if terms.any?
      end
    end

    def fact_lines
      ["Components in the contents list: #{@refs.size}", "Top-level components: #{@groups.size}"] +
        @groups.filter_map do |number, title, size|
          "[#{number}] #{title}: #{size} components beneath it" if size.positive?
        end
    end

    def contents_lines
      @archdesc.xpath('./dsc/*').select { |node| component?(node) }.flat_map do |node|
        number = @refs.size + 1
        lines = component_lines(node, 0, false)
        @groups << [number, unit_title(node), @refs.size - number]
        lines
      end
    end

    def component_lines(node, depth, inherited)
      @refs << node['id']&.strip&.tr('.', '-')
      restricted = inherited || restricted?(node)
      children = node.element_children.select { |child| component?(child) }
      own_lines(node, '  ' * depth, restricted, inherited) +
        children.flat_map { |child| component_lines(child, depth + 1, restricted) }
    end

    # A component that declares its own restriction stays open for #private_words,
    # so a summary can name what is closed.
    def own_lines(node, indent, restricted, inherited)
      lines = ["#{indent}[#{@refs.size}] #{summary(node, restricted)}"] + note_lines(node, "#{indent}    ")
      @lines << lines.join("\n")
      @titles << unit_title(node)
      (inherited ? @restricted_lines : @open_lines).concat(lines)
      lines
    end

    def note_lines(node, indent)
      COMPONENT_NOTES.flat_map do |name, label|
        texts = node.xpath("./#{name}").map { |note| note_text(note) }.reject(&:empty?)
        texts.map { |text| "#{indent}#{label}: #{text}" }
      end
    end

    def summary(node, restricted)
      did = node.at_xpath('./did')
      parts = [unit_title(node), level(node), joined(did&.xpath('./unitdate')), joined(did&.xpath('./physdesc'))]
      parts << 'digital object' if did&.at_xpath('./dao | ./daogrp')
      parts << 'restricted' if restricted
      parts.compact.reject(&:empty?).join(' | ')
    end

    def restricted?(node)
      node.xpath('./accessrestrict').any? { |note| note_text(note).match?(RESTRICTED) }
    end

    def unit_title(node)
      clean(node.at_xpath('./did/unittitle'))
    end

    def level(node)
      "(#{node['level']})" if node['level'] && node['level'] != 'file'
    end

    def joined(nodes)
      Array(nodes).map { |node| clean(node) }.join(', ')
    end

    def words(lines)
      lines.flat_map { |line| line.scan(NAME_WORD) }.uniq
    end

    def labeled(label, nodes)
      values = Array(nodes).map { |node| note_text(node) }.reject(&:empty?)
      "#{label}: #{values.join(' / ')}" if values.any?
    end

    def note_text(node)
      copy = node.dup
      copy.xpath('./head').each(&:remove)
      clean(copy)
    end

    def clean(node)
      node&.text.to_s.gsub(/\s+/, ' ').strip
    end

    def component?(node)
      node.element? && node.name.match?(COMPONENT)
    end
  end
  # rubocop:enable Metrics/ClassLength
end
