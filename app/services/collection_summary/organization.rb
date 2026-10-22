# frozen_string_literal: true

require 'nokogiri'

module CollectionSummary
  # How a collection's components are arranged: in groups (such as series),
  # in one flat list, or not described at all.
  #
  # This class is Rails-free so it can run inside the standalone Traject process.
  class Organization
    COMPONENT = /\Ac(0[1-9]|1[0-2])?\z/

    # One top-level component that holds other components. The ref matches
    # Arclight's ref_ssi, which forms the second part of the component's Solr id.
    Group = Struct.new(:title, :level, :component_count, :ref)

    # @param path [String] path to an EAD XML file
    def self.from_file(path)
      doc = Nokogiri::XML(File.read(path), &:huge)
      doc.remove_namespaces!
      new(doc)
    end

    # @param doc [Nokogiri::XML::Document] an EAD document without namespaces
    def initialize(doc)
      @top = doc.xpath('/ead/archdesc/dsc/*').select { |node| component?(node) }
    end

    def component_count
      @component_count ||= @top.sum { |node| 1 + descendant_count(node) }
    end

    def groups
      @groups ||= @top.filter_map do |node|
        size = descendant_count(node)
        Group.new(title(node), node['level'], size, ref(node)) if size.positive?
      end
    end

    def largest_group
      groups.max_by(&:component_count)
    end

    def arrangement
      if component_count.zero? then :none
      elsif groups.empty? then :flat
      else :grouped
      end
    end

    private

    def component?(node)
      node.element? && node.name.match?(COMPONENT)
    end

    def title(node)
      node.at_xpath('./did/unittitle')&.text.to_s.gsub(/\s+/, ' ').strip
    end

    def ref(node)
      node['id']&.strip&.tr('.', '-')
    end

    def descendant_count(node)
      node.xpath('.//*').count { |child| component?(child) }
    end
  end
end
