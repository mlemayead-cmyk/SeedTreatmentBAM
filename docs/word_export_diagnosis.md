# Why the Word export hangs: diagnosis before any redesign

**Status:** Diagnosis only. No reporting code has been changed as a result of
this document. Written for a scientific reviewer, not an R developer.

## Your question, answered directly

**Is this a performance problem or a mistaken reporting architecture?**
Mostly the second, but it's worth being precise about which part.

`risk_and_duration` is not a mistake in the sense of "wrong code" — it
correctly reproduces every scenario the model calculates. The mistake is
that it was wired *unfiltered* into a Word export path with no row-count
awareness, when a table that size was never going to be a usable printed
document. The published assessment's own Tables 27-29 (which this table is
explicitly modelled on) never show one row per crop — they group similar
crops together and report a range. That grouping step is the piece that is
missing here, not a rendering optimisation.

## 1. What is `risk_and_duration`?

It is one of four "official tables" the model can produce
(`R/reporting/31_tables.R`, function `table_risk_and_duration()`). It reports,
for every combination the model evaluates, the risk quotient and the number
of days the dose stays at or above the applicable effects metric. Its
column layout intentionally mirrors the published assessment's duration
tables (Word Tables 27-29 for birds; the equivalent mammal tables).

## 2. Why does it contain 8,928 rows?

Because the table groups by every one of these axes and collapses nothing
else:

```
crop × rate_level × application_rate × receptor (6 sizes/taxa) ×
diet_fraction (6 values: 100/50/25/10/5/1%) × effects_metric ×
duration_class (acute/chronic) × metric_role
```

For the Small Cereals workbook alone — about 19 crops, 3 rate levels, and
the screening plus refined-additional metrics per taxon — that product is
exactly the observed 8,928 rows. This is the full cross-product of every
scientifically distinct scenario the engine can calculate for that
workbook. It is not a bug in the sense of duplicated or spurious rows: every
row is a real, distinct combination.

The published Word tables never show this cross-product directly. They
report a **range across a crop family** (e.g. "Small Cereals" spanning
several individual crops) in a single row, the same way this model's own
`table_seed_availability()` and `table_exposure_by_diet()` already report
ranges across the seeding-rate/seed-mass bounds using `fmt_range()`. What
those two tables do *not* do — and what `risk_and_duration` also does not
do — is collapse across **crop**. That is the one grouping axis the source
assessment uses that this model has not yet implemented.

## 3. Is it a canonical machine-readable result dataset?

No, and this distinction matters. The four **canonical datasets** are
`scenario_inputs`, `daily_timecourse`, `scenario_summary`, and
`table162_support` (specification §11) — these are allowed to be large,
because nothing downstream is required to print them. `risk_and_duration` is
one layer up: it is a **derived "official table"**, built by
`build_official_table()` from `scenario_summary`, and the same function
feeds three different consumers: the Shiny "Official tables" tab, the CSV
export, and the Word export. That single-source-of-truth design is correct
and should be kept. The problem is that "official table" was treated as
synonymous with "Word-appropriate," and for this table it is not.

## 4/5. Was this an intermediate analytical table, or intentionally designed as a report table?

Both, in a way that reveals the actual gap. The column layout was clearly
*designed* to mirror a specific published table (the docstring names
Tables 27-29 explicitly). But the row structure was left at full scenario
granularity, which only makes sense for analysis (filtering in Shiny,
querying in CSV), not for a fixed report. Nobody made an explicit decision
between "this is a report table" and "this is a queryable dataset" — the
code does both jobs with one un-grouped table.

## 6. Which function sends it to Word?

Three call sites in `R/reporting/32_word_export.R`, all of which call
`build_official_table()` and then hand the full result straight to
`flextable::flextable()` with no row limit or grouping:

- `export_table_docx()` — a single table, used by the Shiny "This table
  (Word)" download button.
- `export_tables_docx()` — all four official tables in one document, used
  by "All tables (Word)" and by `scripts/build_canonical_outputs.R`.
- `export_quantitative_appendix()` — all four tables again, plus provenance
  and override sections, used by "Quantitative appendix (Word)".

Measured render cost (isolated, fixed-layout `flextable`, this machine):

| Rows | Time |
|---:|---:|
| 100 | 4.2 s |
| 400 | 20.5 s |
| 800 | 59.0 s |

The scaling is worse than linear. Extrapolated, the full 8,928-row table is
on the order of an hour by itself, and `export_quantitative_appendix()`
rebuilds all four tables again in one document. I confirmed this is not the
`autofit` layout setting — a fixed-width layout was only 10 s faster at 800
rows. The cost is in `flextable`'s per-cell XML construction, which no
formatting change fixes. **I stopped this benchmark early rather than let
it run for an hour; I have not attempted a full render of the untouched
table.**

## 7. What output did the previous implementation intend the user to receive?

Based on the docstring and the table's title ("Risk quotients and duration
above the effects metric"), the intent was a **regulatory-style summary
table** a reviewer could read directly — the Word equivalent of the
published Tables 27-29. What was actually wired up instead produces a
document that is not readable as a table at all; at 8,928 rows it would be
several hundred printed pages of a single table with no crop grouping. That
was never going to be the intended deliverable — it is what happens when a
"generate every scenario" default is not paired with a "then group it back
down for reporting" step before Word.

## 8. Recommended reporting design (not implemented; for your review)

Keep the layers already partially in place and complete the missing one:

```
canonical detailed results   (scenario_summary, 100k+ rows — CSV/XLSX/Shiny only)
        |
human-oriented summary        (NEW: grouped by crop family or by explicit
                                scenario selection, ranges reported the way
                                fmt_range() already does across bounds)
        |
regulatory Word tables        (small, fixed number of rows, one crop family
                                or one user-selected scenario per row)
```

Concretely, three options — not mutually exclusive:

1. **Crop-family grouping**, extending `fmt_range()` to also range across
   crop within a family (the same axis the published Word tables collapse).
   This most directly reproduces the original tables' scale and intent.
2. **Selection-scoped export**, where the Word download always operates on
   whatever the user has currently filtered to in Shiny (workbook, crops,
   rate levels — this already flows through `results()$summary`, so
   selecting one or two crops before downloading already produces a small
   table today). This needs a loud row-count guard so an unfiltered
   selection fails fast with a clear message instead of hanging.
3. **A fixed catalogue of summary views** purpose-built for Word (e.g. "peak
   RQ and duration by crop, at the highest rate and full diet"), separate
   from the exhaustive `risk_and_duration` dataset, which stays CSV/XLSX-only.

None of this has been implemented. I have not changed
`R/reporting/31_tables.R`, `32_word_export.R`, or `STBAM_TABLES`. This is
explicitly deferred per your instruction until after the independent
engine audit is complete, and until you've told me which of the above (or
another approach) you want.

## What this means for the acceptance-test document right now

`docs/manual_acceptance_test.md` and `docs/manual_shiny_smoke_test.md` do
**not** include downloading the unfiltered `risk_and_duration` table or the
full quantitative appendix as a test step. CSV/XLSX export of the same data,
and Word export of the smaller `seed_availability` (186 rows) and
`exposure_by_diet` (1,116 rows — still large, treat with caution) tables,
remain reasonable to test.
