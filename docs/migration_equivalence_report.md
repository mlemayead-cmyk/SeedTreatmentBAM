# Phase 2 migration-equivalence report

**Purpose:** evidence that the automated Phase 2 migration produces a complete
evaluation, scientifically equivalent to the pre-migration project, per the
9-point gate in `docs/planning/migration_plan.md` §4. Written after running
the migration and the full test suite; every number below is either directly
observed from a run recorded in this document or a hard-coded, independently
derived expected value (never inferred from the migration's own output).

## 1. Source/current-model state compared

- Repository: `C:\MonDossierMartin\R\seed_treatment_bam_model`, branch `main`.
- Pre-Phase-2 commit: `30a246c` ("Phase 1: evaluation folder/input schema, GUI
  editing, validation").
- Current-model reference data: `data/reference/*.csv` (13 files) +
  `scenario_definitions.csv`, loaded via `load_baseline()` /
  `R/inputs/10_reference_data.R`, unchanged by this phase.
- Tier-1 source workbooks (6 `.xlsm`) and the Table 162 source document,
  under the sibling project `C:\MonDossierMartin\Python_Local\Python_Document
  analysis\`, independently re-verified by SHA-256 during this phase's
  implementation (§6 below) — read-only, unmodified.

## 2. Migrated evaluation identity

- Path: `evaluations/thiamethoxam_bam_2026/` (created by
  `scripts/migrate_to_evaluation.R`, calling `migrate_to_evaluation()` in
  `R/migration/10_scenario_migration.R`).
- Structure: `inputs/assumptions/{agronomy/{seeding_sets,planting_method_sets},
  receptors/receptor_sets, effects/effects_sets, fate/fate_sets,
  reporting/reporting_sets}`, `inputs/uses/use_patterns.csv`,
  `inputs/reference/` (6 tier-3 provenance files + `tier1_source_provenance.csv`
  + preserved `fir_regressions.csv`).
- Every category populated with exactly one named set, `set_id = "default"`,
  copied wholesale from `data/reference/` (reusing `create_evaluation()`
  unchanged, per `migration_plan.md` §3 step 1), plus `reporting_sets/
  crop_family.csv` (new, extracted from `STBAM_WORKBOOK_TO_CROP_FAMILY`).

## 3. Adapter used

`build_baseline_from_evaluation()` / `build_parameter_set_from_evaluation()`
(`R/migration/20_engine_adapter.R`). Boundary:

```
evaluation files (named sets + use_patterns.csv)
      -> read_named_set()/read_use_patterns() (Phase 1, unchanged)
      -> build_baseline_from_evaluation() (new, Phase 2)
           - resolves exactly one requested set_id per category
             (default "default"); aborts if missing or unresolved
           - reconstructs the workbook x crop x rate_level scenario table
             from use_patterns.csv (lossless, since the per-method
             explosion is driven by the same seeding-set booleans this
             function cross-checks against)
           - aborts if use_patterns.csv references an unknown crop or
             planting method, or if its planting methods disagree with
             the selected seeding set's own availability booleans
      -> parameter_set() (existing, unchanged) -- empty override layer
      -> build_scenario_inputs() / build_scenario_summary() (existing,
         UNCHANGED -- no signature or behaviour change)
```

No legacy fallback: the adapter never reads `data/reference/` directly and
never falls back to it; every value comes from the evaluation's own files or
the call aborts.

## 4. Nine-point migration-equivalence gate

| # | Criterion | Result | Evidence |
|---|---|---|---|
| 1 | Exact `scenario_inputs` match | PASS | `test-15-phase2-migration.R`: "the adapter's scenario_inputs is exactly equivalent..." — row-for-row, column-for-column `expect_equal()` against a freshly-computed `load_baseline()` + `parameter_set()` + `build_scenario_inputs()` baseline (not a stored file). 1,456 rows both sides. |
| 2 | Exact `scenario_summary` match | PASS | Same test file, "...scenario_summary is exactly equivalent...". 104,832 rows both sides. |
| 3 | Hard-coded row-count assertions | PASS | "ground truth: real reference data has the documented row counts" computes expected counts independently from raw CSVs (157 scenario rows, 85 crop rows, 42 distinct crops, 11 small_cereals crops, 364 exploded use_pattern rows) — not derived from migration output. |
| 4 | Tier-3 provenance-file completeness (6 files, SHA-256) | PASS | "...copies all 6 tier-3 provenance files, byte-identical..." — `tools::md5sum()` match, migrated vs. pre-migration `data/reference/`. |
| 5 | Lossless named-set copy | PASS | "...performs a lossless named-set copy..." — `stbam_content_hash()` identity per category against the original CSV. |
| 6 | Crop-grouping data carried forward | PASS | `reporting_sets/crop_family.csv` extracted unchanged from `STBAM_WORKBOOK_TO_CROP_FAMILY`'s 6 mappings; validates against `stbam_schema_reporting_sets()` (crop-only, I7). |
| 7 | No truncation regression | PASS | "...does not truncate crops..." — 11 crops for `small_cereals`, 42 crops overall, both via the adapter's own `build_scenario_inputs()`, no `head()`/row cap anywhere in the migration or adapter path. |
| 8 | Existing test suite passes unmodified | PASS | See §7 below. |
| 9 | Re-runnability | PASS | "...two independent runs produce byte-identical inputs/..." (fresh names, same day) and "...re-running migration with the SAME evaluation name fails cleanly..." (via `create_evaluation()`'s existing-folder guard) — matches `migration_plan.md` §4 point 9's stated policy for the pre-Phase-3 period. |

## 5. Canonical equivalence detail

- `scenario_inputs`: migrated 1,456 rows vs. current-baseline 1,456 rows;
  0 mismatched rows; column sets identical (`expect_setequal`).
- `scenario_summary`: migrated 104,832 rows vs. current-baseline 104,832 rows;
  0 mismatched rows; column sets identical.
- Comparison method: exact `data.frame` equality (`expect_equal()`, R's
  default numeric tolerance, consistent with the existing test suite's own
  convention — no rounding introduced for this comparison), ordered by a
  stable key (`scenario_id`; `scenario_id`+`receptor_id`+`metric_id`+
  `diet_fraction`), with the informational `parameter_set` label column
  excluded (it legitimately differs — "migrated" vs. "current" — and carries
  no scientific content).

## 6. Crop/use completeness

- 42 distinct crops modelled (matches `scenario_definitions.csv`); all
  present in the migrated `use_patterns.csv` and reachable through the
  adapter's `scenario_inputs`.
- 11 distinct crops for `small_cereals` specifically (the positive control
  for the legacy R7 24-row truncation defect) — confirmed present, not
  capped, at every stage (migration output, adapter output,
  `build_scenario_inputs()`).
- 364 `use_patterns.csv` rows (157 scenario-definition rows exploded across
  each crop's available planting methods) — independently computed and
  matched, not inferred from the migration's own output.

## 7. Provenance

- Tier-3 provenance files copied: `source_manifest.csv`,
  `review_core_assumptions.csv`, `review_effects_metrics.csv`,
  `table162_considerations.csv`, `table162_decision_matrix.csv`,
  `copied_register_manifest.csv` — all 6 present, byte-identical
  (`tools::md5sum()`) to the pre-migration `data/reference/` copies.
- `fir_regressions.csv` also preserved (copied unchanged into
  `inputs/reference/`) as supporting, currently-unused reference data — not
  one of the 6 gated tier-3 files, documented separately.
- Tier-1 source-document provenance: `inputs/reference/
  tier1_source_provenance.csv` records path + SHA-256 for the 6 original
  `.xlsm` workbooks and the Table 162 source `.docx`, referenced only, never
  copied. All 7 hashes were independently re-verified this session
  (`Get-FileHash` against the sibling project's live files) and matched
  `data/reference/source_manifest.csv` / `migration_plan.md` §0.1 exactly —
  see the git-tracked command output in this session's record.
- No file under `C:\MonDossierMartin\Python_Local\Python_Document analysis\`
  was modified, renamed, or copied — confirmed by this phase performing only
  read (hash) operations against that project.

## 8. Tests

- Starting baseline (confirmed before any Phase 2 edit): 801/801 passing.
- New Phase 2 assertions: `tests/testthat/test-15-phase2-migration.R` (121
  assertions, including the regression tests added in response to the
  independent review's findings below).
- Final full-suite result: **921/921 passing, 0 failures, 0 warnings, 0
  skips, 0 errors** — confirmed by two independent runs: this session's own
  (`testthat::test_dir()`, all 15 files clean) and, separately, the
  independent reviewer's own from-scratch re-run (§9), which reported the
  identical 921/921 total without relying on this document's own numbers.

## 9. Independent review (ADR-019, mandatory for the adapter and
migration-equivalence categories)

**Method:** two passes, each by a separate agent process with no prior
authorship of the implementation, following this project's existing
`docs/independent_engine_audit.md` methodology (adversarial, encouraged to
run its own independent recomputations rather than trust the report).

**First pass** read the migration plan, both new Phase 2 files, the Phase 1
machinery they build on, the three unchanged engine files they call, the
new test file, and the equivalence report; independently re-derived the
hard-coded counts and the `scenario_inputs`/`scenario_summary` bit-exact
equivalence from scratch (not from this report); and wrote its own
adversarial probes beyond the existing test file.

Findings: 2 `CONFIRMED_ERROR`, 3 `ROBUSTNESS_ISSUE`/`DOCUMENTATION_GAP`
(one of which was itself the "this report's placeholders aren't filled in
yet" observation now resolved by this section), 7 `PASS`.

1. **CONFIRMED_ERROR — adapter's planting-method guard checked only a
   per-crop aggregate**, which could silently accept a `use_patterns.csv`
   where one specific use (e.g. a low-rate use) declared a *narrower*
   planting-method set than the crop's own availability, and separately
   could silently collapse two distinct declared uses (different `use_id`,
   e.g. two different registered products at the same crop/rate) into one
   scenario row with no error. **Fixed**: `build_baseline_from_evaluation()`
   (`R/migration/20_engine_adapter.R`) now validates planting-method
   agreement per `use_id` (not per crop), and separately rejects any
   `(workbook, crop, rate_level, rate_value, rate_unit)` scenario identity
   claimed by more than one distinct `use_id`. Does not change today's
   actual migration output (the real dataset has neither condition), but
   closes a latent defect in infrastructure explicitly slated for direct
   reuse by Phase 3.
2. **CONFIRMED_ERROR — per-scenario `source`/`status`/`seed_use_number`
   from `scenario_definitions.csv` were silently dropped** during
   migration, with no field anywhere in the evaluation to recover them.
   **Fixed**: `stbam_transform_use_patterns()`
   (`R/migration/10_scenario_migration.R`) now maps `source` to
   `use_patterns.csv`'s existing `product_identifier` column (a direct,
   non-misleading fit — `folder_and_input_schema.md` §3 already defines
   that column as generic registration/context metadata) and folds
   `status`/`seed_use_number` into `notes` as `"seed_use_number=N;
   status=Y"`.
3. **ROBUSTNESS_ISSUE — a mistyped `set_ids` category key was silently
   ignored** (fell back to `"default"` with no warning). **Fixed**:
   `build_baseline_from_evaluation()` now validates every `set_ids` key
   against the known category names and aborts on any unrecognized one.
4. **DOCUMENTATION_GAP — this report's §8a/§9 were unfilled placeholders**
   at the time of the first review pass. Resolved by this section.
5. **DOCUMENTATION_GAP (minor) — gate point 7's test name overstated its
   connection to the legacy R7 Shiny-layer defect** (a different layer,
   out of Phase 2 scope). **Fixed**: test name reworded to describe it as
   a positive-control regression guard for the new raw layer, distinct
   from R7.
6. **ROBUSTNESS_ISSUE (minor, accepted, not fixed) — "byte-identical"
   re-runnability is only demonstrated same-day**, since the crop-family
   reporting set's manifest embeds `Sys.Date()`. A cross-midnight
   re-run would legitimately differ in that one date-stamp field while
   remaining scientifically equivalent. Both review passes assessed this
   as low-severity and acceptable to leave as a documented limitation
   rather than a required fix.

Also independently reconfirmed as **PASS** (not defects, but explicitly
checked and worth recording): no legacy-fallback path exists anywhere in
the adapter; type/unit conversion is sound (every numeric column forced to
`col_double()`); the CSV round-trip is lossless at full double precision;
all documented adapter failure modes are real, reachable, and correctly
triggered; multi-named-set-per-category selection is deliberate and
disclosed, not a silent ambiguity; the engine itself (`R/calculations/`,
`R/summaries/`) was not modified; and the bit-exact
`scenario_inputs`/`scenario_summary` equivalence and the five hard-coded
counts were independently reproduced from scratch, not taken on trust.

**Second pass** (re-review of the three fixes specifically, not
self-certified) confirmed all three genuinely closed, traced each fix
against the exact failure case originally demonstrated, checked for
new-issue introduction (none found), and independently re-ran the full
test suite from scratch (921/921, matching this document's own count
without relying on it). Confirmed finding 6 remains acceptable to leave as
a documented limitation.

**Unresolved issues after both passes: none.** Independent review is
complete; both mandatory ADR-019 categories (the adapter; migration
equivalence) have a closed, non-self-certified sign-off.

## 10. Scientific behaviour

No file under `R/calculations/` was modified. `STBAM_MODEL_VERSION` is
unchanged (`"1.2.0"`). The adapter and migration script are new,
Phase-2-scoped files only; `build_scenario_inputs()` and
`build_scenario_summary()` were called, not edited.

## 11. Deferred scope confirmation

Not implemented, as required: run lifecycle / `Run_001` creation / dedup,
raw or grouped results, `key_day_results`, table/figure definitions, Table
162 or Sensitivity redesign, legacy app retirement.
