# Migration plan — existing project to first evaluation

**Derived from:** ADR-015, revised this session per ADR-016, ADR-017, and
ADR-018 (`assessment_workspace_architecture.md`). See those entries for
rationale and rejected alternatives (manual GUI recreation, parallel
operation, copying original source documents into every evaluation).

**Revision note (this session):** the original version of this plan's
input inventory (§2) was incomplete — it omitted the six read-only
provenance files and the only existing crop-grouping data in the
codebase. It also did not identify the dependency between the migration-
equivalence check (§4) and an evaluation-inputs → engine-parameter-set
adapter that no earlier ticket built. Both are corrected below. The
verification gate (§4) is also expanded from a 2-point check to 9 points,
adopting `docs/planning/implementation_readiness_review.md` §5 as the
authoritative Phase 2 acceptance gate.

---

## 0. Source-material tiers (ADR-018) — read before using this plan

Four tiers of material are in play. This plan touches all four
differently, and none may be conflated:

| Tier | What | Where | Touched by migration how |
|---|---|---|---|
| 1. **Original assessment source files** | 6 `.xlsm` calculation workbooks; the assessment Word document(s), including the one containing the actual Table 162 | Sibling project, `C:\MonDossierMartin\Python_Local\Python_Document analysis\` | **Never copied, never modified.** Referenced by verified path + SHA-256 in provenance metadata only (§2.1). |
| 2. **Extracted/reference data** | `data/reference/*.csv`'s 7 assumption-category files | This project, `data/reference/` | Copied into named sets, one set per category (§2.2, §3 step 2) — the bulk of this plan's work. |
| 3. **Reviewer/document-analysis registers** | `review_core_assumptions.csv`, `review_effects_metrics.csv`, `table162_considerations.csv`, `table162_decision_matrix.csv` | This project, `data/reference/`, copied from the sibling project's `03_registers/` | Copied unchanged into `inputs/reference/` (§2.3, §3 step 2b) — preserved as provenance/support material, not redesigned (ADR-016). |
| 4. **Calculated R-model outputs** | `scenario_inputs`, `scenario_summary`, etc. | Computed at run time | Not migrated — recomputed by the unchanged engine from the migrated `inputs/` and compared against the pre-migration canonical outputs (§4). |

**This project's own `data/reference/*.csv` files (tier 2) and copied
registers (tier 3) are not automatically treated as a complete,
authoritative restatement of tier 1.** Where migration records
provenance, it distinguishes which tier a given piece of data came from,
per ADR-018.

**No file under
`C:\MonDossierMartin\Python_Local\Python_Document analysis\` is modified
by this plan, this migration script, or any other part of this redesign,
unless the user explicitly authorizes it separately.** All tier-1
references below are read-only lookups (path + independently-verified
SHA-256), not copy operations.

### 0.1 Verified tier-1 inventory (this session)

`data/reference/source_manifest.csv` records 6 original calculation
workbooks by bare filename + SHA-256 (no stored folder path). All 6 were
located in the sibling project this session and their SHA-256 hashes
independently recomputed — **all match the manifest exactly**:

| `workbook_key` | Role (`source_manifest.csv`) | Verified full path (relative to the sibling project root) |
|---|---|---|
| `small_cereals` | `PRIMARY_AUDITED_REFERENCE` | `Documents\Calculation Workbooks\THE 1 small cereals Bird and Mammal Seed Treatment RA Workbook 2026 for QAQC 08MAY2026.xlsm` |
| `small_cereals_msa` | `SCENARIO_SOURCE` | `Documents\THE 1b small cereals Bird and Mammal Seed Treatment RA Workbook 2026 for QAQC 08MAY2026 MSA doses.xlsm` |
| `canola` | `SCENARIO_SOURCE` | `Documents\THE 2 canola rapeseed mustard Bird and Mammal Seed Treatment RA Workbook 2026 for QAQC 08MAY2026 MSA doses.xlsm` |
| `legumes_deep` | `SCENARIO_SOURCE` | `Documents\Calculation Workbooks\THE 3 deep legumes Bird and Mammal Seed Treatment RA Workbook 2026 for QAQC 08MAY2026 MSA doses.xlsm` |
| `legumes_shallow` | `SCENARIO_SOURCE` | `Documents\Calculation Workbooks\THE 3 shallow legumes Bird and Mammal Seed Treatment RA Workbook 2026 for QAQC 08MAY2026 MSA doses.xlsm` |
| `cucurbits` | `SCENARIO_SOURCE` | `Documents\Calculation Workbooks\THE 5 cucurbits Bird and Mammal Seed Treatment RA Workbook 2026 for QAQC 08MAY2026 MSA doses.xlsm` |

**Correction to the two paths supplied when this plan was revised**: the
path given for "small cereals" is actually `small_cereals_msa`
(`SCENARIO_SOURCE`), not the `PRIMARY_AUDITED_REFERENCE` small-cereals
workbook — the latter is the un-suffixed "THE 1" file, under
`Calculation Workbooks\`, not `Documents\` directly. The `canola` path
supplied matches exactly. All 6 workbooks above (not 2) exist and are
this project's complete tier-1 workbook inventory, per
`source_manifest.csv`.

The Table 162 source document was also verified:
`THE BAM ST RA - interim draft TABLES and FIGS - LIVE.mdlAug26.docx`
(sibling project root) — SHA-256
`ea76adfa0044db808867d880325a1932b891a1d72566f4a8c7b8752a0a36fb6a`,
matching the sibling project's own `PROJECT_STATE.md`-pinned baseline for
this file (ID `TABLES`) exactly. Note: the sibling project's `Documents\`
folder also contains a similarly-named but distinct file,
`THE BAM ST RA - interim draft - LIVE.mdl-Aug26.docx` (no "TABLES and
FIGS" in the title) — not the same document; not used by this plan.

These paths and hashes are recorded as **provenance metadata only** (§2.1)
— none of these files are copied into `evaluations/`.

---

## 1. Objective

Produce `evaluations/<Name>/` (target name to be finalized at
implementation time, e.g. reflecting the active ingredient —
`thiamethoxam` or similar) that is scientifically equivalent, expressed in
the new schema (`folder_and_input_schema.md`), to the current
`data/reference/*.csv` + `scenario_definitions.csv`, and that reproduces
identical `scenario_inputs`/`scenario_summary` output when run through the
(unchanged) calculation engine.

**Explicitly out of scope for this migration's completion gate** (ADR-016,
ADR-017): Table 162 support parity and Sensitivity parity. Both are
preserved as source data/legacy functionality (§2.3, §6) but neither is
required to have a redesigned counterpart in the migrated evaluation for
Phase 2 to be considered done.

## 2. Inputs to the migration script

### 2.1 Tier-1 provenance metadata (referenced, not copied)

The verified paths and SHA-256 hashes in §0.1 are written into the
migrated evaluation's provenance record (e.g. an `inputs/reference/`
manifest entry or extension of the existing `source_manifest.csv`
pattern) as **path + hash references**, per ADR-018 — the `.xlsm`/`.docx`
files themselves are never copied into `evaluations/`.

### 2.2 Tier-2 assumption-category files → named sets (ADR-004)

`data/reference/*.csv`'s 7 assumption-category files, one file per
category, becoming one named set per category:

| Source file | Destination |
|---|---|
| `crop_seeding_parameters.csv` | `assumptions/agronomy/seeding_sets/<set_id>.csv` |
| `receptor_parameters.csv` | `assumptions/receptors/receptor_sets/<set_id>.csv` |
| `fir_regressions.csv` | Carried with the receptor set's provenance, per `folder_and_input_schema.md` §2.2's note that a receptor set is a complete definition, not just body weight — exact placement (own file vs. embedded) is an implementation-time schema choice, not fixed here. |
| `effects_metrics.csv` | `assumptions/effects/effects_sets/<set_id>.csv` |
| `dissipation_parameters.csv` | `assumptions/fate/fate_sets/<set_id>.csv` |
| `planting_method_parameters.csv` | Joined into the seeding set (surface-seed fraction by planting method is an agronomy parameter) or its own file within `agronomy/` — implementation-time choice; must be unambiguous which named set "owns" it since `use_patterns.csv` (§2.4) references planting method by label, not by a set ID of its own. |
| `scenario_definitions.csv` | Transformed into `uses/use_patterns.csv` (§2.4) — the one step with genuine transformation logic. |

### 2.3 Tier-3 reviewer/document-analysis registers → `inputs/reference/` (unchanged)

**Newly added to this plan's scope (was missing in the original version):**
the following files are copied **unchanged, byte-identical** into the
migrated evaluation's `inputs/reference/` (`folder_and_input_schema.md`
§1 — "read-only provenance material... not meant for routine editing"):

- `source_manifest.csv`
- `review_core_assumptions.csv`
- `review_effects_metrics.csv`
- `table162_considerations.csv`
- `table162_decision_matrix.csv`
- `copied_register_manifest.csv`

Each copy is verified by SHA-256 match against the pre-migration
`data/reference/` original (§4 point 4). These are preserved for Table
162's future redesign checkpoint (ADR-016) and for general provenance
continuity — none are joined into any calculation this migration performs.

### 2.4 `STBAM_WORKBOOK_TO_CROP_FAMILY` → initial `reporting_sets/` scheme (ADR-010, ADR-016)

**Newly added to this plan's scope:** `STBAM_WORKBOOK_TO_CROP_FAMILY`
(`R/summaries/24_table162_support.R` — a hard-coded R named vector, *not*
a CSV, and therefore outside the original plan's "copy `data/reference/`
files" framing entirely) is extracted, unchanged in its 6 workbook→family
mappings, into `assumptions/reporting/reporting_sets/<scheme_id>.csv`
(recommend `crop_family.csv`) per the `folder_and_input_schema.md` §2.2
schema (`crop`, `group_label`, optional `display_order`). This gives the
new architecture equivalent crop-grouping capability from the moment
migration completes, independent of whether Table 162 itself is ever
redesigned (ADR-016 point 4).

### 2.5 `use_patterns.csv` source

`scenario_definitions.csv` — becoming the normalized `use_patterns.csv`
(§3 step 3, unchanged from the original plan).

### 2.6 Existing session-exported overrides, if any

Any existing exported override configuration on disk from the current
session-based `export_scenario_config()` mechanism, **if any exists** — to
be checked against the actual repository state at implementation time;
unchanged from the original plan (§7).

## 3. Steps

1. **Create the target evaluation folder** using the same folder-creation
   logic Decision 14's picker "Create" action will use
   (`shiny_information_architecture.md`), so the migration script is a
   caller of ordinary evaluation-creation logic, not a separate code
   path that could drift from it.
2. **Populate one named set per assumption category** (§2.2), each
   holding the corresponding `data/reference/*.csv` content, unchanged in
   value, under a descriptive starting name (e.g. `default`, or a name
   reflecting the actual source, such as `pmra_2024_reference` — exact
   naming is an implementation-time choice, not fixed by this plan).
   Populate each category's `_manifest.csv` (per
   `folder_and_input_schema.md` §2.1) with `set_id`, a descriptive
   `set_name`, and `source` referencing the original file's provenance
   (reusing the SHA-256 / `PRIMARY_AUDITED_REFERENCE` audit trail already
   established for the current reference data — §0.1's verified table).
   2a. **Copy tier-3 provenance files** (§2.3) into `inputs/reference/`,
       unchanged, with SHA-256 verification.
   2b. **Extract the crop-family reporting scheme** (§2.4) into an
       initial `reporting_sets/` file.
3. **Transform `scenario_definitions.csv` into `use_patterns.csv`**: add
   a stable `use_id` per crop/rate/workbook combination, with one row per
   `(use_id, planting_method)` pair where a use is registered under
   multiple planting methods. This is the one step with genuine
   transformation logic (not a plain copy) and needs its own unit test
   (see §5).
4. **Build the evaluation-inputs → engine-parameter-set adapter.**
   **Newly added to this plan's scope** (this was previously scheduled
   only inside Phase 3's "raw-result computation wiring" ticket, which
   comes *after* Phase 2 — but Phase 2's own verification step, §4 point
   1-2 below, needs it to exist first). This is a minimal, focused piece
   of infrastructure: given a migrated evaluation's selected named sets +
   `use_patterns.csv`, produce an `stbam_parameter_set`/`stbam_baseline`-
   shaped object the *unchanged* `build_scenario_inputs()`/
   `build_scenario_summary()` functions can consume directly, with no
   change to those functions' own signatures or behaviour. Built once
   here; reused unchanged by Phase 3's full run lifecycle — not
   duplicated logic.
5. **Do not fabricate an initial run** as part of migration itself.
   Migration produces valid `inputs/` only; creating the first `Run_001`
   is an ordinary use of the run-lifecycle mechanism
   (`run_lifecycle_and_validation.md`), exercised once as an end-to-end
   check (§4) but not treated as part of the migration script's
   responsibility — keeps the migration script's scope limited to input
   conversion, consistent with ADR-008's separation of inputs from runs.
   The adapter built in step 4 is used directly by the §4 verification
   below, without needing a full run/`inputs_snapshot`/dedup apparatus
   (Phase 3) to exist yet.

## 4. Verification — the Phase 2 acceptance gate (expanded, 9 points)

**Adopted this session as the authoritative Phase 2 gate**, superseding
the original 2-point recompute-and-compare check. Phase 2 does not pass
merely because the evaluation folder and input files can be created —
every point below must pass. Any single failure blocks Phase 2 from being
considered complete; it indicates either a transformation bug or an
undocumented difference between the old and new schemas, and must be
resolved (not worked around):

1. **Exact match, `scenario_inputs`** — using the §3 step 4 adapter, feed
   the migrated evaluation's inputs through the unchanged
   `build_scenario_inputs()`; every row and column must match the current
   canonical output (`scripts/build_canonical_outputs.R`'s existing
   output, or an equivalent freshly-computed baseline) exactly, subject
   only to whatever floating-point tolerance the existing test suite
   already establishes.
2. **Exact match, `scenario_summary`** — same method, via
   `build_scenario_summary()`. This transitively exercises receptor/
   effects-metric/fate resolution, since those feed the closed-form
   grid — a pass here is strong evidence those layers migrated correctly
   too, not just agronomy.
3. **Explicit, hard-coded row-count assertions**, independent of the
   row-by-row comparison — e.g. the known current row counts (85 crops,
   157 `scenario_definitions` rows, and the resulting expected
   `use_patterns.csv` row count once multi-planting-method rows are
   exploded) are asserted directly in the migration test, not inferred
   solely from "the comparison happened to match." (Direct precedent:
   this project's own AUD-099 finding — an acceptance criterion that
   compared against a stored value instead of an independent
   recomputation — is exactly the failure mode this redundant check
   exists to catch.)
4. **Tier-3 provenance-file completeness**: all 6 files in §2.3 present,
   byte-identical (SHA-256 match against the pre-migration
   `data/reference/` copy), under the migrated evaluation's
   `inputs/reference/`.
5. **Lossless named-set copy check** (unchanged from the original plan,
   §5 below): every value in each `data/reference/<file>.csv` appears
   unchanged in the corresponding migrated set file.
6. **Crop-grouping data carried forward**: `STBAM_WORKBOOK_TO_CROP_FAMILY`'s
   6 workbook→family mappings appear, unchanged, in the migrated
   `reporting_sets/crop_family.csv` (or equivalent), and validate cleanly
   against the Phase 4 reporting-scheme schema (crop-only, per ADR-010/I7)
   once Phase 4 exists to check against.
7. **No truncation regression**: assert the migrated evaluation's first
   run produces the full crop count per workbook (e.g. 11 crops for
   `small_cereals`), not a subset — the direct, positive-control check
   that migration does not reintroduce the existing R7 crop-dropdown
   truncation defect (`docs/current_implementation_inventory.md` §15)
   into the new architecture's raw layer.
8. **Existing test suite passes unmodified** (`tests/testthat/`) — run
   before and after the migration script and adapter (§3 step 4) are
   added to the repository, confirming I16 (engine untouched) throughout
   Phase 2's work.
9. **Re-runnability**: run the migration script twice against the same
   repository state; assert the second run's output is either rejected
   as a duplicate (once the Phase 3 dedup mechanism exists) or byte-
   identical to the first — ADR-015's own "re-runnable and testable"
   requirement, made concrete.

**Explicitly not part of this gate** (ADR-016, ADR-017): Table 162
Shiny-module parity; Sensitivity-tab parity. Points 4 and 6 above cover
*data preservation* for Table 162's future redesign, which is required;
they do not require any Table 162 *calculation or display* equivalence,
which is not required at this phase.

This verification is itself the first concrete instance of the
reproducibility invariant tracked in `invariants_and_test_plan.md` (I11),
and — per ADR-019 — is one of the change categories for which independent
adversarial agent review is mandatory, not optional.

## 5. Testing the migration script itself

- Unit test the `scenario_definitions.csv -> use_patterns.csv`
  transformation directly: given a small hand-constructed input with a
  known multi-planting-method case, assert the expected normalized rows
  and shared `use_id`.
- Unit test that named-set population is a lossless copy (every value in
  `data/reference/<file>.csv` appears unchanged in the corresponding
  migrated set file) — this is §4 point 5 above, restated as its own
  test.
- Unit test the §3 step 4 adapter directly: given a hand-constructed
  minimal evaluation (one named set per category, a small
  `use_patterns.csv`), assert it produces a parameter-set object the
  unchanged engine accepts and computes correctly against a
  hand-verified expected result — independent of the full migration
  script, so the adapter's correctness is not only ever tested through
  the one large integration test below.
- Integration test: full migration script run + adapter + engine
  recomputation + comparison against canonical outputs (§4), automated
  and re-runnable, not a one-time manual check.

## 6. Scope boundary

This is a one-time conversion for the current project. The script is not
required to be a general-purpose "any legacy project -> evaluation"
importer, though nothing here precludes reusing its logic later if a
second legacy dataset ever needed the same treatment.

**Explicit non-goals, all confirmed this session:**
- Original `.xlsm`/`.docx` source documents (tier 1) are never copied
  into `evaluations/` — referenced by path + SHA-256 only (§0.1, §2.1,
  ADR-018).
- No file under
  `C:\MonDossierMartin\Python_Local\Python_Document analysis\` is
  modified by this plan or any part of this redesign without separate,
  explicit authorization.
- Table 162 Shiny-module redesign and Sensitivity-module redesign are not
  required for this migration to be considered complete (ADR-016,
  ADR-017) — both remain available via the legacy application (ADR-020)
  and are addressed at their own, separately-scheduled checkpoints.

## 7. Open items carried from ADR-015 / this session's revision

- Exact migrated evaluation name and default-set naming convention —
  implementation-time choice.
- Whether any existing session-exported override configurations
  represent real work product needing conversion — check actual
  repository state at implementation time; if none exist, this step is
  simply skipped.
- Exact destination schema field(s) for tier-1 provenance metadata (§2.1)
  — an extension of the existing `source_manifest.csv` pattern is
  recommended, but the precise column layout is an implementation-time
  choice.
- Whether `planting_method_parameters.csv` becomes its own named-set
  category or is folded into `seeding_sets` (§2.2 table) — implementation-
  time schema choice, flagged so it is made deliberately rather than
  defaulted silently.
- Exact timing for the Table 162 and Sensitivity redesign checkpoints —
  deliberately not fixed by this plan or by ADR-016/ADR-017; tracked as
  deferred capabilities in `implementation_phases_proposal.md`.
