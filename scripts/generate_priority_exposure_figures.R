#!/usr/bin/env Rscript
# Generate self-contained static exposure/risk figures for the current
# Small Cereals, shallow-legume and deep-legume assessment scenarios.
#
# Run from the project root:
#   "C:/Program Files/R/R-4.4.3/bin/x64/Rscript.exe" scripts/generate_priority_exposure_figures.R
#
# Optional development-only smoke run (one selected scenario):
#   ... scripts/generate_priority_exposure_figures.R --smoke

root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
if (!file.exists(file.path(root, "R", "load_model.R"))) {
  stop("Run this script from the project root.", call. = FALSE)
}
source(file.path(root, "R", "load_model.R"))
load_stbam(root, include = c("core", "reporting"))

args <- commandArgs(trailingOnly = TRUE)
smoke <- "--smoke" %in% args
unknown <- setdiff(args, "--smoke")
if (length(unknown) > 0L) {
  stop("Unknown argument(s): ", paste(unknown, collapse = ", "), call. = FALSE)
}

started <- Sys.time()
generated_at <- format(started, "%Y-%m-%d %H:%M %Z")
workbooks <- c("small_cereals", "legumes_shallow", "legumes_deep")
group_folders <- c(
  small_cereals = "small_cereals",
  legumes_shallow = "legumes_shallow",
  legumes_deep = "legumes_deep"
)
group_labels <- c(
  small_cereals = "Small Cereals",
  legumes_shallow = "Legumes — shallow seeded",
  legumes_deep = "Legumes — deep seeded"
)
receptor_ids <- c("bird_small", "bird_medium", "bird_large")
screening_metric_ids <- c("bird_acute_screening", "bird_chronic_screening")
plot_days <- 0:120

slug <- function(x, max_chars = 48L) {
  x <- iconv(x, from = "", to = "ASCII//TRANSLIT", sub = "")
  x <- tolower(gsub("[^a-zA-Z0-9]+", "_", x))
  x <- gsub("^_+|_+$", "", x)
  substr(x, 1L, max_chars)
}

rate_tag <- function(row) {
  unit <- if (identical(row$application_rate_unit[[1]], "mg a.i./seed")) {
    "mg_ai_seed"
  } else {
    "mg_ai_kg_seed"
  }
  paste0(format(row$application_rate[[1]], scientific = FALSE, trim = TRUE),
         "_", unit)
}

figure_stub <- function(row) {
  short_id <- substr(digest::digest(row$scenario_id[[1]], algo = "sha256",
                                    serialize = FALSE), 1L, 8L)
  paste(
    group_folders[[row$workbook[[1]]]], slug(row$crop[[1]]), rate_tag(row),
    slug(row$planting_method[[1]]), row$figure_envelope_role[[1]], short_id,
    sep = "_"
  )
}

cat("Loading assessment-default scenarios and bird metadata ...\n")
baseline <- load_baseline()
params <- parameter_set(baseline, "Assessment baseline")
stopifnot(!has_overrides(params))
scenario_inputs <- build_scenario_inputs(params, workbooks = workbooks)
bird_receptors <- resolve_receptors(params, receptor_ids)
bird_metrics <- resolve_effects_metrics(
  params, c("SCREENING", "REFINED", "REFINED_ADDITIONAL"), taxa = "bird"
)
screening_metrics <- bird_metrics[
  bird_metrics$metric_id %in% screening_metric_ids,
]

out_root <- file.path(root, "outputs", "figures")
dir.create(out_root, recursive = TRUE, showWarnings = FALSE)
for (group in unname(group_folders)) {
  for (subdir in c("acute", "chronic", "process", "dietary_fraction")) {
    dir.create(file.path(out_root, group, subdir), recursive = TRUE,
               showWarnings = FALSE)
  }
}

# Full human-readable table: every canonical priority scenario row, all three
# bird receptors, and every canonical bird effects metric. Only day 0 is needed
# because peaks occur at sowing and both LOC crossings are solved exactly.
cat("Building complete priority summary (all scenarios and bird metrics) ...\n")
summary_inputs <- if (smoke) scenario_inputs[1, ] else scenario_inputs
summary_timecourse <- build_daily_timecourse(
  params, summary_inputs, bird_receptors, bird_metrics,
  diet_fractions = 1, days = 0
)
priority_summary <- summarise_max_obtainable_exposure(summary_timecourse)

metric_provenance <- bird_metrics[, c(
  "metric_id", "endpoint_description", "endpoint_value", "unit",
  "uncertainty_factor", "source"
)]
names(metric_provenance)[names(metric_provenance) == "source"] <-
  "effects_metric_source"
priority_summary <- dplyr::left_join(priority_summary, metric_provenance,
                                     by = "metric_id")
priority_summary$crop_group <- unname(group_labels[priority_summary$workbook])
priority_summary$shallow_deep_designation <- dplyr::case_when(
  priority_summary$workbook == "legumes_shallow" ~ "shallow seeded",
  priority_summary$workbook == "legumes_deep" ~ "deep seeded",
  TRUE ~ "not applicable"
)
priority_summary$effects_metric_label <- mapply(
  format_metric_label, priority_summary$taxon,
  priority_summary$duration_class, priority_summary$metric_role,
  priority_summary$effects_metric, SIMPLIFY = TRUE, USE.NAMES = FALSE
)
priority_summary$loc <- STBAM_DEFAULT_LOC
priority_summary$rq_definition <- "RQ = dose / effects metric"
priority_summary$user_override_status <- "ASSESSMENT DEFAULT — no overrides"
priority_summary$model_version <- STBAM_MODEL_VERSION
priority_summary$git_commit <- read_project_git_commit()
priority_summary$generated_at <- generated_at
priority_summary <- dplyr::relocate(
  priority_summary, "crop_group", "shallow_deep_designation",
  .after = "workbook"
)
priority_summary <- dplyr::arrange(
  priority_summary, .data$workbook, .data$crop, .data$application_rate_unit,
  .data$application_rate, .data$planting_method, .data$seeding_rate_bound,
  .data$seed_mass_bound, .data$receptor_id, .data$duration_class,
  .data$metric_id
)

summary_csv <- file.path(out_root, "priority_exposure_summary.csv")
summary_xlsx <- file.path(out_root, "priority_exposure_summary.xlsx")
readr::write_csv(priority_summary, summary_csv, na = "")

# Figure selection: preserve every actual treatment-loading x planting-method
# signature. Within each signature select the canonical rows with the lowest
# and highest initial surface seed mass supply (surface seeds/m2 x seed mass).
# This brackets the joint TKW, seeding-rate and surface-fraction inputs without
# generating a redundant figure for all 836 canonical agronomic rows. The CSV
# summary above still covers every row.
cat("Selecting non-redundant agronomic-envelope scenarios for figures ...\n")
scenario_inputs$.surface_seed_mass_supply_g_m2 <-
  scenario_inputs$initial_surface_seeds_per_m2 * scenario_inputs$seed_mass_g
signature <- interaction(
  scenario_inputs$workbook, scenario_inputs$application_rate,
  scenario_inputs$application_rate_unit, scenario_inputs$planting_method,
  drop = TRUE, lex.order = TRUE
)
signature_indices <- split(seq_len(nrow(scenario_inputs)), signature)
selection_rows <- vector("list", length(signature_indices))
selection_info <- vector("list", length(signature_indices))

for (i in seq_along(signature_indices)) {
  ix <- signature_indices[[i]]
  candidates <- scenario_inputs[ix, ]
  candidates <- candidates[order(candidates$scenario_id), ]
  low_i <- which.min(candidates$.surface_seed_mass_supply_g_m2)
  high_i <- which.max(candidates$.surface_seed_mass_supply_g_m2)
  chosen <- candidates[unique(c(low_i, high_i)), ]
  chosen$figure_envelope_role <- if (low_i == high_i) {
    "lower_upper_supply"
  } else {
    c("lower_supply", "upper_supply")
  }
  signature_id <- paste(
    candidates$workbook[[1]], candidates$application_rate[[1]],
    candidates$application_rate_unit[[1]], candidates$planting_method[[1]],
    sep = "|"
  )
  chosen$figure_signature_id <- signature_id
  chosen$represented_scenario_rows <- nrow(candidates)
  chosen$represented_crops <- paste(sort(unique(candidates$crop)), collapse = "; ")
  selection_rows[[i]] <- chosen
  selection_info[[i]] <- data.frame(
    figure_signature_id = signature_id,
    workbook = candidates$workbook[[1]],
    application_rate = candidates$application_rate[[1]],
    application_rate_unit = candidates$application_rate_unit[[1]],
    planting_method = candidates$planting_method[[1]],
    represented_scenario_rows = nrow(candidates),
    represented_crops = paste(sort(unique(candidates$crop)), collapse = "; "),
    stringsAsFactors = FALSE
  )
}
figure_scenarios <- dplyr::bind_rows(selection_rows)
if (smoke) {
  smoke_i <- grep("upper", figure_scenarios$figure_envelope_role,
                  fixed = TRUE)[[1]]
  figure_scenarios <- figure_scenarios[smoke_i, ]
}
figure_scenarios <- dplyr::arrange(
  figure_scenarios, .data$workbook, .data$application_rate_unit,
  .data$application_rate, .data$planting_method, .data$figure_envelope_role
)
selection_manifest <- dplyr::select(
  figure_scenarios,
  "figure_signature_id", "figure_envelope_role", "represented_scenario_rows",
  "represented_crops", "scenario_id", "workbook", "crop", "rate_level",
  "application_rate", "application_rate_unit", "planting_method",
  "planting_method_label", "seeding_rate_bound", "seed_mass_bound",
  "tkw_g_per_1000", "seeding_rate_kg_per_ha", "seeds_per_m2",
  "surface_seed_fraction", "initial_surface_seeds_per_m2",
  ".surface_seed_mass_supply_g_m2", "field_rate_g_ai_per_ha"
)
names(selection_manifest)[names(selection_manifest) ==
                            ".surface_seed_mass_supply_g_m2"] <-
  "initial_surface_seed_mass_supply_g_m2"
selection_manifest$selection_basis <- paste(
  "Actual canonical row representing the lower or upper initial surface",
  "seed mass supply within its crop-group x treatment-loading x",
  "planting-method signature."
)
selection_manifest$model_version <- STBAM_MODEL_VERSION
selection_manifest$git_commit <- read_project_git_commit()
selection_manifest$generated_at <- generated_at
selection_csv <- file.path(out_root, "priority_figure_scenarios.csv")
readr::write_csv(selection_manifest, selection_csv, na = "")
export_xlsx(
  list(priority_exposure_summary = priority_summary,
       figure_scenario_selection = selection_manifest),
  summary_xlsx
)

cat(sprintf("Generating figures for %d selected scenario rows ...\n",
            nrow(figure_scenarios)))
file_records <- list()
logical_figure_count <- 0L

record_plot <- function(plot, path, type, row, metric_id = NA_character_,
                        width = 14, height = 10.5) {
  paths <- save_plot(plot, path, width = width, height = height, dpi = 300)
  logical_figure_count <<- logical_figure_count + 1L
  file_records[[length(file_records) + 1L]] <<- data.frame(
    figure_id = basename(path),
    figure_type = type,
    scenario_id = row$scenario_id[[1]],
    workbook = row$workbook[[1]],
    crop = row$crop[[1]],
    envelope_role = row$figure_envelope_role[[1]],
    metric_id = metric_id,
    file = normalizePath(paths, winslash = "/", mustWork = TRUE),
    format = tools::file_ext(paths),
    bytes = file.size(paths),
    stringsAsFactors = FALSE
  )
  invisible(paths)
}

for (i in seq_len(nrow(figure_scenarios))) {
  row <- figure_scenarios[i, ]
  tc <- build_daily_timecourse(
    params, row, bird_receptors, screening_metrics,
    diet_fractions = STBAM_DIET_FRACTIONS, days = plot_days
  )
  stub <- figure_stub(row)
  group_dir <- file.path(out_root, group_folders[[row$workbook[[1]]]])

  for (metric_id in screening_metric_ids) {
    metric_tc <- tc[tc$metric_id == metric_id, ]
    metadata_by_receptor <- stats::setNames(lapply(receptor_ids, function(id) {
      meta_row <- metric_tc[
        metric_tc$receptor_id == id & metric_tc$day == 0 &
          metric_tc$diet_fraction == 1,
      ][1, ]
      build_figure_metadata(meta_row, bird_metrics, params)
    }), receptor_ids)
    duration <- unique(metric_tc$duration_class)[[1]]

    main_plot <- plot_max_obtainable_small_multiple(
      metric_tc, metadata_by_receptor, free_y = TRUE, detail = "full"
    )
    record_plot(
      main_plot,
      file.path(group_dir, duration,
                paste0(stub, "_bird_", duration, "_max_obtainable")),
      "conditional_vs_maximum_obtainable_small_multiple", row, metric_id
    )

    # The dietary-fraction view is conventional conditional exposure and is
    # therefore generated once per treatment signature (upper-supply selected
    # row) rather than duplicated for both availability envelopes.
    if (grepl("upper", row$figure_envelope_role[[1]], fixed = TRUE)) {
      dietary_plot <- plot_dietary_fraction_small_multiple(
        metric_tc, metadata_by_receptor, free_y = TRUE, detail = "full"
      )
      record_plot(
        dietary_plot,
        file.path(group_dir, "dietary_fraction",
                  paste0(stub, "_bird_", duration,
                         "_assumed_dietary_fractions")),
        "assumed_dietary_fraction_small_multiple", row, metric_id
      )
    }
  }

  acute_tc <- tc[tc$metric_id == "bird_acute_screening" &
                   tc$diet_fraction == 1, ]
  process_metadata <- stats::setNames(lapply(receptor_ids, function(id) {
    meta_row <- acute_tc[acute_tc$receptor_id == id & acute_tc$day == 0, ][1, ]
    build_figure_metadata(meta_row, bird_metrics, params)
  }), receptor_ids)
  process_plot <- plot_exposure_processes(
    acute_tc, process_metadata, detail = "full"
  )
  record_plot(
    process_plot,
    file.path(group_dir, "process", paste0(stub, "_exposure_processes")),
    "four_panel_exposure_process", row, NA_character_,
    width = 13.5, height = 11
  )

  if (i %% 10L == 0L || i == nrow(figure_scenarios)) {
    cat(sprintf("  completed %d/%d selected scenarios\n",
                i, nrow(figure_scenarios)))
  }
}

figure_files <- dplyr::bind_rows(file_records)
figure_files$sha256 <- vapply(figure_files$file, function(path) {
  as.character(digest::digest(path, algo = "sha256", file = TRUE))
}, character(1), USE.NAMES = FALSE)
figure_files$model_version <- STBAM_MODEL_VERSION
figure_files$git_commit <- read_project_git_commit()
figure_files$generated_at <- generated_at
figure_manifest_csv <- file.path(out_root, "priority_figure_files.csv")
readr::write_csv(figure_files, figure_manifest_csv, na = "")

selection_document <- c(
  "# Priority exposure/risk figure set",
  "",
  sprintf("Generated: %s", generated_at),
  sprintf("Model/specification version: %s", STBAM_MODEL_VERSION),
  sprintf("Git commit: %s", read_project_git_commit()),
  "Parameter status: assessment baseline; no user overrides.",
  "",
  "## Coverage",
  "",
  paste(
    "The summary CSV/XLSX covers every canonical Small Cereals, shallow-legume",
    "and deep-legume agronomic row, all three bird receptors, and every",
    "canonical bird effects metric."
  ),
  "",
  "## Figure grouping",
  "",
  paste(
    "Figures preserve every crop-group × numeric treatment-loading × planting-",
    "method signature. For each signature, the selected actual canonical rows",
    "represent the lower and upper initial surface seed mass supply",
    "(surface seeds/m2 × seed mass). This brackets the joint TKW, seeding-rate",
    "and surface-fraction inputs while avoiding figures for all 836 agronomic",
    "rows. priority_figure_scenarios.csv records the selected rows and all",
    "represented crops; priority_exposure_summary.csv retains complete coverage."
  ),
  "",
  paste(
    "Acute and chronic screening figures are separate 1×3 bird small multiples.",
    "Process figures contain surface seed, residue per seed, surface a.i. loading",
    "and MSA feasibility. Conventional assumed-dietary-fraction figures are",
    "generated once per signature (the upper-supply representative) because",
    "those curves are not demonstrations of obtainability."
  )
)
writeLines(selection_document,
           file.path(out_root, "README_priority_figures.md"), useBytes = TRUE)

elapsed <- as.numeric(difftime(Sys.time(), started, units = "mins"))
cat(sprintf(
  paste0("\nDone in %.1f minutes.\n",
         "  canonical priority scenario rows: %d\n",
         "  summary rows: %d\n",
         "  selected figure scenarios: %d\n",
         "  logical figures: %d\n",
         "  exported PNG/SVG files: %d\n",
         "  output root: %s\n"),
  elapsed, nrow(scenario_inputs), nrow(priority_summary),
  nrow(figure_scenarios), logical_figure_count, nrow(figure_files), out_root
))
