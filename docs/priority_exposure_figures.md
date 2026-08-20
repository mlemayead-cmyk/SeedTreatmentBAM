# Priority static exposure/risk figures

## Purpose

This workflow produces publication-quality, self-contained figures without
launching Shiny. It uses the canonical calculation engine and the assessment
baseline parameters. The conventional conditional dietary RQ is preserved and
shown separately from the maximum exposure obtainable from accessible treated
surface seed within the applicable maximum search area (MSA).

## What the figures are presenting

These figures show how predicted dietary risk changes during the 120 days
after sowing. They deliberately separate a standard conservative exposure
assumption from an estimate constrained by the amount of treated seed present
in the field.

In each main acute or chronic figure, the **blue curve** is the conventional
conditional risk quotient (RQ): it assumes that the bird obtains 100% of its
daily dry-weight food requirement as treated seed, whether or not that amount
of seed is actually present. The **orange curve** is the maximum-obtainable RQ:
treated-seed consumption is capped at the smaller of the bird's daily food
requirement and the treated surface seed available within its maximum search
area (MSA). The orange curve is therefore an availability refinement, not a
replacement for or alteration of the conventional calculation.

The horizontal dashed line marks the level of concern, **RQ = 1**. Values above
1 mean that the modelled dose is greater than the selected effects metric;
values below 1 mean that it is lower. RQ is a screening ratio, not a probability
of harm and not evidence that an effect occurred in the field. The most useful
features to compare are the peak RQ, the time at which each curve drops below 1,
and the size and timing of the gap between the blue and orange curves.

If the blue and orange curves overlap, sufficient treated seed is present within
the MSA to support the assumed 100% treated-seed diet. If the orange curve lies
below the blue curve, exposure is limited by field seed availability. Both
curves decrease as residue dissipates from each remaining seed. Once seed
availability becomes limiting, the orange curve can decrease more quickly
because it reflects both residue dissipation and the disappearance of surface
seed. A low orange RQ should therefore be interpreted as a lower physically
obtainable exposure under the model assumptions, not as a change to the
effects endpoint.

The three panels represent small (20 g), medium (100 g) and large (1,000 g)
birds. Body weight, daily food requirement and MSA differ among them. Each panel
has an independent RQ scale so its curves remain legible; compare the printed
axis values and LOC crossings rather than the apparent height of curves across
panels. Acute and chronic figures use different effects metrics. Consistent with
the source assessment, birds use the short-term MSA for both characterizations.

The four-panel process figure shows why the maximum-obtainable curve changes:

- **A — Surface seeds remaining:** the number of accessible treated seeds per
  m2 declines according to the surface-seed disappearance DT50.
- **B — Residue remaining per seed:** the active ingredient on each seed
  declines independently according to the residue DT50.
- **C — Active ingredient with surface seed:** active ingredient per m2 is the
  product of the seed count in panel A and residue per seed in panel B.
- **D — Exposure feasibility:** treated seeds available within each bird's MSA
  divided by the seeds required for a 100% treated-seed diet. Values above 1
  indicate sufficient seed, 1 is the transition point, and values below 1
  indicate that exposure is seed-limited.

The dietary-fraction figures are sensitivity scenarios. They show the
conventional RQ that would result if treated seed made up an assumed 1%, 5%,
10%, 25%, 50% or 100% of the diet. They do **not** show that a bird can find or
will consume those fractions. Their curves decline only with residue per seed;
physical obtainability must be evaluated from the orange maximum-obtainable
curve and process panel D.

## Command

Run from the project root:

```powershell
& "C:\Program Files\R\R-4.4.3\bin\x64\Rscript.exe" scripts\generate_priority_exposure_figures.R
```

A development-only `--smoke` argument generates one selected scenario while
testing the export path. It is not the complete deliverable.

## Coverage and grouping

The human-readable CSV and XLSX summaries cover every canonical scenario row
for:

- Small Cereals;
- Legumes — shallow seeded;
- Legumes — deep seeded;
- small, medium and large birds; and
- every canonical bird screening and refined-additional effects metric.

Generating a separate figure for every crop × rate × method × seeding-rate
bound × TKW bound would produce hundreds of near-duplicate figures. The figure
batch therefore preserves every actual crop-group × numeric treatment-loading
× planting-method signature and selects two real canonical rows within each
signature: the lower and upper initial surface seed mass supply, defined as
initial surface seeds/m² × seed mass. This brackets the joint TKW, seeding-rate
and surface-fraction inputs. The exact selected rows, represented crop list and
selection basis are recorded in
`outputs/figures/priority_figure_scenarios.csv`; the complete scenario results
remain in `priority_exposure_summary.csv` and `.xlsx`.

The static figure set uses the bird acute screening metric (43.1 mg a.i./kg
bw/d) and bird chronic screening metric (7.78 mg a.i./kg bw/d), exported as
separate one-row, three-receptor small multiples. The full summary also retains
all canonical bird refined-additional metrics and their endpoint provenance.

## Maximum-obtainable calculation

For each receptor and day:

```text
maximum obtainable treated seeds consumed
  = min(seeds required for the assumed diet,
        accessible treated seeds within the applicable MSA)

maximum obtainable intake
  = maximum obtainable treated seeds consumed × a.i. remaining per seed

maximum obtainable dose
  = maximum obtainable intake / body weight

maximum obtainable RQ
  = maximum obtainable dose / effects metric
```

Consumption therefore never exceeds the daily food requirement and never
exceeds accessible seed within the MSA. This quantity is a separately named
diagnostic/refinement; it does not replace the conventional conditional RQ.

The MSA policy follows assessment paragraph `MAIN-P000209`: birds use the
short-term MSA for both acute and chronic/reproductive characterization.
Mammals (not part of the priority figure batch) use short-term MSA for acute
and long-term MSA for chronic/reproductive characterization.

## Outputs

Outputs are under `outputs/figures/`:

```text
small_cereals/{acute,chronic,process,dietary_fraction}/
legumes_shallow/{acute,chronic,process,dietary_fraction}/
legumes_deep/{acute,chronic,process,dietary_fraction}/
priority_exposure_summary.csv
priority_exposure_summary.xlsx
priority_figure_scenarios.csv
priority_figure_files.csv
README_priority_figures.md
```

Each logical figure is exported as 300-dpi PNG and SVG. The file manifest
records size and SHA-256 for every export. Figure captions carry scenario,
agronomic, fate, receptor, toxicity/effects-metric, LOC, override and model/Git
traceability metadata so the image can be reviewed outside Shiny.
