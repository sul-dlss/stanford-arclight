# frozen_string_literal: true

require 'json'

module SemanticSearch
  # Parses a relevance test suite into the uniform spec the Evaluator scores.
  # Two input formats are accepted:
  #
  #   * The UX team's JSON schema - a JSON array of test-case objects (query +
  #     graded 0-3 judgments + test_type/subject metadata + out_of_scope /
  #     fact_lookup extras). The durable, shareable format.
  #   * The legacy one-line-per-query textarea (`query => id:x:3, Title`), kept
  #     for quick ad-hoc checks.
  #
  # Both yield specs of the shape:
  #   { query:,
  #     expects: ["id:doc:grade", ...],          # graded (score > 0) targets
  #     distractors: { "doc" => "why it's a false match" }, # judged score 0
  #     expected_nothing: Boolean,               # out_of_scope: success = no hits
  #     meta: { test_id:, subject_id:, test_type:, test_description:,
  #             expected_answer:, judge:, judged_on:, human_reviewed: } | nil }
  module TestSuite
    module_function

    # @param text [String] a JSON array/object, or the legacy textarea
    # @return [Array<Hash>] specs (see the module doc)
    # @raise [ArgumentError] on malformed JSON, so the page can show the reason
    def parse(text)
      body = text.to_s.strip
      body.start_with?('[', '{') ? parse_json(body) : parse_text(text)
    end

    def parse_json(body)
      Array.wrap(JSON.parse(body)) # a lone case object is kept intact, not splatted
           .filter_map { |c| case_to_spec(c) if c.is_a?(Hash) && c['query'].present? }
    rescue JSON::ParserError => e
      raise ArgumentError, "Could not parse JSON: #{e.message}"
    end

    def case_to_spec(test_case)
      judgments = Array(test_case['judgments'])
      { query: test_case['query'].to_s,
        expects: judgments.filter_map { |j| graded_expect(j) },
        distractors: distractor_map(judgments),
        expected_nothing: test_case['expected_nothing'] == true,
        meta: meta_of(test_case) }
    end

    # A score>0 judgment becomes a graded id target the Evaluator understands.
    def graded_expect(judgment)
      score = judgment['score'].to_i
      return unless score.positive?

      "id:#{judgment['document_id']}:#{score.clamp(1, 3)}"
    end

    # score==0 judgments are documented false positives - kept so the UI can
    # flag them (with the judge's explanation) when they surface.
    def distractor_map(judgments)
      judgments.select { |j| j['score'].to_i.zero? }
               .to_h { |j| [j['document_id'].to_s, j['explanation'].to_s] }
    end

    def meta_of(test_case)
      { test_id: test_case['test_id'], subject_id: test_case['subject_id'].presence || 'unspecified',
        test_type: test_case['test_type'].presence || 'unspecified',
        test_description: test_case['test_description'], expected_answer: test_case['expected_answer'],
        judge: test_case['judge'], judged_on: test_case['judged_on'],
        human_reviewed: test_case['human_reviewed'] == true }
    end

    # --- legacy textarea format ---

    def parse_text(text)
      text.to_s.lines.filter_map { |line| parse_line(line.strip) }
    end

    def parse_line(line)
      return if line.blank? || line.start_with?('#')

      query, rest = line.split('=>', 2).map(&:strip)
      return if query.blank?

      { query: query, expects: rest.to_s.split(',').map(&:strip).reject(&:empty?),
        distractors: {}, expected_nothing: false, meta: nil }
    end
  end
end
