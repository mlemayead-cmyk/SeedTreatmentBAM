# Shiny reactive workflow for the "Maximum obtainable exposure" tab.
#
# This module deliberately runs its own bounded computation rather than
# reading the shared results()$timecourse slice (see the file header of
# R/shiny/44_module_max_obtainable.R for why); this test exists specifically
# to confirm that independent computation actually works end to end inside a
# live reactive graph, not just when called directly as in test-10.

skip_if_not_installed("shiny")

baseline <- load_baseline()

test_that("the maximum-obtainable-exposure tab computes without error inside the full app", {
  shiny::testServer(stbam_server(baseline), {
    session$setInputs(`inputs-workbook` = "small_cereals")
    session$flushReact()
    session$setInputs(
      `inputs-crops` = "Barley", `inputs-rate_levels` = "high",
      `inputs-methods` = "broadcast", `inputs-receptors` = "bird_small",
      `inputs-metric_roles` = "SCREENING", `inputs-diets` = 100,
      `inputs-msa_term` = "short", `inputs-days` = 60
    )
    session$flushReact()

    # Same scenario the shared inputs module would resolve to.
    params <- inputs$params()
    scenario_inputs <- build_scenario_inputs(
      params, crops = "Barley", workbooks = "small_cereals",
      rate_levels = "high", planting_methods = "broadcast"
    )
    a_scenario_id <- scenario_inputs$scenario_id[[1]]

    session$setInputs(
      `max_obtainable-scenario_id` = a_scenario_id,
      `max_obtainable-metric_id` = "bird_acute_screening",
      `max_obtainable-free_y` = TRUE
    )
    session$flushReact()

    expect_error(session$getOutput("max_obtainable-principal_plot"), NA)
    expect_error(session$getOutput("max_obtainable-summary_table"), NA)
    expect_error(session$getOutput("max_obtainable-assumptions_panel"), NA)
  })
})

test_that("changing the effects metric on the maximum-obtainable tab does not error", {
  shiny::testServer(stbam_server(baseline), {
    session$setInputs(`inputs-workbook` = "small_cereals")
    session$flushReact()
    session$setInputs(
      `inputs-crops` = "Barley", `inputs-rate_levels` = "high",
      `inputs-methods` = "broadcast", `inputs-receptors` = "bird_small",
      `inputs-metric_roles` = "SCREENING", `inputs-diets` = 100,
      `inputs-msa_term` = "short", `inputs-days` = 60
    )
    session$flushReact()
    params <- inputs$params()
    scenario_inputs <- build_scenario_inputs(
      params, crops = "Barley", workbooks = "small_cereals",
      rate_levels = "high", planting_methods = "broadcast"
    )
    a_scenario_id <- scenario_inputs$scenario_id[[1]]
    session$setInputs(`max_obtainable-scenario_id` = a_scenario_id,
                      `max_obtainable-metric_id` = "bird_acute_screening",
                      `max_obtainable-free_y` = TRUE)
    session$flushReact()

    session$setInputs(`max_obtainable-metric_id` = "bird_chronic_screening")
    session$flushReact()
    expect_error(session$getOutput("max_obtainable-principal_plot"), NA)
  })
})
