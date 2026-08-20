# Data dictionary

## Part 1 — Reference tables (`data/reference/`)

These are the immutable assessment baseline. Nothing in the application
writes to them. All were produced from the source Word documents and
Excel workbooks by `scripts/extract_reference_data.py`; see
`source_manifest.csv` and `copied_register_manifest.csv` for exact
provenance and SHA-256 hashes of every source file used.

### `source_manifest.csv`

One row per source calculation workbook. Columns: `workbook_key` (join key
used everywhere else, e.g. `small_cereals`), `file_name`, `sha256`, `role`
(`PRIMARY_AUDITED_REFERENCE` — only `small_cereals`, which received the
1,115-check independent numeric audit — or `SCENARIO_SOURCE` for the other
five), `extracted_at`.

### `crop_seeding_parameters.csv`

One row per crop or crop/use variant (86 rows — this is a broad agronomic
reference table, the "EAD Seed Weight and Seeding Rate Report", **not**
limited to crops with a registered application rate). Key columns:
`crop`, `tkw_low_g_per_1000` / `tkw_high_g_per_1000` (thousand-seed weight
bounds), `seeding_rate_low_seeds_per_ha_direct` /
`seeding_rate_high_seeds_per_ha_direct` (seed-count bounds, where supplied
directly), `seeding_rate_*_kg_per_ha_*_tkw` (four mass-basis seeding rates,
one per TKW bound per rate bound), `seeds_per_ha_low` / `seeds_per_ha_high`
(the resolved values actually used), `seeds_per_ha_low_basis` /
`_high_basis` (`DIRECT` or `CONVERTED_FROM_MASS`), planting-method
booleans (`spring_seeded`, `fall_seeded`, `broadcast_seeded`,
`drill_seeded`, `precision_planted`), `source`, `status`.

**A crop appearing here does not mean it can be modelled for exposure** —
see `scenario_definitions.csv` below.

**`seeds_per_ha_low` / `seeds_per_ha_high` / their `_basis` columns are not
read by the calculation engine** (independent audit finding AUD-029). They
encode the historical outer-bracket convention described in
`docs/scientific_model_specification.md` §4.2 (equal to the min/max of the
engine's actual 2×2 seed-count grid, and useful for cross-checking against
the published Word tables), but `R/calculations`, `R/inputs` and
`R/summaries` all derive `seeds_per_ha` per grid corner instead. Only the
Shiny input module's display and one test assertion read these two columns
directly. Comparing them to the engine's own `scenario_inputs$seeds_per_ha`
output will show apparent mismatches for any crop whose seeding rate is
supplied on a mass basis — this is the same definitional difference, not an
error in either place.

### `scenario_definitions.csv`

One row per crop x rate-level x workbook combination with an actual
registered application rate (158 rows, covering 6 workbook keys:
`small_cereals`, `small_cereals_msa`, `canola`, `cucurbits`,
`legumes_deep`, `legumes_shallow`). Columns: `workbook`, `seed_use_number`,
`crop`, `rate_level` (`high`/`mid`/`low`), `application_rate`,
`application_rate_unit` (`mg a.i./kg seed` or `mg a.i./seed`), `source`,
`status`. **This is the join that actually gates which crops can be
modelled** — `build_scenario_inputs()` starts from this table, not from
`crop_seeding_parameters.csv`.

### `planting_method_parameters.csv`

One row per planting method (4 rows: broadcast, drill_spring, drill_fall,
precision). Columns: `planting_method_label` (display text),
`planting_method` (the code used everywhere else), `surface_seed_fraction`
(the proportion of sown seed left on the surface — de Snoo & Luttik 2004),
`source`, `status`.

### `receptor_parameters.csv`

One row per receptor (6 rows: bird_small/medium/large,
mammal_small/medium/large). Columns: `receptor_id`, `taxon`, `size_class`,
`body_weight_g`, `fir_regression_name` (which Nagy 1987 regression),
`fir_coefficient_a` / `fir_exponent_b` (the regression's `a` and `b`),
`food_intake_g_dw_per_day` (the pre-computed baseline FIR — dry weight
basis, no fresh-weight conversion applied), `msa_short_term_m2` /
`msa_long_term_m2`, `surface_seed_only` (`TRUE` for all birds; `FALSE` for
mammals per ASSUMPTION-020 — the accessible pool becomes the full sown
density, not just the surface fraction), `source`, `status`.

### `fir_regressions.csv`

The full library of alternative food-intake-rate regressions (10 forms,
including granivore-specific Nagy et al. 1999 variants), available so the
intake model basis can be changed as an explicit, provenance-tagged
override rather than by editing code. Not used by default — the baseline
uses the single regression named in `receptor_parameters.csv`.

### `effects_metrics.csv`

One row per toxicological reference value. Columns: `metric_id` (join key,
e.g. `bird_acute_screening`), `active_ingredient`, `taxon`, `duration_class`
(`acute`/`chronic`), `metric_role` (`SCREENING` / `REFINED` /
`REFINED_ADDITIONAL` — kept strictly separate, never combined in one RQ),
`endpoint_description`, `endpoint_value` (the raw study result before any
uncertainty factor), `uncertainty_factor`, `effects_metric` (the value
actually used — `endpoint_value / uncertainty_factor` for screening
metrics; refined metrics generally carry `uncertainty_factor = 1`), `unit`,
`source`, `status`. Contains both mammalian chronic screening values (1.8
and 2.4 mg a.i./kg bw/d as separate rows, `mammal_chronic_screening` and
`mammal_chronic_refined`) — these are deliberately distinct workflow
stages per reviewer clarification recorded in the source review project
(`TRC-002`); do not collapse them into one value.

### `dissipation_parameters.csv`

Exactly 2 rows: `residue_dt50_days` (10 days — pesticide breakdown on/in a
surviving seed) and `surface_seed_dt50_days` (14 days — physical
disappearance of seed from the surface). These are the assessment-wide
defaults; both can be overridden per session without touching this file.

### `review_core_assumptions.csv`, `review_effects_metrics.csv`, `table162_considerations.csv`, `table162_decision_matrix.csv`

Copied read-only from the source document-review project's own registers
(`copied_register_manifest.csv` records the exact source path and hash for
each). Used by `build_table162_support()` to join calculated results to the
evidence/consideration register — see
`docs/table162_support_methodology.md`.

### `copied_register_manifest.csv`

Provenance record for the four files copied from the review project: source
path and SHA-256 at copy time.

## Part 2 — Canonical datasets (built at runtime, not stored as source)

These are produced by the `R/summaries/` builders and are what every plot,
table, and export actually reads. See `docs/scientific_model_specification.md`
§11 for their formal definition; this section lists every column.

### `scenario_inputs` (`build_scenario_inputs()`)

One row per crop x rate x planting method x seeding-rate bound x
seed-mass bound. All time-independent agronomic quantities.

| Column | Meaning |
|---|---|
| `scenario_id` | Stable composite key: `workbook\|crop\|rate_level\|method\|rate_bound\|mass_bound` |
| `workbook`, `crop`, `rate_level` | Identify the source scenario row |
| `application_rate`, `application_rate_unit` | Registered rate, effective value (after any override) |
| `planting_method`, `planting_method_label` | Code and display text |
| `seeding_rate_bound` (`low`/`high`), `seed_mass_bound` (`low_tkw`/`high_tkw`) | Which corner of the independent 2x2 grid this row is |
| `seeding_basis` | `SEED_COUNT_SUPPLIED`, `MASS_RATE_SUPPLIED`, or `UNAVAILABLE` |
| `tkw_g_per_1000`, `seed_mass_g` | Thousand-seed weight and individual seed mass used |
| `seeds_per_ha`, `seeds_per_m2` | Sown seed density |
| `seeding_rate_kg_per_ha` | Mass-basis seeding rate |
| `concentration_mg_per_kg_seed`, `dose_per_seed_mg` | Both forms of the treatment loading |
| `field_rate_g_ai_per_ha` | Active ingredient applied per hectare |
| `surface_seed_fraction`, `initial_surface_seeds_per_m2`, `area_per_surface_seed_m2` | Surface availability at sowing |
| `*_status` columns | `ASSESSMENT_DEFAULT` or the override status for each overridable input |
| `parameter_set` | Name of the parameter set that produced this row |
| `provenance_class` | Always `CALCULATED` for this dataset |

### `scenario_summary` (`build_scenario_summary()`)

One row per scenario x receptor x effects metric x dietary fraction.
Closed-form (no day-by-day loop). Includes every `scenario_inputs` column
above plus receptor/metric/exposure columns:

| Column | Meaning |
|---|---|
| `receptor_id`, `taxon`, `size_class`, `body_weight_g` | Receptor identity |
| `food_intake_g_dw_per_day` | FIR, dry-weight basis |
| `msa_term`, `msa_m2` | Which MSA and its value |
| `metric_id`, `duration_class`, `metric_role`, `effects_metric`, `endpoint_description` | Which effects metric |
| `diet_fraction` | The dietary fraction this row evaluates |
| `accessible_seeds_per_m2`, `accessible_pool_basis` | Surface-only for birds; surface+buried for mammals |
| `seeds_required_full_diet`, `seeds_required_per_day` | At 100% diet, and at `diet_fraction` |
| `ede_full_diet` | Dose at a 100% treated-seed diet (used for `screening_rq`) |
| `initial_dose_mg_kg_bw_day` | Dose at `diet_fraction`, day 0 |
| `screening_rq`, `initial_rq`, `peak_rq`, `peak_rq_day` | Risk quotients; peak always occurs at day 0 (monotonic decline) |
| `days_above_loc`, `day_below_loc` | Duration the dose stays at/above the metric |
| `threshold_diet_fraction_pct` | Dietary fraction at which the metric is exactly reached |
| `seeds_to_metric`, `area_to_reach_metric_m2` | Seeds/area needed to reach the metric |
| `initial_available_seeds_within_msa`, `initial_required_search_area_m2`, `initial_max_feasible_diet_fraction`, `diet_fraction_is_feasible_at_sowing` | Feasibility diagnostics — never feed back into dose/RQ above |
| `days_at_full_diet_available`, `day_100/50/25pct_diet_infeasible`, `days_assumed_diet_feasible` | Feasibility over time, using the surface-seed half-life |
| `residue_dt50_days`, `surface_seed_dt50_days` | The two half-lives actually used for this row |
| `provenance_class` | Always `DERIVED` |

### `daily_timecourse` (`build_daily_timecourse()`)

One row per scenario x receptor x metric x diet fraction x day. Same core
columns as above, evaluated at each `day`, plus explicit time-varying
columns: `surface_seeds_per_m2`, `ai_per_seed_mg`, `surface_ai_mg_per_m2`
(the product of the two — see model walkthrough §6), `dose_mg_kg_bw_day`,
`rq`, `above_loc`, and the day-specific feasibility columns. **Not built
for every scenario at full scale** — `scripts/build_canonical_outputs.R`
writes a documented representative slice (see that script's header
comment); `scenario_summary` is closed-form and always covers every
scenario.

**Maximum-obtainable-exposure columns** (specification §10.4; model
walkthrough §10), distinct from the manually-toggled `msa_m2`/
`available_seeds_within_msa`/`max_feasible_diet_fraction` columns above
(which remain driven by whatever `msa_term` the caller passed to
`resolve_receptors()`):

| Column | Meaning |
|---|---|
| `max_obtainable_msa_term` | `"short"` or `"long"`, resolved automatically per row's taxon/duration_class from the source assessment's own policy (`resolve_msa_term_for_metric()`), not a manual choice |
| `max_obtainable_msa_m2` | The resolved MSA value for that policy term |
| `max_obtainable_seeds_within_msa` | Treated seed available within that MSA, at time `t` |
| `max_obtainable_diet_fraction` | Maximum feasible dietary fraction under the policy-correct MSA (parallels `max_feasible_diet_fraction`) |
| `diet_fraction_is_obtainable` | Whether `diet_fraction` is obtainable under the policy-correct MSA (parallels `diet_fraction_is_feasible`) |
| `max_obtainable_seeds_per_day` | `min(seeds_required_per_day, max_obtainable_seeds_within_msa)` — never assumes the receptor eats past its own food requirement even when seed is abundant |
| `max_obtainable_dose_mg_kg_bw_day` | Dose from `max_obtainable_seeds_per_day`, using the same per-seed dose function as the conditional dose |
| `max_obtainable_rq` | `max_obtainable_dose_mg_kg_bw_day / effects_metric` |
| `above_loc_max_obtainable` | `max_obtainable_rq >= LOC` |

`seeds_per_m2` is also carried on this dataset (added alongside the above)
for scenarios/tooling that need sown seed density directly rather than via
`seeds_per_ha / 10000`.

### `table162_support` (`build_table162_support()`)

One row per crop family x rate x planting method x receptor x duration
class. See `docs/table162_support_methodology.md` for the full column
list and how this joins calculated results to the evidence register.

## Part 3 — Generated output files (`outputs/`, gitignored)

Written by `scripts/build_canonical_outputs.R`: `outputs/canonical/`
(the four datasets as CSV/CSV.GZ/XLSX), `outputs/tables/` (official tables
as CSV, plus Word — see `docs/word_export_diagnosis.md` for current
limitations), `outputs/build_manifest.csv` (SHA-256 and timestamp of every
written file). Not committed to git; regenerate as needed.
