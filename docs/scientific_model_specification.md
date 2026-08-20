# Scientific model specification

**Model:** Bird and Mammal Seed-Treatment Risk Assessment Model (`stbam`)
**Specification version:** 1.0.0
**Status:** Canonical model contract. Any change to an equation, unit or default
must be made here first and then in code.

---

## 1. Purpose and boundary

This specification defines the quantitative exposure and risk model for birds
and mammals ingesting pesticide-treated crop seed left on the soil surface after
sowing. It reconstructs the calculation chain implemented in the source
assessment workbooks and makes every step, unit and assumption explicit.

The model **calculates**. It does not decide. It produces quantitative results
and structured decision-support views; the acceptability judgement in Table 162
remains a human decision.

### What is in scope

- Refined seed-ingestion exposure for birds and mammals.
- Screening exposure using maximum rates and a 100 % treated-seed diet.
- Time-dependent surface-seed availability and residue dissipation.
- Maximum-search-area (MSA) based exposure-feasibility analysis.
- Risk quotients against screening and refined-additional effects metrics.

### What is out of scope

- Endpoint selection and toxicological interpretation. Effects metrics are
  inputs, taken from the assessment.
- Quantitative refined clothianidin exposure. The assessment excludes it
  (`ASSUMPTION-004`); the screening molar-ratio conversion is documented in
  §9 but is not part of the refined chain.
- Routes other than seed ingestion.
- Any automatic regulatory conclusion.

---

## 2. Provenance of this specification

| Source | Role |
|---|---|
| `THE 1 small cereals ... 08MAY2026.xlsm` | Primary audited reference. 1,115 independent numeric checks passed (review workspace `phase3a_workbook_qaqc.md`). Authority for shared assumption sheets and all equations. |
| Canola, deep/shallow legumes, cucurbits workbooks | Additional crop × rate scenario definitions only. |
| `bird_small_cereals_calculation_checks.csv` | 28 independently reconstructed calculations used as regression fixtures. |
| `core_assumptions.csv`, `effects_metrics.csv` (review workspace) | Cross-check on assumption values and stated uncertainty. |
| Assessment Word documents | Narrative context, stated uncertainty, and the Table 1 screening endpoints. |

Source workbooks and Word documents are **immutable**. They are read
statically (no Excel, no COM, no VBA execution) by
`scripts/extract_reference_data.py`, which records a SHA-256 for every file
before and after reading and aborts if any hash changes.

---

## 3. Notation and units

All internal computation uses one canonical unit per quantity. Unit
conversion happens only at defined boundaries.

| Symbol | Quantity | Canonical unit |
|---|---|---|
| `C_seed` | Concentration of active ingredient in/on seed | mg a.i./kg seed |
| `m_seed` | Individual seed mass | g/seed |
| `TKW` | Thousand-seed weight | g/1000 seeds |
| `D_seed` | Dose of active ingredient per seed | mg a.i./seed |
| `N_ha` | Seeds planted | seeds/ha |
| `R_mass` | Seeding rate, mass basis | kg seed/ha |
| `R_field` | Active ingredient applied to the field | g a.i./ha |
| `f_surface` | Proportion of sown seed remaining on the surface | dimensionless (0–1) |
| `S(t)` | Surface seed density at time `t` | seeds/m² |
| `A_seed(t)` | Active ingredient remaining per surface seed | mg a.i./seed |
| `A_area(t)` | Active ingredient on the surface, area basis | mg a.i./m² |
| `BW` | Receptor body weight | g |
| `FIR` | Food ingestion rate | g dry weight diet/day |
| `p_diet` | Fraction of the daily diet that is treated seed | dimensionless (0–1) |
| `n_req(t)` | Seeds required per day to meet `p_diet` | seeds/day |
| `MSA` | Maximum search area | m² |
| `EDE`, `Dose(t)` | Estimated daily exposure / dose | mg a.i./kg bw/day |
| `M` | Effects metric | mg a.i./kg bw/day |
| `RQ(t)` | Risk quotient | dimensionless |
| `DT50_res` | Residue dissipation half-life on/in seed | days |
| `DT50_seed` | Surface-seed disappearance half-life | days |

`log2(x)` denotes the base-2 logarithm. `t` is time in days since sowing;
`t = 0` is the moment of sowing.

---

## 4. Scenario definition

A **scenario** is a fully specified combination. Nothing is left implicit.

| Axis | Values |
|---|---|
| `crop` | One of the crops in `crop_seeding_parameters.csv` |
| `application_rate` + `application_rate_unit` | mg a.i./kg seed **or** mg a.i./seed |
| `planting_method` | `broadcast`, `drill_spring`, `drill_fall`, `precision` |
| `seeding_rate_bound` | `low` or `high` (bounds on seeds/ha) |
| `seed_mass_bound` | `low_tkw` or `high_tkw` (bounds on individual seed mass) |
| `receptor` | `bird_small/medium/large`, `mammal_small/medium/large` |
| `diet_fraction` | e.g. 1.00, 0.50, 0.25, 0.10, 0.05, 0.01 |
| `effects_metric` | A row of `effects_metrics.csv` |

### 4.1 The two agronomic bound axes are independent

This is a deliberate and important departure from how the source Word tables
present results.

The workbook derives a lower and an upper bound on **seeds/ha**, and separately
a low and a high **TKW**. These two bounds are used as **independent axes**,
not as a single paired scenario: at a given seeding-rate bound the workbook
still computes seed counts using both the low and the high TKW. The evidence
for this is the crop sheets (rows 19–27 and 79–82) and the
`Seeding Assumptions!J:M` block described in §4.2 below — **not**
`Seed Inputs and EECs!AC:AR`, whose header row (`AC3:AR3`) is labelled only
"Low Seeding Rate" / "High Seeding Rate" and carries no seed-weight axis at
all. (An earlier version of this specification cited `AC:AR` for this claim;
that citation did not support it and has been corrected here per the
independent audit, `docs/independent_engine_audit.md` §2.4.)

The Word tables then report a *range* across crops and across both axes, which
loses the information about which combination produced each end of the range.

This model therefore evaluates the **full 2 × 2 grid** of
`seeding_rate_bound × seed_mass_bound` and labels every result with the
combination that produced it. Ranges reported in regulatory tables are computed
as summaries over that grid (§11), not hard-coded.

### 4.2 Resolving seeds/ha: the full 2×2 grid, not a single bracket

**Corrected 2026-08-20 following the independent audit** (`docs/independent_engine_audit.md`
§2.3, finding AUD-027). An earlier version of this section described a
one-dimensional bracketing rule that does not match what the engine
implements or what the audited workbook's crop-sheet calculations use. That
description is retained below as a labelled aside because it is still the
convention the **published Word tables** report; it is not the convention
this model's row-level `seeds_per_ha` column follows.

**What the engine actually computes, and what the audited workbook's
`Seeding Assumptions!J:M` block computes, is a full 2×2 grid.** For each
crop, at each corner of `seeding_rate_bound × seed_mass_bound`:

```
seeds_per_ha(rate_bound, mass_bound) =
    seeding_rate_<rate_bound>_seeds_per_ha_direct        if supplied
    else 1000 * (seeding_rate_<rate_bound>_kg_per_ha_low_tkw
                 / (TKW_<mass_bound> / 1000))
```

i.e. the seed count at a given `rate_bound` is recomputed independently at
**both** the low and the high TKW, giving four distinct seed counts per crop
where the seeding rate is supplied on a mass basis — not two. This
reproduces the workbook's `Seeding Assumptions!J:M` block cell for cell
(columns `J`=low-rate÷low-weight, `K`=low-rate÷high-weight,
`L`=high-rate÷low-weight, `M`=high-rate÷high-weight), and it is the
convention the workbook's own crop-sheet feasibility calculations
(`available_seed_within_msa`, `required_search_area`, etc.) use.

**Consequence for a reader of `scenario_inputs`.** A row labelled
`seeding_rate_bound = "low"` can carry a seed count well above what the
*published Word tables* and this specification's own §11.1 summary call the
"lower bound" — for winter wheat, 1,500,000 seeds/ha at `low`/`low_tkw`
versus the 600,000 the outer bracket (`K`) reports. **Any table drawn from
this engine must display `seed_mass_bound` alongside `seeding_rate_bound`**,
or must be built from the grid's min/max (which do coincide exactly with the
traditionally reported bounds — see below).

**The historical bracket, still relevant for matching published tables:**

```
seeds_per_ha_low  (outer bracket, = grid column K)
                  = seeding_rate_low_seeds_per_ha_direct   if supplied
                    else 1000 * (seeding_rate_low_kg_per_ha_high_tkw / (TKW_high / 1000))

seeds_per_ha_high (outer bracket, = grid column L)
                  = seeding_rate_high_seeds_per_ha_direct  if supplied
                    else 1000 * (seeding_rate_high_kg_per_ha_low_tkw / (TKW_low / 1000))
```

This bracket is what `Seed Inputs and EECs!AC/AD` (the workbook's own
summary columns) and the published Word tables report, and it is exactly
the minimum and maximum of the engine's full grid — so any range computed
across the grid is correct and matches the published bracket. The bracket
values are retained, unused by the calculation engine, in
`crop_seeding_parameters.csv` (`seeds_per_ha_low`/`_high` and their
`_basis` columns) for cross-reference against published tables; they are
read by the Shiny input module's display only, not by any function under
`R/calculations`, `R/inputs` or `R/summaries`.

**Known defect in the source workbook itself, not in this model.** For
crops whose seeding rate is supplied on a mass basis, the audited workbook
is internally inconsistent about which "low bound" density it uses: on the
buckwheat crop sheet (sheet `7`), cell `D7` reports the low broadcast
surface density as 53.62 seeds/m² (derived from grid column `K`), while
cells `J79` and `M20` on the **same sheet** compute the feasible seed pool
and required search area from column `J` (68.97 seeds/m²). This model
cannot match both; it consistently follows the `J`/`K`/`L`/`M`
crop-sheet-feasibility convention. Which convention the assessment intends
is a scientific judgement referred to the assessment team
(`docs/independent_engine_audit.md`, finding AUD-031), not resolved here.

**Verified against:** pearl millet lower (bracket) 861,538 seeds/ha; oat upper
(bracket) 5,814,815; buckwheat upper (bracket) 3,103,448; winter wheat lower
(bracket) 600,000 — all reproduced exactly by the grid's min/max (review
checks BSC-CALC-016, 020, 021, 028; independent audit AUD-027).

---

## 5. Seed and treatment parameter conversions

All conversions are bidirectional and unit-safe. The model never requires the
user to enter a redundant value.

### 5.1 Seed mass ↔ thousand-seed weight

```
m_seed [g/seed] = TKW [g/1000 seeds] / 1000
TKW             = m_seed * 1000
```

### 5.2 Seeding rate: mass ↔ count

```
N_ha [seeds/ha]   = 1000 * (R_mass [kg/ha] / (TKW [g/1000] / 1000))
                  = R_mass * 1e6 / TKW      (equivalent, exact)

R_mass [kg/ha]    = (N_ha / 1000) * TKW / 1000
                  = N_ha * TKW / 1e6
```

Both forms appear in the workbook (`Seeding Assumptions!F:I` and `J:M`) and are
algebraically identical. The engine implements the second, closed form and
tests the round trip to machine precision.

```
N_m2 [seeds/m²]   = N_ha / 10000
```

### 5.3 Treatment loading

Registered rates are supplied either per unit seed mass or per seed.

```
if unit == "mg a.i./kg seed":
    C_seed = application_rate
    D_seed = C_seed * TKW / 1e6          # = C_seed * m_seed / 1000

if unit == "mg a.i./seed":
    D_seed = application_rate
    C_seed = D_seed * 1e6 / TKW          # = D_seed * 1000 / m_seed
```

Workbook form: `D_seed = C_seed / (1000000 / TKW)`, which is identical.

**Verified:** barley 300 mg/kg, TKW 24.8 → 0.00744 mg a.i./seed (workbook
`Seed Inputs and EECs!Q4`).

### 5.4 Field loading

```
R_field [g a.i./ha] = (C_seed [mg/kg] / 1000) * R_mass [kg seed/ha]
```

The workbook computes and reports **two** field rates per crop and rate
level: `W` (low bound × low seed weight) and `X` (high bound × high seed
weight). This model evaluates the field rate at **all four** corners of the
§4.2 grid, since field rate is downstream of `seeding_rate_kg_per_ha`, which
is itself resolved per grid corner. The two additional cells this produces
(for barley: 32.130 and 34.968 g a.i./ha, at the `low/high_tkw` and
`high/low_tkw` corners) are internally consistent and correctly derived by
the same formula, but **have no counterpart in the audited source workbook**
and must not be presented as workbook-reproduced values — only the `W4`/`X4`
corners below carry that provenance (independent audit AUD-030).

**Verified:** barley 300 mg/kg, 44.64 kg/ha → 13.392 g a.i./ha (`W4`).

---

## 6. Surface seed at sowing

```
S(0) [seeds/m²] = (N_ha / 10000) * f_surface
```

`f_surface` by planting method (`General Look ups!F:G`; de Snoo & Luttik 2004
as cited by the assessment):

| Planting method | `f_surface` | Assumption ID |
|---|---:|---|
| Broadcast | 1.000 | `ASSUMPTION-007` |
| Standard drill, spring | 0.033 | `ASSUMPTION-008` |
| Standard drill, fall | 0.092 | `ASSUMPTION-009` |
| Precision planter | 0.005 | `ASSUMPTION-010` |

The mean area per surface seed is the reciprocal:

```
area_per_seed [m²/seed] = 1 / S(0)
```

**Verified:** barley broadcast low 180 seeds/m²; spring drill 5.94; fall drill
16.56; reciprocal 0.005556 m²/seed (`Seed Inputs and EECs!AC4, AE4, AG4, AK4`).

---

## 7. Two independent time-dependent processes

The model treats surface-seed disappearance and residue dissipation as
**separate first-order processes with separate half-lives**. This distinction is
explicit in the assessment (`ASSUMPTION-005` vs `ASSUMPTION-011`) and is
preserved in calculations, plots, documentation and the user interface.

### 7.1 Surface-seed disappearance

Loss of surface seed by displacement, burial, germination and predation.

```
S(t) = S(0) * 2^(-t / DT50_seed)          DT50_seed = 14 d  (ASSUMPTION-011)
```

### 7.2 Residue dissipation on/in seed

Decline of active ingredient associated with a seed that is still present.

```
A_seed(t) = D_seed * 2^(-t / DT50_res)    DT50_res = 10 d   (ASSUMPTION-005)
```

For pelleted seed (e.g. sugar beet) the assessment treats thiamethoxam as
stable (`ASSUMPTION-006`). This is represented by `DT50_res = Inf`, giving
`A_seed(t) = D_seed` for all `t`. The engine accepts `Inf` and returns a
constant; it does not special-case a crop name.

### 7.3 Combined surface loading

The active ingredient present on the surface, on an area basis, is the product
of the two processes:

```
A_area(t) [mg a.i./m²] = S(t) * A_seed(t)
                       = S(0) * D_seed * 2^(-t/DT50_seed) * 2^(-t/DT50_res)
```

Equivalently a combined half-life
`DT50_combined = (DT50_seed * DT50_res) / (DT50_seed + DT50_res)`
(7.0 d + 4.1 d ≈ 5.83 d at the default values). The engine computes the product
form and asserts agreement with the combined-half-life form in tests.

**This product is reported and plotted separately from each component**, because
conflating the two processes is the single most likely source of scientific
misinterpretation in this model.

---

## 8. Receptor food requirement

Food ingestion rate follows the Nagy allometric regressions stored in the
workbook (`FIR Assumptions`, `FIR Bird Regressions`, `FIR Mammal Regressions`):

```
FIR [g dry weight diet/day] = a * BW [g] ^ b
```

| Receptor | BW (g) | Regression | `a` | `b` | FIR (g dw/d) |
|---|---:|---|---:|---:|---:|
| Small bird | 20 | Nagy 1987, Passerines | 0.398 | 0.850 | 5.078770267 |
| Medium bird | 100 | Nagy 1987, Passerines | 0.398 | 0.850 | 19.947251898 |
| Large bird | 1000 | Nagy 1987, All birds | 0.648 | 0.651 | 58.153385884 |
| Small mammal | 15 | Nagy 1987, All eutherians | 0.235 | 0.822 | 2.176781698 |
| Medium mammal | 35 | Nagy 1987, All eutherians | 0.235 | 0.822 | 4.368092180 |
| Large mammal | 1000 | Nagy 1987, All eutherians | 0.235 | 0.822 | 68.717580879 |

> **Provenance note (resolves review gap `TRC-001`).** The assessment Word
> documents state the daily food quantities but not their source or mass basis,
> which was recorded as an open traceability gap. The workbook does state both:
> the values are Nagy allometric regressions on a **dry-weight** basis
> (`FIR Regression g dw/d = a(body mass (g))^b`). The model records the
> regression name, coefficients and dry-weight basis for every receptor. The
> full regression library (10 alternative models including granivore-specific
> Nagy et al. 1999 forms) is available in `fir_regressions.csv` so the intake
> model can be changed as an explicit, provenance-tagged override.

The model does **not** apply a dry-to-fresh weight conversion. The workbook does
not apply one, and no conversion factor is stated in the assessment. Applying
one would change every dose. This is recorded as a stated limitation (§14).

### 8.1 Seeds required per day

```
n_full [seeds/day]   = FIR / m_seed              # 100 % treated-seed diet
n_req(t) [seeds/day] = (FIR / m_seed) * p_diet
```

Note `n_req` is time-invariant: it is what the animal *needs*, not what is
available. Time enters through availability (§10) and through residue decline
(§9).

**Verified:** small bird, TKW 13 g → 390.67 seeds/d; medium bird, millet
TKW 6.5 → 3068.81 seeds/d; large bird, TKW 13 → 4473.34 seeds/d
(BSC-CALC-010, 011, 012).

---

## 9. Exposure and risk

### 9.1 Estimated daily exposure

```
EDE [mg a.i./kg bw/day] = C_seed [mg/kg seed] * FIR [g/d] / BW [g] * p_diet
```

The `g/g` ratio is dimensionless, so `mg/kg seed` carries through to
`mg/kg bw/day` with no numeric factor. This is the workbook form and is
dimensionally exact.

Equivalently, in per-seed terms:

```
EDE = n_req * D_seed / (BW / 1000)
```

The engine computes both and asserts equality in tests; they differ only by
floating-point rounding.

**Note.** `EDE` does not depend on seed mass when the rate is expressed per unit
seed mass. Seed mass affects seed *counts*, dose per seed, and availability —
not the dose. This is why the source tables report a single EDE per rate and
dietary fraction alongside a *range* of seed counts.

**Verified:** small bird, 300 mg/kg, 100 % diet → 76.1816 mg/kg bw/d;
medium bird, 300 mg/kg, 25 % → 14.9604; large bird, 200 mg/kg, 50 % → 5.8153
(BSC-CALC-004, 005, 006).

### 9.2 Time-dependent dose

Dose declines with residue dissipation:

```
Dose(t) = EDE * 2^(-t / DT50_res)
```

This assumes the animal continues to obtain `p_diet` of its diet as treated
seed. Whether that is physically possible at time `t` is the separate
feasibility question of §10 and is **not** applied as a cap here (§10.3).

### 9.3 Risk quotient

```
RQ(t) = Dose(t) / M
RQ(0) = EDE / M
```

`RQ ≥ 1` indicates the effects metric is reached or exceeded. Screening and
refined-additional metrics are kept explicitly separate and are never mixed in
one RQ.

**Verified:** small bird, 300 mg/kg screening acute → RQ 1.768; chronic → 9.794
(BSC-CALC-013, 014).

### 9.4 Duration above an effects metric

Solving `Dose(t) = M`:

```
days_above_metric = DT50_res * log2(EDE / M)      for EDE > M
                  = 0                              for EDE <= M
```

**Verified:** small bird 300 mg/kg acute screen → 8.2175 d; small bird 200 mg/kg
chronic → 27.0664 d; medium bird 300 mg/kg 25 % diet chronic → 9.4331 d; large
bird 300 mg/kg chronic → 11.6506 d (BSC-CALC-022, 023, 025, 026).

### 9.5 Threshold dietary fraction

The dietary fraction at which the metric is exactly reached at `t = 0`:

```
p_threshold [%] = M / EDE(p_diet = 1) * 100
```

**Verified:** small bird 300 mg/kg chronic → 10.21 %, bracketed by the reported
"no exceedance at 10 %, exceedance at 25 %" (BSC-CALC-015).

### 9.6 Seeds required to reach a metric

```
n_to_metric = M [mg/kg bw/d] * (BW / 1000) [kg] / D_seed [mg/seed]
```

### 9.7 Screening clothianidin conversion (documented, not in the refined chain)

Screening applies complete molar conversion of thiamethoxam to clothianidin
(`ASSUMPTION-003`):

```
C_clothianidin = C_thiamethoxam * (249.68 / 291.7) = C_thiamethoxam * 0.8560
```

(0.8560 is a four-figure rounding of the exact ratio, 0.85594789…; the engine
stores and uses the exact fraction, `STBAM_CLOTHIANIDIN_MOLAR_RATIO`, not the
rounded constant. Independent audit AUD-041 confirmed this function has zero
call sites anywhere in the production code, so this rounding note is
informational only — the conversion is not reachable from any dose, RQ, or
canonical dataset column.)

The refined seed-ingestion assessment excludes a quantitative clothianidin
contribution (`ASSUMPTION-004`). The engine implements the conversion as an
isolated, clearly named screening function; it is never applied silently.

---

## 10. Exposure feasibility (maximum search area)

This layer answers a question the risk quotient cannot: *could an animal
realistically find enough treated seed to achieve the modelled exposure?*

### 10.1 Quantities

```
available_seeds_in_MSA(t) = S(t) * MSA

max_feasible_diet_fraction(t) = available_seeds_in_MSA(t) / n_full
                              = S(t) * MSA * m_seed / FIR

required_search_area(t) [m²] = n_req / S(t)
                             = (FIR / m_seed) * p_diet / S(t)

area_to_reach_metric [m²]    = n_to_metric / S(t)
```

MSA values (`Further Risk Characterization!C11:D13`, `H11:I13`;
EFSA 2023 and Northern Zone guidance as cited):

| Receptor | Short-term (1 d) | Long-term (21 d) | Assumption |
|---|---:|---:|---|
| Small / medium bird | 70 m² | 35 m² | `ASSUMPTION-012`, `-014` |
| Large bird | 140 m² | 70 m² | `ASSUMPTION-013`, `-014` |
| All mammals | 70 m² | 35 m² | `ASSUMPTION-015`, `-016` |

Birds are assessed on surface seed only (`ASSUMPTION-019`). For mammals the
workbook sets "assume only surface seed accessible" to **N**, consistent with
`ASSUMPTION-020` (shallow-sown seed may be presumed available in selected
scenarios). The engine carries `surface_seed_only` as an explicit per-receptor
flag; when `FALSE` the accessible pool is the full sown density `N_ha / 10000`
rather than `S(0)`, and this is labelled in every output.

**Time-dependence of the non-surface-restricted pool (documented following
independent audit finding, `docs/independent_engine_audit.md` §6.3).** When
`surface_seed_only = FALSE`, the accessible pool at time `t` is the full sown
density decayed at the **surface-seed** half-life —
`(N_ha / 10000) × 2^(-t/DT50_seed)` — not a constant, and not decayed at the
residue half-life. This is a defensible modelling choice (the same physical
disappearance process that removes visible surface seed presumably also
removes buried seed over time) but it is a choice this specification did not
previously state, and a reviewer could not have audited it from this document
alone.

**Verified:** wheat lower broadcast, small bird → 4200 seeds in 70 m² MSA,
4134.86 % of daily diet available; buckwheat upper spring drill, medium bird →
104.22 %; barley broadcast low, small bird → 0.474 m² required for the low seed
count and 1.138 m² for the high seed count (BSC-CALC-017, 018, 020; workbook
crop sheet `1!K20`, `1!M20`).

### 10.2 Days of availability

The number of days for which at least a full daily diet remains available
within the MSA, using the **surface-seed** half-life:

```
days_at_full_diet = DT50_seed * log2(max_feasible_diet_fraction(0) / 1)
```

for `max_feasible_diet_fraction(0) > 1`, else 0.

**Verified:** wheat lower broadcast → 75.18 d; oat upper fall drill, large bird
→ 25.17 d (BSC-CALC-019, 021).

### 10.3 Feasibility is a diagnostic, not a cap

**The regulatory exposure calculation is not capped at the feasible dietary
fraction.** The assessment uses MSA as a plausibility and refinement check, not
as a direct exposure cap. The model preserves that distinction:

- `dose_mg_kg_bw_day`, `rq` and `days_above_metric` are the **calculated
  regulatory exposure**, computed at the assumed `p_diet`.
- `max_feasible_diet_fraction`, `required_search_area_m2` and
  `diet_fraction_is_feasible` are the **exposure-feasibility analysis**.

A capped dose is available as a clearly separate, explicitly named column
(`dose_capped_at_feasible_mg_kg_bw_day`) for sensitivity work. It is never
substituted for the regulatory value, and the user interface presents the two in
separate views.

---

## 11. Canonical result datasets

Four datasets. Everything downstream — dashboard, plots, Word tables, CSV/XLSX
exports, reports, Table 162 support — reads these and nothing else.

### 11.1 `scenario_inputs`

One row per `crop × application_rate × planting_method × seeding_rate_bound ×
seed_mass_bound`. Fully resolved, time-independent agronomic quantities:
`tkw_g_per_1000`, `seed_mass_g`, `seeds_per_ha`, `seeding_rate_kg_per_ha`,
`concentration_mg_per_kg_seed`, `dose_per_seed_mg`, `field_rate_g_ai_per_ha`,
`surface_seed_fraction`, `initial_surface_seeds_per_m2`,
`area_per_surface_seed_m2`.

### 11.2 `daily_timecourse`

One row per `scenario × receptor × effects_metric × diet_fraction × day`.
Carries `surface_seeds_per_m2`, `ai_per_seed_mg`, `surface_ai_mg_per_m2`,
`dose_mg_kg_bw_day`, `rq`, `above_loc`, `available_seeds_within_msa`,
`required_search_area_m2`, `max_feasible_diet_fraction`,
`diet_fraction_is_feasible`.

### 11.3 `scenario_summary`

One row per `scenario × receptor × effects_metric × diet_fraction`:
`screening_rq`, `initial_rq`, `peak_rq`, `days_above_loc`, `day_below_loc`,
`threshold_diet_fraction_pct`, `seeds_to_metric`,
`initial_surface_seeds_per_m2`, `initial_required_search_area_m2`,
`initial_max_feasible_diet_fraction`, `days_at_full_diet_available`,
`day_100pct_diet_infeasible`, `day_50pct_diet_infeasible`,
`day_25pct_diet_infeasible`.

### 11.4 `table162_support`

One row per `crop × planting_method × receptor × duration_class`, joining the
quantitative backbone to the consideration register. Quantitative fields are
`CALCULATED`; evidence fields are `SOURCE_EVIDENCE`; peer-review consensus
fields are **never populated by the software**.

---

## 12. Provenance classes

Every value carries a provenance class, visible in the data architecture and the
interface:

| Class | Meaning |
|---|---|
| `MODEL_INPUT` | Supplied parameter |
| `CALCULATED` | Computed by the engine from model inputs |
| `DERIVED` | Computed from other calculated results (e.g. summaries) |
| `SOURCE_EVIDENCE` | Statement or value taken from a source document |
| `REVIEWER_INTERPRETATION` | Human reading of evidence |
| `PEER_REVIEW_DECISION` | Human decision; never written by the software |

Parameter status values: `ASSESSMENT_DEFAULT`, `USER_OVERRIDE`,
`UPDATED_SOURCE`, `PROVISIONAL`, `REVIEWED`. Baseline assessment values are
never silently overwritten; overrides live in a separate layer and are labelled
in every output that uses them (see `docs/user_guide.md`, "Baseline versus
override").

---

## 13. Validation requirements

The implementation is accepted only if:

1. All 28 review calculation checks in
   `inst/fixtures/bird_small_cereals_calculation_checks.csv`, classified
   `MATCH` or `MATCH_WITH_ROUNDING`, reproduce within 1 × 10⁻⁶ relative
   tolerance **of a value recomputed from the same exact inputs by this
   engine** — not of the fixture file's own stored figure. **Corrected
   2026-08-20 following independent audit finding AUD-099**: several
   fixture values were themselves computed from pre-rounded intermediates
   in the original manual reconstruction and cannot meet a 1×10⁻⁶ tolerance
   against an exact recomputation (e.g. `BSC-CALC-013` records RQ 1.767981
   from a rounded EDE of 76.2, against the exact chain's 1.767553 — a
   relative difference of 2.4×10⁻⁴; `BSC-CALC-019` similarly at 6×10⁻⁵).
   The engine's exact values are correct in both cases; the fixture's
   stored figures are display-precision checks, not the tolerance
   reference. **This criterion is not yet machine-enforced**: no code
   currently reads this fixture file (it is copied into `inst/fixtures/`
   by `scripts/extract_reference_data.py` and named in four test comments,
   but no automated check compares the engine's output against every row).
   Implementing that automated comparison — recomputing each fixture's
   scenario from its exact inputs and asserting agreement, rather than
   comparing to the fixture's own rounded stored value — is an open,
   recommended follow-up; see `PROJECT_STATE.md`.
2. The 4 checks classified `MATERIAL_DISCREPANCY` reproduce the **expected**
   value, not the erroneous published value, and are asserted as such. These are
   confirmed Word display/transfer errors, not workbook or model errors
   (`CAL-001`, `CAL-002`).
3. Workbook-stored values for FIR, dose per seed, EEC, field rate, surface
   density and reciprocal area reproduce to 1 × 10⁻⁹ relative tolerance.
4. Unit round trips (mass ↔ count, TKW ↔ seed mass, rate unit conversion) are
   exact to machine precision.
5. Invariants in §15 hold.

---

## 14. Stated limitations

- **Dry/fresh weight basis.** FIR is dry-weight. No dry-to-fresh conversion is
  applied because none is specified in the assessment or workbook. If treated
  seed moisture were accounted for, doses would change.
- **Large-bird FIR regression is non-unique.** Only one large-bird body weight
  is used, so the `0.648 · BW^0.651` form reproduces the value but is not
  uniquely identified by the data alone. The workbook does name the regression
  (`Nagy 1987, All birds`), which the review workspace could not confirm from
  the Word documents.
- **Mammalian chronic stage distinction.** 1.8 mg/kg bw/d (screening) and
  2.4 mg/kg bw/d (further/refined) are intentionally different workflow stages.
  Both are carried; they must not be collapsed.
- **Grouped Word tables.** Published tables group crops and report ranges. This
  model computes per crop; grouped ranges are reproduced as explicit summaries.
- **Surface fractions are estimates.** de Snoo & Luttik values carry substantial
  field variability; they are not fixed proportions.
- **No probabilistic treatment.** Sensitivity analysis varies parameters over
  user-defined ranges. Results are **not** uncertainty distributions and must
  not be presented as such.
- **Precision-planted and oat scenarios** exist in the workbook but their
  mapping to published recommendation rows is unresolved (`CON-002`).

---

## 15. Invariants asserted by the test suite

Only scientifically valid invariants are encoded.

1. `S(t)` is non-increasing in `t` for finite positive `DT50_seed`.
2. `A_seed(t)` is non-increasing in `t` for finite positive `DT50_res`.
3. `A_seed(t) = D_seed` for all `t` when `DT50_res = Inf`.
4. `RQ(t) = Dose(t) / M` exactly.
5. `application_rate = 0` ⇒ `D_seed = 0`, `EDE = 0`, `Dose(t) = 0`, `RQ = 0`,
   `days_above_metric = 0`.
6. `p_diet = 0` ⇒ `EDE = 0` and `n_req = 0`.
7. `EDE` is strictly increasing in `C_seed`, all else equal.
8. `EDE` is strictly increasing in `p_diet`, all else equal.
9. `S(0)` is strictly increasing in `f_surface` and in `N_ha`.
10. Mass ↔ count seeding-rate conversion round-trips to machine precision.
11. `EDE` computed by the concentration form equals the per-seed form.
12. `A_area(t)` equals the combined-half-life form to machine precision.
13. `days_above_metric = 0` whenever `EDE ≤ M` (never negative).
14. `required_search_area(t) × S(t) = n_req` exactly.
15. `EDE` is invariant to `seed_mass_bound` when the rate unit is
    mg a.i./kg seed.

---

## 16. Error handling

The engine fails loudly and never substitutes a guessed value. Conditions that
raise an error:

- a required parameter is missing or `NA`;
- a negative body weight, seed mass, seeding rate, half-life, MSA or
  application rate;
- a dietary fraction outside `[0, 1]`;
- a surface-seed fraction outside `[0, 1]`;
- an unrecognised application-rate unit;
- an unknown crop, receptor, planting method or effects metric;
- a `DT50` of exactly zero (undefined first-order decay).

`DT50 = Inf` is valid and means "no dissipation" (§7.2).

---

## 17. Change control

| Version | Date | Change |
|---|---|---|
| 1.0.0 | 2026-08-19 | Initial specification reconstructed from the audited Small Cereals workbook and the Phase 3A review record. |
| 1.1.0 | 2026-08-20 | Corrections following the independent adversarial audit (`docs/independent_engine_audit.md`; zero confirmed or potential numerical errors found). §4.2 rewritten to describe the implemented 2×2 seed-count grid rather than a one-dimensional bracket (the code was correct; the specification was not). §4.1's workbook citation corrected. §5.4 notes the engine's two additional, non-workbook-sourced field-rate cells. §9.7 adds a rounding note. §10.1 documents the time-dependence of the non-surface-restricted (mammal) accessible pool. §13's acceptance criterion reworded to compare against exact recomputation rather than the fixture file's own rounded values, and marked not yet machine-enforced. Three engine robustness defects found by the audit (`diet_fraction = 0` crash, `clear_override()` default-scope failure, stale mass rate after a `seeds_per_ha` override) were corrected in code and covered by new regression tests; see `PROJECT_STATE.md` and `docs/model_validation_report.md` for detail. |
