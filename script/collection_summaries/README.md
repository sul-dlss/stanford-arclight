# AI collection summaries

This directory makes the AI version of the "About this collection" block. It
writes one JSON file per EAD. `AboutThisCollectionComponent` reads the file
from `Settings.collection_summaries_dir`, which has the same layout as
`Settings.data_dir`. Nothing calls the model when a page renders.

See `CRITERIA.md` for what a summary must do, and `DECISIONS.md` for why.

## Files

| File | What it is |
| --- | --- |
| `prompt.md` | The system prompt. `{{LABELS}}` becomes `CollectionSummary::Check::LABELS`. |
| `generate.rb` | Builds the input, calls the model, checks the result, and writes the JSON. |
| `dev_set.txt` | 12 EADs to look at after each prompt change. |
| `holdout_set.txt` | 6 EADs to look at only at the end. |
| `CRITERIA.md` | The criteria from a full reading of the development set. |
| `DECISIONS.md` | Each choice and its reason. |

The code that both sides use is in `app/services/collection_summary/`. It
does not need Rails, so Traject can load it later:

- `Evidence`: the model input, with every component numbered.
- `Check`: the checks on a result.
- `Organization`: the counts for the code-made block.

## Commands

Generate the development set:

```sh
bundle exec ruby script/collection_summaries/generate.rb \
  data/prod-10-21-2026/data tmp/collection_summaries/out $(cat script/collection_summaries/dev_set.txt)
```

The script skips a file when its EAD, prompt, and model are unchanged. Set
`FORCE=1` to call the model again. Set `RECHECK=1` to run the checks again
on the saved summaries, without a model call. Set `COLLECTION_SUMMARY_MODEL`
to try another model.

The gateway key comes from `SEMANTIC_SEARCH_EMBEDDING_API_KEY`, the same as
the other AI features.

## Output

Each JSON file has:

- `summary`: the model's statements and highlights, with `cites`.
- `refs`: the ref and title of each cited component, for the links.
- `problems`: the review notes from `Check`.
- `model`, `prompt_sha256`, and `ead_sha256`: which run made the file, and
  whether it is out of date.
- `error` and `raw`, in place of `summary`, when the call or the parse failed.
