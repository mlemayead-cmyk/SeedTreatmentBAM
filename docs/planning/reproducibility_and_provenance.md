# Reproducibility and provenance requirements

**Derived from:** provenance requirements scattered across ADR-004,
ADR-008, ADR-009, ADR-012, ADR-013, ADR-015. Consolidated here so
implementers have one place to check what must be recorded, at every
layer, rather than reconstructing it from multiple ADR entries.

---

## 1. Why three separate version identifiers, not one

This architecture tracks **three independently-evolving version
identifiers**, because each can change without the others changing, and
conflating them would make an old artifact's interpretability ambiguous:

| Identifier | Tracks | Changes when |
|---|---|---|
| `model_version` (`STBAM_MODEL_VERSION`, existing) | Calculation-engine semantics | The scientific equations/model change (requires **SCIENTIFIC MODEL CHANGE — HUMAN APPROVAL REQUIRED**). |
| Reporting/table-builder version (new) | How grouped results are composed and formatted into a table | Table-composition/formatting logic changes, independent of the engine. |
| Figure-builder version (new) | How results are rendered into a figure | Figure-rendering logic changes, independent of the engine and the table builder. |

A future reader of an old table or figure definition must be able to tell
*which* of these changed since it was created, if any — that is the whole
point of tracking them separately (ADR-012).

## 2. What each persisted object must record

### 2.1 Named assumption sets (`folder_and_input_schema.md` §2.1)
- `set_id`, `set_name`, `description`, `source`, `date_or_version`,
  `status`, `notes` — per-category `_manifest.csv`.

### 2.2 Runs (`run_lifecycle_and_validation.md` §3)
- `run_id`, `created_at`, `description`, `content_hash`.
- The named-set IDs used per category (`seeding_set_id`,
  `receptor_set_id`, `effects_set_id`, `fate_set_id`,
  `reporting_scheme_ids`).
- `model_version`, `git_commit`.
- `validation_status`.
- The full `inputs_snapshot/` itself — the actual values used, not just
  IDs, so an old run survives later edits to a shared named set
  (ADR-008's central reproducibility guarantee).

### 2.3 Table definitions (`table_and_figure_architecture.md` §2)
- `run_id`, full configuration (grouping scheme, dimensions, filters,
  columns, formatting).
- Reporting/table-builder version (new identifier, §1) — recorded at
  definition save time and re-checked/updated at each open, so a
  definition always reflects what version last successfully rendered it.

### 2.4 Table exports (`table_and_figure_architecture.md` §3)
- Evaluation identity, `run_id`, the definition/configuration (or a
  reference to the saved `definition_id`), generation timestamp,
  `model_version`, reporting/table-builder version **at export time**
  (frozen — does not update later).

### 2.5 Figure definitions (`table_and_figure_architecture.md` §4)
- `run_id`, `detail_level`, `series`, `group_scheme_id`, `filters`,
  `time_selection`, `display_settings`.
- Figure-builder version (new identifier, §1).

### 2.6 Figure exports (`table_and_figure_architecture.md` §6)
- Same fields as table export (§2.4), plus figure-builder version at
  export time.

### 2.7 Migration (`migration_plan.md`)
- The migration script's own version/date, so a migrated evaluation's
  origin is traceable, and the verification result (§4 of the migration
  plan, the 9-point Phase 2 acceptance gate) confirming reproducibility
  against the pre-migration canonical outputs.

### 2.8 Original source-document provenance (ADR-018, new this session)

Distinct from every provenance field above, which concerns *this
project's own* artifacts (runs, definitions, exports), this class of
provenance concerns **material this project did not create**: the 6
original `.xlsm` calculation workbooks and the assessment Word
document(s) (including the one containing the actual Table 162), all
maintained in the sibling document-review project
(`C:\MonDossierMartin\Python_Local\Python_Document analysis\`).

Four tiers are distinguished, never conflated (ADR-018 full detail):
1. **Original source files** (tier 1) — the `.xlsm`/`.docx` documents
   themselves, read-only, never modified or copied wholesale into an
   evaluation.
2. **Extracted/reference data** (tier 2) — `data/reference/*.csv`'s 7
   assumption-category files, produced from tier 1 by
   `scripts/extract_reference_data.py`.
3. **Reviewer/document-analysis registers** (tier 3) — the copied
   `review_*`/`table162_*` CSVs, derived from tier 1 by the sibling
   project's independent review process, not a mechanical extraction of
   it.
4. **Calculated R-model outputs** (tier 4) — every canonical dataset this
   project computes.

What must be recorded, wherever tier-1 material is referenced (e.g. an
evaluation's `inputs/reference/` provenance metadata, or a future Table
162 redesign's source citation): the **verified full path** (relative to
the sibling project root) and **SHA-256 hash** of the specific tier-1
file — never the file itself. The current, independently-verified
inventory (all 6 workbooks + the Table 162 Word document, hash-checked
against both this project's `source_manifest.csv` and, for the Word
document, the sibling project's own pinned baseline) is recorded in
`migration_plan.md` §0.1. If the sibling project's directory is ever
reorganized, these recorded paths become stale and require
re-verification — a maintenance note, not a design flaw.

## 3. Deduplication provenance (ADR-008)

The `content_hash` recorded on every run (§2.2) is the basis for
deduplication: before creating a new run, compare its would-be hash
against existing runs. On a match, the user is told explicitly and
chooses to reuse or force a new run — this choice itself should be
logged (e.g. as a note on the resulting run's manifest, or in an
application log) so "why does this run exist despite matching an earlier
one" remains answerable later.

## 4. Peak-day provenance (ADR-009)

`key_day_results`' `day_label = "peak"` rows must be traceable to the
peak-finding mechanism's actual search (not merely asserted) — at minimum
this means the day value stored is the argmax actually found for that
specific scenario/receptor/metric/diet-fraction combination, not a
constant. No separate provenance field is required beyond the `day` value
itself and the shared engine `model_version`, since peak-finding is part
of ordinary raw-result computation, not a separately versioned process.

## 5. Cross-cutting rule

**Anything that could plausibly need to be reproduced later must carry
enough recorded state to actually be reproduced** — not just labeled with
an ID that assumes nothing referenced by that ID will ever change. This
is the same principle ADR-008 established for runs (full value snapshots,
not just set IDs), and it is deliberately generalized here to every other
persisted object in this architecture.
