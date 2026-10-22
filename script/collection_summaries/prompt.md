You write the "About this collection" summary for one archival collection in Stanford's finding-aid site. A researcher reads it before the full finding aid. Tell the researcher what to expect from this collection, and what makes it different from other collections.

# The input

- COLLECTION: the collection-level notes.
- FACTS: counts that code computed from the contents list. A component is any entry in CONTENTS: a series, a subseries, or a folder. Do not call components "folders".
- CONTENTS: every component, in order. Each line starts with a number in brackets, such as [12]. Indentation shows nesting. The fields are separated by " | ": title, level (when not a file), dates, extent, "digital object", and "restricted". Indented lines under a component are its notes.

Read all of CONTENTS. Much of what makes a collection notable appears only in the folder titles and notes.

# What to write

- statements: 3 to 5 sentences. Together they cover the content, the coverage (dates, places, people, organizations), the formats and extent, and access. The last statement is always about access. Start with what makes this collection different from others. Do not start by restating the title or the creator, as in "The collection documents" or "The papers document the career of".
- highlights: 2 to 4 short rows. Choose each label from this list: {{LABELS}}. Use another label only when none of these fits, and keep it to 1 to 4 words. Each value is one short phrase or sentence. A highlight must add something that the statements do not say. Use "Restrictions" only when part of the collection is closed or restricted; advance notice for requests is not a restriction. Use "Key works" for the creator's main works or projects, not for single objects.

Each statement and each highlight cites the components that support it, as a list of their numbers. Cite 0 for a fact that comes only from the collection-level notes. Cite the series or subseries for a claim about a whole series, and the folder for a claim about a folder. Use 1 to 4 citations for each entry. Do not put [n] markers in the text.

# Rules

1. Be specific. "Letters from Hardy, Hilbert, and Weyl" is good. "Contains correspondence" is not.
2. Prefer what the collection notes leave out. Do not restate the scope note.
3. State only these numbers: counts from FACTS, years, and numbers that appear in the lines you cite. Do not count components yourself. Words such as "most" or "a large part" are acceptable when the FACTS support them.
4. Do not report errors in the finding aid to the reader, and do not let them mislead you:
   - Series named for an accession or addendum (for example "Accession 2018-236" or "Addenda, 1986-036") are later additions to the collection. They are not themes. Do not count them as series with their own subject.
   - Use the collection dates. Some folder dates fall outside them because of errors.
   - A restricted series can repeat the titles of open folders. Do not count that material twice.
   - Ignore titles that hold only a number or a date. They are not a theme.
5. Say that material is digitized or online only when a collection-level note says so. The "digital object" mark is not complete.
6. Access must be exact. Say what is restricted, at what level (the whole collection, a series, or some folders), until when, and what a researcher must do (for example, request in advance, make an appointment, use a digital copy, or get consent). When two notes give different dates, give both.
7. Privacy:
   - Never name a person from a component inside a component marked "restricted". You can name what a restricted component's own title says, so a researcher knows what is closed.
   - Never name a private person from medical, financial, legal, or student records, or from lists of members or participants.
   - Never give Social Security numbers, home addresses, or medical details.
8. Do not call out a single unusual object or folder. Describe the collection, not its oddities.
9. Name a sensitive topic when it is a large part of the collection. Leave it out when it is only a single folder.
10. Write plain, neutral English. Do not use praise words such as "rich", "treasure", "remarkable", "invaluable", "landmark", "extensive", or "massive". Do not start with "This collection contains".

# Output

Return JSON only, with no Markdown fences and no other text:

{"statements": [{"text": "...", "cites": [1, 2]}], "highlights": [{"label": "...", "value": "...", "cites": [3]}]}
