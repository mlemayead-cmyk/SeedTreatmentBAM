# Evaluation folder and input schema specification

**Derived from:** ADR-001 through ADR-006 in
`docs/planning/assessment_workspace_architecture.md`. See that document
for rationale and rejected alternatives; this document specifies the
concrete, implementable shape.

**Verification note for implementers:** exact current column names in
`data/reference/*.csv` must be re-checked against the live files at
implementation time (via `R/inputs/10_reference_data.R` and the
`docs/current_implementation_inventory.md` reference-data inventory
table) before finalizing any schema below — this specification proposes
the *structure*, not a guaranteed-verbatim column list.

---

## 1. Folder layout

```text
evaluations/
  Evaluation_Name/
    inputs/
      uses/
        use_patterns.csv

      assumptions/
        agronomy/
          seeding_sets/
            <set_name>.csv
          planting_method_sets/
            <set_name>.csv
        receptors/
          receptor_sets/
            <set_name>.csv
        effects/
          effects_sets/
            <set_name>.csv
        fate/
          fate_sets/
            <set_name>.csv
        reporting/
          reporting_sets/
            <scheme_name>.csv

      reference/
        <read-only provenance material: source manifests, Table 162
         registers, SHA-256 audit records, and similar — see §1.1 for
         which of these are copied in full vs. referenced by path+hash>

    outputs/
      runs/
        Run_<NNN>/
          inputs_snapshot/     <- frozen copy of every input file used
          raw_results/
            scenario_inputs.csv
            scenario_summary.csv
            key_day_results.csv
          grouped_results/
            grouped_results.csv
            grouped_result_bounds.csv
          run_manifest.csv      <- see run_lifecycle_and_validation.md

      tables/
        definitions/
          <definition_id>.csv (or a small structured format — see
           table_and_figure_architecture.md)
        exports/
          <export files: CSV/XLSX/Word snapshots>

      figures/
        definitions/
          <definition_id>.csv
        exports/
          <export files: PNG/SVG snapshots>
```

Every evaluation is created by copying `data/reference/` wholesale into
`inputs/assumptions/*/*_sets/` as one starting named set per category
(ADR-003, ADR-015), plus an initial `use_patterns.csv` derived from
`scenario_definitions.csv` (see `migration_plan.md` for the one-time
conversion of the *existing* project; new evaluations created after
migration start from whatever `data/reference/` contains at creation
time).

### 1.1 What `inputs/reference/` holds: two different provenance patterns (ADR-018)

`inputs/reference/` mixes two categories of material, handled differently
— never conflated:

- **Reviewer/document-analysis registers and manifests** (tier 3/2 in
  ADR-018's four-tier model) — `source_manifest.csv`,
  `review_core_assumptions.csv`, `review_effects_metrics.csv`,
  `table162_considerations.csv`, `table162_decision_matrix.csv`,
  `copied_register_manifest.csv`. These are small, plain-text CSVs,
  already this project's existing convention — **copied wholesale**,
  byte-identical, into every evaluation, exactly like the assumption-
  category sets above.
- **Original assessment source documents** (tier 1) — the 6 `.xlsm`
  calculation workbooks and the assessment Word document(s) containing
  the actual Table 162, all in the sibling document-review project
  (`C:\MonDossierMartin\Python_Local\Python_Document analysis\`), never
  under this project's control and never modified by it. These are
  **never copied** into an evaluation's `inputs/reference/` — they are
  referenced by **verified path + SHA-256 hash only** (see
  `migration_plan.md` §0.1/§2.1 for the current, hash-verified inventory
  of all 6 workbooks plus the Table 162 document). This avoids
  duplicating multi-megabyte binary files into every evaluation folder
  for content that provides no additional reproducibility guarantee
  beyond its recorded hash, since these originals are never edited by
  this project. If a future tool needs to read tier-1 content directly,
  it resolves the recorded path against the sibling project at read
  time — it does not assume a local copy exists inside the evaluation.

## 2. Named assumption sets (ADR-004, ADR-021)

Each of `seeding_sets/`, `planting_method_sets/`, `receptor_sets/`,
`effects_sets/`, `fate_sets/`, `reporting_sets/` is a folder of
independently named, complete CSV files. No file in one of these folders
is ever a diff or override against another; each is a complete,
standalone dataset for its category.

`planting_method_sets` was added as a sixth category by ADR-021,
ratifying a Phase 1 implementation-time finding: planting method is
scientifically load-bearing (surface-seed fraction by method), so its
data is its own independently-selectable category rather than being
folded into `seeding_sets` or treated as metadata. See ADR-021 for the
full rationale and the alternatives considered.

### 2.1 Set metadata

Every set file carries a metadata header, stored as a small commented
block at the top of the CSV (parsed by the loader, not by `read.csv`
directly) **or** a companion `_manifest.csv` per category folder listing
one row per set — **recommendation: companion manifest**, because it
keeps every set file itself a plain, directly-openable data table (better
for the Excel round-trip requirement, ADR-006) without embedding
non-tabular metadata inside a CSV meant for bulk data review.

`assumptions/<category>/<category>_sets/_manifest.csv`:

| Column | Type | Description |
|---|---|---|
| `set_id` | string | Stable identifier, filename-safe, unique within the category. |
| `set_name` | string | Human-readable name (e.g. "2026 seeding assumptions"). |
| `description` | string | Free text. |
| `source` | string | Provenance reference (e.g. source workbook, literature citation). |
| `date_or_version` | string | Date or version label, where relevant — never interpreted as a sequential V1/V2/V3 ordering (ADR-004 point 3). |
| `status` | string | e.g. `active`, `draft`, `superseded` — informational, not enforced. |
| `notes` | string | Free text. |

`set_id` is the value stored wherever run provenance records which set
was used (`seeding_set_id`, `receptor_set_id`, `effects_set_id`,
`fate_set_id`, `reporting_scheme_id` — ADR-004 point 6, ADR-010).

### 2.2 Category schemas

**`seeding_sets/<set_id>.csv`** — one row per crop, generalizing today's
`crop_seeding_parameters.csv`. Minimum columns: `crop`, thousand-kernel-
weight (TKW) value/bounds, seeding-rate bounds, per-crop planting-method
*availability* booleans (which methods are agronomically possible for
this crop), and any other agronomy parameter currently in that reference
file (verify exact list against `data/reference/crop_seeding_parameters.csv`
at implementation time). Surface-seed fraction is **not** here — see
`planting_method_sets` immediately below (ADR-021).

**`planting_method_sets/<set_id>.csv`** — one row per planting method,
generalizing today's `data/reference/planting_method_parameters.csv`
(ADR-021). Columns: `planting_method_label`, `planting_method` (key;
restricted to the project's known method list), `surface_seed_fraction`
(0-1), `source` (optional — see the note below), `status`. This is
method-level data (a property of the method, independent of any one
crop), complementary to `seeding_sets`' per-crop availability booleans,
not a duplicate of them.

*Note on `source` nullability (ADR-021):* a named set's `source` column,
here and generally, may legitimately be `NA` for an individual row — the
live `planting_method_parameters.csv`'s `broadcast` row has no source
citation because `surface_seed_fraction = 1.0` is definitional, not
citation-derived. Schemas must accept this as valid reference data, not
reject it as incomplete.

**`receptor_sets/<set_id>.csv`** — one row per receptor, generalizing
today's receptor parameter file(s). Body weight, food intake, MSA/
search-area basis, and taxon/species identity travel **together in one
set**, per ADR-004's explicit correction that a receptor set is not just
a body-weight table — a set must be a complete, internally consistent
receptor definition, not a partial parameter list.

**`effects_sets/<set_id>.csv`** — one row per effects-metric record
(toxicity endpoint values, metric definitions), generalizing today's
effects/toxicity reference file(s).

**`fate_sets/<set_id>.csv`** — one row per fate/dissipation parameter
record (DT50 values for the two independent decay processes — surface-
seed disappearance and residue dissipation, kept distinct per the
existing scientific model), generalizing today's fate reference file(s).

**`reporting_sets/<scheme_name>.csv`** — a crop-grouping scheme, per
ADR-010:

| Column | Type | Description |
|---|---|---|
| `crop` | string | Must match a crop value used in `use_patterns.csv`. |
| `group_label` | string | The reporting group this crop belongs to under this scheme. May be the crop's own name (singleton group) or blank/absent (ungrouped) — partial coverage is explicitly permitted (ADR-010). |
| `display_order` | integer, optional | Ordering hint for GUI/report display. |

A scheme's `set_id`/filename doubles as its `reporting_scheme_id` in
grouped-result provenance (ties into ADR-010's open follow-up on grouped-
result keying).

## 3. Use patterns (ADR-005)

`inputs/uses/use_patterns.csv` — single normalized table, one row per
atomic use condition:

| Column | Type | Description |
|---|---|---|
| `use_id` | string | Stable identifier. Shared across multiple rows when one crop/rate use is registered under several planting methods (ADR-005). |
| `crop` | string | Must match a `seeding_sets` entry for whichever seeding set is selected at run time. |
| `rate_value` | numeric | Treatment rate. |
| `rate_unit` | string | Unit for `rate_value`. |
| `rate_level` | string | e.g. `high`/`mid`/`low`, matching today's `scenario_definitions.csv` convention. |
| `planting_method` | string | One row per method; multiple methods for the same `use_id` are separate rows. |
| `workbook` | string | Source-workbook grouping, preserved from today's schema for traceability. |
| `product_identifier` | string, optional | Registration/context metadata. |
| `region` | string, optional | Registration/context metadata. |
| `target_pest` | string, optional | Registration/context metadata. |
| `notes` | string, optional | Free text. |

Quantitative agronomic assumptions (TKW, seeding-rate bounds) are **not**
stored here — they live in the selected `seeding_sets/` set, joined by
`crop` at calculation time; surface-seed fraction lives in the selected
`planting_method_sets/` set (ADR-021), joined by `planting_method`. Both
joins happen at calculation time exactly as today's
`build_scenario_inputs()` joins `scenario_definitions.csv` against
`crop_seeding_parameters.csv` and `planting_method_parameters.csv`.

## 4. Validation schema (ADR-006)

Each editable table above needs a validation schema used both by the
Shiny structured-edit form and by the Excel/CSV import path, so both
entry paths enforce identical rules:

| Rule type | Applies to | Example |
|---|---|---|
| Column presence/type | every table | `rate_value` must be numeric. |
| Permitted values | categorical columns | `rate_level` in `{high, mid, low}`; `planting_method` in the project's known method list. |
| Referential integrity | cross-table joins | every `use_patterns.csv` `crop` value must exist in the currently-selected `seeding_sets` set; every `use_patterns.csv` `planting_method` value must exist in the currently-selected `planting_method_sets` set (ADR-021). |
| Uniqueness | key columns | `use_id` + `planting_method` unique within `use_patterns.csv`; `set_id` unique within a category's manifest. |
| Range sanity | numeric columns | e.g. reject a body weight of zero or a negative rate — exact bounds sourced from existing scientific validation in `R/calculations/00_validation.R`, not reinvented here. |

A failed validation, on either the Shiny form path or the Excel/CSV
import path, never replaces the previously saved, valid file (ADR-006).

## 5. Explicit non-goals for this schema

- `data/reference/` itself is **not** restructured into named sets by
  this specification (Q002, open) — it remains the single-set-per-
  category central template feeding evaluation creation.
- No file in this schema is ever a partial override/diff against another
  file. Every set, every `use_patterns.csv`, every `reporting_sets`
  scheme is a complete, standalone table.
