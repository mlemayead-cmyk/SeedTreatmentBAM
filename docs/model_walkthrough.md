# Model walkthrough: the calculation chain, in plain language

**Who this is for:** a scientific reviewer who wants to understand the
model without reading R code. Every number in this document was verified by
running `scripts/reviewer_validation_walkthrough.R`, which recomputes
everything below independently and compares it against the live engine (see
that script's own output for the exact comparison).

**Companion documents:** `docs/scientific_model_specification.md` is the
formal, terse contract (equations, units, provenance IDs). This document is
the narrated, worked-example version of the same material. If the two ever
disagree, the specification is authoritative and this document has drifted
and needs fixing.

We follow one running example throughout: **Barley, treated at 300 mg
active ingredient (a.i.) per kg of seed, broadcast-sown, assessed for a
small bird (20 g body weight)**, at the low-seeding-rate / low-seed-weight
corner of the agronomic grid (explained in section 1). This is the same
scenario the specification cites repeatedly, so every number here is
independently checkable against a named cell in the audited source
workbook.

---

## 1. Two independent "how much seed" questions

Before any pesticide arithmetic, the model has to answer two separate
agronomic questions about a crop, and it keeps them explicitly separate
because the source workbook does:

- **How many seeds are sown, and how heavy is each one?** This depends on
  the seeding rate (which a grower can vary) and the crop variety's seed
  size (which also varies). The source data gives a *low* and a *high*
  bound for each, independently — not as a single paired "small seed at low
  rate, big seed at high rate" scenario. The model evaluates **all four
  combinations** (low rate x low seed weight, low rate x high seed weight,
  high rate x low seed weight, high rate x high seed weight), because
  inspection of the audited workbook confirmed the source calculations
  actually use all four, not just two. Collapsing this into two paired
  bounds — the more intuitive-looking shortcut — would silently discard
  real scenarios. See specification §4.1.

- **How much of that sown seed ends up visible on the soil surface, where a
  bird or mammal can actually find it?** Most of it doesn't — drilling
  buries the great majority of sown seed. Broadcast seeding is the
  exception: because the seed is scattered rather than placed in a furrow,
  essentially all of it stays on the surface.

Our worked example uses the **low seeding rate, low seed weight** corner
(Barley: 1,800,000 seeds/ha, thousand-seed weight 24.8 g/1000 seeds), and
**broadcast** planting (100% surface fraction).

*R code:* `R/summaries/20_scenario_inputs.R`, function `build_scenario_inputs()`.

---

## 2. From thousand-seed weight to how many seeds are on the ground

```
seed weight (g)         = thousand-seed weight (g/1000 seeds) / 1000
                         = 24.8 / 1000 = 0.0248 g/seed

seeds per hectare        = (given directly for Barley in the source data:
                             1,800,000 seeds/ha at the low bound)

seeds per square metre   = seeds per hectare / 10,000
                         = 1,800,000 / 10,000 = 180 seeds/m2

surface seeds per m2     = seeds per m2 x surface fraction for the
                            planting method
                         = 180 x 1.0 (broadcast) = 180 seeds/m2
```

This last number — **180 surface seeds per square metre** — is directly
checkable against the audited workbook (`Seed Inputs and EECs!AC4`). It is
the physical starting point for everything a bird might eat.

*Note on Barley specifically:* some crops in the source data give a
**mass** seeding rate (kg seed/ha) instead of a seed count, in which case
the model derives the seed count using the seed weight:
`seeds/ha = seeding_rate_kg_per_ha x 1,000,000 / TKW`. Barley's low bound
happens to be given as a seed count directly, so that conversion doesn't
apply to this particular number — but it does apply elsewhere, and the
model handles both directions bidirectionally (specification §5.2).

*R code:* `R/calculations/01_seed_parameters.R` (`seed_mass_from_tkw()`,
`seeds_per_ha_from_mass()`, `seeds_per_m2()`); `R/calculations/02_surface_seed.R`
(`surface_seed_initial()`).

---

## 3. How much pesticide is on each seed, and on the field overall

The registered rate (300 mg a.i. per **kilogram** of seed) has to be turned
into two different things: how much is on **one seed**, and how much lands
on **one hectare** of field.

```
active ingredient per seed (mg)  = rate (mg/kg) x seed weight (g) / 1000
                                  = 300 x 0.0248 / 1000
                                  = 0.00744 mg a.i./seed

field rate (g a.i./ha)           = (rate (mg/kg) / 1000) x mass seeding
                                    rate (kg seed/ha)
                                  = (300 / 1000) x 44.64
                                  = 13.392 g a.i./ha
```

Both numbers are directly checkable against the audited workbook
(`Seed Inputs and EECs!Q4` = 0.00744; `!W4` = 13.392).

Registered rates can also be supplied the other way round — mg a.i. **per
seed** instead of per kg — and the model converts in whichever direction is
needed, never assuming one form (specification §5.3).

*R code:* `R/calculations/01_seed_parameters.R`, functions
`treatment_loading()` and `field_rate_g_ai_per_ha()`.

---

## 4. How much food a bird or mammal needs, and how many seeds that is

The model uses a standard ecological method (a **Nagy allometric
regression**) to estimate how much a receptor eats per day, based only on
its body weight:

```
food eaten per day (g, dry weight) = a x (body weight, g) ^ b
```

`a` and `b` are fitted constants that differ by taxon and, for birds, by
size class. For our small bird (20 g, "Nagy 1987, Passerines" regression,
a = 0.398, b = 0.85):

```
food per day = 0.398 x 20^0.85 = 5.078770267 g dry-weight diet/day
```

This is a **dry-weight** figure. The model does not convert it to a
fresh-weight basis, because no such conversion is stated anywhere in the
source assessment or workbook — applying one would change every dose
figure in the model, so it is treated as an explicit, documented gap
(specification §14) rather than silently assumed one way or the other.

If the bird ate **only** treated barley seed (a "100% treated-seed diet" —
the conservative screening assumption), it would need to eat:

```
seeds needed per day = food per day / seed weight
                      = 5.078770267 / 0.0248
                      = 204.79 seeds/day
```

Note this is what the bird **needs**, not what is physically **available**
on the ground — that is a separate question, addressed in section 7.

*R code:* `R/calculations/03_receptor.R`, functions `food_requirement()` and
`seeds_required_per_day()`.

---

## 5. Turning "seeds eaten" into a dose, and the dose into a risk quotient

There are two equally valid ways to arrive at the daily dose, and the model
computes both and checks they agree (they do, to machine precision):

```
Method A (from concentration):
  dose (mg a.i./kg bw/day) = seed concentration (mg/kg) x food per day (g)
                              / body weight (g) x dietary fraction
                            = 300 x 5.078770267 / 20 x 1.0
                            = 76.1816 mg a.i./kg bw/day

Method B (from seed count):
  dose = seeds eaten per day x dose per seed (mg) / (body weight (g)/1000)
       = 204.79 x 0.00744 / (20/1000)
       = 76.1816 mg a.i./kg bw/day       (same answer)
```

A useful, non-obvious consequence of Method A: **the dose does not depend
on seed weight** when the rate is expressed per kg of seed — a heavier seed
carries proportionally more pesticide, but the bird also needs to eat
proportionally fewer of them, and the two effects cancel exactly. Seed
weight *does* still affect how many individual seeds are involved (relevant
to sections 4 and 7), just not the dose itself. This is exactly the kind of
relationship that is easy to get backwards by intuition, which is why the
specification calls it out explicitly (§9.1) and the independent audit
checks it directly.

The **risk quotient (RQ)** simply divides the dose by a toxicological
reference value (an "effects metric" — a screening dose known, with a
safety margin already built in, to be a level of concern):

```
RQ = dose / effects metric

Acute screening metric for birds:   43.1 mg a.i./kg bw/d
RQ (acute)   = 76.1816 / 43.1  = 1.768

Chronic screening metric for birds: 7.78 mg a.i./kg bw/d
RQ (chronic) = 76.1816 / 7.78  = 9.794
```

An RQ at or above 1 means the modelled exposure reaches or exceeds the
effects metric.

*R code:* `R/calculations/04_exposure_risk.R`, functions
`estimated_daily_exposure()`, `daily_ai_intake_dose()`, `risk_quotient()`.

---

## 6. Two things get less over time, for two completely different reasons

This is the part of the model most likely to be misunderstood if read
quickly, so it is worth stating plainly: **two separate processes cause
exposure to decline after sowing, and the model never lets them share a
number.**

**Process 1 — seeds disappear from the surface.** Seeds get buried,
germinate, get eaten by something else, or get displaced, regardless of
whether they still carry pesticide. This has its own half-life
(**14 days**, the "surface-seed DT50"):

```
seeds remaining on the surface at day t = seeds at day 0 x 2^(-t / 14)
```

**Process 2 — the pesticide on a seed that is STILL THERE breaks down.**
This is a completely separate chemical process with its own half-life
(**10 days**, the "residue DT50"):

```
a.i. remaining on a surviving seed at day t = a.i. at day 0 x 2^(-t / 10)
```

**The total pesticide sitting on the field surface** is the product of
both — how many seeds are still there, times how much each one still
carries — and because it is a product of two declines, it falls away
**faster than either process alone**:

```
day    surface seeds        a.i./seed         surface loading (product)
  0    180.0                0.00744           1.339
  7    127.3                0.00526           0.583
 14     90.0                0.00372           0.254
 21     55.1                0.00263           0.111
 28     45.0                0.00186           0.048
```

For sugar beet's pelleted seed, the assessment treats the pesticide as
essentially not breaking down at all over the relevant timeframe (residue
DT50 = infinity); the model represents this literally — an infinite
half-life returns a constant, not a special-cased crop name.

The **regulatory dose and RQ decline using Process 2 only** (residue
dissipation) — a bird's exposure is capped by how much pesticide is left on
whatever seed it eats, not by whether enough seed is still visible.
Whether enough seed is *physically findable* is a third, separate question,
covered next.

*R code:* `R/calculations/02_surface_seed.R` (both processes and their
product); `R/calculations/04_exposure_risk.R`, function
`daily_dose_over_time()` (residue decline applied to dose);
`duration_above_effect_metric()` (solves for the day the dose falls back to
the effects metric).

---

## 7. Could the animal actually find that much seed? A separate question

Sections 5-6 calculate the **regulatory exposure** — what the model assumes
the animal eats, as a fixed dietary fraction, for as long as the math says
exposure remains above a threshold. That is deliberately a conservative,
assumption-driven number, not a claim about literal foraging behaviour.

A separate diagnostic asks a different, more concrete question: **given how
much seed is actually visible on the ground, and how large an area the
animal is assumed to search, could it physically obtain that much treated
seed?** This uses a **maximum search area (MSA)** — 70 m² for a small bird
over a short period, per the assessment's own values.

```
seeds available within the search area = surface seeds/m2 x MSA (m2)
                                        = 180 x 70 = 12,600 seeds

maximum feasible dietary fraction = seeds available / seeds needed for a
                                     full diet
                                   = 12,600 / (5.079 / 0.0248)
                                   = 12,600 / 204.79 = 61.5
                                     (i.e. 6,150% of a full diet — far more
                                     than needed, at day 0, for this
                                     scenario)

search area actually required for a full diet = seeds needed per day /
                                                  surface seeds per m2
                                                = 204.79 / 180
                                                = 1.14 m2   (well under
                                                  the 70 m2 MSA)
```

**This is a plausibility check, not a cap.** Nothing calculated here is
allowed to reduce the dose or RQ computed in sections 5-6 — the model keeps
"what we assume the animal eats" and "what we can show is physically
available" as two clearly separate output columns, never one overriding the
other, because the source assessment itself treats MSA as a refinement
check rather than a hard exposure limit (specification §10.3). This
separation is one of the things the independent audit specifically checked
for, because silently letting a feasibility number cap a regulatory
exposure number would be a serious, easy-to-miss error.

*R code:* `R/calculations/05_feasibility.R`, entire file. None of its
functions write to any dose/RQ column — check this yourself by searching
for every place `available_seed_within_msa`, `required_search_area`,
`maximum_feasible_diet_fraction` or `days_diet_fraction_feasible` is used
downstream.

---

## 8. How it all fits together

```
thousand-seed weight ──► seed weight ──► seeds/ha ──► seeds/m2 ──► surface seeds/m2
                                                                          │
seed treatment rate (mg/kg or mg/seed) ──► dose per seed ──► field rate  │
                                                    │                    │
                                                    ▼                    ▼
                                    body weight ──► food/day ──► seeds needed/day
                                                    │                    │
                                                    ▼                    │
                                    dose (EDE) ──► risk quotient (RQ)    │
                                                    │                    │
                                    residue DT50 ──► dose over time      │
                                                    │                    │
                                                    ▼                    │
                                    duration above the effects metric    │
                                                                          │
                        surface-seed DT50 ──► surface seeds over time ◄──┘
                                                    │
                                                    ▼
                        MSA ──► seeds available ──► feasibility diagnostic
                                (never feeds back into dose or RQ above)
```

---

## 9. Where each canonical dataset fits

The model produces exactly four authoritative result tables, and every
plot, Word table, CSV export and Shiny view is built from these and nothing
else (specification §11):

| Dataset | What one row is | Roughly how many rows |
|---|---|---:|
| `scenario_inputs` | One crop x rate x planting method x seeding-bound x seed-weight-bound combination | Hundreds |
| `daily_timecourse` | One scenario x receptor x metric x diet fraction x day | Large; built for a documented representative slice, not every scenario at once |
| `scenario_summary` | One scenario x receptor x metric x diet fraction, closed-form (no day loop needed) | Tens of thousands, across all crops in a workbook |
| `table162_support` | One crop family x rate x method x receptor x duration class, joined to the evidence/consideration registers | One row per decision the assessment has to make a Table 162 call on |

`scenario_summary` is deliberately large because it is meant to be queried
and filtered (in Shiny, in CSV, in a spreadsheet), not printed. The "how
many rows should end up in a Word document" question is handled separately
— see `docs/word_export_diagnosis.md`.

---

## 10. Two exposure questions: conditional versus maximum obtainable

Section 7 already distinguished the calculated regulatory exposure from
the MSA feasibility diagnostic. The "maximum obtainable exposure" figure
(the "Maximum obtainable exposure" dashboard tab) puts both on one plot so
the difference is visible directly, and answers a sharper version of the
feasibility question: not just "is the assumed diet fraction obtainable?"
but "what is the largest dose this receptor could actually get, given how
much treated seed genuinely remains?"

**Two curves, two different questions:**

- **"100% treated-seed diet"** — the same conditional RQ from section 5,
  assuming the receptor gets a stated fraction of its diet (100% here) from
  treated seed. This never depends on how much seed is actually present.
- **"Maximum obtainable within MSA"** — the RQ if the receptor eats as much
  treated seed as it can find within its search area, **capped at whichever
  is smaller**: the seed actually available, or the receptor's own daily
  food requirement (a receptor is never modelled as eating past its own
  appetite just because seed is abundant).

```
maximum obtainable seeds/day = min(seeds required for the assumed diet,
                                    seeds available within the applicable MSA)
```

**Worked example, continuing the Barley scenario from section 5** (small
bird, 300 mg a.i./kg seed, broadcast, chronic screening metric 7.78 —
figures verified by `scripts/reviewer_validation_walkthrough.R` and the
independent audit):

| Day | Seeds required for 100% diet | Seeds available within MSA (70 m²) | Conditional RQ | Maximum-obtainable RQ |
|---:|---:|---:|---:|---:|
| 0 | 205 | 12,600 | 1.77 | 1.77 (identical — abundant seed) |
| 60 | 205 | 646 | 0.0276 | 0.0276 (still identical — still abundant) |
| 83.2 | 205 | 205 | 0.00553 | 0.00553 (the exact crossover point) |
| 95 | 205 | 114 | 0.00244 | **0.00136 (now seed-limited — the curves have diverged)** |

The two curves are **identical** for as long as more seed is available than
the receptor needs — the cap never binds, so "maximum obtainable" and
"100% assumed diet" describe the same thing. They **diverge** exactly at
the day availability drops below requirement (day 83.2 here — the same
value independently audited from the source workbook, `docs/independent_engine_audit.md`
§6.1). Past that point the maximum-obtainable curve falls faster, because
it is now driven by **both** declining processes at once (surface-seed
disappearance **and** residue dissipation) rather than residue dissipation
alone.

**Which maximum search area (MSA) is used is not a free choice for this
figure.** The source assessment states explicitly (paragraph `MAIN-P000209`):
birds use the short-term MSA for **both** acute and chronic/reproductive
characterization — a long-term bird MSA was considered and explicitly not
applied, because the assessment found no evidence that reproductive effects
were due to sustained exposure rather than a critical parental exposure
window. Mammals use the short-term MSA for acute characterization and the
long-term MSA for chronic/reproductive characterization, because mammalian
reproductive effects were attributed to prolonged parental exposure. The
dashboard resolves this automatically per receptor and effects metric — it
is not a manual toggle for this specific figure, unlike the general
"Exposure feasibility" tab's MSA control (specification §10.4).

**When each curve crosses the level of concern (LOC, RQ = 1) is computed
exactly, not read off a plot.** The conditional crossing uses the same
closed-form solution as section 6. The maximum-obtainable crossing is
piecewise: while seed is abundant it follows the same closed form as the
conditional curve (both are governed by residue dissipation alone); once
seed becomes limiting, it follows the **combined** half-life from section 6
instead. In the worked example above, the chronic RQ already falls below 1
at day 8.22 — well before seed becomes limiting at day 83.2 — so both
crossing days happen to coincide exactly in this case.

*R code:* `R/calculations/05_feasibility.R` (`resolve_msa_term_for_metric()`,
`max_obtainable_seeds_per_day()`); the new columns in
`R/summaries/22_daily_timecourse.R`; `R/summaries/26_max_obtainable_summary.R`;
plotting in `R/reporting/35_max_obtainable_plots.R`.

---

## 11. Where to go next

- Run `scripts/reviewer_validation_walkthrough.R` yourself and change the
  crop, rate, or receptor in Parts 1 and 8 to walk through a different
  scenario end to end.
- `docs/manual_acceptance_test.md` gives you a structured pass/fail sheet
  covering the Shiny dashboard using these same relationships.
- `docs/independent_engine_audit.md` is a separate, adversarial check of
  this same calculation chain, performed without trusting the code that
  implements it.
