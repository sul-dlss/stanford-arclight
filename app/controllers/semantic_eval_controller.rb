# frozen_string_literal: true

# Stage/dev-only page for running the semantic-search relevance eval from the
# browser - no CLI, env vars, or API key needed. A non-developer edits a set of
# test queries and sees keyword / hybrid / semantic compared side by side, run
# through the real search pipeline (see SemanticSearch::Evaluator).
#
# Gated by SemanticSearch.tuning_enabled? (the same dev/stage flag as the
# relevance-tuning panel), so it is invisible in production. Also requires
# query_enabled?, since there is nothing to evaluate without semantic search on.
class SemanticEvalController < ApplicationController
  DEFAULT_QUERIES_PATH = Rails.root.join('config/semantic_eval_queries.txt')

  before_action :require_eval_enabled

  def index
    @queries_text = params[:queries].presence || default_queries_text
    @json_text = params[:test_cases_json]
    @tuning = tuning_params
    @group_by_collection = params[:group] == '1'
    run_eval(suite_source)
  end

  private

  # Parse the chosen suite and score it, or capture a parse error for display.
  # No-op on first load, when nothing has been submitted yet.
  def run_eval(source)
    return if source.blank?

    specs = SemanticSearch::TestSuite.parse(source)
    @rows = SemanticSearch::Evaluator.new(tuning: @tuning, group_by_collection: @group_by_collection).call(specs)
    @scorecard = SemanticSearch::Evaluator.summary(@rows)
    @ran = true
  rescue ArgumentError => e
    @error = e.message
  end

  # The test suite to run, in priority order: an uploaded .json file, then
  # pasted JSON, then the legacy textarea. Nil on first load (nothing submitted).
  def suite_source
    file = params[:file]
    return file.read.force_encoding('UTF-8') if file.respond_to?(:read)
    return @json_text if @json_text.present?

    @queries_text if params[:queries].present?
  end

  # The SemanticQuery tuning knobs (topK / reRankDocs / reRankWeight /
  # min-similarity), applied to hybrid & semantic modes for this run.
  def tuning_params
    params.permit(*SearchBehavior::SemanticQuery::TUNING_PARAMS).to_h.symbolize_keys
  end

  def require_eval_enabled
    return if SemanticSearch.tuning_enabled? && SemanticSearch.query_enabled?

    head :not_found
  end

  def default_queries_text
    File.exist?(DEFAULT_QUERIES_PATH) ? File.read(DEFAULT_QUERIES_PATH) : ''
  end
end
