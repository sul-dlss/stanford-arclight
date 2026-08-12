# frozen_string_literal: true

# View helpers for the stage-only semantic eval page (SemanticEvalController).
module SemanticEvalHelper
  # A colored badge for where the expected result landed in a mode:
  # green 1-3, amber 4-10, red beyond / missing, muted when no target was given.
  def eval_rank_badge(rank, expects)
    return tag.span('—', class: 'badge text-bg-light', title: 'no expected result set') if expects.blank?
    return tag.span('not in top 20', class: 'badge text-bg-danger') if rank.nil?

    klass = if rank <= 3 then 'text-bg-success'
            elsif rank <= 10 then 'text-bg-warning'
            else 'text-bg-danger'
            end
    tag.span("rank #{rank}", class: "badge #{klass}")
  end

  # The best (max) value in each metric column, so the winning cell can be
  # highlighted. @param modes [Hash] mode => { ndcg:, ap:, rr:, p10: }
  def best_metrics(modes)
    SemanticSearch::Evaluator::METRIC_KEYS.index_with { |key| modes.values.map { |m| m[key] }.max }
  end

  # The relevant matches in a mode's pooled results as [{ id:, rank: }], so the
  # UI can list WHICH targets were found and where - including hits that fall
  # below the handful of rows shown. In grouped mode the ids are collection ids.
  def eval_matches(data)
    ids = Array(data[:ids])
    Array(data[:rel]).each_index.filter_map { |i| { id: ids[i], rank: i + 1 } if data[:rel][i].to_i.positive? }
  end

  # Documented false positives (judged score 0) that actually surfaced, as
  # [{ id:, rank:, why: }] - so the UI can show the harness caught the exact
  # distractor the judge flagged. Keyed on the retrieved id (flat-mode concept).
  def eval_distractors(data, distractors)
    return [] if distractors.blank?

    ids = Array(data[:ids])
    ids.each_index.filter_map do |i|
      { id: ids[i], rank: i + 1, why: distractors[ids[i]] } if data[:rel][i].to_i.zero? && distractors.key?(ids[i])
    end
  end

  # Per-group scorecards keyed by a meta field (test_type / subject_id), each the
  # same shape Evaluator.summary returns. Out-of-scope rows carry no metrics, so
  # only groups with at least one scored query appear. @return [Hash] label => summary
  def eval_group_summaries(rows, key)
    rows.reject { |row| row[:expected_nothing] }
        .group_by { |row| row.dig(:meta, key).presence || 'unspecified' }
        .transform_values { |group| SemanticSearch::Evaluator.summary(group) }
        .select { |_label, summary| summary[:count].positive? }
        .sort.to_h
  end
end
