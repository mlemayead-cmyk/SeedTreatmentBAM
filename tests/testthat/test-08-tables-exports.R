# Official tables, Word export, data export and Table 162 support.

baseline <- load_baseline()
params <- parameter_set(baseline)
inputs <- build_scenario_inputs(params, crops = c("Barley", "Oat"),
                                workbooks = "small_cereals",
                                rate_levels = "high")
summary <- build_scenario_summary(
  params, inputs,
  receptors = resolve_receptors(params, c("bird_small", "bird_large")),
  diet_fractions = c(1, 0.25)
)

test_that("significant-digit formatting behaves at the edges", {
  expect_equal(fmt_sig(0), "0")
  expect_equal(fmt_sig(NA_real_), "-")
  expect_equal(fmt_sig(Inf), "no limit")
  expect_equal(fmt_sig(1234567, 3), "1,230,000")
  expect_equal(fmt_sig(0.00012345, 3), "0.000123")
  expect_equal(fmt_sig(76.181554, 3), "76.2")
})

test_that("ranges collapse when both ends round to the same value", {
  expect_equal(fmt_range(5.0001, 5.0002, 3), "5")
  expect_equal(fmt_range(1, 10, 3), "1 - 10")
  expect_equal(fmt_range(NA_real_, NA_real_), "-")
})

test_that("every registered official table builds", {
  for (table_id in names(STBAM_TABLES)) {
    table <- build_official_table(table_id, summary)
    expect_s3_class(table, "data.frame")
    expect_gt(nrow(table), 0)
    expect_gt(ncol(table), 3)
    expect_false(anyNA(names(table)))
    expect_true(all(nzchar(names(table))))
  }
})

test_that("an unknown table id is rejected", {
  expect_error(build_official_table("not_a_table", summary), "Unknown")
})

test_that("the availability table reports units in its column names", {
  table <- build_official_table("seed_availability", summary)
  expect_true(any(grepl("seeds/m2", names(table), fixed = TRUE)))
  expect_true(any(grepl("m2/seed", names(table), fixed = TRUE)))
})

test_that("the risk table separates screening from refined-additional metrics", {
  metrics <- resolve_effects_metrics(params,
                                     c("SCREENING", "REFINED_ADDITIONAL"),
                                     taxa = "bird")
  wide <- build_scenario_summary(
    params, inputs, receptors = resolve_receptors(params, "bird_small"),
    effects_metrics = metrics, diet_fractions = 1
  )
  table <- build_official_table("risk_and_duration", wide)
  expect_true(any(grepl("screening", table$`Effects metric`)))
  expect_true(any(grepl("additional", table$`Effects metric`)))
  # A single row never mixes two metrics.
  expect_equal(nrow(table),
               nrow(dplyr::distinct(wide, .data$crop, .data$rate_level,
                                    .data$receptor_id, .data$diet_fraction,
                                    .data$metric_id)))
})

test_that("the feasibility table is labelled as a diagnostic, not a cap", {
  notes <- STBAM_TABLES$exposure_feasibility$notes
  expect_true(any(grepl("does not cap", notes, fixed = TRUE)))
})

test_that("the dashboard, Word and CSV outputs come from one builder", {
  # Any drift would mean the same table_id produced different data.
  for (table_id in names(STBAM_TABLES)) {
    a <- build_official_table(table_id, summary)
    b <- build_official_table(table_id, summary)
    expect_identical(a, b)
  }
})

test_that("a single table exports to Word and contains the expected values", {
  skip_if_not_installed("officer")
  skip_if_not_installed("flextable")
  path <- withr::local_tempfile(fileext = ".docx")
  export_table_docx("risk_and_duration", summary, path,
                    caption_prefix = "Table 27.")
  expect_true(file.exists(path))
  expect_gt(file.size(path), 8000)

  contents <- officer::read_docx(path)
  text <- paste(officer::docx_summary(contents)$text, collapse = " ")
  expect_true(grepl("Table 27.", text, fixed = TRUE))
  expect_true(grepl("Barley", text, fixed = TRUE))
  expect_true(grepl("Risk quotient", text, fixed = TRUE))
  # A value that must survive into the document.
  expect_true(grepl("76.2", text, fixed = TRUE))
})

test_that("a group of tables exports to one Word document", {
  skip_if_not_installed("officer")
  path <- withr::local_tempfile(fileext = ".docx")
  export_tables_docx(names(STBAM_TABLES), summary, path,
                     document_title = "Model output tables")
  expect_true(file.exists(path))
  text <- paste(officer::docx_summary(officer::read_docx(path))$text,
                collapse = " ")
  expect_true(grepl("Model output tables", text, fixed = TRUE))
  for (table_id in names(STBAM_TABLES)) {
    expect_true(grepl(STBAM_TABLES[[table_id]]$title, text, fixed = TRUE),
                info = table_id)
  }
})

test_that("the quantitative appendix records provenance and override state", {
  skip_if_not_installed("officer")
  path <- withr::local_tempfile(fileext = ".docx")
  export_quantitative_appendix(params, inputs, summary, path)
  text <- paste(officer::docx_summary(officer::read_docx(path))$text,
                collapse = " ")
  expect_true(grepl("Quantitative appendix", text, fixed = TRUE))
  expect_true(grepl("Source provenance", text, fixed = TRUE))
  expect_true(grepl("No parameter overrides were applied", text, fixed = TRUE))

  changed <- set_override(params, "residue_dt50_days", 21, baseline_value = 10,
                          source = "Test")
  path2 <- withr::local_tempfile(fileext = ".docx")
  export_quantitative_appendix(changed, inputs, summary, path2)
  text2 <- paste(officer::docx_summary(officer::read_docx(path2))$text,
                 collapse = " ")
  expect_true(grepl("NOT the assessment baseline", text2, fixed = TRUE))
  expect_true(grepl("residue_dt50_days", text2, fixed = TRUE))
})

test_that("CSV and XLSX export write every requested dataset", {
  dir <- withr::local_tempdir()
  bundle <- export_bundle(params, inputs, summary)
  paths <- export_csv(bundle, dir)
  expect_equal(length(paths), length(bundle))
  expect_true(all(file.exists(paths)))

  reread <- readr::read_csv(file.path(dir, "scenario_inputs.csv"),
                            show_col_types = FALSE)
  expect_equal(nrow(reread), nrow(inputs))

  skip_if_not_installed("writexl")
  xlsx <- file.path(dir, "bundle.xlsx")
  export_xlsx(bundle[c("scenario_inputs", "scenario_summary")], xlsx)
  expect_true(file.exists(xlsx))
  expect_gt(file.size(xlsx), 5000)
})

test_that("plots build from canonical data and save at publication quality", {
  timecourse <- build_daily_timecourse(
    params, inputs[1:2, ],
    receptors = resolve_receptors(params, "bird_small"),
    effects_metrics = resolve_effects_metrics(params, taxa = "bird"),
    diet_fractions = c(1, 0.25), days = 0:30
  )
  plots <- list(
    plot_surface_seeds(timecourse), plot_ai_per_seed(timecourse),
    plot_surface_ai(timecourse), plot_process_separation(timecourse),
    plot_dose(timecourse), plot_risk_quotient(timecourse),
    plot_search_area(timecourse), plot_feasible_diet(timecourse)
  )
  for (plot in plots) expect_s3_class(plot, "ggplot")

  dir <- withr::local_tempdir()
  written <- save_plot(plots[[1]], file.path(dir, "test"), width = 8,
                       height = 5)
  expect_true(all(file.exists(written)))
  expect_gt(file.size(written[1]), 10000)
})

test_that("plotting an empty selection fails loudly", {
  timecourse <- build_daily_timecourse(
    params, inputs[1, ], receptors = resolve_receptors(params, "bird_small"),
    diet_fractions = 1, days = 0:5
  )
  expect_error(plot_surface_seeds(timecourse[0, ]), "No data to plot")
})

# --------------------------------------------------------------------------
# Table 162 support
# --------------------------------------------------------------------------

full_summary <- build_scenario_summary(
  params,
  build_scenario_inputs(params, workbooks = "small_cereals"),
  diet_fractions = c(1, 0.5, 0.25, 0.1)
)
support <- build_table162_support(params, full_summary)

test_that("the Table 162 support dataset builds and covers Small Cereals", {
  expect_gt(nrow(support), 0)
  coverage <- table162_coverage(support)
  cereals <- coverage[coverage$crop_family == "Small Cereals", ]
  expect_equal(cereals$coverage_pct, 100)
  expect_gt(cereals$decision_rows, 0)
})

test_that("crop families with no supplied workbook are reported, not hidden", {
  coverage <- table162_coverage(support)
  uncovered <- coverage[coverage$coverage_pct == 0, ]
  expect_gt(nrow(uncovered), 0)
  expect_true("Legumes" %in% uncovered$crop_family)
  # The rows still exist in the support table.
  expect_gt(sum(!support$quantitative_backbone_available), 0)
})

test_that("peer-review consensus fields are never populated by the software", {
  expect_true(assert_human_fields_empty(support))
  for (field in STBAM_HUMAN_ONLY_FIELDS) {
    expect_true(field %in% names(support))
    expect_true(all(is.na(support[[field]])), info = field)
  }
})

test_that("the guard detects a populated human-only field", {
  tampered <- support
  tampered$peer_review_consensus[1] <- "Agreed"
  expect_error(assert_human_fields_empty(tampered),
               "must never be written by the software")
})

test_that("evidence, interpretation and decision stay in separate fields", {
  expect_true(all(c("factors_increasing_concern", "factors_decreasing_concern",
                    "important_uncertainty", "current_narrative_reasoning",
                    "current_table162_position", "peer_review_consensus") %in%
                    names(support)))
  # The recorded position is read from the register, never computed.
  expect_true(all(support$current_table162_position %in%
                    c("Y", "N", "?", "NOT_POPULATED", NA)))
})

test_that("the quantitative backbone matches the scenario summary", {
  row <- support[support$quantitative_backbone_available &
                   support$crop_family == "Small Cereals", ][1, ]
  matching <- full_summary[
    full_summary$crop == row$model_crop &
      full_summary$application_rate == as.numeric(
        sub("^\\s*([0-9.]+).*$", "\\1", row$application_rate)
      ) &
      tools::toTitleCase(full_summary$size_class) == row$receptor_size &
      tools::toTitleCase(full_summary$taxon) == row$taxon &
      tools::toTitleCase(full_summary$duration_class) == row$effect_window &
      full_summary$metric_role == "SCREENING",
  ]
  expect_gt(nrow(matching), 0)
  expect_equal(row$screening_rq_max, max(matching$screening_rq),
               tolerance = 1e-9)
})
