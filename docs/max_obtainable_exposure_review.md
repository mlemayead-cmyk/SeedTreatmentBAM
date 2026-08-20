# Independent adversarial review — maximum obtainable exposure feature

Reviewer: independent adversarial review (did not author any part of the feature).
Date: 2026-08-20.
Model version under review: `STBAM_MODEL_VERSION = "1.2.0"`, git commit `e7ccae108164`.
R: `C:\Program Files\R\R-4.4.3\bin\x64\Rscript.exe`.

Scope: the **new** maximum-obtainable-exposure feature only —
`R/calculations/05_feasibility.R` (`resolve_msa_term_for_metric()`,
`max_obtainable_seeds_per_day()`), the "Maximum obtainable exposure" block of
`R/summaries/22_daily_timecourse.R`, all of
`R/summaries/26_max_obtainable_summary.R`, `R/reporting/34_figure_metadata.R`,
`R/reporting/35_max_obtainable_plots.R`, `R/shiny/44_module_max_obtainable.R`,
`scripts/generate_priority_exposure_figures.R`,
`docs/priority_exposure_figures.md`, and
`tests/testthat/test-10-*` / `test-11-*`.
The previously audited base engine (`docs/independent_engine_audit.md`,
`docs/model_validation_report.md`) is **not** re-audited here except where the
new feature depends on it.

Method: the code was read, the mathematics was re-derived independently, and
every quantitative claim below was checked by **running R against real
scenarios** — not by reading the code and agreeing with it. Independent
numerical root-finding, hand recomputation of the full unit chain, fine-grid
time courses (`by = 0.05`–`0.25` d), empirical half-life regression, live
`shiny::testServer()` reactive probes, and deliberate malformed inputs were used.
No project file was modified.

Status vocabulary (as used in `docs/independent_engine_audit.md`):
`PASS`, `CONFIRMED_ERROR`, `POTENTIAL_ERROR`, `ROBUSTNESS_ISSUE`,
`DOCUMENTATION_GAP`, `REQUIRES_HUMAN_REVIEW`.

**Starting point.** `testthat::test_dir("tests/testthat")` after
`load_stbam(".", include = c("core","reporting","shiny"))`:
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 556 ]`. The suite passes on the current
state of disk. Passing tests were not treated as evidence of correctness;
independent probes were written for every numbered check below.

---

## 1. Double-counting of seed disappearance / residue dissipation

**Status: PASS**

Chain traced on disk:
`accessible_seeds_per_m2_t` (surface DT50 applied **once**, line 36–43 of
`22_daily_timecourse.R`) → `available_seed_within_msa()` (pure multiplication by
m²) → `max_obtainable_seeds_per_day()` (pure `pmin`, no time term) →
`daily_ai_intake_dose(seeds, ai_per_seed_mg, bw)` where `ai_per_seed_mg` carries
the residue DT50 **once** (line 44–46) → `risk_quotient()` (pure division).
No decay factor appears twice anywhere on the path, and
`daily_dose_over_time()` (which would have applied the residue decline a second
time) is deliberately *not* used for the max-obtainable dose.

Numerical confirmation (Barley/high/broadcast/low/low_tkw, `bird_small`,
`days = seq(0, 200, by = 0.25)`):

| Inverted quantity | Expected | Max relative error over 801 days |
|---|---|---|
| `max_obt_dose · BW_kg / seeds_eaten` | `dose_per_seed_mg · 2^(−t/10)` | `2.3e-16` |
| `max_obt_seeds_within_msa / max_obt_msa_m2` | `surf₀ · 2^(−t/14)` | `7.9e-17` |

Empirical half-life of `max_obtainable_rq` fitted by `lm(log2(rq) ~ day)`:

* abundant phase (333 points): **10.000 d** — exactly the residue DT50, i.e. the
  surface-seed process is correctly *absent* while seed is not binding;
* seed-limited phase (468 points): **5.83333 d** — exactly
  `combined_surface_ai_dt50(14, 10) = 1/(1/14 + 1/10) = 5.833…`, i.e. each
  process appears exactly once, neither twice nor missing;
* conditional `rq` over the whole grid: **10.000 d** — the conditional curve is
  untouched by surface-seed availability, as specified.

The regime transition observed in the data (first seed-limited row at day 83.25
on a 0.25 d grid) matches the analytic `Ds·log2(f₀) = 83.2039715861` d, which is
also the independently audited workbook value `1!N79`.

## 2. MSA applied as intended (35 m² only for mammal + chronic; 70/140 m² for all bird rows)

**Status: PASS**

`resolve_msa_term_for_metric()` was not trusted in isolation. A real
`build_daily_timecourse()` was built over **all 6 receptors × all 16 canonical
effects metrics** (SCREENING + REFINED + REFINED_ADDITIONAL), 27 distinct
receptor × duration × role combinations. Result, read off the actual output
columns:

* every `bird_small` / `bird_medium` row (acute **and** chronic, screening and
  refined-additional): `max_obtainable_msa_term = "short"`, `max_obtainable_msa_m2 = 70`;
* every `bird_large` row (acute **and** chronic): `"short"`, **140**;
* every mammal **acute** row: `"short"`, 70;
* every mammal **chronic** row (SCREENING, REFINED and REFINED_ADDITIONAL):
  `"long"`, **35**.

No bird row anywhere used the long-term term or the long-term value.

Two adversarial attempts to break the policy were made and both failed to break it:

1. Caller resolves receptors with `resolve_receptors(params, msa_term = "long")`
   and passes that table in. The legacy `msa_m2` column duly becomes 35/70, but
   `max_obtainable_msa_m2` stayed at the policy values (bird_large 140, mammal
   acute 70, mammal chronic 35). The two layers are genuinely independent.
2. Live `shiny::testServer(stbam_server(baseline))` with the sidebar toggle
   `inputs-msa_term = "long"`. The shared `results()$timecourse` correctly
   showed `msa_m2 = 35`, while the max-obtainable tab's "Current assumptions"
   panel reported 70 m² short-term for bird acute, 70 m² short-term for bird
   **chronic**, 70 m² short-term for mammal acute and 35 m² long-term for
   mammal chronic. **The global toggle does not leak into this tab.** The tab
   exposes no `msa_term` control of its own (`R/shiny/44_module_max_obtainable.R`
   has only `scenario_id`, `metric_id`, `free_y`, `diag_receptor`), so the bug
   this feature exists to prevent cannot be reopened from the UI.

The module reads `inputs$params()` for every derived object
(`panel_data()` line 132, `metadata_list()` line 149, `all_metrics()` line 94,
`override_banner` line 172), and `results()$inputs` is itself built from
`inputs$params()` in `43_app.R` line 49, so overrides are respected consistently
with the rest of the app. Verified live: an override raises the amber
"N override(s) applied" banner on this tab.

One residual hole in the policy is recorded separately as finding **A2** below
(an `msa_m2` *value* override collapses the short/long distinction while the
footnote still asserts the term).

## 3. Food requirement correctly limits consumption

**Status: PASS**

Scenario constructed with deliberately absurd supply:
`set_override(params, "seeds_per_ha", 5e9, scope = "Barley:low")` plus
`set_override(params, "surface_seed_fraction", 1, scope = "broadcast")`,
giving `max_obtainable_diet_fraction ≈ 3.99e5` at sowing (≈400 000 daily
diets available within the MSA). Over all 6 receptors × 16 metrics ×
61 days (5 856 rows):

* `max(max_obtainable_seeds_per_day − seeds_required_per_day) = 0` exactly;
* `all(|obtainable − required|) < 1e-9` → `TRUE`;
* `max_obtainable_dose / dose_mg_kg_bw_day ∈ [1, 1]` — the max-obtainable curve
  collapses onto the conditional curve and never rises above it;
* `max |max_obtainable_rq − rq| = 1.07e-14` (floating point only).

The receptor is never modelled as eating more than its own food requirement.
The complementary direction was also confirmed: over the entire fine grid,
`max_obtainable_seeds_per_day ≤ max_obtainable_seeds_within_msa` and the plotted
"Maximum obtainable" series never exceeded the "100% treated-seed diet" series
at any day in any probe.

## 4. Units

**Status: PASS**

Every conversion on the new path was recomputed by hand from raw reference data
for a real row (Barley, high, broadcast, low/low_tkw, `bird_small`,
`bird_acute_screening`, day 5) and compared with the model output:

| Quantity | Hand value | Model | Rel. diff |
|---|---|---|---|
| `seed_mass_g` = TKW/1000 | 0.0248 g/seed | 0.0248 | 0 |
| `dose_per_seed_mg` = C·m_seed/1000 | 0.00744 mg a.i./seed | 0.00744 | 1.2e-16 |
| `initial_surface_seeds_per_m2` = (seeds/ha)/10 000 · f | 180 seeds/m² | 180 | 0 |
| `surface_seeds_per_m2(5)` = 180·2^(−5/14) | 140.5276528 | 140.5276528 | 0 |
| `accessible_seeds_per_m2_t(5)` | 140.5276528 | 140.5276528 | 0 |
| `ai_per_seed_mg(5)` = 0.00744·2^(−5/10) | 0.005260874452 | 0.005260874452 | 0 |
| `max_obt_seeds_within_msa` = 140.5277 × 70 m² | 9836.935695 seeds | 9836.935695 | 0 |
| `seeds_required_per_day` = FIR/m_seed | 204.7891237 seeds/d | 204.7891237 | 0 |
| `max_obtainable_seeds_per_day` = min(·) | 204.7891237 | 204.7891237 | 0 |
| `max_obt_dose` = seeds·mg/seed / (BW_g/1000) | 53.86849344 mg/kg bw/d | 53.86849344 | 0 |
| `max_obtainable_rq` = dose/43.1 | 1.249849036 | 1.249849036 | 0 |

Dimensional walk-through, confirmed correct and non-redundant:

* seeds/m² × m² → seeds (`available_seed_within_msa`, no factor);
* (g dw/day) ÷ (g/seed) → seeds/day (`seeds_required_per_day`, no factor);
* seeds/day × (mg a.i./seed) → mg a.i./day;
* mg a.i./day ÷ (g bw / 1000) → mg a.i./kg bw/day — the **only** unit factor on
  the max-obtainable dose path, `/1000` for g→kg, present exactly once in
  `daily_ai_intake_dose()` and nowhere else;
* mg a.i./kg bw/day ÷ mg a.i./kg bw/day → dimensionless RQ.

Cross-consistency of the inputs was also re-derived: `seeds_per_m2 · seed_mass_g
· 10 = 44.64 = seeding_rate_kg_per_ha`, and
`C · seeding_rate / 1000 = 13.392 = field_rate_g_ai_per_ha`. No factor is
missing, duplicated or inverted. The `m²`-basis conversion `(seeds/ha)/10 000`
appears exactly once (in `surface_seed_initial()`), inherited unchanged from the
audited engine.

## 5. Acute/chronic MSA pairing against the assessment's own text

**Status: PASS** (policy function and pairing).
Sub-findings **A2** (POTENTIAL_ERROR) and **A3** (DOCUMENTATION_GAP) below.

I read `MAIN-P000209` myself
(`01_extracted/paragraph_index.csv`, row 210, section heading *"Daily Foraging
Area for Ground-foraging Granivorous Birds and Mammals"*). Verbatim, the
operative sentences are:

> "a short-term 70 m2 MSA was assumed for all mammals and for small- and
> medium-sized birds. A 140-m2 short-term MSA was assumed for large birds. For
> birds, a long-term MSA was not considered because there was a paucity of
> evidence to suggest that observed effects on reproduction were due to a
> long-term exposure, as opposed to parental exposure occurring over critical
> window within the reproductive cycle… For mammals, a long-term MSA of 35 m2
> was considered."

Independent judgement, made against the paragraph and not against the code's own
comments:

* **Birds always short-term, acute and chronic alike** — the assessment says a
  long-term MSA "was not considered" for birds. `resolve_msa_term_for_metric()`
  returns `"short"` for `bird`/`acute` and `bird`/`chronic`. **Correct.**
* **Mammals: short-term acute, long-term chronic/reproductive** — the assessment
  attributes mammalian reproductive effects to prolonged parental exposure and
  states this as the basis for a long-term MSA. The function returns `"short"`
  for `mammal`/`acute` and `"long"` for `mammal`/`chronic`. **Correct.**
* **The numeric values in `data/reference/receptor_parameters.csv` also match the
  paragraph**: `msa_short_term_m2` = 70 for `bird_small`, `bird_medium` and all
  three mammals; **140** for `bird_large`; `msa_long_term_m2` = 35 for all three
  mammals. Every value the feature actually consumes is traceable to the
  paragraph. Verified live in the timecourse output (check 2).

Note that the mapping *chronic → REFINED / REFINED_ADDITIONAL as well as
SCREENING* was verified: `mammal_chronic_refined` (2.4 mg/kg bw/d) and the three
`mammal_chronic_additional_*` metrics all correctly resolve to 35 m² long-term,
so the policy is applied by `duration_class`, not by `metric_role`. That is the
right discriminator given the paragraph's wording ("reproduction", "prolonged
parental exposure"), which is about duration, not about screening vs refined.

## 6. Footnote accuracy against canonical model data

**Status: CONFIRMED_ERROR** (mammal / non-surface-seed receptors),
PASS for bird scenarios.

Three real scenarios were generated end to end and every stated number was
compared with the canonical `daily_timecourse` / `resolve_effects_metrics`
value it should have come from.

### Scenario 1 — Barley, high (300 mg a.i./kg seed), broadcast, low / low_tkw, `bird_small`, `bird_acute_screening`

Every field cross-checked against the canonical row: `application_rate` 300,
`field_rate_g_ai_per_ha` 13.392, `tkw_g_per_1000` 24.8,
`seeding_rate_kg_per_ha` 44.64, `seeds_per_m2` 180,
`initial_surface_seeds_per_m2` 180, `surface_seed_fraction` 1,
surface DT50 14 d, residue DT50 10 d, `body_weight_g` 20,
`food_intake_g_dw_per_day` 5.07877026681, `msa_m2` 70,
`effects_metric` 43.1 — **all OK, zero mismatches**. `msa_m2` and `msa_term`
are correctly taken from `max_obtainable_msa_m2` / `max_obtainable_msa_term`
(the policy columns), *not* from the manually-toggled `msa_m2`. The
effects-metric provenance line (`Canary`, endpoint 431, 10× UF, source 3251286)
matches `data/reference/effects_metrics.csv` row 2 exactly. Nothing invented.

### Scenario 2 — small-multiple, three bird sizes

Per-receptor lines correctly differ and correctly report the *per-receptor*
MSA: `Small bird (20 g) … MSA 70 m2 (short-term)`, `Medium bird (100 g) … 70 m2`,
`Large bird (1,000 g) … Applicable MSA 140 m2 (short-term)`. Body weights and
food requirements (5.08 / 19.9 / 58.2 g dw/day) match
`receptor_parameters.csv` to displayed precision.

### Scenario 3 — Barley, high, **drill_spring**, high / high_tkw, `mammal_small`, `mammal_chronic_screening` — **DEFECT**

The footnote reads:

> `… Seeding rate 280 kg/ha (high; 470 seeds/m2 planted) | Initial surface seed
> 15.5 seeds/m2 (Spring - standard drill: 3.3% of sown seed on the surface)`

but the canonical row says:

```
accessible_pool_basis        = SURFACE_PLUS_BURIED
surface_seeds_per_m2  (day0) = 15.51
accessible_seeds_per_m2_t    = 470          <-- what the curve actually uses
max_obtainable_msa_m2        = 35
max_obtainable_seeds_within_msa = 470 * 35  = 16 450 seeds
```

`mammal_*` receptors have `surface_seed_only = FALSE`, so
`build_daily_timecourse()` line 39–43 sets the accessible pool to the **full
sown density** (`seeds_per_m2`), not the surface fraction. The maximum-obtainable
curve, `max_obtainable_diet_fraction`, and the `day_100pct/50pct/25pct_diet_unobtainable`
annotations are therefore all driven by **470 seeds/m², while the footnote
states 15.5 seeds/m² and explicitly attributes it to "3.3% of sown seed on the
surface"**. That is a factor of **30.3×** between the number a reader is given
and the number the figure is actually built on.

`build_figure_metadata()` (`34_figure_metadata.R` lines 187–189) carries
`seeds_per_m2` and `initial_surface_seeds_per_m2` but **not**
`accessible_pool_basis` or `accessible_seeds_per_m2_t`, and
`format_figure_footnotes()` never mentions the pool basis. The words "buried",
"accessible pool" and `SURFACE_PLUS_BURIED` do not appear anywhere in the
footnote, the plot captions, or the Shiny "Current assumptions" panel — confirmed
by string search of the generated caption text.

Reproduction:
```r
source("R/load_model.R"); load_stbam(".", include = c("core","reporting"))
p   <- parameter_set(load_baseline())
met <- resolve_effects_metrics(p, "SCREENING", taxa = "mammal")
sc  <- build_scenario_inputs(p, crops="Barley", workbooks="small_cereals",
                             rate_levels="high", planting_methods="drill_spring")
sc1 <- sc[sc$seeding_rate_bound=="high" & sc$seed_mass_bound=="high_tkw", ]
tc  <- build_daily_timecourse(p, sc1, resolve_receptors(p, "mammal_small"),
                              met, diet_fractions = 1, days = 0)
row <- tc[tc$metric_id == "mammal_chronic_screening", ]
cat(format_figure_footnotes(build_figure_metadata(row, met, p), "full"))
row$initial_surface_seeds_per_m2   # 15.51  <- printed in the footnote
row$accessible_seeds_per_m2_t      # 470    <- actually used
```

Severity: this is a **reporting** defect, not a calculation defect — the
arithmetic follows the pre-existing engine's `ASSUMPTION-020` faithfully (see
finding **A1**). But it directly defeats the feature's own stated requirement
that a figure be interpretable without Shiny: a reader given the footnote cannot
reproduce the curve, and would understate the available seed 30-fold. It is
**not** currently present in any exported static figure on disk, because
`scripts/generate_priority_exposure_figures.R` is bird-only
(`receptor_ids <- c("bird_small","bird_medium","bird_large")`), and it does not
arise for broadcast (surface fraction = 1). It **is** reachable in the live
Shiny tab by selecting any mammal metric with a drill or precision scenario.

## 7. Exported figures interpretable without Shiny

**Status: PASS with DOCUMENTATION_GAPs**

`plot_max_obtainable_exposure()` and `plot_max_obtainable_small_multiple()` were
actually called with `detail = "full"` and `p$labels$title` /
`$subtitle` / `$caption` extracted and read as a naive reader. Against the
self-contained-interpretation checklist:

| Question a reader must be able to answer | Answerable from title+subtitle+caption alone? |
|---|---|
| Crop | **Yes** — subtitle `"Barley — high treatment rate — Broadcast — low seeding rate / low TKW scenario"`; also inside `Scenario ID:` line |
| Treatment / rate | Yes — `300 mg a.i./kg seed (13.4 g a.i./ha)` |
| Seed weight / TKW | Yes — `TKW 24.8 g/1000 seeds (low_tkw)` |
| Initial surface seed density | Yes for birds — `Initial surface seed 180 seeds/m2 (Broadcast: 100% of sown seed on the surface)`. **No for mammals** — see check 6 |
| Both DT50s, and which is which | Yes — `Surface-seed disappearance DT50 = 14 d (seeds remaining on the surface) \| Residue dissipation DT50 = 10 d (a.i. remaining per seed present) \| independent first-order processes` |
| Receptor size / body weight / food requirement | Yes — one line per panel, e.g. `Large bird (1,000 g) \| Body weight 1,000 g \| Food requirement 58.2 g dry-weight diet/day` |
| Which MSA value **and term**, and why | Yes — `Applicable MSA 140 m2 (short-term)` per panel, plus the MAIN-P000209 policy sentence |
| Effects metric value / units / role / taxon | Yes — `Bird acute screening — 43.1 mg a.i./kg bw/day`, plus `Effects-metric basis: Canary (endpoint 431 mg a.i./kg bw/d; 10x uncertainty factor); source 3251286` |
| RQ / LOC definition | Yes — `RQ = dose / effects metric; RQ = 1 is the level of concern (LOC) used here` |
| What each curve means | Yes — both series are defined verbatim in the `full` caption |
| Whether assumptions were changed from default | Yes — `Assessment baseline. No overrides applied.` / `SCENARIO CONTAINS USER OVERRIDES (…): residue_dt50_days (global): 10 -> 21 days [USER_OVERRIDE]` |
| Provenance | Yes — scenario id, parameter set, model version, git commit, timestamp |

**Series are never conflated or mislabelled.** Verified numerically, not visually:
`p$data` was split by `series` and compared element-wise against the source
columns —
`max|plot["100% treated-seed diet"] − timecourse$rq| = 0` and
`max|plot["Maximum obtainable within MSA"] − timecourse$max_obtainable_rq| = 0`
over 183 points × 3 panels, and no day exists on which the max-obtainable series
exceeds the conditional series. Factor levels are fixed in the intended order.

**Free-y handling is honestly labelled.** With `free_y = TRUE` the caption ends
`"Note: y-axis (risk quotient) scales are independent per panel."` and
`ggplot_build()` confirms three genuinely different panel y-ranges
(`[-0.059, 1.855]`, `[-0.051, 1.457]`, `[-0.046, 1.050]`). With
`free_y = FALSE` the caption says `"Note: all panels share the same y-axis
(risk quotient) scale."` and all three ranges are identical
(`[-0.0847, 1.8558]`). The note is generated from the same `free_y` argument
that drives `facet_wrap(scales = …)`, so the two cannot drift apart.

Documentation gaps (do not invalidate the figures):

* The crop name appears in plain language only in the **subtitle**; within the
  caption itself it appears only embedded in the pipe-delimited
  `Scenario ID: small_cereals|Barley|high|broadcast|low|low_tkw`. If a caption is
  ever reused detached from its subtitle (e.g. a Word table of figure notes), the
  crop is not stated in readable form. In `detail = "concise"` the
  `Scenario ID:` line is dropped entirely, so the crop is then absent from the
  caption altogether.
* `msa_policy_note()` renders as `"both acute and chronic/ reproductive
  characterization"` — a stray space from `paste()` on a fragment ending in `/`
  (`34_figure_metadata.R` line 83).
* `format_metric_label()` hard-codes `unit = "mg a.i./kg bw/day"` and ignores
  `metric_row$unit`. The register value is `"mg a.i./kg bw/d"`, so the same
  caption shows both spellings (`43.1 mg a.i./kg bw/day` and
  `endpoint 431 mg a.i./kg bw/d`). Harmless today; a silent mislabel if a metric
  is ever registered in different units.

---

## Additional findings (outside the seven numbered checks)

### A1. Mammalian accessible pool = 100% of sown seed, declining at the *surface*-seed DT50
**Status: REQUIRES_HUMAN_REVIEW**

Because `surface_seed_only = FALSE` for all three mammal receptors, the new
maximum-obtainable calculation for mammals asserts that a 15 g mammal can obtain
**every seed sown** — including drilled/buried seed — within 35 m² (16 450 seeds
in Scenario 3 above), and that this buried pool disappears at the *surface*-seed
disappearance DT50 (14 d, sourced to deSnoo & Luttik 2004 for *surface* seed).
The new feature inherits this from `build_exposure_grid()` (`ASSUMPTION-020`) and
applies it faithfully; it is not a new coding error. But the feature changes its
consequence: in the old diagnostic this only affected a "could they?" flag,
whereas it now sets a headline **maximum obtainable RQ**, i.e. a number
presented as a physical upper bound. Whether a mammal can access buried seed
within its MSA, and whether the surface DT50 is the right disappearance rate for
buried seed, is a scientific judgement that a subject-matter expert should
confirm or refine. Flagging it, not asserting it is wrong.

### A2. An `msa_m2` override silently collapses the mammal short/long MSA distinction while the footnote still asserts the term
**Status: POTENTIAL_ERROR**

`build_daily_timecourse()` lines 98–103 build both lookups via
`resolve_receptors(params, ids, msa_term = "short"/"long")`, but
`resolve_receptors()` applies `effective_value(params, "msa_m2", scope = receptor_id,
default = baseline_msa)` — an override **wins over both branches**. `msa_m2` is
in `STBAM_OVERRIDABLE`.

Reproduced:
```r
pF  <- set_override(parameter_set(load_baseline()), "msa_m2", 0.5, scope = "mammal_small")
...  # mammal_small, SCREENING, Barley/high/broadcast/low/low_tkw, day 0
#   duration_class  max_obtainable_msa_term  max_obtainable_msa_m2
#   acute           short                    0.5
#   chronic         long                     0.5      <-- distinction gone
```
The footnote then reads `Applicable MSA 0.5 m2 (long-term)` and still carries
`"Mammalian chronic/reproductive characterization uses the long-term MSA; the
source assessment attributes mammalian reproductive effects to prolonged
parental exposure (assessment paragraph MAIN-P000209)."` — i.e. the figure cites
the assessment's policy as the basis for a value that is not the assessment's
policy value. The `SCENARIO CONTAINS USER OVERRIDES` line does appear (so it is
detectable, not silent at the whole-figure level), but the MSA line itself is
misleading. Not reachable from the built-in numeric override controls in
`40_modules_inputs.R` (they expose only DT50s, surface fraction, TKW and
seeds/ha); **is** reachable via `import_scenario_config()` CSV upload and via any
scripted `set_override()`.

Suggested (not applied): have the metadata/footnote report the override status of
`msa_m2` alongside the term, or suppress the "per MAIN-P000209" attribution when
the MSA carries a `USER_OVERRIDE` status.

### A3. Birds carry `msa_long_term_m2` values with no basis in MAIN-P000209
**Status: DOCUMENTATION_GAP** (pre-existing; adjacent to this feature)

`receptor_parameters.csv` stores `msa_long_term_m2` = 35 / 35 / 70 for
bird_small / medium / large. The assessment states a long-term MSA **was not
considered for birds**; these numbers are therefore model-invented, not
assessment-derived, and their `status` column nevertheless reads
`ASSESSMENT_DEFAULT`. The new feature never uses them (verified in check 2), but
the pre-existing "Exposure feasibility" tab's `msa_term` radio will happily
produce bird results at 35 m² — which is precisely the class of error this
feature was created to prevent, still live one tab away. Verified in
`testServer`: with `inputs-msa_term = "long"`, the shared timecourse reports
`msa_m2 = 35` for `bird_small`. Recommend a provenance/status correction or a
UI guard on that tab.

### A4. `STBAM_DEFAULT_LOC` is not actually honoured end-to-end
**Status: POTENTIAL_ERROR** (latent — no current metric uses LOC ≠ 1)

`STBAM_DEFAULT_LOC`'s own documentation claims it is
*"Kept as a named constant, not a literal `1` scattered through plotting and
summary code, so a different LOC could be substituted … without hunting for
hard-coded values."* That claim is false on the new path. Demonstrated by
setting `STBAM_DEFAULT_LOC <- 2` and rebuilding:

| Column | LOC = 1 | LOC = 2 | Honoured? |
|---|---|---|---|
| `day_max_obtainable_below_loc` | 8.2175 | 0 | yes |
| `day_conditional_below_loc` | 8.2175 | **8.2175** | **no** |
| `above_loc_max_obtainable` (rows TRUE) | 9 | **9** (should be 0) | **no** |

Causes: `summarise_max_obtainable_exposure()` computes the conditional crossing
with `duration_above_effect_metric()`, which has **no `loc` argument** and
implicitly solves dose = metric (LOC = 1); and `22_daily_timecourse.R` lines 57
and 135 hard-code `>= 1`. With a non-unit LOC the two "days above LOC" columns
in the *same summary row* would be computed against *different thresholds*, and
the boolean column would disagree with the closed-form duration. Harmless today
(every registered metric uses LOC = 1) but it is exactly the failure the constant
was introduced to prevent.

### A5. `duration_above_max_obtainable_rq()` — mathematics verified exactly
**Status: PASS**

I re-derived the piecewise solution independently before reading the
implementation. With `R` = seeds required (time-invariant), `A(t) = A₀·2^(−t/Dₛ)·MSA`,
`f₀ = A(0)/R`, and per-seed residue `∝ 2^(−t/Dᵣ)`:

* seed binds from `t* = Dₛ·log₂(f₀)` (0 if `f₀ ≤ 1`);
* for `t ≤ t*`: `RQ(t) = RQ₀ᶜᵒⁿᵈ·2^(−t/Dᵣ)`;
* for `t > t*`: `RQ(t) = RQ₀ᶜᵒⁿᵈ·f₀·2^(−t/Dₛ)·2^(−t/Dᵣ)`, which at `t*` equals
  `RQ₀ᶜᵒⁿᵈ·2^(−t*/Dᵣ)` (continuous), and thereafter
  `= RQ(t*)·2^(−(t−t*)/D_c)` with `1/D_c = 1/Dₛ + 1/Dᵣ`;
* hence the crossing is `t* + D_c·log₂(RQ(t*)/LOC)` when the conditional
  crossing exceeds `t*`, and the conditional crossing otherwise.

This is exactly what lines 42–64 implement, including the `f₀ ≤ 1` shortcut
(`rq_at_seed_limit <- max0`, correct because `max0 = cond0·f₀` when seed binds at
sowing).

Empirical verification against an **independently written** root-finder that
rebuilds `min(required, available(t)) · ai(t) / BW / metric − LOC` from raw day-0
columns and calls `uniroot(tol = 1e-12)`:

| Case | Rows | Max |closed − numeric| |
|---|---|---|
| A. Barley/high/broadcast, all 6 receptors × all metrics | 46 | 8.5e-14 |
| B. drill_spring (3.3% surface) | 46 | 1.1e-13 |
| C. `surface_seed_dt50_days = 200` | 46 | 9.9e-14 |
| D. `surface_seed_dt50_days = 2` | 46 | 1.5e-13 |
| E. `residue_dt50_days = 60`, `surface_seed_dt50_days = 5` | 46 | 2.5e-13 |
| F. `msa_m2 = 0.5` on all receptors (seed-limited from sowing) | 46 | 2.5e-13 |
| G. precision planting (0.5% surface, f₀ ≈ 0.007–0.039) | 6 | 0 |

Fine-grid cross-check also agrees: e.g. `bird_medium` acute closed form 4.7346 d
vs last grid day above LOC 4.70 on a 0.05 d grid. Closed-form edge cases all
behave correctly: `f₀ = 1` exactly → `10/3·log₂8 = 10`; `Dₛ = Inf` → conditional
crossing; `Dᵣ = Inf` → `t* + Dₛ·log₂(RQ₀/LOC)`; both `Inf` → `Inf`;
`max₀ = LOC` exactly → 0; `f₀ = 0` → 0; vectorised recycling correct.
`days_diet_fraction_feasible()` for the 100/50/25% annotations was likewise
matched against `uniroot` and against the audited workbook value 83.20397158607 d.

**Verdict: the "exact closed-form" claim is true.** It is genuinely exact, it is
not an approximation, and it correctly reproduces the grid-scan answer it
replaced, to ~1e-13 d over every scenario I could construct.

### A6. Single-figure plot functions silently accept multi-metric / multi-receptor input
**Status: ROBUSTNESS_ISSUE**

`plot_max_obtainable_exposure()` documents `@param timecourse … filtered to ONE
scenario_id x receptor_id x metric_id` but enforces nothing. Passing two metrics
produced a plot with 244 rows (two overlaid curve pairs, day-0 RQs 1.768 and
9.792) while the subtitle asserted only `"Bird acute screening — 43.1 mg
a.i./kg bw/day"`. Passing three receptors produced 366 rows while the title
asserted only `"— Small bird (20 g)"`. The result is a legitimately mislabelled
figure with no warning. `plot_seed_availability_vs_requirement()` has the same
shape. Not currently triggered by the Shiny module (which uses the small-multiple
function and subsets by receptor for the diagnostic) or by
`generate_priority_exposure_figures.R`, but both functions are `@export`ed and
this is a live footgun for scripted use. A `stbam_abort()` on
`length(unique(...)) > 1` would close it.

### A7. Shiny "Current assumptions" sidebar reports only the *first* receptor's MSA
**Status: CONFIRMED_ERROR (minor, display only)**

`44_module_max_obtainable.R` line 189: `m <- meta_list[[1]]` with the comment
`# scenario/agronomy/fate/metric shared across panels`. Body weight, food
requirement and **MSA are not shared across panels**: for birds the figure
contains a `bird_large` panel at **140 m²** while the sidebar states
`MSA (this taxon/metric): 70 m2 (short-term)`. Confirmed live:
`metadata_list[[1]]$msa_m2 = 70` while the per-receptor metadata is
`bird_small = 70 ; bird_medium = 70 ; bird_large = 140`. The figure's own
caption is correct (it lists all three); only the on-screen sidebar understates
the large-bird MSA by half. Same issue for the body-weight/FIR fields, which are
simply absent from the sidebar.

### A8. Caller-modified `receptors` tables are honoured for dose but ignored for the max-obtainable MSA
**Status: ROBUSTNESS_ISSUE**

`build_daily_timecourse()` re-derives `short_lookup`/`long_lookup` from `params`
by `receptor_id`, so a caller who hand-edits the receptors tibble gets an
internally inconsistent row. Demonstrated: setting `rec$msa_m2 <- 1000` and
`rec$body_weight_g <- 40` produced `body_weight_g = 40` (used in the
max-obtainable dose) but `max_obtainable_msa_m2 = 70` (from `params`, ignoring
the caller). For the MSA this is arguably the intended policy behaviour; the
concern is that it is silent and that the two receptor attributes are treated
inconsistently. Low practical risk — every in-repo call site builds receptors via
`resolve_receptors(params, …)`. Unknown receptor ids are caught loudly
(`check_choice` in `resolve_receptors`); duplicated receptor rows are tolerated
and produce duplicated output rows.

### A9. `duration_above_max_obtainable_rq()` accepts physically impossible inputs
**Status: ROBUSTNESS_ISSUE (minor)**

`duration_above_max_obtainable_rq(cond0 = 2, max0 = 8, …)` — a maximum-obtainable
RQ *above* the conditional RQ, which the model cannot produce — returns 10
without complaint. `NA`, negative values, `loc = 0` and `f₀ = Inf` are all
correctly rejected by `check_numeric`. Since `summarise_max_obtainable_exposure()`
always passes `day0$rq` and `day0$max_obtainable_rq` from the same row, the
invariant `max0 ≤ cond0` holds in practice; an explicit check would make the
function safe for direct use.

### A10. Missing `metadata_by_receptor` entries degrade to raw internal ids
**Status: ROBUSTNESS_ISSUE (minor)**

Dropping `bird_large` from `metadata_by_receptor` produced panel labels
`"Small bird (20 g) | Medium bird (100 g) | bird_large"` — a reader-facing figure
mixing readable labels with an internal id, silently. If the *first* receptor's
metadata is missing, `first_meta` is `NULL` and the caption/subtitle are built
from `NULL` fields (the caption's first line became the receptor line with an
empty MSA value rather than aborting).

### A11. Redundant duplicated summary columns
**Status: DOCUMENTATION_GAP (minor)**

`summarise_max_obtainable_exposure()` emits `day_conditional_below_loc` and
`days_above_loc_conditional` with byte-identical values (confirmed
`all(... == ...)` → TRUE), and likewise `day_max_obtainable_below_loc` /
`days_above_loc_max_obtainable`. The two names imply opposite quantities ("day it
falls below" vs "number of days above"); they happen to coincide because the
curve starts at its peak on day 0, but a downstream consumer could reasonably
mis-read one of them. Worth either documenting the identity or dropping the
duplicate pair.

### A12. `plot_exposure_processes()` panels A/C are inconsistent with panel D for mammals
**Status: CONFIRMED_ERROR (minor; birds unaffected)**

Panels A ("Surface seeds remaining") and C ("Active ingredient with surface
seed") are drawn from `surface_seeds_per_m2` / `surface_ai_mg_per_m2`, while
panel D ("Exposure feasibility, available / required seeds") is drawn from
`max_obtainable_diet_fraction`, which for mammals uses the full sown density.
Measured on the drill_spring mammal scenario: panel A day-0 value **15.51**
seeds/m²; panel D day-0 values 449.6 / 224.1 / 14.24 for small / medium / large
mammal, which are reproducible only from a **470 seeds/m²** pool
(e.g. `470 × 35 m² / (68.72 g ÷ 0.0595 g) = 14.24` for the large mammal). A
reader tracing panel A → panel D would be out by 30×. Panels A/C are also drawn
from `one$receptor_id[[1]]` only, which is fine (they are receptor-independent)
but only because the surface curves happen not to depend on the receptor —
whereas the *accessible pool* does. Birds (`surface_seed_only = TRUE`) are
unaffected, and the exported priority-figure batch is birds-only, so no figure
currently on disk is wrong.

---

## Assessment of the test suite

**Status: PARTIALLY ADVERSARIAL — DOCUMENTATION_GAP**

`test-10-max-obtainable-exposure.R` is better than a confirmation suite. It
contains genuine falsifiable content:

* **Real independent anchors.** `day_100pct_diet_unobtainable == 83.20397158607`
  is the audited workbook value `1!N79`, not a value read back out of the
  implementation. `format_metric_label` is asserted against a literal string.
* **Genuine orthogonality probes.** Four tests establish that surface-seed DT50
  moves availability but not residue-per-seed or conditional RQ; residue DT50
  moves dose but not seed counts; MSA moves availability but not conditional
  dose; the effects metric moves RQ but not dose. These are exactly the
  double-counting/cross-contamination failures that matter, and they are written
  as inequalities and equalities that would fail if the wiring were wrong.
* **Boundary case.** Zero surface seed → zero max-obtainable exposure *and* an
  unchanged conditional RQ.
* **Closed-form spot checks** at all three regimes of
  `duration_above_max_obtainable_rq()` with hand-written expected expressions
  (`5*log2(8)`, `(10/3)*log2(4)`, and a transition case), tolerance `1e-12`.

Gaps, in rough order of importance:

1. **No mammal max-obtainable *arithmetic* test.** Mammals are tested only for
   which MSA term/value is selected (`days = 0`, no dose/RQ assertions). Every
   quantitative test uses `bird_small`, i.e. the `surface_seed_only = TRUE`
   branch. The `SURFACE_PLUS_BURIED` branch — the one carrying the check-6 and
   A12 defects — is never exercised numerically.
2. **No fine-grid vs closed-form agreement test.** The three closed-form checks
   are algebraic identities on synthetic scalars; nothing compares
   `duration_above_max_obtainable_rq()` against a numerically-located crossing of
   a real `daily_timecourse`. That is the single test most likely to have caught
   a piecewise error (it would have passed — I ran it — but it is the missing
   guard).
3. **No test that the policy survives a hostile caller.** Nothing asserts that
   passing `resolve_receptors(..., msa_term = "long")` leaves
   `max_obtainable_msa_*` untouched, and `test-11` sets
   `inputs-msa_term = "short"` — the *benign* value — so the Shiny test never
   demonstrates that the global toggle fails to leak. Both are the feature's
   central safety property; both are currently unguarded by tests.
4. **No `bird_large` MSA = 140 assertion in the numeric path**, and no test that
   the small-multiple caption's per-panel MSA differs across panels (A7 would
   have been caught).
5. **No negative/misuse tests** for the plot functions (A6, A10) — every plot
   test is a happy path asserting `expect_s3_class(p, "ggplot")` plus a `grepl`
   on the caption.
6. **`test-11` is a smoke test only.** It asserts `expect_error(..., NA)` on three
   outputs; it never inspects a single rendered value. It does establish that the
   reactive graph wires up, which is what its header claims.
7. **Footnote tests check for presence, not correctness.** `grepl("70 m2", full)`
   would pass if the 70 came from the wrong column; no test compares a footnote
   number against the canonical column it should have come from.

None of the gaps mask a defect in the *calculation*; they mask the reporting
defects found in check 6, A7 and A12.

---

## Overall verdict

**19 items checked** (7 numbered checks + 12 additional findings):
**PASS 8**, **CONFIRMED_ERROR 3**, **POTENTIAL_ERROR 2**,
**ROBUSTNESS_ISSUE 4**, **DOCUMENTATION_GAP 3** (one item, check 6, is scored as
CONFIRMED_ERROR; check 7 is scored PASS with its documentation gaps rolled into
A-items), **REQUIRES_HUMAN_REVIEW 1**.

| Item | Status |
|---|---|
| 1. Double-counting | PASS |
| 2. MSA applied as intended | PASS |
| 3. Food-requirement cap | PASS |
| 4. Units | PASS |
| 5. Acute/chronic pairing vs MAIN-P000209 | PASS |
| 6. Footnote accuracy | CONFIRMED_ERROR |
| 7. Figures self-contained | PASS |
| A1. Mammal accessible pool = all sown seed at surface DT50 | REQUIRES_HUMAN_REVIEW |
| A2. `msa_m2` override collapses short/long, term still asserted | POTENTIAL_ERROR |
| A3. Bird `msa_long_term_m2` values not in MAIN-P000209 | DOCUMENTATION_GAP |
| A4. `STBAM_DEFAULT_LOC` not honoured end-to-end | POTENTIAL_ERROR |
| A5. `duration_above_max_obtainable_rq()` closed form | PASS |
| A6. Single-figure fns accept multi-metric input | ROBUSTNESS_ISSUE |
| A7. Shiny sidebar reports only first receptor's MSA | CONFIRMED_ERROR |
| A8. Caller-modified receptors table partially ignored | ROBUSTNESS_ISSUE |
| A9. `max0 > cond0` accepted | ROBUSTNESS_ISSUE |
| A10. Missing metadata degrades to internal ids | ROBUSTNESS_ISSUE |
| A11. Duplicated summary columns | DOCUMENTATION_GAP |
| A12. Process figure panels A/C vs D inconsistent for mammals | CONFIRMED_ERROR |
| Test suite | DOCUMENTATION_GAP (partially adversarial) |

### What can be trusted

* **The calculation itself.** The maximum-obtainable dose/RQ chain is
  dimensionally correct, applies each of the two first-order processes exactly
  once, and correctly caps consumption at `min(food requirement, seed available
  within the applicable MSA)`. Verified by hand recomputation (rel. err ≤ 1.2e-16)
  and by empirical half-life regression in both regimes.
* **The MSA policy.** `resolve_msa_term_for_metric()` is a faithful, correct
  encoding of MAIN-P000209 as I read it independently, and it is applied
  correctly across all 27 receptor × duration × role combinations, including the
  140 m² large-bird value. It cannot be overridden by the global `msa_term`
  toggle, by a hostile caller-supplied receptors table, or by any control on the
  tab itself. **The bug this feature exists to prevent is genuinely prevented.**
* **`duration_above_max_obtainable_rq()`.** The "exact closed-form" claim is
  true. Independently derived and matched against independent root-finding to
  ≤ 2.5e-13 d across 7 scenario families and 282 receptor/metric rows, including
  `Inf` DT50s, `f₀ ≤ 1`, `f₀ = 1` exactly, and seed-limited-from-sowing cases.
  It is a real improvement over the grid scan it replaced.
* **Bird figure captions and footnotes.** Every number checked traces to canonical
  model data; nothing is invented; the free-y note is honest; the two series are
  never conflated. A bird figure is genuinely interpretable without Shiny.
* All 128 static figures currently in `outputs/figures/` are bird-only and are
  unaffected by the mammal defects.

### What cannot be trusted

* **Any mammal maximum-obtainable figure, footnote, or "Current assumptions"
  panel produced for a drill or precision scenario.** The stated initial surface
  seed density is not the seed pool the curve uses (15.5 vs 470 seeds/m² in the
  worked example — 30×). The arithmetic is right; the reported basis is not. Do
  not circulate a mammal figure from this feature until the footnote reports
  `accessible_pool_basis` / `accessible_seeds_per_m2_t`.
* **The large-bird MSA as shown in the Shiny sidebar** (says 70 m², figure uses
  140 m²). The exported caption is correct; the on-screen panel is not.
* **Any figure produced by calling `plot_max_obtainable_exposure()` or
  `plot_seed_availability_vs_requirement()` from a script without pre-filtering**
  to a single scenario/receptor/metric — the label will not match the data and
  nothing will warn you.
* **Any scenario carrying an `msa_m2` override** — the footnote will still cite
  MAIN-P000209 as the basis for a value that is not the assessment's.

### Needing human (subject-matter) judgement

1. **A1** — is it defensible that mammals access 100% of sown seed (including
   drilled/buried seed) within 35 m², and that this pool decays at the
   *surface*-seed DT50? This assumption is inherited, but the new feature
   promotes its consequence from a diagnostic flag to a headline "maximum
   obtainable RQ". This is the one item where a wrong answer would make a
   *number*, not just a caption, wrong.
2. **A3** — should birds retain `msa_long_term_m2` values at all, given the
   assessment did not consider a long-term MSA for birds, and should the legacy
   "Exposure feasibility" tab still allow selecting them?
3. Whether `duration_class` (rather than `metric_role`) is the correct
   discriminator for the mammal short/long split when applied to the
   `REFINED_ADDITIONAL` metrics. I judged it correct from the paragraph's wording,
   but the paragraph does not address refined-additional endpoints explicitly.

### Reproduction environment

All probes were run with `Rscript.exe` 4.4.3 from the project root after
`source("R/load_model.R"); load_stbam(".", include = c("core","reporting","shiny"))`.
Probe scripts were written to a scratch directory outside the project and no
project file was created or modified by this review other than this document.
