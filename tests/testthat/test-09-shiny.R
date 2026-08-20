# Critical Shiny reactive workflows.
#
# The application must never display a stale result after an input changes, and
# must never be the place where a scientific decision is made.

skip_if_not_installed("shiny")

baseline <- load_baseline()

test_that("the user interface builds with every expected section", {
  ui <- stbam_ui()
  html <- as.character(htmltools::renderTags(ui)$html)
  for (section in c("Scenario and inputs", "Overview", "Exposure through time",
                    "Exposure feasibility", "Comparison", "Official tables",
                    "Table 162 support", "Sensitivity")) {
    expect_true(grepl(section, html, fixed = TRUE), info = section)
  }
})

test_that("the application object is constructible", {
  app <- run_stbam_app(getOption("stbam.project_root", getwd()))
  expect_s3_class(app, "shiny.appobj")
})

test_that("the input module starts on the assessment baseline", {
  shiny::testServer(mod_inputs_server, args = list(baseline = baseline), {
    session$setInputs(workbook = "small_cereals")
    session$flushReact()
    session$setInputs(crops = "Barley", rate_levels = "high",
                      methods = "broadcast", receptors = "bird_small",
                      metric_roles = "SCREENING", diets = 100,
                      msa_term = "short", days = 30, edit_crop = "Barley")
    expect_false(has_overrides(overrides()))
    expect_equal(selection()$crops, "Barley")
    expect_equal(selection()$diet_fractions, 1)
  })
})

test_that("editing a control records an override with provenance", {
  shiny::testServer(mod_inputs_server, args = list(baseline = baseline), {
    session$setInputs(workbook = "small_cereals")
    session$flushReact()
    session$setInputs(crops = "Barley", rate_levels = "high",
                      methods = "broadcast", receptors = "bird_small",
                      metric_roles = "SCREENING", diets = 100,
                      msa_term = "short", days = 30, edit_crop = "Barley",
                      residue_dt50 = 20)
    params <- overrides()
    expect_true(has_overrides(params))
    row <- params$overrides[params$overrides$parameter == "residue_dt50_days", ]
    expect_equal(row$value, 20)
    expect_equal(row$status, "USER_OVERRIDE")
    expect_equal(row$baseline_value, 10)
    expect_true(nzchar(row$source))
  })
})

test_that("entering the assessment default records no override", {
  shiny::testServer(mod_inputs_server, args = list(baseline = baseline), {
    session$setInputs(workbook = "small_cereals")
    session$flushReact()
    session$setInputs(crops = "Barley", rate_levels = "high",
                      methods = "broadcast", receptors = "bird_small",
                      metric_roles = "SCREENING", diets = 100,
                      msa_term = "short", days = 30, edit_crop = "Barley",
                      residue_dt50 = 10)
    expect_false(has_overrides(overrides()))
  })
})

test_that("reset clears every override", {
  shiny::testServer(mod_inputs_server, args = list(baseline = baseline), {
    session$setInputs(workbook = "small_cereals")
    session$flushReact()
    session$setInputs(crops = "Barley", rate_levels = "high",
                      methods = "broadcast", receptors = "bird_small",
                      metric_roles = "SCREENING", diets = 100,
                      msa_term = "short", days = 30, edit_crop = "Barley",
                      residue_dt50 = 20, tkw_low = 30)
    expect_equal(nrow(overrides()$overrides), 2L)
    session$setInputs(reset = 1)
    expect_false(has_overrides(overrides()))
  })
})

test_that("the whole application recomputes rather than serving stale results", {
  shiny::testServer(stbam_server(baseline), {
    session$setInputs(`inputs-workbook` = "small_cereals")
    session$flushReact()
    session$setInputs(
      `inputs-crops` = "Barley", `inputs-rate_levels` = "high",
      `inputs-methods` = "broadcast", `inputs-receptors` = "bird_small",
      `inputs-metric_roles` = "SCREENING", `inputs-diets` = 100,
      `inputs-msa_term` = "short", `inputs-days` = 30
    )
    session$flushReact()
    first <- safe_results()
    expect_gt(nrow(first$inputs), 0)
    expect_gt(nrow(first$summary), 0)
    expect_gt(nrow(first$timecourse), 0)
    baseline_rq <- max(first$summary$screening_rq)
    expect_equal(baseline_rq, 9.791974, tolerance = 1e-5)

    # Change a scientific input; the results must change with it.
    session$setInputs(`inputs-residue_dt50` = 20)
    session$flushReact()
    second <- safe_results()
    expect_true(has_overrides(second$params))
    expect_equal(unique(second$timecourse$residue_dt50_days), 20)
    # A longer residue half-life must lengthen the duration above the metric.
    expect_gt(max(second$summary$days_above_loc),
              max(first$summary$days_above_loc))
    # But it must not change the dose at sowing.
    expect_equal(max(second$summary$initial_dose_mg_kg_bw_day),
                 max(first$summary$initial_dose_mg_kg_bw_day))

    # Reset must restore the baseline results exactly.
    session$setInputs(`inputs-reset` = 1, `inputs-residue_dt50` = NA)
    session$flushReact()
    third <- safe_results()
    expect_false(has_overrides(third$params))
    expect_equal(max(third$summary$days_above_loc),
                 max(first$summary$days_above_loc))
  })
})

test_that("changing the surface fraction changes availability but not dose", {
  shiny::testServer(stbam_server(baseline), {
    session$setInputs(`inputs-workbook` = "small_cereals")
    session$flushReact()
    session$setInputs(
      `inputs-crops` = "Barley", `inputs-rate_levels` = "high",
      `inputs-methods` = "drill_spring", `inputs-receptors` = "bird_small",
      `inputs-metric_roles` = "SCREENING", `inputs-diets` = 100,
      `inputs-msa_term` = "short", `inputs-days` = 30
    )
    session$flushReact()
    before <- safe_results()

    session$setInputs(`inputs-f_drill_spring` = 0.10)
    session$flushReact()
    after <- safe_results()

    expect_gt(max(after$summary$initial_surface_seeds_per_m2),
              max(before$summary$initial_surface_seeds_per_m2))
    expect_equal(max(after$summary$initial_dose_mg_kg_bw_day),
                 max(before$summary$initial_dose_mg_kg_bw_day))
  })
})

test_that("the sensitivity sweep produces a monotone availability response", {
  selection <- list(
    workbook = "small_cereals", crops = "Barley", rate_levels = "high",
    methods = "broadcast", receptors = "bird_small",
    metric_roles = "SCREENING", diet_fractions = 1, msa_term = "short"
  )
  swept <- run_sensitivity(baseline, selection, "surface_seed_fraction",
                           values = c(0.2, 0.4, 0.6, 0.8, 1.0),
                           scope = "broadcast")
  expect_equal(nrow(swept), 5L)
  expect_true(all(diff(swept$initial_surface_seeds_per_m2) > 0))
  # Surface fraction does not change the dose, so the risk quotient is flat.
  expect_equal(length(unique(round(swept$peak_rq, 9))), 1L)
})

test_that("a residue half-life sweep lengthens the duration above the metric", {
  selection <- list(
    workbook = "small_cereals", crops = "Barley", rate_levels = "high",
    methods = "broadcast", receptors = "bird_small",
    metric_roles = "SCREENING", diet_fractions = 1, msa_term = "short"
  )
  swept <- run_sensitivity(baseline, selection, "residue_dt50_days",
                           values = c(5, 10, 15, 20))
  expect_true(all(diff(swept$days_above_loc) > 0))
  expect_equal(length(unique(round(swept$peak_rq, 9))), 1L)
})
