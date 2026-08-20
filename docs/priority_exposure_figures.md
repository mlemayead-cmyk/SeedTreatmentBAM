# Priority static exposure/risk figures

## Purpose

This workflow produces publication-quality, self-contained figures without
launching Shiny. It uses the canonical calculation engine and the assessment
baseline parameters. The conventional conditional dietary RQ is preserved and
shown separately from the maximum exposure obtainable from accessible treated
surface seed within the applicable maximum search area (MSA).

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
bw/day) and bird chronic screening metric (7.78 mg a.i./kg bw/day), exported as
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
