# AI collection summaries: draft criteria

Status: draft for review. The criteria come from a full reading of the 12
development EADs (`dev_set.txt`). Each `[n]` below is a component number in
that EAD's evidence file.

## What the summary is for

The summary tells a researcher what to expect from this collection, and what
makes it different from other collections. It is not a second scope note. In
4 of the 12 EADs, the main themes are only in the folder titles:

- sc1179 has a one-sentence scope note. Its contents show the Katherine
  Dunham residency [159]-[189] and the East Palo Alto oral histories [200]-[242].
- The sc0340 biography stops at 1981. The contents show Feigenbaum's
  companies [2795]-[2993] and his work as USAF Chief Scientist [4328]-[4633].
- The m0733 index has no entry for Eliot, Sartre, Kissinger, Warhol, or Havel.
  All of them are in the folder titles.
- The m0702 index lists only the 4 founders. The contents name about 30
  artists.

## The parts of the summary

### Statements

There are 3 to 5 sentences for now. The target is 3 to 4 sentences in the
paragraph (the highlight rows do not count). Longer text is acceptable while
we find out what the summaries should hold. Together they cover content, coverage, format and
extent, and access. Each sentence cites at least one `[n]`, which becomes a
superscript link. A sentence that comes only from the collection-level notes
cites `[0]`, which links to the collection page. (Today `Evidence#ref(0)`
returns nil, so this needs a small change.)

### Highlights (the `dl` rows)

There are 2 to 4 rows. The model chooses the rows that suit this collection,
from the labels below. It can also propose a new label. A new label shows in
the review, and we decide if it goes into the list.

| Label | Seen in | Example |
| --- | --- | --- |
| Key works | 8 of 12 | Howl, m0733 [18586]; DENDRAL, sc0340 [470]-[481]. Main works or projects, not single objects. |
| Notable names | 12 of 12 | the Fung, Snook, and Goldman tape traders, ars0124 [389], [441], [192] |
| Bulk of the material | all (code computes it) | Series 10 recordings, 252 of about 636 boxes, ars0043 [403] |
| Formats | 7 of 12 | DAT, Minidisc, and Hi-8, m2508 [546], [1252] |
| Not in the collection notes | 4 of 12 | the sc1179 example above |
| Held elsewhere | 3 of 12 | early Kerouac letters at Columbia, m0733 [1]; ARS.0054, ars0043 [403] |
| Restrictions | 5 of 12 | financial records closed until 2069, m0733 [22114] |

"Seen in" counts the reports that found that kind of trait. It is my count
from the reports, not a computed number.

## Rules for the model

1. **Prefer the specific to the general.** "Letters from Hardy, Hilbert, and
   Weyl" is good. "Contains correspondence" is not.
2. **Use the folder titles to find what the collection notes leave out.** Do
   not repeat the scope note.
3. **Do not report data errors to the reader.** Do not let them mislead the
   summary either. These traps are in most of the 12 EADs:
   - Accessions shown as series, in 6 of 12. Do not call an accession a
     "series" with its own subject. Do not count it as a theme.
   - Folder dates outside the collection dates, in 10 of 12. Use the
     collection dates.
   - A series count in the notes that differs from the contents: m1463,
     m0733, m1125.
   - Restricted series that repeat open folder titles one for one: m1463
     [9988]-[12432]. Do not count these twice.
   - Opaque titles, such as about 2,180 m1463 workshop folders with only a
     number and a date [3]-[2186]. Do not treat these as a theme.
   - The "digital object" mark, which is not reliable. In m0733, only the
     Howl typescript has the mark, but the notes say that much of the media
     streams online. Do not say that something is digitized unless a
     collection note says so.
4. **Access must be exact.** Give the level of each restriction (collection,
   series, or folder), the end date, and what a researcher must do. In most of
   the 12 EADs, some restrictions or handling needs are only at folder level:
   - Mold, with PPE required: sc0337 [949].
   - Consent of the person: ms_3800 [421].
   - A digital use copy before viewing: m1463 [8968].
   When two sources disagree, give both dates. ms_3800 says 2078 at [796] and
   2053 at [797]-[798].
5. **Privacy.** Do not name a private person from:
   - Components inside a restricted component. The title of a component that
     declares its own restriction can be named, so a researcher knows what is
     closed.
   - Medical, financial, legal, or student records.
   - Lists of members or participants.
   Do not give Social Security numbers, addresses, or medical details. In
   m1463, restricted folder titles hold the full names of HIV program
   participants [11887]-[11907].
6. **No numbers that code did not supply.** The model can use counts from a
   FACTS section that code computes, such as the series counts from
   `Organization`. It must not count folders itself. (`Evidence` has no FACTS
   section yet.)

## Checks that code makes on each result

- Each `[n]` is in range, and `Evidence#ref` resolves it.
- Each number in the text is in the FACTS section, or is a year.
- No word in the result matches a personal name taken from the title of a
  restricted component. This needs a list of restricted components, and
  `Evidence` does not build one yet.
- The number of statements and rows is within the limits.

## Decided

1. **Very large inputs.** We test a single call on m0733 first. If it misses
   known traits, such as the Howl typescript [18586] or the 2069 closure
   [22114], we summarize each series first, then combine.
2. **No single unusual items.** The summary does not call out a single object,
   such as the curare in m0733 [33443] or the bulletproof vest in ms_3800
   [49]. One item can give a wrong idea of the collection, and it can cause
   harm for other reasons.
3. **Sensitive topics.** The summary names a sensitive topic, such as the
   Jonestown deaths, when it is a large part of the collection. It leaves the
   topic out when it is only a single folder.
