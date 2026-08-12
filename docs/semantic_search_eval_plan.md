# Semantic search: relevance & pipeline-fidelity eval plan

Working notes for evaluating whether semantic (vector) search actually improves
retrieval, and for tuning *what* we embed before a full-corpus backfill. Feature
mechanics live in the README "Semantic search" section; this doc is about
**signals and decisions**, not configuration.

## Guiding principle

KNN relevance is a property of the **whole vector space**, not a single repo. A
"good result" means the right doc ranks above the *other* millions competing for
that slot, so precision failures (semantic search surfacing plausible-but-wrong
docs) and cross-collection ranking only become visible at scale. Single-repo
tests are an easier, different test that hides exactly the failures we'd deploy
into. Therefore: **generate broadly, then evaluate against a large / full
corpus.** Generation is cheap (~$0.20/1M tokens, ~$5.51 for the whole ~1.2M-doc
corpus, cached once); the real constraints are throughput (see Blockers) and
Solr footprint — not embedding cost.

## What we've established (with evidence)

- **Thin-doc policy — DECIDED: index everything, no filter (see "Thin docs"
  section below).** The original hypothesis was that "thin" (title-only) docs are
  noise worth dropping. Profiling every title in all repos (~1.14M) overturned
  it: **94% of titles are unique/distinctive**, only a **~1.9% tail** is genuine
  container-label boilerplate (correspondence, photographs, ...), and the
  clustering test already showed even that boilerplate doesn't hurt retrieval (it
  self-segregates). So there is no filtering problem worth solving: skip-thin
  (drops ~70%) and the frequency/centroid filters (false positives on meaningful
  repeated titles like `Tony & Gus`) were all removed. **We embed and index every
  doc.**

- **Keep names in the embed text.** Reliance on names is repo-dependent: only
  ~4% of kept ARS docs hinge solely on a name, but **63% of kept EAL docs do** —
  and EAL's names are recognizable entities (Kazuko Shiraishi, Ryūichi Tamura,
  New Directions, Asahi Shinbunsha) that bridge to topics. The `TERMS_PER_CATEGORY
  = 12` cap and prose-first ordering bound the noise risk. (This is exactly what
  the with/without-names A/B below is meant to confirm empirically.)

- **`places_ssim` contributes ~nothing here** — but that's the data (≤3 docs
  with `controlaccess/geogname` in EAL/ARS), not a wiring bug: Arclight populates
  `places_ssim` and `geogname_ssim` from the same xpath.

## Thin docs & boilerplate — the full-corpus finding

We nearly shipped skip-thin as the default. Profiling **every `<unittitle>` in
all repos (1,142,954 titles)** stopped that. Title-frequency, % of all titles
whose raw title repeats ≥N× (the boilerplate tail):

| repo | titles | uniq% | ≥3× | ≥5× | ≥10× |
|---|---|---|---|---|---|
| ars | 44,468 | 91% | 14.2% | 8.6% | 5.5% |
| chs | 14,829 | 93% | 11.6% | 6.5% | 4.7% |
| cubberley | 13,530 | 95% | 20.4% | 17.9% | 14.6% |
| eal | 1,129 | 96% | 11.1% | 8.9% | 5.8% |
| manuscripts | 671,718 | 94% | 14.1% | 10.2% | 7.3% |
| uarc | 387,359 | 94% | 16.8% | 12.7% | 9.0% |
| vt | 9,921 | 92% | 7.7% | 2.0% | 0.6% |
| **corpus** | **1,142,954** | **94%** | 15.8% | **11.7%** | 8.5% |

Findings:
- **94% of titles are unique.** Thin ≠ boilerplate — most title-only docs are
  distinctive, meaningful items. The "well-processed vs minimally-processed repo"
  dichotomy does **not** hold; every repo is ~50–83% thin and ~91–96% unique.
- **The real boilerplate is a ~12% tail** of high-frequency container labels
  (`correspondence`, `photographs`, `miscellaneous`, `folders`, `来函`, ...).
  Bigger than early samples/Solr suggested (~1–2.6%) — Solr's *date-appended*
  `normalized_title_ssm` made repeats look unique; the raw `title_ssm` reveals them.
- **Every filter we tried failed the cost/benefit test:**
  - *blunt skip-thin* — drops ~70% to remove ~2%; guts recall (silently dropped
    all 34 EAL Einstein docs + ARS's dated broadcasts).
  - *embedding-centroid "meaningfulness"* — worked within a collection but the
    threshold/centroid did **not** generalize (EAL ~0.84 vs ARS ~0.90; a shared
    centroid failed on EAL entirely).
  - *title-frequency* — false positives: it flags meaningful repeated titles
    (`Tony & Gus` radio series ×234, `Laughlin, James` ×47, cubberley's college
    names). Curating down to *only* unambiguous container labels drops just
    **~1.9%** of the corpus.

**Decision: no filter — index everything.** The genuinely-droppable boilerplate
is ~1.9%, it doesn't hurt retrieval (clustering test: 8% of a query's neighbors
vs 74% base rate — it self-segregates), and every automated filter either
over-drops or mis-classifies. So the skip-thin flag, the `BoilerplateFilter`
module, the stoplist rake task, and the centroid asset were all **removed**. If a
hard footprint limit ever appears, a *curated* generic-vocabulary stoplist could
reclaim that ~1.9% — but it's not worth building until then.

## Experiments to run

Each needs the relevance harness (Exp. 0) and, for honest precision, a
large/full-corpus index (see Guiding principle + Blockers).

### 0. Relevance harness (prerequisite) — now an in-app stage page (DONE)
- **Goal:** compare **keyword vs hybrid vs semantic** on a labeled query set.
- **Method:** curate queries with known-relevant docs; run each mode; report
  where semantic surfaces relevant docs keyword misses (recall) and where it
  injects irrelevant ones (precision). Seed queries already found: cross-lingual
  EAL probes where keyword returns 0 ("theory of relativity" → 爱因斯坦/Einstein
  mss, "literary translation" → Two Lines/Mantis, "postwar Japanese poetry" →
  Shiraishi/Tamura).
- **Now runnable by non-developers on stage:** `/semantic-eval`
  (`SemanticEvalController` + `SemanticSearch::Evaluator`), gated by
  `tuning_enabled?` so it 404s in prod. A UX person edits a plain-text query set
  (one per line, optional `=> expected title words`, seeded from
  `config/semantic_eval_queries.txt`) and clicks Run; each query is executed
  through the **real** SearchBuilder/SemanticQuery pipeline (via
  Blacklight::SearchService) in all three modes, and the page shows target-rank
  badges + top-5 titles side by side. No CLI, env vars, or API key (the key is
  already set on stage). Directly answers the "do evaluations properly" ask. The
  scratchpad `eval_harness.rb` remains for dev-side RRF/experiment work.
- **Decision:** does hybrid beat keyword enough to justify the feature at scale?

### 1. With / without names A/B  ← added this round
- **Hypothesis:** names help as an *entity→topic bridge* for recognizable
  entities, but are near-noise for obscure correspondents; net effect on topical
  precision is unknown.
- **Method:** embed a sample **with** vs **without** the Names access field
  (hold everything else constant), run the Exp. 0 query set against each, compare
  topical precision/recall. EAL is the high-stakes case (63% of kept docs lean on
  names); include an ARS slice as the low-stakes control.
- **Decision:** keep names as-is / drop them / keep but stop counting "names
  only" as substantive in the skip rule (would drop ~63% of EAL's kept set —
  measure the relevance cost before doing this).

### 2. Thin-doc / boilerplate filtering — RESOLVED (index everything)
Closed by the full-corpus analysis (see "Thin docs & boilerplate" above): no
filter is worth it (~1.9% droppable, doesn't hurt retrieval). All filtering
machinery removed.

### 3. Parent-context enrichment (Strategy B) — shelved, revisit for recall
- **Hypothesis:** folding parent unittitles into a thin component's embed text
  (`[Collection › Series] Correspondence 1985`) makes deep leaves findable in
  context. 100% of dropped thin docs have `parent_unittitles_tesim` available.
- **Why shelved:** the clustering test showed thin docs don't pollute results,
  so enrichment is a *recall* play, not a precision fix — lower ROI, and hybrid
  keyword already gives those docs a retrieval path. Risk: shared parent context
  raises intra-collection similarity and could blur sibling docs.
- **Decision:** only pursue if Exp. 0 shows we're missing findable content.

### 4. Full-corpus (or large multi-repo) generation for honest precision
- Per the guiding principle, run once the harness is settled and the throughput
  blocker is resolved. Batching (002) makes this practical; we index every doc.

## Blockers / dependencies

- **Gateway batching — RESOLVED (twice over).** The LiteLLM gateway's Vertex path
  collapsed a multi-input `gemini-embedding-2` request to one vector (`index:0`
  only), so it couldn't batch. Two fixes landed: (1) `text-multilingual-embedding-002`
  batches natively on the OpenAI-compat route (what we shipped on), and (2) infra
  stood up a **native Gemini pass-through** (`/gemini/v1beta/...:batchEmbedContents`,
  generativelanguage not Vertex) that genuinely batches gemini + honors `taskType`
  and `outputDimensionality`. So gemini is no longer infra-blocked — the choice is
  now purely about retrieval quality (see the A/B below).

## Embedding-model A/B — gemini-embedding-2 vs 002 (full EAL+ARS, 2026-08-21)

Ran both models over the **whole EAL+ARS corpus (45,749 docs)** with exact
in-memory cosine KNN (`scratchpad/gemini_ab.rb`), gemini via the new `/gemini`
batch pass-through at **768 dims** (MRL-truncated + renormalized, same budget as
002). Both used asymmetric task types. **Corrected-label MRR: 002=0.717 vs
gemini=0.379** (the raw pre-fix run was 0.572 vs 0.145 — inspecting the returned
titles showed several "misses" were bad labels, so both rose and **gemini rose
most**; the raw run badly under-sold it). 002 wins 5 of 7, gemini wins the
concept query, 1 tie:

- **002 is clearly better at precision / known-item / specific-constraint.** It
  puts the exact *Kirsten Flagstad Collection* at #1 (gemini ranks name-authority
  entries "Flagstad, Kirsten, 1895-1962" first, collection 7th); nails the 1936
  Metropolitan Opera broadcasts for "1930s opera radio broadcasts" (gemini returns
  generic classical/opera broadcasts, ignoring the date+institution). Archival
  discovery is mostly this — hunting a specific collection — so it's the trait
  that matters most, and it drives the MRR gap.
- **gemini is genuinely better on the broad conceptual query**, which the metric
  nearly missed: for "primary sources documenting the west coast traditional jazz
  revival" gemini's top hits are the real primary-source collections (SF
  Traditional Jazz Foundation, Dave Radlauer, Ed Sprankle, Edward Lawless), while
  002 returns secondary "Jazz Research Papers." Our original single mislabeled
  target hid this.
- **Two "failures" were bad labels, not bad models.** "recordings of famous opera
  sopranos" returns on-topic *Sopranos* recordings at #1 for both (we'd wrongly
  labeled only the Flagstad/Lehmann collections) — now a **tie at #1**.
  Cross-lingual "theory of relativity" was scored against a too-narrow `物理` hint
  when the relevant doc uses `相对论`; with the real ids it's **~even (002 #2,
  gemini #3)**, and einstein is #1 vs #2 — so **cross-lingual is a wash**, not the
  002 blowout the raw run implied.
- **gemini's one consistent weakness:** it ranks bare **name-authority entries**
  ("Flagstad, Kirsten, 1895-1962") *above* the collection record (known-item #7,
  flawed #4) at very high scores (~0.92) — the leading suspect for a 768-truncation
  artifact, hence the gemini@3072 follow-up.
- **This overturns the earlier EAL-only read** (002 ≈ gemini, MRR 0.354 vs 0.393,
  gemini even slightly ahead). At scale 002 leads on precision — exactly the
  "single-repo hides the failure; evaluate at scale" principle paying off.

**Decision (PROVISIONAL — see methodology caveat): lean 002** for production —
precision/known-item retrieval is the dominant archival need and 002 wins it, and
it's cheaper. **Caveats/next:** gemini here is **@768**, not native 3072 (the
name-authority-over-collection behavior smells like a truncation artifact →
**gemini@3072 is an open follow-up**); the durable gemini@768 cache for EAL+ARS is
built (`tmp/embeddings-gemini.sqlite`).

### Methodology correction — this A/B measured the wrong thing (fixing it)

The run above scored each model as **pure vector KNN** on a query mix **heavy with
known-item queries** — which is what *keyword* is for, not the vector leg. So it
(a) rewarded 002 for precision that keyword already provides (redundant), and (b)
under-tested the concepts/vocab/cross-lingual queries the vector leg actually
*earns its keep* on (we had essentially one strong conceptual query — and gemini
won it big). Two of 002's wins are genuine value-adds where keyword fails (the
misspelled Flagstad; the 1936 Met broadcasts), so it's not *all* redundant — but
the blended MRR overstates 002.

**The right question is the hybrid *marginal* lift:** on queries where keyword
underperforms, does keyword+002 or keyword+gemini rank the target better? Built a
revised harness (`scratchpad/gemini_ab.rb`) that reports, per category (known_item
/ vocab_mismatch / conceptual / cross_lingual), the pure legs plus **both fusions**
— RRF(keyword, model) and a faithful in-memory reRank replica across a weight
sweep — over a **13-query bucketed set** (9 of 13 in the semantic-value categories).

### Results (full EAL+ARS, corrected labels, hybrid-marginal)

Overall MRR: keyword 0.331, vec-002 **0.682**, vec-gem 0.370, hyb-002(RRF) 0.490,
hyb-gem(RRF) 0.484. reRank sweep overall (002/gemini): W0 0.52/0.52 … **W20
0.59/0.57**. Three findings that update prior beliefs:

- **In realistic hybrid the models are ~TIED** (RRF 0.49/0.48; reRank 0.59/0.57) —
  the pure-vector "002 dominates 0.68 vs 0.37" almost entirely vanishes once you
  measure the *marginal* contribution to hybrid. **gemini owns conceptual** (RRF
  0.45 vs 002's 0.21; jazz-revival hyb-gem #3 vs hyb-002 #49), **002 owns
  known-item protection.** Complementary strengths, no decisive winner.
- **Fusion protects known-items in the OPPOSITE way I expected — and RRF is not a
  clear win.** known_item: **reRank 1.00/1.00 at all weights, RRF 1.00/0.57.**
  reRank's base score is dominated by keyword's huge BM25 (Flagstad collection
  ~4047), so `weight*cosine` (~16) can't dislodge a strong keyword hit → known-item
  is protected. RRF gives keyword-rank-1 and vector-rank-1 *equal* weight, so
  gemini's name-authority components (which also match keyword) out-rank the
  collection → RRF *degrades* gemini's known-item. Overall **reRank@W10–20 ≥ RRF**,
  so this walks back the "RRF is the fix" urgency: RRF's real benefit is narrower
  (no weight to tune) and it carries a known-item risk. Earlier RRF-defect finding
  was likely a few queries + the old mislabels.
- **`reRankWeight` is under-tuned (free win on 9.10):** 5 → 10–20 lifts *both*
  models across *every* category (overall 0.52 → 0.59; conceptual 0.32 → 0.44).

**Updated decision:** keep **002** (tied on merits, cheaper, deployed, safer on
known-items; gemini's conceptual edge → gemini@3072 only if concepts become a
priority). **Don't rush the RRF migration** — bump `reRankWeight` to ~10–15 on
current reRank/9.10 now, and re-evaluate RRF when 9.11 lands rather than assuming
it's an upgrade. (Caveat: 13 queries, corpus-limited — EAL is one physics
collection; `physics-history` is broken for both models via "Physics of the
*Violin*" false friends, a query artifact not a model signal.)

## Status snapshot (2026-08-19)

- **Model:** `text-multilingual-embedding-002`, confirmed by the full EAL+ARS A/B
  above (corrected-label MRR 0.717 vs gemini 0.379 @768; 002 wins precision/
  known-item, gemini wins the concept query, cross-lingual a wash). The old
  "gemini can't batch" blocker is gone (native `/gemini` pass-through), so the
  choice is now on quality, not infra. Open follow-up: gemini@3072.
- **Gateway facts:** 20,000 tokens/request; single-query latency is highly
  variable (0.5–11s) → query-time timeout + keyword fallback in-app, and the real
  fix is a **local query-time embedding model** (interactive latency, not batch).
- **Indexed & searchable:** EAL (1,129) + ARS (44,626 docs, 12k vectors) in Solr
  with 002; hybrid/semantic verified end-to-end in the UI.
- **Relevance eval done** (`relevance_eval.rb`): hybrid preserves keyword on
  specific queries and clearly wins on concept queries (German art songs→Lieder,
  wartime broadcasts→1940s air checks, vocal pedagogy→master classes). **Go signal.**
- **Hybrid ranking: RRF is wired-but-dormant, and NO LONGER a clear win** (see
  the hybrid-marginal A/B above, 2026-08-21). An early harness suggested `bool.should`
  + reRank buried semantic-only hits and RRF fixed it (a vocab target 42→10). The
  bigger bucketed eval walked that back: **reRank@W10–20 ≥ RRF overall and protects
  known-items better** (RRF gives the vector leg equal weight and *degrades*
  known-item, 1.00→0.57 for gemini). So the actionable move is **tune `reRankWeight`
  up (5→10–15) on 9.10 now**, and treat RRF as a *re-evaluate-at-9.11* option, not a
  foregone upgrade. Native RRF still ships wired-but-dormant behind
  `rrf_combiner_enabled?`. **Native RRF needs Solr 9.11 / 10.1
  (SOLR-17319); our dev AND prod are on 9.10, where the `combiner` params are
  silently ignored and the query degrades to match-all.** (A false-positive
  "works" earlier: 9.10 accepted the params + returned a numFound, but it was the
  whole corpus at constant score — the combiner never engaged.)
  - **Decision: keep `bool.should` + reRank as the active hybrid path** (works on
    9.10, correct facets/counts/pagination), and **wire the native combiner up
    behind `SemanticSearch.rrf_combiner_enabled?` (default OFF)** so switching to
    it post-upgrade is a single flag flip. Correct 9.11 combiner syntax is
    captured in `apply_combiner_hybrid`: `json.queries` with the KNN leg as a
    **parser-wrapped object** (`{knn: {f:, topK:, vector:}}`, NOT a raw `{!knn}`
    string) + `combiner=true`, `combiner.algorithm=rrf`, `combiner.query=[…]`,
    `combiner.rrf.k`.
  - **App-side RRF was considered and rejected for now:** it would force facet
    counts + numFound to be computed over a capped candidate pool (Blacklight is
    single-request), and the wonky counts would confuse users. Not worth it when
    the native path is one Solr upgrade away.
  - (out-of-scope "no results" detection is a *separate* problem — needs a cosine
    threshold, not fusion. **Now addressed — see below.**)

- **Out-of-scope / low-confidence handling — DONE (min-similarity floor).**
  KNN always returns *something*, so a query for content the archive doesn't hold
  still yields vector hits. The fix is a single **cosine floor**:
  `SEMANTIC_SEARCH_MIN_SIMILARITY` (default 0 = off). When > 0 the vector clause
  becomes Solr's `{!vectorSimilarity minReturn=X}` (9.10 supports it), dropping
  below-cutoff hits so an out-of-scope query returns few/no vector matches and
  hybrid falls back to keyword; a truly-empty query gets Blacklight's native "no
  results". Crucially the floor only touches the **vector** leg, so relevant
  keyword matches (e.g. searching `basketball`) are untouched and still show.
  Verified live: floor 0.9 cut a hybrid result set to 311 docs.
  - Key calibration finding: **no static cutoff cleanly separates** out-of-scope
    from borderline in-scope — the cross-lingual "theory of relativity" → EAL
    Chinese physics docs sits at 0.828, only ~0.012 above the out-of-scope tail.
    So keep the floor **below ~0.83** (0.80 is a safe start) and calibrate on
    stage. Dev-tunable via the relevance panel (`semantic_min_similarity`).
  - Considered and **dropped**: a separate non-destructive "low confidence"
    advisory component. It was redundant once the floor was in (the floor removes
    the noisy hits and leaves keyword matches / native no-results), and two
    mechanisms for one problem was overkill.
- **Thin-doc policy resolved** (full-corpus analysis above): **no filter, index
  everything.** All skip-thin / boilerplate-filter machinery removed after the
  complete-corpus data showed the droppable boilerplate is ~1.9% and harmless.
- Code (all tested; the filter-removal batch **uncommitted**): configurable
  model, opt-in `task_type`, token-aware batching, query-routing fixes, and the
  query-latency timeout/fallback. TextBuilder/Indexer are back to plain
  embed-everything.

**Next:** (1) commit the pending batch (removal + embed-text cleanups); (2) finish
generating + indexing the remaining repos into the shared cache (EAL/ARS/CHS done;
vt, cubberley, then manuscripts+uarc — the big two are ~1.5 days of gateway time);
(3) the with/without-names A/B. Query-time latency is treated as an infra/gateway
concern (no local model); the app already has the query-embedding cache + timeout-
to-keyword fallback, so it benefits automatically when the gateway is sped up.

## Future features (parked) — query assistance

"Suggest search terms" keeps coming up. Paths, cheapest first:
- **Lexical typeahead + did-you-mean** — already configured in `solrconfig.xml`
  (`SuggestComponent` AnalyzingInfix + `SpellCheckComponent`); likely just needs UI
  wiring. The right tool for as-you-type (semantic typeahead is a non-starter — can't
  embed every keystroke through the gateway).
- **"More like this"** — KNN from a result's *stored* document vector to similar
  collections. Needs **nothing new** (no query embedding), reuses the vector index
  directly. Highest value / lowest cost of the semantic options.
- **Semantic related-terms / query expansion** — embed the corpus's distinct
  controlled-vocabulary terms (subjects + names) once into a *separate small* vector
  set, KNN over it for a completed query → "related: Lieder, opera…". A post-submit
  "refine" affordance, not typeahead; the new piece is the term-vector index (our
  current vectors are document-level).
- **Cross-lingual result display** — make foreign-language hits legible to an
  English searcher (surface existing English subjects/abstracts; translate CJK
  titles on the result card). Deferred deliberately.
