# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SemanticSearch::TestSuite do
  describe '.parse (legacy textarea)' do
    it 'parses queries and comma-separated id/title expects, ignoring comments and blanks' do
      text = <<~TXT
        # category header
        Kirsten Flagstad Collection => id:ars0001, Kirsten Flagstad

        primary sources jazz revival
      TXT

      expect(described_class.parse(text)).to eq(
        [
          { query: 'Kirsten Flagstad Collection', expects: ['id:ars0001', 'Kirsten Flagstad'],
            distractors: {}, expected_nothing: false, meta: nil },
          { query: 'primary sources jazz revival', expects: [], distractors: {}, expected_nothing: false, meta: nil }
        ]
      )
    end
  end

  describe '.parse (JSON schema)' do
    it 'maps graded judgments to expects, score-0 judgments to distractors, and carries metadata' do
      json = <<~JSON
        [
          {
            "test_id": "peoples-temple-1", "subject_id": "peoples-temple",
            "query": "religious group mass deaths in Guyana",
            "test_type": "conceptual_thematic", "test_description": "vocab mismatch",
            "expected_answer": null, "expected_nothing": false,
            "judge": "claude-opus-5", "judged_on": "2026-08-24", "human_reviewed": true,
            "judgments": [
              {"document_id": "ms_3791", "score": 3, "explanation": "the records"},
              {"document_id": "ms_9999", "score": 0, "explanation": "surname collision"}
            ]
          }
        ]
      JSON

      spec = described_class.parse(json).first
      expect(spec[:query]).to eq('religious group mass deaths in Guyana')
      expect(spec[:expects]).to eq(['id:ms_3791:3'])
      expect(spec[:distractors]).to eq('ms_9999' => 'surname collision')
      expect(spec[:expected_nothing]).to be(false)
      expect(spec[:meta]).to include(test_type: 'conceptual_thematic', subject_id: 'peoples-temple',
                                     human_reviewed: true, judge: 'claude-opus-5')
    end

    it 'flags out_of_scope cases and preserves a fact_lookup expected_answer' do
      json = <<~JSON
        [
          {"query": "quantum teleportation patents", "test_type": "out_of_scope",
           "expected_nothing": true, "judgments": []},
          {"query": "when did Jones move to Guyana?", "test_type": "fact_lookup",
           "expected_answer": {"value": "1977", "evidence": [
             {"document_id": "ms_3791", "locator": "p. 4", "quote": "moved in 1977"}]},
           "judgments": [{"document_id": "ms_3791", "score": 3, "explanation": "answer-bearing"}]}
        ]
      JSON

      oos, fact = described_class.parse(json)
      expect(oos[:expected_nothing]).to be(true)
      expect(oos[:expects]).to be_empty
      expect(fact[:meta][:expected_answer]).to include('value' => '1977')
      expect(fact[:expects]).to eq(['id:ms_3791:3'])
    end

    it 'clamps out-of-range scores and defaults missing subject/type to unspecified' do
      json = '[{"query": "q", "judgments": [{"document_id": "d1", "score": 9, "explanation": "x"}]}]'
      spec = described_class.parse(json).first
      expect(spec[:expects]).to eq(['id:d1:3'])
      expect(spec[:meta]).to include(subject_id: 'unspecified', test_type: 'unspecified')
    end

    it 'raises a readable ArgumentError on malformed JSON' do
      expect { described_class.parse('[{"query": ') }.to raise_error(ArgumentError, /Could not parse JSON/)
    end

    it 'accepts a single case object as well as an array' do
      expect(described_class.parse('{"query": "solo", "judgments": []}').pluck(:query)).to eq(['solo'])
    end
  end
end
