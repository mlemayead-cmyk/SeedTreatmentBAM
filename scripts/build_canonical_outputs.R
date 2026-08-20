#!/usr/bin/env Rscript
# Rebuild every canonical output from the assessment baseline.
#
#   Rscript scripts/build_canonical_outputs.R [workbook]
#
# Writes to outputs/ :
#   canonical/     the four canonical datasets, as CSV and one XLSX
#   tables/        the official tables, as CSV and Word
#   figures/       publication-quality plots, as PNG and SVG
#   build_manifest.csv   what was written, when, and from which sources

root <- getwd()
if (!dir.exists(file.path(root, "R"))) {
  stop("Run this from the project root.", call. = FALSE)
}
source(file.path(root, "R", "load_model.R"))
load_stbam(root, include = c("core", "reporting"))

args <- commandArgs(trailingOnly = TRUE)
workbook <- if (length(args) >= 1L) args[[1]] else "small_cereals"

started <- Sys.time()
cat(sprintf("Building canonical outputs for '%s'\n", workbook))

baseline <- load_baseline()
params <- parameter_set(baseline, "Assessment baseline")
stopifnot(!has_overrides(params))

out_dir <- file.path(root, "outputs")
dirs <- file.path(out_dir, c("canonical", "tables", "figures"))
for (dir in dirs) dir.create(dir, recursive = TRUE, showWarnings = FALSE)

# --- Canonical datasets ----------------------------------------------------

cat("  scenario_inputs ...\n")
scenario_inputs <- build_scenario_inputs(params, workbooks = workbook)

cat("  scenario_summary ...\n")
receptors <- resolve_receptors(params)
metrics <- resolve_effects_metrics(params, c("SCREENING", "REFINED",
                                             "REFINED_ADDITIONAL"))
scenario_summary <- build_scenario_summary(params, scenario_inputs, receptors,
                                           metrics, STBAM_DIET_FRACTIONS)

cat("  table162_support ...\n")
table162 <- build_table162_support(params, scenario_summary)
assert_human_fields_empty(table162)

# The daily time course is written for a DOCUMENTED REPRESENTATIVE SLICE, not
# for every scenario. A full daily expansion of every crop, rate, method,
# agronomic bound, receptor, metric, dietary fraction and day would be on the
# order of a gigabyte of CSV and would be useless as an artefact.
#
# The slice is: the maximum registered rate, every crop and planting method,
# the highest-availability agronomic corner (upper seeding rate with the
# lightest seed), every receptor, the screening metrics, every dietary
# fraction, days 0-60.
#
# This loses nothing scientifically, because scenario_summary is closed-form
# and already covers EVERY scenario, and the dashboard and reports rebuild the
# time course on demand for whatever selection the user makes.
cat("  daily_timecourse (documented representative slice) ...\n")
slice <- scenario_inputs[
  scenario_inputs$rate_level == "high" &
    scenario_inputs$seeding_rate_bound == "high" &
    scenario_inputs$seed_mass_bound == "low_tkw",
]
daily_timecourse <- build_daily_timecourse(
  params, slice, receptors,
  resolve_effects_metrics(params, "SCREENING"),
  STBAM_DIET_FRACTIONS, days = 0:60
)
timecourse_slice_note <- paste(
  "Maximum registered rate; every crop and planting method; upper seeding-rate",
  "bound with the low thousand-seed weight (highest availability corner);",
  "every receptor; screening effects metrics; days 0-60."
)

canonical <- list(
  scenario_inputs = scenario_inputs,
  table162_support = table162
)

cat("  writing canonical datasets ...\n")
export_csv(canonical, file.path(out_dir, "canonical"))

# The two large datasets are written compressed. readr selects the compression
# from the file extension, and read_csv() reads them back transparently.
readr::write_csv(scenario_summary,
                 file.path(out_dir, "canonical", "scenario_summary.csv.gz"),
                 na = "")
readr::write_csv(daily_timecourse,
                 file.path(out_dir, "canonical", "daily_timecourse.csv.gz"),
                 na = "")
writeLines(
  c("daily_timecourse.csv.gz covers a representative slice, not every scenario.",
    timecourse_slice_note,
    "",
    "scenario_summary.csv.gz is closed-form and covers EVERY scenario,",
    "receptor, effects metric and dietary fraction."),
  file.path(out_dir, "canonical", "README_slice.txt")
)

export_xlsx(
  c(list(scenario_inputs = scenario_inputs),
    stats::setNames(
      lapply(names(STBAM_TABLES), build_official_table,
             scenario_summary = scenario_summary),
      names(STBAM_TABLES)
    )),
  file.path(out_dir, "canonical", "canonical_datasets.xlsx")
)

# --- Official tables -------------------------------------------------------

cat("  official tables ...\n")
for (table_id in names(STBAM_TABLES)) {
  table <- build_official_table(table_id, scenario_summary)
  readr::write_csv(table, file.path(out_dir, "tables",
                                    paste0(table_id, ".csv")))
}
export_tables_docx(names(STBAM_TABLES), scenario_summary,
                   file.path(out_dir, "tables", "official_tables.docx"),
                   document_title = paste("Model output tables:", workbook))
export_quantitative_appendix(params, scenario_inputs, scenario_summary,
                             file.path(out_dir, "tables",
                                       "quantitative_appendix.docx"))

# --- Figures ---------------------------------------------------------------

cat("  figures ...\n")
figure_slice <- daily_timecourse[
  daily_timecourse$scenario_id == daily_timecourse$scenario_id[1] &
    daily_timecourse$receptor_id == "bird_small" &
    daily_timecourse$metric_id == "bird_chronic_screening",
]
figures <- list(
  surface_seeds = plot_surface_seeds(figure_slice, colour_by = "crop"),
  ai_per_seed = plot_ai_per_seed(figure_slice, colour_by = "crop"),
  surface_ai = plot_surface_ai(figure_slice, colour_by = "crop"),
  process_separation = plot_process_separation(figure_slice),
  dose = plot_dose(figure_slice),
  risk_quotient = plot_risk_quotient(figure_slice),
  search_area = plot_search_area(figure_slice),
  feasible_diet = plot_feasible_diet(figure_slice, colour_by = "receptor_id")
)
comparison <- scenario_summary[
  scenario_summary$metric_id == "bird_chronic_screening" &
    scenario_summary$diet_fraction == 1,
]
figures$rq_comparison <- plot_rq_comparison(comparison)
figures$duration_comparison <- plot_duration_comparison(comparison)

for (name in names(figures)) {
  save_plot(figures[[name]], file.path(out_dir, "figures", name))
}

# --- Manifest --------------------------------------------------------------

written <- list.files(out_dir, recursive = TRUE, full.names = TRUE)
manifest <- tibble::tibble(
  file = sub(paste0(normalizePath(out_dir, winslash = "/"), "/"), "",
             normalizePath(written, winslash = "/")),
  bytes = file.size(written),
  sha256 = vapply(written, function(path) {
    as.character(digest::digest(path, algo = "sha256", file = TRUE))
  }, character(1), USE.NAMES = FALSE),
  built_at = format(started, "%Y-%m-%dT%H:%M:%S%z"),
  workbook = workbook,
  parameter_set = params$name,
  specification_version = STBAM_MODEL_VERSION
)
readr::write_csv(manifest, file.path(out_dir, "build_manifest.csv"))

cat(sprintf(
  "\nDone in %.1f s.\n  scenario_inputs   %s rows\n  scenario_summary  %s rows\n  daily_timecourse  %s rows\n  table162_support  %s rows\n  files written     %d\n",
  as.numeric(difftime(Sys.time(), started, units = "secs")),
  format(nrow(scenario_inputs), big.mark = ","),
  format(nrow(scenario_summary), big.mark = ","),
  format(nrow(daily_timecourse), big.mark = ","),
  format(nrow(table162), big.mark = ","),
  nrow(manifest)
))
