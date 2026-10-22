# frozen_string_literal: true

module CollectionSummary
  # Deterministic checks on a model-written summary, against the Evidence it
  # was written from. A problem marks the summary for review; it does not
  # reject it.
  #
  # This class is Rails-free so it can run inside the standalone Traject process.
  class Check
    LABELS = ['Key works', 'Notable names', 'Bulk of the material', 'Formats',
              'Not in the collection notes', 'Held elsewhere', 'Restrictions'].freeze
    STATEMENTS = (3..5)
    HIGHLIGHTS = (2..4)
    CITES = (1..4)
    NUMBER = /\b\d[\d,]*(?:\.\d+)?\b/
    YEAR = (1000..2099)
    OPEN_ACCESS = /\b(open|available) (for|to) research\b/i
    PRAISE = /\b(rich|treasures?|remarkable|invaluable|landmark|massive|extensive(ly)?|exhaustive|pioneering|
                distinguished)\b/ix

    # @param summary [Hash] parsed model output with "statements" and "highlights"
    def initialize(evidence, summary)
      @evidence = evidence
      @summary = summary
    end

    def problems
      @problems ||= count_problems + access_problems + entries.flat_map { |entry| entry_problems(entry) }
    end

    private

    def statements = Array(@summary['statements'])
    def highlights = Array(@summary['highlights'])
    def entries = statements + highlights

    def count_problems
      problems = []
      problems << "#{statements.size} statements, expected #{STATEMENTS}" unless STATEMENTS.cover?(statements.size)
      problems << "#{highlights.size} highlights, expected #{HIGHLIGHTS}" unless HIGHLIGHTS.cover?(highlights.size)
      problems + label_problems
    end

    # Without an Access note, a summary that says the collection is open made it up.
    def access_problems
      return [] if @evidence.line(0).match?(/^Access: /)

      texts = entries.map { |entry| entry.values_at('text', 'value').compact.join(' ') }
      texts.grep(OPEN_ACCESS).map { |text| "access not stated in the notes: #{text}" }
    end

    def label_problems
      (highlights.map { |highlight| highlight['label'] } - LABELS).map { |label| "new label: #{label}" }
    end

    def entry_problems(entry)
      cites = Array(entry['cites'])
      text = entry.values_at('text', 'value').compact.join(' ')
      cite_problems(text, cites) + number_problems(text, cites) + private_problems(text) +
        text.scan(PRAISE).map { |word, _| "praise word: #{word}" }
    end

    def cite_problems(text, cites)
      return ["no citation: #{text}"] if cites.empty?

      too_many = cites.size > CITES.max ? ["#{cites.size} citations, expected #{CITES}"] : []
      too_many + cites.filter_map { |number| citation_problem(number) }
    end

    def citation_problem(number)
      if !number.is_a?(Integer) || @evidence.line(number).nil? then "unknown citation [#{number}]"
      elsif number.positive? && @evidence.ref(number).nil? then "citation [#{number}] has no ref to link"
      end
    end

    def number_problems(text, cites)
      sources = ([0] + cites.grep(Integer)).filter_map { |number| @evidence.line(number) }.join("\n").delete(',')
      text.scan(NUMBER).filter_map do |found|
        plain = found.delete(',')
        next if YEAR.cover?(plain.to_i) || @evidence.facts.include?(plain.to_i) || sources.include?(plain)

        "number not in the facts or the cited lines: #{found}"
      end
    end

    def private_problems(text)
      (text.scan(Evidence::NAME_WORD) & @evidence.private_words).map { |word| "word from a restricted part: #{word}" }
    end
  end
end
