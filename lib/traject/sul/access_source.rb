# frozen_string_literal: true

module Sul
  # Finds the indexed record that supplied access text to a component.
  class AccessSource
    FIELDS = {
      id: 'id',
      title: 'normalized_title_ssm',
      level: 'level_ssm'
    }.freeze

    def self.nearest_ancestor(context, field:)
      candidate = parent_of(context)

      while candidate
        return new(candidate.output_hash) if Array(candidate.output_hash[field]).present?

        candidate = parent_of(candidate)
      end
    end

    def self.parent_of(context)
      context.settings[:parent]
    end
    private_class_method :parent_of

    def initialize(output_hash)
      @output_hash = output_hash
    end

    def to_h
      FIELDS.transform_values { |field| Array(output_hash[field]).first }.compact
    end

    private

    attr_reader :output_hash
  end
end
