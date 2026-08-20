# Independent audit of the `stbam` calculation engine

**Auditor role:** independent adversarial scientific/numerical review. The auditor
had not seen this engine before and did not write any part of it, its
specification, its reference data or its test suite.

**Date of audit:** 2026-08-20
**Engine reviewed at:** git branch `main`, baseline commit
*"Baseline: pre-independent-audit recovered implementation"*. Nothing was
committed, and no file under `R/`, `data/reference/`, `tests/`, `app/` or
`scripts/` was modified.

**Companion file:** `audit/independent_engine_findings.csv` — one row per checked
item, with the independent value, the engine value, the workbook value where one
was read, and a status.

---

## 1. How this audit was done, and why that matters

The team that wrote the R code also wrote the specification and the test suite.
A test that passes therefore proves only that the code agrees with itself. To
break that circularity the audit used four separate lines of evidence:

1. **First-principles re-derivation.** Every equation in the calculation chain
   was re-implemented from scratch, in Python, by the auditor, working only from
   the equations stated in `docs/scientific_model_specification.md` and from
   dimensional analysis. That script does not import, source or call anything
   under `R/calculations`, `R/inputs` or `R/summaries`. It reads only the raw
   reference CSVs, which are data rather than calculation logic.

2. **Direct reading of the primary audited workbook.** The source workbook
   `THE 1 small cereals ... 08MAY2026.xlsm` was opened **statically** as an
   OOXML zip archive using a purpose-written, standard-library-only Python
   reader. Excel was never launched; no macro was executed; no formula was
   recalculated. Both the stored formula text and Excel's cached result were
   read for each cell. The project's own `scripts/workbook_static.py` was read
   for reference but deliberately **not** imported, so that the workbook
   evidence is independent of project code.

3. **The engine itself**, run through `Rscript` after
   `source("R/load_model.R"); load_stbam(".", include = c("core","reporting"))`,
   calling the real exported functions and the real canonical-dataset builders.

4. **The prior reconstructed fixture set**
   (`inst/fixtures/bird_small_cereals_calculation_checks.csv`), treated as a
   third opinion, not as truth.

The auditor computed lines 1 and 2 **before** reading any file under
`R/calculations`, `R/inputs` or `R/summaries`.

### Workbook integrity

The SHA-256 of the source workbook was recorded before any reading and again
after all reading was complete:

```
before: 71440554B7B2134CAD5C59AB4F474FF081064BEB9D2467428EB9B0DE08FF8F93
after : 71440554B7B2134CAD5C59AB4F474FF081064BEB9D2467428EB9B0DE08FF8F93
```

These are identical and both match the expected value supplied with the audit
instruction. **The source workbook was not modified by this audit.**

### One caveat on the audited tree

The audit was told that a baseline commit was in place and that the tree would be
static. It was not entirely static. Two things changed under audited paths during
the audit window, neither of them by the auditor (the auditor wrote only the two
files named at the top of this report):

- `scripts/reviewer_validation_walkthrough.R` did not exist in the auditor's
  first directory listing and was present later. It is not part of the
  calculation chain — `load_stbam()` sources only `R/calculations`, `R/inputs`,
  `R/summaries`, `R/validation`, `R/reporting` and `R/shiny`, never `scripts/` —
  so it cannot affect any result in this report.
- `R/load_model.R` acquired a newer modification timestamp. Its content was
  re-read afterwards and is byte-for-byte what the auditor originally read, so no
  functional change occurred.

As a precaution the auditor re-ran the headline chain after detecting this. Dose
per seed (0.00744), field rate (13.392), surface density (180), EDE
(76.1815540021432), chronic RQ (9.791973522126375), duration above the metric
(32.91599656932871), feasible dietary fraction (6152.670500615 %), required
search area (1.137717353676 m²) and days at full diet (83.20397158607) were all
unchanged and still match the workbook cells cited later in this report. **The
findings below stand.** The tree should nonetheless be re-verified against the
baseline commit before this audit is relied on formally.

### Scenarios re-derived independently

Fifteen scenario variants were carried end to end, chosen to span the required
spread:

| Label | Crop | Rate | Unit | Planting | Bounds | Receptor | Diet |
|---|---|---|---|---|---|---|---|
| S01 / S01b | Barley | 300 | mg a.i./kg seed | broadcast | low / low TKW | small bird | 1.00 |
| S02 | Barley | 300 | mg a.i./kg seed | spring drill | low / high TKW | small bird | 1.00 |
| S03 | Barley | 300 | mg a.i./kg seed | broadcast | low / low TKW | small bird | 0.10 (near threshold) |
| S04 | Buckwheat | 200 | mg a.i./kg seed | spring drill | high / low TKW | medium bird | 0.25 |
| S05 | Winter wheat | 300 | mg a.i./kg seed | broadcast | low / high TKW | small mammal | 0.50 |
| S06 | Pearl millet | 100 | mg a.i./kg seed | spring drill | low / low TKW | large mammal | 0.10 |
| S07 | Oat | 200 | mg a.i./kg seed | fall drill | high / low TKW | large bird | 1.00 |
| S08 | Soybean | 0.045 | **mg a.i./seed** | precision | high / low TKW | medium mammal | 0.50 |
| S09 | Cucumber (processing) | 0.25 / 0.75 | **mg a.i./seed** | precision | low / high TKW | small bird | 1.00 |
| S10 | Barley | **0** | mg a.i./kg seed | broadcast | low / low TKW | small bird | 1.00 (edge) |
| S11 | Barley | 300 | mg a.i./kg seed | broadcast | low / low TKW | small bird | **0.00** (edge) |
| S12 | Sugar beet | 300 | mg a.i./kg seed | precision | low / low TKW | small bird | 1.00, **DT50 = Inf** |
| S13–S15 | Barley variants for the doubling, TKW-override and MSA-override tests |

Beyond these, closed-form identities were checked across **all 348** small-cereals
scenario-input rows and **125,280** daily time-course rows.

---

## 2. Agronomic conversions

### 2.1 What was checked and how

Seed mass from thousand-seed weight and back; mass-basis to count-basis seeding
rate and back; seeds per hectare to seeds per square metre; treatment loading in
both rate-unit directions; field loading; initial surface seed density by
planting method; and the reciprocal mean area per surface seed.

The auditor computed each from the raw numbers, then read the corresponding
workbook cell, then ran the engine.

### 2.2 Results

Every one of these reproduced **exactly** — to the last stored digit of the
workbook's own cached value.

| Quantity | Workbook cell | Workbook value | Independent | Engine |
|---|---|---|---|---|
| Dose per seed, barley 300 mg/kg, TKW 24.8 | `Seed Inputs and EECs!Q4` | 0.00744 | 0.00744 | 0.00744 |
| Dose per seed, barley 300 mg/kg, TKW 59.5 | `Seed Inputs and EECs!R4` | 0.01785 | 0.01785 | 0.01785 |
| Field rate, barley low bound | `Seed Inputs and EECs!W4` | 13.392 | 13.392 | 13.392 |
| Field rate, barley high bound | `Seed Inputs and EECs!X4` | 83.895 | 83.895 | 83.895 |
| Surface density, broadcast, barley low | `Seed Inputs and EECs!AC4` | 180 | 180 | 180 |
| Surface density, spring drill, barley low | `Seed Inputs and EECs!AE4` | 5.94 | 5.94 | 5.94 |
| Surface density, fall drill, barley low | `Seed Inputs and EECs!AG4` | 16.56 | 16.56 | 16.56 |
| Area per surface seed, broadcast | `Seed Inputs and EECs!AK4` | 0.0055555555555556 | same | same |

The workbook's own formula for dose per seed is
`EEC / (1000000 / TKW)`, which is algebraically identical to the
`C_seed × TKW / 1e6` form the engine uses. The workbook's surface-fraction
values (`General Look ups!G2:G5` = 0.033, 0.092, 0.005, 1) match
`planting_method_parameters.csv` exactly.

Across all 348 small-cereals rows, the following identities held to machine
precision or exactly:

- `seed_mass_g == tkw / 1000` — bit-for-bit identical.
- `seeds_per_m2 == seeds_per_ha / 10000` — bit-for-bit identical.
- `field_rate == concentration / 1000 × seeding_rate_kg_per_ha` — relative error 0.
- `field_rate == dose_per_seed × seeds_per_ha / 1000` — relative error 2.2e-16.
- `initial_surface_seeds_per_m2 == seeds_per_ha / 1e4 × surface_fraction` — relative error 0.
- `area_per_surface_seed × surface_density == 1` — relative error 1.1e-16.
- `seeds_per_ha × TKW / 1e6 == seeding_rate_kg_per_ha` — relative error 1.3e-16.
- Mass↔count round trip, TKW↔seed-mass round trip, and rate-unit round trip — all
  exact (relative error 0).

**Unit sweep conclusion.** The auditor traced every kg↔g↔mg factor, every
ha↔m² factor and every %↔fraction factor in the chain. The only numeric factors
used are `/1000` (g→kg and mg→g), `/1e6` (mg/kg × g/1000-seeds → mg/seed),
`/10000` (ha→m²) and `×100` (fraction→percent, only in the two reported
percentage columns). No factor is duplicated, omitted or inverted. The engine
never applies a percentage where a fraction is required: `surface_seed_fraction`
and `diet_fraction` are validated to lie in [0, 1] and are stored as fractions
throughout, with percentages produced only at the reporting boundary.

### 2.3 The one substantive finding: what "seeding-rate bound" means

**This is the most important finding of the audit.** It is not a numerical
error, but it is a divergence between the model's canonical contract and the
model's behaviour, and it can be misread in a regulatory table.

Specification §4.2 states a **one-dimensional** rule with a deliberate
asymmetry:

> `seeds_per_ha_low` = direct value if supplied, else the low mass rate converted
> using the **high** TKW; `seeds_per_ha_high` = direct value if supplied, else the
> high mass rate converted using the **low** TKW.

The engine does **not** implement this. `resolve_seeding()` in
`R/summaries/20_scenario_inputs.R` recomputes the seed count at whichever TKW the
grid cell selects, so `seeds_per_ha` depends on **both** axes. For a crop whose
seeding rate is supplied on a mass basis, one gets four distinct seed counts, not
two:

| Crop | low / low TKW | low / high TKW | high / low TKW | high / high TKW | Spec §4.2 "low" | Spec §4.2 "high" |
|---|---:|---:|---:|---:|---:|---:|
| Buckwheat | 689,655 | 536,193 | 3,103,448 | 2,412,869 | 536,193 | 3,103,448 |
| Pearl millet | 1,056,604 | 861,538 | 6,415,094 | 5,230,769 | 861,538 | 6,415,094 |
| Oat | 1,992,593 | 1,169,565 | 5,814,815 | 3,413,043 | 1,169,565 | 5,814,815 |
| Winter wheat | 1,500,000 | 600,000 | 5,500,000 | 5,500,000 | 600,000 | 5,500,000 |

**Which of these is right?** The auditor went to the primary workbook. The
workbook's `Seeding Assumptions` sheet contains exactly this 2 × 2 block in
columns J, K, L and M:

- `J` = low mass rate ÷ low seed weight
- `K` = low mass rate ÷ high seed weight
- `L` = high mass rate ÷ low seed weight
- `M` = high mass rate ÷ high seed weight

The engine's four values reproduce workbook `J20/K20/L20/M20` (buckwheat),
`J54/K54/L54/M54` (pearl millet), `J62/K62/L62/M62` (oat) and `J84/K84`
(winter wheat) **to the last digit**. The spec's two values are `K` and `L`
only — the outer bracketing pair, which is what the workbook's *summary* columns
`Seed Inputs and EECs!AC/AD` use.

So both are present in the source. The engine chose the full grid; the
specification documents only the bracket. Two further observations settle which
is scientifically preferable:

1. **The engine's choice keeps each output row internally consistent.** In the
   engine, `seeds_per_ha × TKW / 1e6` always equals `seeding_rate_kg_per_ha` for
   the TKW shown on that row. If one instead followed §4.2 literally *and* kept
   the seed-mass axis, one would produce rows in which the seed count was derived
   at one TKW while the seed mass shown was a different TKW — an internally
   incoherent row. The auditor's own first-principles script, written to the
   letter of §4.2, produced exactly such incoherent rows (for example pearl
   millet: 861,538 seeds/ha derived at TKW 6.5 g, presented alongside a seed mass
   of 0.0053 g). The engine avoids this.

2. **The workbook is itself internally inconsistent here, and only for crops
   whose seeding rate is supplied on a mass basis.** On the buckwheat crop sheet
   (sheet `7`), cell `D7` reports the "low" broadcast surface density as
   **53.62 seeds/m²** (derived from column `K`), while cells `J79` and `M20` on
   the *same sheet* compute the seed pool and the required search area from
   column `J`, i.e. **68.97 seeds/m²**. The workbook therefore uses two different
   "low bound" seed densities in two places. The engine cannot match both; it
   consistently matches the `J`/`K`/`L`/`M` convention used in the crop-sheet
   feasibility calculations.

**What this means for a reader of the engine's output.** A reviewer who filters
the canonical `scenario_inputs` dataset on `seeding_rate_bound == "low"` for
winter wheat will see two rows: 600,000 seeds/ha and 1,500,000 seeds/ha. Only
the first matches the figure the workbook and the specification call the "lower
bound". The second is a legitimate, workbook-derived grid cell, but it is **2.5×
higher** and is labelled "low". Presented in a regulatory table without the
`seed_mass_bound` column visible, that is a real misreading hazard.

**Mitigating facts, established by the auditor:**

- The minimum and maximum of the engine's 2 × 2 grid coincide **exactly** with
  the specification's `seeds_per_ha_low` and `seeds_per_ha_high`. Any range
  reported across the grid is therefore correct.
- **No dose, EDE or risk quotient is affected.** For a rate expressed in
  mg a.i./kg seed, exposure does not depend on seed mass or seed count at all
  (see §4). The auditor confirmed this exhaustively over 125,280 rows.
- **No feasibility fraction or required search area is affected either**, for
  mass-supplied crops. The auditor proved algebraically and then confirmed
  numerically that `seeds_per_m2 × seed_mass_g` reduces to
  `seeding_rate_kg_per_ha / 10`, independent of TKW. Engine output for buckwheat:
  `max_feasible_diet_fraction` = 2756.5728049350 % at *both* TKW cells, matching
  workbook `7!M79` = 2756.5728049350646 %; `required_search_area` = 2.53938513340
  m² at both, matching workbook `7!M20` = 2.5393851334047737 m².
- What *is* affected is the set of raw seed-count columns: `seeds_per_ha`,
  `seeds_per_m2`, `initial_surface_seeds_per_m2`, `area_per_surface_seed_m2`,
  `available_seeds_within_msa` and `seeds_required_full_diet`.

**Recommendation.** Do not change the code. Correct §4.2 of the specification to
describe the 2 × 2 seed-count grid that is actually implemented, cite
`Seeding Assumptions!J:M` as its provenance, state explicitly that the outer
bracket (`K`, `L`) is the pair the source Word tables report, and record the
workbook's own `D7`-versus-`J79` inconsistency as a known source-document defect.
Any regulatory table drawn from this engine must display `seed_mass_bound`
alongside `seeding_rate_bound`, or must be built from the min/max summary.

### 2.4 Two smaller documentation defects in the same area

- **The §4.1 citation does not support the claim it is attached to.** §4.1 says
  inspection of `Seed Inputs and EECs!AC:AR` confirms the two bounds are used as
  independent axes. The auditor read that range: its header row (`AC3:AR3`) is
  labelled only "Low Seeding Rate" / "High Seeding Rate". There is **no**
  seed-weight axis anywhere in `AC:AR`. The evidence for an independent 2 × 2
  does exist, but it is on the crop sheets (rows 19–27 and 79–82) and in
  `Seeding Assumptions!J:M` — not in `AC:AR`. The second half of the §4.1
  citation ("crop sheet rows 7–11 and 19–21") is correct.

- **The reference CSV carries two columns the engine never reads.**
  `crop_seeding_parameters.csv` contains `seeds_per_ha_low`, `seeds_per_ha_high`
  and their `_basis` columns, which encode the §4.2 bracketing rule. Nothing in
  `R/calculations`, `R/inputs` or `R/summaries` uses them; they are read only by
  the Shiny input module and by one assertion in `test-07`. A reviewer comparing
  those columns to the engine's `seeds_per_ha` output will see apparent
  mismatches that are in fact this same definitional difference.

- **The engine reports four field rates per crop and rate level; the workbook
  reports two.** The workbook computes only `W` (low bound × low seed weight) and
  `X` (high bound × high seed weight). The engine's other two cells — for barley,
  32.13 and 34.968 g a.i./ha — are internally consistent and correctly derived,
  but have no counterpart in the audited source and should not be presented as
  workbook-reproduced values.

---

## 3. Receptor food requirement

Food ingestion rate is `FIR = a × BW^b`. The auditor computed all six receptor
values from the coefficients, then read the workbook's `FIR Assumptions` sheet,
whose formula is literally `D3*(B3^E3)`.

| Receptor | BW (g) | a | b | Workbook `F` cell | Independent | Engine |
|---|---:|---:|---:|---|---|---|
| Small bird | 20 | 0.398 | 0.850 | F3 = 5.0787702668095474 | 5.078770266809547 | 5.078770266809547 |
| Medium bird | 100 | 0.398 | 0.850 | F4 = 19.94725189836544 | 19.947251898365437 | 19.94725189836544 |
| Large bird | 1000 | 0.648 | 0.651 | F5 = 58.153385883648525 | 58.15338588364852 | 58.15338588364852 |
| Small mammal | 15 | 0.235 | 0.822 | F6 = 2.1767816975014869 | 2.176781697501487 | 2.176781697501487 |
| Medium mammal | 35 | 0.235 | 0.822 | F7 = 4.3680921800285555 | 4.368092180028557 | 4.368092180028557 |
| Large mammal | 1000 | 0.235 | 0.822 | F8 = 68.717580879318348 | 68.71758087931836 | 68.71758087931836 |

All agree to within one unit in the last place of a double-precision number.

**Dry-weight basis — checked adversarially.** §8 and §14 claim no dry-to-fresh
conversion is applied. The auditor verified this two ways. First, the R function
`food_requirement()` is `coefficient_a * body_weight_g^exponent_b` and nothing
else; no other function multiplies FIR by a moisture term. Second — and more
tellingly — the workbook's `FIR Bird Regressions` and `FIR Mammal Regressions`
sheets **do** carry a `Water Content (%)` column (`H`), populated for the Nagy
et al. 1999 rows (9.3 % for seeds, 69 % for insects). The `FIR Assumptions`
formula `D*(B^E)` does not reference column `H` at all. So the source workbook
holds moisture data and deliberately does not use it, and the engine matches
that. The claim in §14 is substantiated.

Seeds required per day (`FIR / seed mass × diet fraction`) reproduced the three
fixture cases exactly: 204.789 seeds/d (small bird, 24.8 g TKW), 3068.808 seeds/d
(medium bird, 6.5 g TKW), 4473.337 seeds/d (large bird, 13 g TKW).

Maximum search areas and the "surface seed only" flag were read directly from
`Further Risk Characterization!C11:D13`, `E11:E13`, `H11:I13` and `J11:J13`:
birds 70/35 m² (small, medium) and 140/70 m² (large) with the flag set to `Y`;
all mammals 70/35 m² with the flag set to `N`. `receptor_parameters.csv` matches
cell for cell, and the engine's `accessible_pool_basis` column correctly reports
`SURFACE_SEED_ONLY` for birds and `SURFACE_PLUS_BURIED` for mammals.

---

## 4. Exposure, dose and risk quotient

### 4.1 Estimated daily exposure

The workbook's `BAM EDEs` sheet computes `EEC * FIR / BW`. The auditor read the
cached value for barley at the high rate, small bird:

```
workbook BAM EDEs!F2 = 76.181554002143201
independent          = 76.1815540021432
engine ede_full_diet = 76.1815540021432
```

Exact agreement. The medium-bird 25 % case (14.96043892377408) and the
large-bird 200 mg/kg 50 % case (5.815338588364853) likewise agree with both the
workbook chain and the auditor's arithmetic.

**Both forms of EDE agree.** The concentration form
`C_seed × FIR / BW × p_diet` and the per-seed form
`n_req × D_seed / (BW/1000)` were computed independently for every scenario. The
largest absolute disagreement seen anywhere was 1.4 × 10⁻¹⁴ mg/kg bw/day on a
value of 76.18, i.e. a relative difference of about 2 × 10⁻¹⁶ — pure
floating-point rounding, exactly as the specification predicts.

**EDE does not depend on the seed-mass bound** when the rate is in
mg a.i./kg seed. The auditor confirmed this three ways: the workbook's own
`BAM EDEs!F2` and `G2` (low and high seed weight) hold the identical number;
the auditor's independent arithmetic gives the same; and across all 125,280
engine time-course rows with a mass-basis rate, every group defined by
crop × rate × method × seeding bound × receptor × metric × diet × day had a
single distinct dose value across the two TKW cells. This is specification
invariant 15, and it holds.

### 4.2 Risk quotient

`RQ = dose / effects metric`. Over all 125,280 rows the engine's `rq` column and
a freshly computed `dose_mg_kg_bw_day / effects_metric` were compared with R's
`identical()`, which requires bit-for-bit equality of the double representation.
The result was `TRUE`, and the maximum absolute difference was exactly 0. The
requirement "exactly, not approximately" is met.

Likewise `dose_mg_kg_bw_day` was bit-for-bit identical to
`initial_dose × 2^(-day/10)`.

Effects-metric values were checked against the workbook's
`Further Risk Characterization!E18:E26` and `K18:K26` (the additional avian and
mammalian metrics) — 67, 104, 155, 10.8, 33.8, 78 for birds and 314, 500, 50,
79, 150 for mammals — all matching `effects_metrics.csv`. A bird is never
assessed against a mammalian metric: the auditor confirmed the taxon join is
sound over 384 crossed rows, and every row's `effects_metric` equals the value
stored for its `metric_id`. Screening and refined metrics carry distinct
`metric_role` labels and are never combined into one quotient.

### 4.3 Duration above an effects metric

`days = DT50_residue × log2(EDE / M)`, zero when `EDE ≤ M`. The workbook
implements this as `LN(M/EDE) / (LN(0.5)/Diss_half_life)`, which is the same
expression. The auditor read the cached workbook value:

```
workbook 1!P285 = 8.2175384794260236   (small bird, 300 mg/kg, acute screen)
independent     = 8.217538479426024
engine          = 8.217538479426024
```

Three further cases (27.06637156, 9.43310443, 11.65055538) matched the
independent values and the fixture set to eight significant figures. Where
`EDE ≤ M` the engine returns exactly 0, never a negative number.

### 4.4 Screening clothianidin conversion — §9.7 verified

The auditor searched the entire repository for every occurrence of
`screening_clothianidin_equivalent` and of `STBAM_CLOTHIANIDIN_MOLAR_RATIO`.

- `STBAM_CLOTHIANIDIN_MOLAR_RATIO` is defined once, in
  `R/calculations/00_validation.R`, as `249.68 / 291.7`.
- `screening_clothianidin_equivalent()` is defined once, in
  `R/calculations/01_seed_parameters.R`, and multiplies its argument by that
  ratio.
- **It has zero call sites anywhere in the production code.** The only other
  reference in the whole repository is a single unit test.
- It is therefore not reachable from `estimated_daily_exposure()`,
  `risk_quotient()`, `build_scenario_inputs()`, `build_exposure_grid()`,
  `build_daily_timecourse()`, `build_scenario_summary()` or
  `build_table162_support()`. No canonical dataset column is a clothianidin
  equivalent, and `effects_metrics.csv` contains no clothianidin rows.

The specification's claim that the conversion "is never applied silently" is
correct — it is in fact never applied at all in the current chain, which is the
strongest possible form of the guarantee. Minor note: §9.7 quotes the ratio as
0.8560; the exact value is 0.85594789…, so 0.8560 is a four-figure rounding, not
a discrepancy.

---

## 5. Time-dependent behaviour

### 5.1 The two half-lives really are separate

This was checked at four levels.

1. **In the source workbook.** Two *distinct named ranges* exist:
   `Diss_half_life` → `Further Risk Characterization!$E$4` (value 10 d, residue)
   and `surface_seed_loss_half_life` → `Further Risk Characterization!$J$4`
   (value 14 d, surface seed). The auditor scanned every formula on every sheet
   for any identifier containing "half": only these two names appear, and both
   are used on the crop sheets. There is no third, shared, or hard-coded
   half-life anywhere in the workbook.

2. **In the reference data.** `dissipation_parameters.csv` carries
   `residue_dt50_days = 10` and `surface_seed_dt50_days = 14` as separate rows
   with separate source citations.

3. **In the code.** `resolve_dissipation()` returns two independently resolved
   values. `build_daily_timecourse()` binds `residue_dt50` to
   `ai_per_seed_over_time()` and `daily_dose_over_time()`, and `surface_dt50` to
   `surface_seed_over_time()` and `days_diet_fraction_feasible()`. The auditor
   found no place where one is substituted for the other and no hard-coded
   numeric half-life.

4. **By experiment.** Overriding the residue DT50 to 3 d left the surface DT50 at
   14 d, and vice versa (overriding the surface DT50 to 40 d left the residue at
   10 d). With the residue DT50 set to 3 d, the dose at day 3 was exactly half
   the dose at day 0, while the surface seed density at day 14 was exactly half
   its day-0 value — i.e. the two processes decayed on their own clocks.

### 5.2 Decay form

The workbook writes `value * EXP(day * LN(0.5) / DT50)`; the engine writes
`2^(-day/DT50)`. These are the same function. The auditor confirmed numerically:
the workbook's cached day-1 and day-2 concentrations for barley at the low rate
(93.30329915368074 and 87.055056329612412 from 100) equal `100 × 2^(-1/10)` and
`100 × 2^(-2/10)` to full precision.

### 5.3 Combined surface loading

The engine computes `A_area(t) = S(t) × A_seed(t)` — the product of the two
processes, not a single averaged process. The auditor verified that
`surface_ai_mg_per_m2` is bit-for-bit identical to
`surface_seeds_per_m2 × ai_per_seed_mg` across all 125,280 rows, and that this
product agrees with the closed-form combined half-life
`DT50_combined = 14 × 10 / 24 = 5.8333 d` to a maximum absolute difference of
8.9 × 10⁻¹⁶ mg/m². Both the product and each component are exposed as separate
columns, so a reader cannot accidentally conflate them.

### 5.4 Monotonicity and the pelleted-seed case

- `S(t)` is non-increasing in `t` for every scenario tested (checked at 0.5-day
  resolution out to 60 days, and per-scenario across the full canonical dataset).
- `A_seed(t)` is non-increasing likewise. Neither ever increases.
- With `DT50_residue = Inf`, `A_seed(t)` is exactly constant at `D_seed` for all
  `t` — the auditor's independent value and the engine's agree, and
  `first_order_remaining(t, Inf)` returns exactly 1 rather than `NaN`. The same
  holds for `DT50_surface = Inf`.
- With `DT50_residue = Inf` and `EDE > M`, `duration_above_effect_metric()`
  returns `Inf`. This is the mathematically correct answer (the dose never falls
  below the metric) and matches the auditor's independent derivation. The
  function special-cases it rather than evaluating `Inf × log2(...)`.

---

## 6. Maximum-search-area feasibility

### 6.1 Values reproduced against the primary workbook

| Quantity | Workbook cell | Workbook value | Independent | Engine |
|---|---|---|---|---|
| Seeds in 70 m² MSA, barley broadcast low | `1!J79` | 12,600 | 12,600 | 12,600 |
| Seeds in 70 m² MSA, buckwheat broadcast low | `7!J79` | 4827.5862068966 | 4827.586206897 | 4827.586206897 |
| % of daily diet available, barley low, low TKW | `1!K79` | 6152.6705006151 | 6152.670500615 | 6152.670500615 |
| % of daily diet available, barley low, high TKW | `1!M79` | 14761.447370427 | 14761.44737043 | 14761.44737043 |
| % of daily diet available, buckwheat low | `7!M79` | 2756.5728049351 | 2756.572804935 | 2756.572804935 |
| Required search area, barley broadcast low, high seed count | `1!M20` | 1.1377173536760 | 1.137717353676 | 1.137717353676 |
| Required search area, barley broadcast low, low seed count | `1!K20` | 0.4742082415322 | 0.474208241532 | 0.474208241532 |
| Required search area, barley spring drill low | `1!K22` | 14.369946713096 | 14.36994671310 | 14.36994671310 |
| Required search area, buckwheat broadcast low | `7!M20` | 2.5393851334048 | 2.539385133405 | 2.539385133405 |
| Days at ≥100 % diet, barley broadcast low | `1!N79` | 83.203971586067 | 83.20397158607 | 83.20397158607 |
| Days at ≥100 % diet, barley spring drill low, high TKW | `1!P81` | 31.980202941135 | 31.98020294113 | 31.98020294113 |
| Days at ≥100 % diet, buckwheat broadcast low | `7!P79` | 66.987253205728 | — | — |

Agreement is to 13–16 significant figures throughout. The auditor also confirmed
the fixture set's independently reconstructed values: 4134.86 % (wheat lower
broadcast, small bird), 104.2249 % (buckwheat upper spring drill, medium bird),
25.1715 d (oat upper fall drill, large bird) and 2.843077 seeds/m² (pearl millet
spring drill, low bound at high TKW) — all reproduced by both the auditor and
the engine.

The workbook computes availability on a **mass** basis
(`100 × (kg/ha ÷ 10000 × 1000 × MSA) ÷ FIR`) while the engine computes it on a
**count** basis (`S(t) × MSA × m_seed ÷ FIR`). The auditor confirmed these are
algebraically identical and that they agree numerically to 1 part in 10¹⁵.

The identity `required_search_area(t) × S(t) = n_req` held with a maximum
relative error of 2.1 × 10⁻¹⁶ across the full canonical dataset.

The `surface_seed_only = FALSE` path for mammals was verified against the
workbook's `IF(SSA_bird_small="Y", Method_standard_spring, 1)` construction on
the crop sheets: when the flag is `N`, the surface fraction is replaced by 1, so
the accessible pool is the full sown density. The engine does the same via its
`accessible_seeds_per_m2` column and labels it `SURFACE_PLUS_BURIED`.

### 6.2 Feasibility is a diagnostic, not a cap — §10.3 verified

This was the second claim the auditor set out to break, and it holds.

- **By code reading.** The auditor read all of `R/calculations/05_feasibility.R`
  and the two builders. No function in the feasibility file returns or modifies a
  dose, an EDE or an RQ. In `build_daily_timecourse()`, `dose_mg_kg_bw_day` is
  computed from `initial_dose_mg_kg_bw_day` and the residue DT50 alone, on a line
  that precedes every feasibility line, and is never reassigned.
- **By search.** No `pmin()`, `min()`, `pmax()` or multiplication involving
  `max_feasible_diet_fraction`, `required_search_area_m2`,
  `available_seeds_within_msa` or `diet_fraction_is_feasible` appears anywhere in
  the computation of `dose_mg_kg_bw_day`, `initial_dose_mg_kg_bw_day`, `rq`,
  `initial_rq`, `peak_rq`, `screening_rq` or `days_above_loc`.
- **By experiment.** Overriding the small bird's MSA from 70 m² to 10 m² changed
  `initial_max_feasible_diet_fraction` from 61.527 to 8.790, while
  `initial_dose_mg_kg_bw_day`, `initial_rq` and `days_above_loc` were **bit-for-bit
  identical** to the unmodified run. `required_search_area` was also unchanged,
  correctly, since it does not depend on MSA.
- **The capped column exists and is properly quarantined.** The
  `dose_capped_at_feasible_mg_kg_bw_day` column is populated (it differs from the
  uncapped dose in 12,998 of 125,280 rows) and is always less than or equal to
  the regulatory dose. The auditor searched the reporting layer: **it is never
  read** by `R/reporting/30_plots.R`, `31_tables.R`, `32_word_export.R` or
  `33_data_export.R`, and never appears in a Word or CSV table. It is available
  for sensitivity work and nothing else, exactly as §10.3 promises.

### 6.3 One documentation gap in this area

For a receptor with `surface_seed_only = FALSE`, the engine's accessible pool at
time `t` is the **full sown density decayed at the surface-seed half-life**
(`seeds_per_m2 × 2^(-t/14)`). The specification (§10.1) says only that the
accessible pool is `N_ha/10000` rather than `S(0)`; it is silent about whether
buried seed should decline on the same clock as surface seed. That is a defensible
choice but it is a modelling assumption the specification does not state and a
reviewer cannot audit from the document alone.

---

## 7. Scenario propagation and hidden coupling

**Crop-scoped TKW override does not leak.** The auditor set a `USER_OVERRIDE` on
`tkw_g_per_1000` for scope `Barley:low_tkw` (24.8 → 30 g) and rebuilt the
canonical summary for Barley, Rye and Oat.

- 24 rows changed TKW; **all** were Barley.
- Every non-Barley row was bit-for-bit identical on `initial_dose_mg_kg_bw_day`,
  `initial_rq`, `seeds_per_ha`, `field_rate_g_ai_per_ha` and
  `initial_max_feasible_diet_fraction`.
- Barley's `high_tkw` rows were completely unchanged.
- Within Barley's `low_tkw` rows the propagation was correct and complete:
  seeding rate 44.64 → 54 kg/ha and 116.56 → 141 kg/ha; dose per seed
  0.00744 → 0.009 mg; seeds/ha unchanged (a directly supplied count); and — the
  key check — **EDE unchanged at 76.1815540021432**, because at a mass-basis rate
  the dose does not depend on seed mass.

**Body-weight overrides propagate through the regression.** `resolve_receptors()`
recomputes FIR from `a × BW^b` whenever the body weight is not at its assessment
default, rather than leaving a stale intake. The auditor confirmed the code path
and that the default path returns the stored workbook value untouched.

**A global-scope override deliberately applies to every crop.** Setting
`tkw_g_per_1000` at scope `"global"` rewrote the TKW for Barley *and* Oat (Oat's
seeds/ha moved from 1,992,593 to 1,793,333). This follows from `effective_value()`,
which falls back from the requested scope to `"global"`. It is a documented
design, but it is a coupling hazard for an interactive user who intends a
single-crop change, and neither the specification nor the parameter-set
documentation warns about it.

---

## 8. Invariants and edge cases

Each numeric expectation below was computed by the auditor **before** running the
engine.

| Check | Expected (independent) | Engine | Verdict |
|---|---|---|---|
| `application_rate = 0` ⇒ dose per seed | 0 | 0 | pass |
| `application_rate = 0` ⇒ EDE | 0 | 0 | pass |
| `application_rate = 0` ⇒ RQ | 0 | 0 | pass |
| `application_rate = 0` ⇒ days above metric | 0 | 0 | pass |
| `diet_fraction = 0` ⇒ EDE | 0 | 0 | pass |
| `diet_fraction = 0` ⇒ seeds required | 0 | 0 | pass |
| Doubling mg a.i./kg seed ⇒ dose per seed ratio | exactly 2 | exactly 2 | pass |
| Doubling mg a.i./kg seed ⇒ EDE ratio | exactly 2 | exactly 2 | pass |
| Doubling seeding rate at fixed mg/kg ⇒ g a.i./ha ratio | exactly 2 | exactly 2 | pass |
| `S(t)` never increases (0–60 d, 121 points) | monotone | monotone | pass |
| `A_seed(t)` never increases | monotone | monotone | pass |
| `RQ = dose / M` exactly, 125,280 rows | exact | bit-identical, max diff 0 | pass |
| `DT50_residue = Inf` ⇒ constant residue | constant | constant | pass |
| `DT50_surface = Inf` ⇒ constant surface loading | constant | constant | pass |
| One crop's TKW override does not move another crop | no change | no change | pass |
| MSA change moves feasibility but not dose or RQ | dose/RQ unchanged | bit-identical | pass |
| Near-threshold: barley 300 mg/kg, 10 % diet, chronic screen | RQ 0.9791974 (below 1) | 0.9791973522126375 | pass |
| Threshold dietary fraction, same case | 10.2124 % | 10.2124459154261 % | pass |

The near-threshold case is worth stating plainly for a scientific reader: the
engine puts the chronic screening threshold at **10.21 % of the daily diet as
treated seed**. At an assumed 10 % diet the RQ is 0.979 — just below 1 — and at
25 % it is well above. This brackets the published narrative ("no exceedance at
10 %, exceedance at 25 %") correctly, and the engine does **not** round the RQ up
across the threshold.

**Error handling.** All ten error conditions listed in §16 were exercised. Every
one raised a clear, named error rather than silently substituting a value:
negative body weight, negative application rate, dietary fraction above 1,
dietary fraction below 0, surface fraction above 1, unrecognised rate unit,
`DT50` of exactly zero, `NA` thousand-seed weight, negative MSA and negative
half-life. The `NA` message is exemplary: *"The model does not substitute
defaults for missing scientific inputs."*

### 8.1 Three robustness defects found

These are not wrong numbers. They are places where the engine either crashes on a
legitimate input or silently produces an inconsistent row.

1. **`diet_fraction = 0` crashes the scenario summary.** Specification invariant 6
   explicitly names `p_diet = 0` as a valid input. `build_daily_timecourse()`
   handles it correctly (dose 0). But `build_scenario_summary()` aborts with
   *"`target_diet_fraction` must be strictly greater than 0"*, because
   `days_diet_fraction_feasible()` validates its target as strictly positive. The
   two builders therefore accept different input domains for the same argument.
   The default `STBAM_DIET_FRACTIONS` does not include 0, so this is only reachable
   when a caller passes 0 explicitly.

2. **`clear_override(params, parameter)` always errors.** The function's
   documented signature has `scope = NULL` as a default meaning "any scope". With
   `scope = NULL`, the expression `is.null(scope) | params$overrides$scope == scope`
   evaluates to a zero-length logical, and subsetting a tibble by it raises
   *"Logical subscript `keep` must be size 1 or 2, not 0"*. Clearing all overrides
   for one parameter is therefore impossible via the documented call. Passing an
   explicit scope works, and `clear_override(params)` with no parameter works.
   This is in the parameter-set layer, not the numeric chain, but it is the path a
   "reset this parameter" control in the dashboard would take.

3. **A `seeds_per_ha` override leaves the mass seeding rate stale.** Overriding
   Barley's low-bound seed count from 1,800,000 to 2,400,000 correctly raised the
   surface density from 180 to 240 seeds/m², but `seeding_rate_kg_per_ha` remained
   at 44.64 kg/ha — the value implied by 1,800,000 seeds at TKW 24.8 g. The
   consistent value would be 59.52 kg/ha. Because the field rate is computed from
   the mass rate, `field_rate_g_ai_per_ha` also stayed at 13.392 g a.i./ha while
   the seed count it should correspond to rose by a third. The row's own identity
   `seeds_per_ha × TKW / 1e6 = seeding_rate_kg_per_ha` — which holds to 1.3 × 10⁻¹⁶
   everywhere in the baseline — is silently violated, and only a
   `seeding_status = USER_OVERRIDE` label hints at it. `seeds_per_ha` and
   `seeding_rate_kg_per_ha` are independently overridable and are not
   cross-reconciled.

### 8.2 A gap in the validation regime itself

Specification §13 states that acceptance requires "all 28 review calculation
checks … reproduce within 1 × 10⁻⁶ relative tolerance". The auditor searched the
repository: **no code reads
`inst/fixtures/bird_small_cereals_calculation_checks.csv`.** The file is copied
in by `scripts/extract_reference_data.py` and listed in the manifest, but the test
suite only mentions four of the fixture IDs in comments beside hard-coded
numbers. The stated acceptance criterion is therefore not machine-enforced.

This matters because the auditor found that several fixture values **cannot**
meet a 10⁻⁶ tolerance, having been computed from pre-rounded intermediates. For
example fixture BSC-CALC-013 gives RQ 1.767981 from a rounded EDE of 76.2, whereas
the exact chain gives 1.767553 (relative difference 2.4 × 10⁻⁴); BSC-CALC-019
gives 75.177416 days from a rounded 4135 % availability, whereas the exact chain
gives 75.172930 (relative difference 6 × 10⁻⁵). The engine's values are the
correct ones. If the §13 criterion were implemented literally it would fail on
values that are not in error. The criterion needs rewording to compare against
recomputed-from-exact-inputs values, with the fixture's own rounded figures
treated as display checks.

---

## 9. Overall verdict

### What can be trusted

**The quantitative core of this engine is sound, and I could not break it.**

- Every unit conversion in the chain — kg↔g↔mg, ha↔m², %↔fraction, TKW↔seed
  mass, mass↔count seeding rate, and both directions of the rate-unit conversion
  — is correct, and every round trip is exact to machine precision. I found no
  factor-of-1000 error, no ha/m² slip, and no place where a percentage is used
  where a fraction is required.
- Dose per seed, field rate, surface seed density, area per surface seed, food
  ingestion rate, seeds required per day, estimated daily exposure, risk quotient
  and duration above an effects metric all reproduce the **cached values in the
  audited source workbook to 13–16 significant figures**, and independently
  reproduce my own from-scratch arithmetic to the same precision.
- The two forms of EDE agree to floating-point rounding, as they must.
- `RQ = dose / metric` is exact, not approximate, on every one of 125,280 rows.
- The two dissipation processes really are separate: two named half-lives in the
  workbook, two rows in the reference data, two independently resolved parameters
  in the code, and demonstrably independent behaviour when each is overridden.
  The combined surface loading is the product of the two, and agrees with the
  combined-half-life closed form to 9 × 10⁻¹⁶.
- The clothianidin screening conversion is genuinely isolated: it has **zero call
  sites** in the production code and cannot reach any dose, RQ or canonical
  dataset column.
- MSA feasibility genuinely does not cap the regulatory exposure. I verified this
  by code reading, by exhaustive search, and by experiment: halving the search
  area sevenfold left dose, RQ and duration bit-for-bit identical.
- No dry-to-fresh mass conversion is applied to the Nagy regressions, and the
  workbook — which does hold moisture data — deliberately does not apply one
  either.
- The engine fails loudly on every invalid input I could construct.

For the regulatory outputs that matter most — `dose_mg_kg_bw_day`, `rq`,
`days_above_loc`, `threshold_diet_fraction_pct` — **I found no error of any kind.**

### What cannot yet be trusted, and why

**One substantive issue, and it is a labelling issue rather than an arithmetic
one.** The specification's §4.2 describes a one-dimensional seeding-rate bound
with a deliberate asymmetric TKW rule. The engine implements a two-dimensional
grid in which the seed count depends on both bounds. The engine's behaviour
matches the source workbook's `Seeding Assumptions!J:M` block exactly, and it is
the more internally coherent of the two conventions — but it means a row labelled
`seeding_rate_bound = "low"` can carry a seed count 2.5× the figure the
specification and the published tables call the "lower bound". Nothing downstream
of the seed *counts* is affected: doses, RQs, feasible dietary fractions and
required search areas are all unchanged, and the extremes of the grid coincide
exactly with the documented bounds. **The specification must be corrected to
match the code, not the other way round**, and any regulatory table drawn from
this engine must show `seed_mass_bound` beside `seeding_rate_bound`.

**Three robustness defects** should be fixed before the dashboard is used
interactively for anything that will be submitted: `diet_fraction = 0` crashes
the scenario summary; `clear_override(params, parameter)` always errors; and a
`seeds_per_ha` override silently leaves the mass seeding rate — and hence the
field rate — inconsistent with the seed count.

**Two documentation defects** weaken the audit trail without affecting any
number: the §4.1 citation to `Seed Inputs and EECs!AC:AR` does not show what it
is said to show (the real evidence is elsewhere in the workbook), and the
specification does not state that buried seed is assumed to decline at the
surface-seed half-life.

**One process gap.** The 28-check fixture set that §13 names as an acceptance
criterion is never read by any code. Several of its values were computed from
rounded intermediates and cannot meet the stated 10⁻⁶ tolerance — the engine is
right and the fixture is rounded — so the criterion needs rewording as well as
implementing.

**One finding about the source document, not the engine.** For crops whose
seeding rate is supplied on a mass basis, the audited workbook itself reports two
different "low bound" surface seed densities in different places on the same crop
sheet (buckwheat: 53.62 seeds/m² in `7!D7` versus 68.97 seeds/m² implied by
`7!J79` and `7!M20`). The engine reproduces the crop-sheet convention
consistently. Which convention the assessment intends is a scientific judgement
for the assessment team and is flagged for human review rather than resolved
here.

### Bottom line

One hundred items were checked. **Eighty-nine passed.** The remainder are six
documentation gaps, four robustness defects and one matter referred for human
scientific judgement. **There is no `CONFIRMED_ERROR` and no `POTENTIAL_ERROR`
in this audit**: I did not find a single wrong number anywhere in the exposure,
dose, risk-quotient, dissipation or feasibility chain. Forty-nine of the hundred
items were checked against a specific cell in the primary audited workbook that I
read myself; the other fifty-one were checked against my own from-scratch
arithmetic, against algebraic identities, or by code inspection, and the
`audited_excel_result` column is left blank for those so that the distinction is
visible.

The residual risk in this engine is not that it computes the wrong number; it is
that one of its output columns is labelled in a way the specification does not
describe. That is a documentation and presentation fix, and it should be made
before any table built from `scenario_inputs` is placed in a submission.

---

*Independent audit. No file under `R/`, `data/reference/`, `tests/`, `app/` or
`scripts/` was modified. No commit was made. The source workbook's SHA-256 was
verified unchanged before and after reading.*
