# AI collection summaries: decisions

Each entry records one choice and its reason. The newest entry is last.

1. **Scope is the large EADs only.** The scope is the inventory shape classes
   `structured_large` and `very_large`: 100 or more components, nested. That is
   1,168 of 6,170 EADs in prod-10-21-2026. Smaller collections give the model too
   little to work with. Large flat lists (683 EADs) are out for now, because they
   have no series to cite.

2. **The model is `gemini-3.8-flash`.** The user chose it for now. The gateway
   lists it at `/v1/models`. The gateway does not report its context limit,
   because `/model/info` returns a redirect.

3. **The input lists every component, not a sample.** The set is finite, and a
   sample can miss subtle traits. Each component line has the title, the level,
   the dates, the extent, and a mark for a digital object. Component-level
   notes follow on their own lines.

4. **Component-level notes are in the input.** The ARS EADs put track lists and
   performer names in folder-level scope notes. These notes make ars0043 grow
   to about 390K tokens. They stay in the input, because they hold the detail
   that makes these collections notable.

5. **Numbers stand in for refs.** Each component line starts with `[n]`. The
   model cites `n`, and `Evidence#ref` maps it back to the component ref.
   ArchivesSpace refs such as `aspace_ref52_k0v` are long, and a model can
   garble them. The numbers also make the input smaller: the titles-only test
   of m0673 went from about 738K tokens with refs to 676K with numbers and notes.

6. **Every in-scope input fits under 1M tokens.** The largest is m0673, at about
   676K tokens. The median is about 7.4K. 35 EADs are over 100K tokens. A full
   run sends about 23.5M input tokens. All counts are bytes divided by 4, which
   is a rough estimate and not a real token count.

7. **The development and holdout sets.** `dev_set.txt` (12 EADs) is for prompt
   changes. `holdout_set.txt` (6 EADs) is for the end only, to show whether the
   prompt works on collections it was not tuned on. Both sets take EADs from
   the inventory `test_set.txt` and add large EADs from `ars` and `chs`, which
   that test set does not have.

8. **The exploration reads every line.** Agents read each development input in
   full and report notable traits with `[n]` citations. The draft criteria come
   from these reports.

9. **Empty notes are left out.** In m0702, every component has an empty
   scope note, so the input had an empty `scope:` line on each one.
   `Evidence` now writes a note line only when the note has text.

10. **The draft criteria are in `CRITERIA.md`.** They come from the 6 agent
    reports on the development set. The m0733 input (about 510K tokens) was
    too big for one agent to hold, so that agent split it among 8 readers.
    This is a warning about single calls on the largest inputs, and it is an
    open question in `CRITERIA.md`.

11. **No single unusual items.** The user decided that the summary does not
    call out single objects, such as the curare in m0733. One item can give a
    wrong idea of the collection, and it can cause harm for other reasons.

12. **Sensitive topics are named only when they are large.** The summary
    names a sensitive topic when it is a large part of the collection, and
    leaves it out when it is only a single folder.

13. **Try a single call on m0733 before anything else.** If the result misses
    known traits, we change to one pass per series, then a combining pass.

14. **Code supplies the counts.** `Evidence` has a FACTS section: the total
    number of components, the number of top-level components, and the
    components beneath each one. The prompt allows only these counts, years,
    and numbers from the cited lines. `Check` tests this.

15. **Restriction marks come from component access notes.** A component is
    marked `restricted` when its own `accessrestrict` says closed,
    restricted, sealed, or unavailable. The components inside it are also
    marked. The collection-level access note does not set the mark, because
    it often says "open, except ...".

16. **Private words catch names from restricted parts.** `private_words` are
    the capitalized words that appear only inside restricted components. A
    match marks a summary for review. It also catches ordinary words, such as
    "Raffle" in m1463, so a match is a review note, not a rejection. In m1463
    it catches the names of program participants in the restricted series.

17. **A component that declares its own restriction keeps its title open.**
    A summary must be able to name what is closed ("Donor files are closed").
    Only the components inside it count for `private_words`.

18. **Highlight labels are not checked for private words.** The labels come
    from our own list. In m0733, "Signature" appears only in restricted parts,
    which gave a false match.

19. **`RECHECK=1` runs the checks again without a model call.** When `Check`
    or `Evidence` changes, the saved summaries can be checked again at no
    cost.

20. **The first m0733 call worked in one pass.** It took 65 seconds for about
    510K tokens of input. It found the Howl ditto masters [18586] [18587], the
    2069 closure [22650], and the Columbia sale. So there is no per-series
    pass for now. Faults for prompt work: a generic first sentence, and
    "17,697 folders" where the FACTS count components.

21. **Citations show as numbered superscripts.** The numbers run 1, 2, 3 in
    page order, and a component cited twice keeps its number. A citation of
    `0` (the collection notes) has no link, because those notes are on the
    same page.

22. **Prompt version 2.** The review of version 1 found five faults. Each
    one now has a rule in `prompt.md`:
    - Highlights repeated the statements. A highlight must now add something
      new.
    - "Restrictions" rows held only "request 48 hours ahead". The row is now
      only for material that is closed or restricted.
    - 8 of 12 first sentences restated the title or creator. The summary
      must now start with what makes the collection different.
    - m0733 said "17,697 folders" for a count of components. The prompt now
      says what a component is.
    - "landmark" and "extensive" are now on the list of praise words.

23. **"Signature item" is now "Key works".** "Signature item" asked for single
    objects, such as one signed poster in m1463, against decision 11. "Key
    works" means the creator's main works or projects.

24. **Public figures named in a restricted component's own title are
    allowed.** ms_3800 named Tim Stoen's sealed notes. The user decided this
    is acceptable, because the closure is useful to a researcher and the
    title is the component's own. Names inside restricted components stay
    private. The prompt now matches decision 17.

25. **The number check ignores commas in the source lines.** Version 1 gave
    false problems for "27,607" (m1463) and "89,702.3" (sc0340). Decimal
    numbers are now read as one number. A known gap: any number from 1000 to
    2099 passes as a year.

26. **The generator waits on a 429 and tries again.** The gateway allows 1M
    tokens per minute for each key. In the version 2 run, m0733 used about
    half of that, and ars0043 then got a 429. The generator waits 60 seconds
    and tries again, up to 5 times. The other AI features use the same key,
    so a large run can also slow them.

27. **The output limit is 16,000 tokens.** In the version 2 run, the m0733
    JSON was cut off at 8,000. The client does not return the reason the
    model stopped, so the limit is the likely cause, not a confirmed one.

28. **Code checks for praise words and for more than 4 citations.** The
    prompt forbids both, and version 2 still used "extensive" in 5 of 12
    summaries and 9 citations in one m0733 statement. "features" is not in
    the check, because it is also a correct noun ("radio features" in
    ars0124).

29. **Prompt version 3.** The last statement is always about access, because
    the ars0124 version 2 summary had no access statement. "features" is off
    the list of praise words, because it is also a correct noun. "massive" is
    on it (m0733 version 2). Total component counts in statements stay for
    now; the user chose to leave that fault.

30. **One revision pass.** When `Check` finds problems, the generator sends
    the problems back to the model in the same conversation and asks for a
    corrected summary. It checks the result again, but does not ask a second
    time. The first draft stays in the file as `first_draft`, so the review
    can show what the revision changed. This doubles the cost of each
    summary with problems.

31. **The target length is 3 to 4 sentences.** The user wants the paragraph
    cut to 3 to 4 sentences in the end. For now, 3 to 5 is acceptable while
    we find out what the summaries should hold.

32. **The citations after one entry share one superscript, with ", " between
    them.** The user asked for a separator between the links.

33. **The citations in one superscript are in ascending order.** The numbers
    are given in page order, so an entry that cites components first cited
    earlier showed "7, 5, 1". The links now sort by number. Each component
    keeps the same number.

34. **Prompt version 3 results.** All 12 summaries end with access, and 11
    of 12 have 4 statements. The revision pass ran for 3 summaries (m1125,
    ars0043, ars0124) and fixed all of their problems.

35. **Ordinals are not numbers.** The check read "20" in "20th-century"
    (ars0124) as a number, and the revision then removed a correct phrase.
    The number pattern now needs a word boundary after the digits.

36. **More praise words.** "pioneering" (sc0340), "exhaustive", and
    "distinguished" (m0733) passed version 3. They are now in the check. A
    `RECHECK=1` run marks them, but it does not run the revision pass.

37. **No code check for a highlight that repeats a statement.** Two signals
    were tried on the version 3 results: the share of a highlight's words in
    the closest statement, and the share of its citations. Neither separates
    the repeats. The sc0340 Air Force row repeats statement 2 in other words
    and scores 0.29 and 0.50. The m0224 "Held elsewhere" row says something
    new and scores 1.00 on citations. Whether two sentences say the same
    thing is a judgment, so code does not check it.

38. **Version 4 is the version 3 prompt with the new checks.** The prompt
    does not change. The user chose to leave single objects in highlights
    for now. m0733 and sc0340 were generated again, so the revision pass
    could fix their praise words.

39. **The holdout test is blind.** Agents read each holdout input in full and
    report its notable traits without seeing the summaries, with the same
    instructions as for the development set. The summaries are then compared
    with those reports.

40. **Code catches an access statement that no note supports.** ars0002 has
    no Access note, but the prompt asks for a last statement about access,
    and the model wrote "open for research". When the collection notes have
    no Access line, `Check` now marks "open for research" and "available for
    research". After the revision, the summary says that access is not stated
    in the collection notes.

41. **Holdout results.** The 6 holdout summaries are as good as the
    development summaries, so the prompt is not tuned only to the
    development set. Compared with the blind agent reports:
    - All 6 found the main traits. sc1256 and m1854 put traits that are
      missing from the collection notes in "Not in the collection notes"
      (aviation security, the 1982 governor run).
    - pc_010 named only public figures (Jim and Marceline Jones, Charles
      Garry, Larry Schacht, Richard Dwyer). It named no members, although
      the photo captions name many members and children.
    - Missed traits: the 1991-2010 speaking record (m1854), the
      centennial broadcasts and the 1936 Walküre (ars0002), and the size
      of the audio and video record (m1090).
    - Errors: the invented access statement (ars0002, now caught by code),
      and a wrong "Held elsewhere" in pc_010. The related photographs were
      held by the California Historical Society, but the Acquisition note
      says they moved to Stanford in 2025. Code cannot catch this.

42. **The full run is one EAD at a time.** The user chose this. The list is
    `full_set.txt`: the 1,168 EADs in the shape classes `structured_large`
    and `very_large`. From the 18 test runs, it takes about 11 hours. The
    18 finished summaries are skipped. Progress goes to
    `tmp/collection_summaries/full_run.log`.

43. **One bad file does not stop a batch.** Any error for a file, including
    an EAD that does not parse, goes into that file's JSON as `error`, and
    the run goes on. The next run tries that file again, because the script
    does not skip files with an error.
