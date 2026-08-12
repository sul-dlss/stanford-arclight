# Stanford Arclight

## Starting the development server
```shell
bundle
yarn
./bin/dev
```

## Starting Solr for development
The following command will start a local Solr instance at `localhost:8983`, with a pre-loaded core named `blacklight-core`.

```shell
docker compose up
```
### Managing data
Data for the solr and redis services are persisted using docker named volumes. You can see what volumes are currently present with:

```shell
docker volume ls
````

If you want to remove a volume (e.g. to start with a fresh database or solr core), you can run:

```shell
docker volume rm stanford-arclight_solr-data   # to remove the solr data
```

## Working with data in development

### Fixture data (also used by the test suite)

You can load fixture data locally: 
```shell
rake seed
```

This command will loop through all the directories under `spec/fixtures/ead`, for example `spec/fixtures/ead/ars` and `spec/fixtures/ead/uarc`, and index all the .xml files present. The names of these subdirectories must correspond with a top-level key in the `repositories.yml` file. For example, `uarc` is a top-level key in `repositories.yml`, as well as the title of a subdirectory under `spec/fixtures/ead`. A mis-match will cause indexing issues.

### Loading more data

The easiest way to load data other than the fixtures is to use the `DownloadEadJob` and/or the `IndexEadJob`. See below for instructions about how to use Sidekiq to run these jobs in development. Under most circumstances it's fine to use the default `:async` adapter to run these jobs without Sidekiq in development. 

By default the `DownloadEadJob` will store EAD files in the directory set in `./config/settings.yml` as `Settings.data_dir`. You can choose a different location by setting the `DATA_DIR` environment variable, passing `data_dir:` argument to the job method, or by setting a different location for `data_dir` in `./config/settings.local.yml`

The `DownloadEadJob` will attempt to use the ASpace API to download EADs. You will need to configure the API URL with username and password in order to connect to ASpace. To do this you will need to add the following to `config/settings.local.yml` with the correct URL, port, and account information:

```
aspace:
  default:
    user: USERNAME
    password: PASSWORD
    url: "http://ARCHIVESPACE_URL:PORT"
  chs:
    user: USERNAME
    password: PASSWORD
    url: "http://ARCHIVESPACE_URL:PORT"
```

_**Important Note:**_ ArcLight core includes a number of rake tasks for loading data into Solr, such `rake arclight:index`, `rake arclight:index_dir`, `rake arclight:index_url`, and `rake arclight:index_url_batch`. Using these rake tasks will use the default Traject indexing rules from ArcLight core only and WILL NOT apply any of the local Traject indexing rules. It's important to use either the local app's `IndexEadJob` or the Traject command (`REPOSITORY_ID={REPO_ID} bundle exec traject -u {SOLR_URL} -i xml -c ./lib/traject/sul_config.rb {FILE_PATH}`) to index data that will work correctly with stanford-arclight.

#### Using Sidekiq for development
By default in development Rails will run the `DownloadEadJob` and `IndexEadJob` jobs with the `:async` adapter. If you prefer to run these jobs in the background you can use Sidekiq.

##### Steps to enable Sidekiq
1. In `config/environments/development.rb`, add the line: `config.active_job.queue_adapter = :sidekiq`
2. Make sure Redis and Solr are running. The included Docker enviroment will start both Redis and Solr for you.
3. Start Sidekiq:
```shell
bundle exec sidekiq
```
4. Run a job. For example, to download and index all the `ars` (Archive of Recorded Sound) collections updated after March 1, 2024, run:
```shell
bin/rails runner 'DownloadEadJob.enqueue_one_by(aspace_repository_code: "ars", updated_after: "2024-03-01")'
```
5. You can monitor job progress in the Sidekiq admin UI, which is available at: `http://localhost:3000/sidekiq`

### Deleting a collection
There is a rake task for deleting a single collection and all of its components from the Solr index.

1. Find the Solr document id for the collection (which is a form of the EAD ID)
2. Run the rake task:
```shell
# Some shells (such as zsh) require that the brackets are escaped.
bundle exec rake stanford_arclight:delete_by_id\['ars0167'\]
```
3. Enter YES at the prompt to delete the collection and its components.

## Semantic search

Semantic (vector) search adds embedding-based KNN retrieval on top of the
existing Solr keyword search. It is built on the existing Solr infrastructure
(no separate vector database): an additive `embedding_vector` dense-vector field
(768 dims, cosine, HNSW) holds `gemini-embedding-2` embeddings (truncated to 768
dims via Matryoshka truncation), generated through the Stanford LiteLLM AI
gateway.

The whole feature is gated by two independent feature flags, **both off by
default** in all shared/production config. Nothing about indexing, query
results, or Solr behavior changes until a flag is deliberately enabled.

### Feature flags

Both are read from `Settings.semantic_search` (see `config/settings.yml`), which
is backed by environment variables so a flag can be turned on for one
environment (e.g. stage) by setting the ENV var on that environment's hosts,
without editing shared config.

| ENV var / setting | Controls |
| --- | --- |
| `ENABLE_SEMANTIC_INDEXING` / `Settings.semantic_search.indexing_enabled` | Whether the Traject indexer generates and writes `embedding_vector`. When off, no embedding API calls are made and indexed documents are identical to current behavior. |
| `ENABLE_SEMANTIC_QUERY` / `Settings.semantic_search.query_enabled` | Whether searches blend semantic (KNN) retrieval with keyword results. When off, search behaves exactly as it does today. |

Accepted truthy values: `true`, `1`, `yes`, `on`.

### Embedding gateway configuration

Config is read from the environment by `SemanticSearch::EmbeddingService`
(identical values are used at index time and query time — they must match). It
calls the Stanford **LiteLLM AI gateway**, which exposes an OpenAI-compatible
`/embeddings` endpoint and routes `gemini-embedding-2` to Gemini on Vertex AI.
The bearer token is sent via the `Authorization` header.

| ENV var | Purpose | Default |
| --- | --- | --- |
| `SEMANTIC_SEARCH_EMBEDDING_API_KEY` | LiteLLM gateway bearer token | _required when indexing/query is on_ |
| `SEMANTIC_SEARCH_EMBEDDING_API_BASE` | Gateway base URL | `https://dlss-aigateway-prod.stanford.edu` |
| `SEMANTIC_SEARCH_EMBED_BATCH_SIZE` | Inputs per `/embeddings` request | `100` |
| `SEMANTIC_SEARCH_EMBED_MAX_RETRIES` | Retries on a 429 rate limit (with backoff / `Retry-After`). Query path stays fail-fast at `0`; the generation rake task defaults it to `8`. | `0` |
| `SEMANTIC_SEARCH_TOP_K` | KNN neighbors fetched per query | `100` |
| `SEMANTIC_SEARCH_RERANK_DOCS` | Top docs reranked by vector similarity | `100` |
| `SEMANTIC_SEARCH_RERANK_WEIGHT` | Weight of the vector score in the rerank | `5` |

Notes: the gateway doesn't accept the OpenAI `dimensions` param, so the service
truncates to 768 dims client-side (Matryoshka: first 768 values, renormalized).
Inputs are clamped to stay under the model's input-token limit. A batch that comes
back with fewer embeddings than inputs (e.g. a rate-limited partial `200`) is
rejected and retried whole, never silently under-stored.

Retrieval `task_type` (`RETRIEVAL_DOCUMENT` for documents, `RETRIEVAL_QUERY` for
queries) is derived from the configured model — see
`SemanticSearch::TASK_TYPE_MODELS` — because `gemini-embedding-2` rejects it while
the Vertex text-embedding models accept it. It matters: the same text embedded
with and without a task type differs by ~0.93 cosine, so this must not vary
between index time and query time. (The retired `SEMANTIC_SEARCH_EMBED_TASK_TYPE`
env var is no longer read; unset it.)

### Embedding cache (generate once, reuse everywhere)

Generating embeddings costs money and time; re-indexing shouldn't re-pay for it.
A persistent, content-addressed cache (`SemanticSearch::EmbeddingCache`) keyed on
`SHA256(embed text)` fixes that: `Indexer` checks the cache before calling the
gateway, so a doc whose text is unchanged reuses its vector for free, and a
changed doc (new hash) re-embeds itself.

| ENV var | Purpose |
| --- | --- |
| `SEMANTIC_SEARCH_EMBEDDING_CACHE` | Path to the SQLite cache file. Unset = no cache (always call the gateway). |
| `SEMANTIC_SEARCH_EMBEDDING_CACHE_WRITE` | Truthy only during **generation** (write mode). |

Workflow:

1. **Generate once, locally** with the batched, resumable rake task (no Solr):

   ```shell
   SEMANTIC_SEARCH_EMBEDDING_CACHE=/local/path.sqlite \
   SEMANTIC_SEARCH_EMBEDDING_API_KEY=... \
     bundle exec rake stanford_arclight:generate_embeddings[/path/to/data]
   ```

   It runs the Traject extraction, batch-embeds each collection/component doc via
   the gateway (far fewer API round-trips than per-doc), de-duplicates identical
   texts, and stores vectors in the SQLite file. Resumable — a re-run skips
   already-cached texts. (~1.19M docs ≈ ~$5 / ~4–5 GB file.) It's single-process
   (one writer); for speed you can run it per-repo in parallel against the same
   file (WAL handles concurrent writers). The per-doc write-through during normal
   indexing also populates the cache, but the rake task is far faster for a full
   backfill.

   The task runs **one Traject pass per repository**, deriving each
   `REPOSITORY_ID` from the EAD's parent directory name (the same
   directory-name-matches-`repositories.yml` convention described above). This is
   required for correctness, not just tidiness: `TextBuilder` strips a document's
   own repository name out of the embedded `Names:` list, so generating a
   repository's EAD under a different slug leaves that name in the embed text and
   changes the SHA256 that keys the cache. The vector would then never be found
   again when the document is indexed under its real repository — visible as
   collection-level docs missing vectors while their components all hit. A data
   directory with no matching slug in `repositories.yml` is reported and skipped,
   since there is no correct slug to embed it under.
2. **Ship the file** to each app host (local disk, e.g. `/app`, is preferred over
   the NFS data mount for read performance).
3. **Serve read-only** — set only `SEMANTIC_SEARCH_EMBEDDING_CACHE=/path.sqlite`
   (no `_WRITE`). It's opened `immutable=1`, so SQLite skips locking — safe for a
   static file, NFS-tolerant, and fine for many concurrent readers across hosts.
   Every doc is a cache hit; indexing makes **no** API calls. Never write to the
   file while it's on an NFS mount.

The backend is a seam: a Postgres adapter can implement the same
`fetch`/`store`/`writable?` contract later without touching the indexer.

### How the hybrid query works

When `ENABLE_SEMANTIC_QUERY` is on and there is a keyword query, `SearchBuilder`
rewrites the request into a **single** Solr query (see `#add_semantic_query`):
the lexical edismax query and a `{!knn f=embedding_vector …}` vector query become
`bool.should` clauses (so semantically-relevant documents the keywords missed
can still surface), and the top `SEMANTIC_SEARCH_RERANK_DOCS` are reranked by
vector similarity via Solr's `{!rerank}` parser. Because it is one Solr request,
facets, counts, and pagination are computed over the blended result set. The
nested edismax subquery inherits `qf`/`pf`/`mm`/`defType` from the `search`
request handler defaults, so keyword ranking is unchanged. `RERANK_WEIGHT` is the
main relevance-tuning knob for the stage review. Embedding failures fall back to
pure keyword search.

When the flag is on, two extra options are folded into the existing **search
field** dropdown, and **hybrid** becomes the default search:

- **Keyword + semantic** (`search_field=hybrid`) — the blended query described
  above. The default.
- **Semantic** (`search_field=semantic`) — the KNN vector query replaces the
  lexical query (pure semantic).
- The ordinary lexical fields (Keyword, Name, Place, Subject, Title, …) are
  unchanged and stay purely lexical — vector similarity is whole-document, so it
  is deliberately not applied to field-scoped searches.

`SearchBehavior::SemanticQuery` keys off the selected search field (or the
configured default), so the mode is carried across facets, sort, and pagination
for free via Blacklight's normal `search_field` handling. (The landing-page
search bar is unchanged and searches in the default hybrid mode.)

When `SEMANTIC_SEARCH_EMBEDDING_API_KEY` is unset the service fails closed with a
clear error; at index time this is caught so the document still indexes without a
vector. Because both flags default off, none of this runs until the feature is
enabled. Do **not** hardcode the token.

### Relevance tuning (dev / stage only)

For the relevance-evaluation workflow, the three tuning values can be overridden
per request, so an eval harness (or a human) can sweep parameters without a
redeploy. This is gated by a **third flag** that must never be set in production:

| ENV var / setting | Effect |
| --- | --- |
| `SEMANTIC_SEARCH_TUNING` / `Settings.semantic_search.tuning_enabled` | When on, the URL params below override the defaults, and a tuning panel is shown above search results. Default off. |

> Gated by its own ENV flag rather than `Rails.env`, because **stage runs as the
> production Rails environment** here — an env check could not tell stage from
> real prod. Set `SEMANTIC_SEARCH_TUNING=true` only on dev/stage hosts.

When the flag is on, these URL params override the defaults (clamped, and
persisted across facet/pagination navigation via `search_state_fields`):

| Param | Overrides | Useful range | Clamp |
| --- | --- | --- | --- |
| `semantic_top_k` | KNN neighbors (recall pool) | 20–500 | 1000 |
| `semantic_rerank_docs` | top docs reranked | 20–200 | 1000 |
| `semantic_rerank_weight` | vector weight in the rerank | 0–50 | 100 |

Keep `topK >= reRankDocs` (docs past topK get no vector score in the rerank) and
`reRankDocs >= rows` (the page size). `reRankWeight=0` is lexical-only (a useful
A/B control); cosine scores are 0–1 while edismax scores run into the tens, so it
takes weights in the tens before semantics meaningfully compete — it's the main
lever to sweep first.

Example: `/catalog?q=ships&search_field=hybrid&semantic_rerank_weight=15`. A
`SemanticTuningComponent` panel on the results page exposes the same three knobs
for interactive spot-checks.

### Running a subset backfill on stage

Enable indexing on the stage hosts (`ENABLE_SEMANTIC_INDEXING=true`,
`SEMANTIC_SEARCH_EMBEDDING_API_KEY=...`) and reload the Solr core so it picks
up the additive `embedding_vector` field (schema-only change — no full reindex
required to add the field). Then re-index a **subset** of collections before any
full stage backfill, using the same local indexing paths that apply the SUL
Traject rules (not the `rake arclight:*` tasks):

```shell
# Re-index one collection (its EAD + all components) by file path:
REPOSITORY_ID=ars bundle exec traject -u $SOLR_URL -i xml \
  -c ./lib/traject/sul_config.rb /path/to/ars/ars0001.xml

# Or via the app job, one file at a time:
bin/rails runner 'IndexEadJob.perform_now(file_path: "/path/to/ars/ars0001.xml", arclight_repository_code: "ars")'

# Or a whole repository's already-downloaded EADs:
bin/rails runner 'DownloadEadJob.enqueue_one_by(aspace_repository_code: "ars", updated_after: "2024-03-01")'
```

Validate cost, latency, and relevance on the subset, then proceed to a full
stage backfill and only afterward enable `ENABLE_SEMANTIC_QUERY` on stage for
relevance review. Do not perform the production steps as part of this work.

## PDF Generation
### Requirements
Finding aid PDFs can be automatically generated from EAD XML. The following are needed:
- [Saxon](https://www.saxonica.com/welcome/welcome.xml)
- [Apache FOP](https://xmlgraphics.apache.org/fop/)
- Java

### Configuration
Paths to those tools must be configured in `./config/settings.yml`.
- `Settings.pdf_generation.fop_path` to specify the path to the fop executable
- `Settings.pdf_generation.saxon_path` to specify the path to the saxon jar

The path to the referenced fonts must be set in `config/pdf_generation/fop-config.xml`. They are not bundled in this repository. They can be found in [ArchivesSpace](https://github.com/archivesspace/archivesspace).

PDFs can be automatically generated as part of `DownloadEadJob` by setting `Settings.pdf_generation.create_on_ead_download`.

### Running a PDF Generation Job
The `GeneratePdfJob` can be used to generate PDFs not created automatically via `DownloadEadJob`.

For example, the following generates all missing PDFs but does not regenerate existing PDFs:
```shell
bin/rails runner 'GeneratePdfJob.enqueue_all'
```
