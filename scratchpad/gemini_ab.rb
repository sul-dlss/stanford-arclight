# frozen_string_literal: true

# gemini-embedding-2  vs  text-multilingual-embedding-002  A/B harness.
#
# Runs the SAME corpus (EAL + ARS by default) and query set through BOTH models
# and reports where each query's known-good doc(s) rank under each model (MRR +
# per-query rank). No production code changes and no Solr schema change: KNN is
# exact cosine done in-memory over the two vector sets.
#
#   * 002 doc vectors come from the existing content-addressed cache
#     (tmp/embeddings.sqlite) - already generated.
#   * gemini doc vectors are generated via the native /gemini batchEmbedContents
#     pass-through (768-dim) and cached to a SEPARATE sqlite file so it's a
#     one-time cost, reusable in the future. Resumable: re-runs only fill misses.
#
# Run (needs the gateway key; 002 side needs the 002 model + task_type):
#   SEMANTIC_SEARCH_EMBEDDING_API_KEY=... \
#   SEMANTIC_SEARCH_EMBEDDING_MODEL=text-multilingual-embedding-002 \
#   SEMANTIC_SEARCH_EMBED_TASK_TYPE=true \
#   bin/rails runner scratchpad/gemini_ab.rb
#
# Optional env: AB_REPOS=eal (smoke-test on the small repo first), AB_MAX_POOL=5000,
#   SEMANTIC_SEARCH_GEMINI_CACHE=tmp/embeddings-gemini.sqlite, AB_QUERIES=path.json
require 'json'
require 'faraday'
require_relative 'gemini_embedder'

REPO_NAMES = { 'eal' => 'East Asia Library', 'ars' => 'Archive of Recorded Sound',
               'chs' => 'California Historical Society', 'cubberley' => 'Cubberley Education Library' }.freeze
REPOS      = ENV.fetch('AB_REPOS', 'eal,ars').split(',').map(&:strip)
V002_CACHE = ENV.fetch('SEMANTIC_SEARCH_EMBEDDING_CACHE', Rails.root.join('tmp/embeddings.sqlite').to_s)
GEM_CACHE  = ENV.fetch('SEMANTIC_SEARCH_GEMINI_CACHE', Rails.root.join('tmp/embeddings-gemini.sqlite').to_s)
QUERIES    = ENV.fetch('AB_QUERIES', File.join(__dir__, 'gemini_ab_queries.json'))
MAX_POOL   = ENV['AB_MAX_POOL']&.to_i
SOLR       = 'http://localhost:8983/solr/blacklight-core/select'
FIELDS     = %w[id normalized_title_ssm abstract_tesim scopecontent_tesim bioghist_tesim
                access_subjects_ssim names_ssim places_ssim repository_ssim].freeze
CONN = Faraday.new { |f| f.options.timeout = 120 }

def log(msg) = warn("[#{Time.now.strftime('%H:%M:%S')}] #{msg}")

def normalize(vec)
  norm = Math.sqrt(vec.sum { |x| x * x })
  norm.zero? ? vec : vec.map { |x| x / norm }
end

def pack(vec) = normalize(vec).map(&:to_f).pack('e*')

def dot(query_arr, packed)
  dv = packed.unpack('e*')
  sum = 0.0
  i = 0
  n = query_arr.length
  while i < n
    sum += query_arr[i] * dv[i]
    i += 1
  end
  sum
end

# --- 1. Fetch EAL/ARS docs and build embed text (via the real TextBuilder) ----
def fetch_docs
  filter = REPOS.map { |r| %("#{REPO_NAMES.fetch(r)}") }.join(' OR ')
  cursor = '*'
  docs = []
  loop do
    body = { query: '*:*', filter: ["repository_ssim:(#{filter})"], fields: FIELDS.join(','),
             sort: 'id asc', limit: 500, params: { cursorMark: cursor } }
    r = JSON.parse(CONN.post(SOLR) { |c| c.headers['Content-Type'] = 'application/json'; c.body = JSON.generate(body) }
                      .body.force_encoding('UTF-8'))
    batch = r.dig('response', 'docs')
    batch.each do |d|
      text = SemanticSearch::TextBuilder.new(d).call
      next if text.nil?

      docs << { id: d['id'], title: Array(d['normalized_title_ssm']).first.to_s.squish, text: text }
    end
    log("fetched #{docs.size} docs...") if (docs.size % 5000).zero? && docs.any?
    nxt = r['nextCursorMark']
    break if nxt == cursor || batch.empty?

    cursor = nxt
    break if MAX_POOL && docs.size >= MAX_POOL
  end
  MAX_POOL ? docs.first(MAX_POOL) : docs
end

# --- 2. Ensure gemini vectors exist for every doc text (batched, resumable) ----
def generate_gemini(docs, cache)
  missing = docs.reject { |d| cache.fetch(d[:text]) }
  log("gemini cache: #{docs.size - missing.size}/#{docs.size} present, generating #{missing.size}")
  embedder = GeminiEmbedder.new
  missing.each_slice(200).with_index do |slice, i|
    vectors = embedder.embed_batch(slice.map { |d| d[:text] }, task_type: GeminiEmbedder::DOCUMENT_TASK_TYPE)
    slice.each_with_index { |d, j| cache.store(d[:text], vectors[j]) }
    log("  gemini generated #{[(i + 1) * 200, missing.size].min}/#{missing.size}")
  end
end

# --- 3. Build the comparison pool (docs present in BOTH vector sets) -----------
def build_pool(docs, v002, gem)
  pool = { ids: [], titles: [], v002: [], gem: [] }
  dropped = 0
  docs.each do |d|
    a = v002.fetch(d[:text])
    b = gem.fetch(d[:text])
    if a.nil? || b.nil?
      dropped += 1
      next
    end
    pool[:ids] << d[:id]
    pool[:titles] << d[:title]
    pool[:v002] << pack(a)
    pool[:gem]  << pack(b)
  end
  log("pool: #{pool[:ids].size} docs in both vector sets (#{dropped} dropped for a missing vector)")
  pool
end

# Top-n doc ids by cosine for a query vector (the pure-vector ranking).
def vector_order(query_vec, packed_list, ids, top_n)
  scores = packed_list.map { |p| dot(query_vec, p) }
  (0...scores.size).sort_by { |i| -scores[i] }.first(top_n).map { |i| ids[i] }
end

# Keyword (edismax/BM25) ranking over the SAME repos, via real Solr - the
# baseline the vector leg is supposed to *add recall to* in hybrid.
def keyword_order(query, top_n)
  filter = REPOS.map { |r| %("#{REPO_NAMES.fetch(r)}") }.join(' OR ')
  body = { query: { edismax: { query: query } }, filter: ["repository_ssim:(#{filter})"],
           fields: 'id', sort: 'score desc', limit: top_n, params: { qt: 'search' } }
  r = JSON.parse(CONN.post(SOLR) { |c| c.headers['Content-Type'] = 'application/json'; c.body = JSON.generate(body) }
                    .body.force_encoding('UTF-8'))
  Array(r.dig('response', 'docs')).map { |d| d['id'] }
end

# Reciprocal Rank Fusion of ranked id lists (rank-based, scale-independent) -
# the hybrid we want in production. Fuses keyword + one model's vector ranking.
def rrf(lists, k = 60)
  score = Hash.new(0.0)
  lists.each { |ids| ids.each_with_index { |id, i| score[id] += 1.0 / (k + i + 1) } }
  score.sort_by { |_id, s| -s }.map(&:first)
end

# 1-based rank of the first id that is a target or whose title matches, else nil.
def rank_in(ordered, targets, expect_title, id2title)
  needle = expect_title&.downcase
  ordered.find_index { |id| targets.include?(id) || (needle && id2title[id].to_s.downcase.include?(needle)) }&.+(1)
end

def mrr(rank) = rank ? 1.0 / rank : 0.0

# Emit standard TREC files so the run can be scored with trec_eval / ir_measures
# (NDCG, MAP, P@k, ...), interoperable with the SUL Website Search Relevance POC.
#   qrels line:  <query-id> 0 <doc-id> <relevance>
#   run line:    <query-id> Q0 <doc-id> <rank> <score> <run-tag>
# Relevance is written as the 4th column (grade). Binary here (any listed target
# = 1); when the shared query-set format carries 0-3 grades, emit those instead
# and ir_measures' nDCG picks them up automatically. The in-app Evaluator already
# scores graded (SemanticSearch::Evaluator, `:GRADE` suffix).
def write_trec(dir, specs, pool, id2title, runs)
  require 'fileutils'
  FileUtils.mkdir_p(dir)
  qrels = File.join(dir, 'qrels.txt')
  File.open(qrels, 'w') do |f|
    specs.each do |q|
      targets = Array(q['targets'])
      needle = q['expect_title']&.downcase
      pool[:ids].each do |id|
        relevant = targets.include?(id) || (needle && id2title[id].to_s.downcase.include?(needle))
        f.puts("#{q['id']} 0 #{id} 1") if relevant
      end
    end
  end
  runs.each do |tag, per_query|
    File.open(File.join(dir, "run.#{tag}.txt"), 'w') do |f|
      per_query.each do |qid, ids|
        ids.each_with_index { |id, i| f.puts("#{qid} Q0 #{id} #{i + 1} #{format('%.6f', 1.0 / (i + 1))} #{tag}") }
      end
    end
  end
  qrels
end

# Keyword (edismax) ranking WITH BM25 scores, for the reRank replication.
def keyword_scored(query, top_n)
  filter = REPOS.map { |r| %("#{REPO_NAMES.fetch(r)}") }.join(' OR ')
  body = { query: { edismax: { query: query } }, filter: ["repository_ssim:(#{filter})"],
           fields: 'id,score', sort: 'score desc', limit: top_n, params: { qt: 'search' } }
  r = JSON.parse(CONN.post(SOLR) { |c| c.headers['Content-Type'] = 'application/json'; c.body = JSON.generate(body) }
                    .body.force_encoding('UTF-8'))
  Array(r.dig('response', 'docs')).to_h { |d| [d['id'], d['score'].to_f] }
end

# The vector should-clause contributes only for the top-K by cosine (matches the
# prod knn topK): {id => cosine} for the top_k docs.
def knn_scored(query_vec, packed_list, ids, top_k)
  scores = packed_list.map { |p| dot(query_vec, p) }
  (0...scores.size).sort_by { |i| -scores[i] }.first(top_k).to_h { |i| [ids[i], scores[i]] }
end

# Faithful in-memory replica of the CURRENT-prod (Solr 9.10) hybrid:
# bool.should[edismax, knn] scored by (kw + knn), then Solr reRank adds
# reRankWeight*knn to the top reRankDocs and re-sorts them. Score-based, so it is
# sensitive to each model's cosine SCALE (gemini's run higher) - which is exactly
# why the model choice may differ between reRank and (rank-based) RRF.
def rerank_order(kw, knn, rerank_docs, weight)
  base = Hash.new(0.0)
  kw.each { |id, s| base[id] += s }
  knn.each { |id, s| base[id] += s }
  order = base.keys.sort_by { |id| -base[id] }
  head = order.first(rerank_docs).sort_by { |id| -(base[id] + weight * (knn[id] || 0.0)) }
  head + order.drop(rerank_docs)
end

# A query is "testable" only if a matching doc actually exists in the pool;
# otherwise both models score 0 and would dilute the MRR. (The pool is shared,
# so testability is model-independent.)
def testable?(ids, titles, targets, expect_title)
  needle = expect_title&.downcase
  ids.each_index.any? { |i| targets.include?(ids[i]) || (needle && titles[i].downcase.include?(needle)) }
end

# ------------------------------------------------------------------------------
log("repos=#{REPOS.inspect}  002 model=#{SemanticSearch.embedding_model}")
docs = fetch_docs
log("total docs with embed text: #{docs.size}")

v002 = SemanticSearch::EmbeddingCache::Sqlite.new(V002_CACHE, writable: false)
gem_cache = SemanticSearch::EmbeddingCache::Sqlite.new(GEM_CACHE, writable: true)
generate_gemini(docs, gem_cache)

# preload vectors into hashes keyed by text (single fetch per doc)
v002_by_text = {}
gem_by_text = {}
docs.each do |d|
  v002_by_text[d[:text]] ||= v002.fetch(d[:text])
  gem_by_text[d[:text]] ||= gem_cache.fetch(d[:text])
end
pool = build_pool(docs, v002_by_text, gem_by_text)

specs = JSON.parse(File.read(QUERIES, encoding: 'UTF-8'))['queries']
id2title = docs.to_h { |d| [d[:id], d[:title]] }
svc = SemanticSearch::EmbeddingService.new
gem_embedder = GeminiEmbedder.new
FUSE_N = Integer(ENV.fetch('AB_FUSE_N', 500))
RERANK_WEIGHTS = (ENV['AB_RERANK_WEIGHTS'] || '0,2,5,10,20').split(',').map(&:to_f)
RERANK_DOCS = Integer(ENV.fetch('AB_RERANK_DOCS', 100))
KNN_TOPK = Integer(ENV.fetch('AB_KNN_TOPK', 100))
# Modes compared: keyword-only, each model alone (pure vector), and hybrid =
# RRF(keyword, model-vector). The hybrid columns are the production question:
# "which model makes hybrid better?"; the keyword column shows the baseline it
# has to improve on.
MODES = %w[keyword vec-002 vec-gem hyb-002 hyb-gem].freeze

results = []
runs = Hash.new { |h, k| h[k] = {} } # tag => { query-id => [ranked doc ids] } for TREC export
specs.each do |q|
  targets = Array(q['targets'])
  expect = q['expect_title']
  cat = q['category'] || 'uncategorized'
  unless testable?(pool[:ids], pool[:titles], targets, expect)
    results << { q: q, cat: cat, skipped: true }
    next
  end
  kw_scores = keyword_scored(q['query'], FUSE_N)
  kw = kw_scores.keys
  q002 = normalize(svc.embed(q['query'], task_type: SemanticSearch::EmbeddingService::QUERY_TASK_TYPE))
  qgem = normalize(gem_embedder.embed(q['query'], task_type: GeminiEmbedder::QUERY_TASK_TYPE))
  v002 = vector_order(q002, pool[:v002], pool[:ids], FUSE_N)
  vgem = vector_order(qgem, pool[:gem], pool[:ids], FUSE_N)
  kn002 = knn_scored(q002, pool[:v002], pool[:ids], KNN_TOPK)
  kngem = knn_scored(qgem, pool[:gem], pool[:ids], KNN_TOPK)
  orders = { 'keyword' => kw, 'vec-002' => v002, 'vec-gem' => vgem,
             'hyb-002' => rrf([kw, v002]), 'hyb-gem' => rrf([kw, vgem]) }
  ranks = orders.transform_values { |o| rank_in(o, targets, expect, id2title) }
  # reRank (current-prod fusion) at each weight, for both models.
  rerank = RERANK_WEIGHTS.to_h do |w|
    [w, { '002' => rank_in(rerank_order(kw_scores, kn002, RERANK_DOCS, w), targets, expect, id2title),
          'gem' => rank_in(rerank_order(kw_scores, kngem, RERANK_DOCS, w), targets, expect, id2title) }]
  end
  results << { q: q, cat: cat, ranks: ranks, orders: orders, rerank: rerank }

  # Capture ranked lists as TREC runs: keyword, each model's vector, and both
  # fusions (RRF + reRank at the shipped weight 10).
  qid = q['id']
  %w[keyword vec-002 vec-gem].each { |t| runs[t][qid] = orders[t] }
  runs['hyb-002-rrf'][qid] = orders['hyb-002']
  runs['hyb-gem-rrf'][qid] = orders['hyb-gem']
  runs['hyb-002-rerank10'][qid] = rerank_order(kw_scores, kn002, RERANK_DOCS, 10)
  runs['hyb-gem-rerank10'][qid] = rerank_order(kw_scores, kngem, RERANK_DOCS, 10)
end

tested = results.reject { |r| r[:skipped] }
fmt = '%-22s %9s %9s %9s %9s %9s'
puts "\n# Hybrid-marginal A/B (RRF fusion): does keyword + 002 or keyword + gemini rank better?"
puts "corpus: #{REPOS.join(' + ')} (#{pool[:ids].size} docs), #{tested.size} testable queries\n"

# Per-category table + MRR, then overall.
tested.group_by { |r| r[:cat] }.each do |cat, rs|
  puts "\n## #{cat} (#{rs.size})"
  puts format(fmt, 'query', *MODES)
  rs.each { |r| puts format(fmt, r[:q]['id'][0, 22], *MODES.map { |m| r[:ranks][m] || '>N' }) }
  puts format(fmt, 'MRR', *MODES.map { |m| format('%.3f', rs.sum { |r| mrr(r[:ranks][m]) } / rs.size) })
end
puts "\n## OVERALL (#{tested.size} testable, #{results.count { |r| r[:skipped] }} skipped)"
puts format(fmt, 'MRR', *MODES.map { |m| format('%.3f', tested.sum { |r| mrr(r[:ranks][m]) } / tested.size) })

# reRank fusion sweep (the CURRENT-prod Solr 9.10 hybrid) vs RRF, to see whether
# the fusion method flips the model winner. Cells are 002/gemini MRR.
puts "\n# reRank fusion (current prod) vs RRF — does the fusion change the winner?"
puts '  cells = 002 MRR / gemini MRR;  W=0 is bool.should union (no reRank boost)'
wfmt = "%-14s#{' %11s' * RERANK_WEIGHTS.size}  %11s"
puts format(wfmt, 'category', *RERANK_WEIGHTS.map { |w| "reRank#{w.to_i}" }, 'RRF')
by_cat = tested.group_by { |r| r[:cat] }
(by_cat.keys + ['OVERALL']).each do |cat|
  rs = cat == 'OVERALL' ? tested : by_cat[cat]
  pair = lambda do |get002, getgem|
    format('%.2f/%.2f', rs.sum { |r| mrr(get002.call(r)) } / rs.size, rs.sum { |r| mrr(getgem.call(r)) } / rs.size)
  end
  cells = RERANK_WEIGHTS.map { |w| pair.call(->(r) { r[:rerank][w]['002'] }, ->(r) { r[:rerank][w]['gem'] }) }
  rrf_cell = pair.call(->(r) { r[:ranks]['hyb-002'] }, ->(r) { r[:ranks]['hyb-gem'] })
  puts format(wfmt, cat, *cells, rrf_cell)
end

# Detail: keyword vs the two hybrids, top-5 titles (✓ = target).
if SemanticSearch.truthy?(ENV.fetch('AB_DETAIL', 'true'))
  tested.each do |r|
    targets = Array(r[:q]['targets'])
    needle = r[:q]['expect_title']&.downcase
    puts "\n### [#{r[:cat]}] #{r[:q]['id']}  \"#{r[:q]['query']}\""
    %w[keyword hyb-002 hyb-gem].each do |m|
      puts "  #{m} (rank #{r[:ranks][m] || '>N'})"
      r[:orders][m].first(5).each_with_index do |id, i|
        hit = targets.include?(id) || (needle && id2title[id].to_s.downcase.include?(needle))
        puts format('    %d.%s %s', i + 1, hit ? ' ✓' : '  ', id2title[id].to_s[0, 58])
      end
    end
  end
end
gem_cache.close

# TREC export: qrels + one run file per config, for standard metric tooling.
trec_dir = ENV.fetch('AB_TREC_DIR', File.join(__dir__, 'trec'))
tested_specs = specs.select { |q| runs['keyword'].key?(q['id']) }
qrels_path = write_trec(trec_dir, tested_specs, pool, id2title, runs)
puts "\n# TREC files written to #{trec_dir}/"
puts "  qrels.txt + #{runs.size} run files (#{runs.keys.join(', ')})"
puts '  Score with ir_measures (python3 -m pip install --user ir_measures):'
puts %(  for r in #{trec_dir}/run.*.txt; do echo "== $(basename "$r")"; ) +
     %(python3 -m ir_measures #{qrels_path} "$r" nDCG@10 AP RR P@10 R@100; done)
