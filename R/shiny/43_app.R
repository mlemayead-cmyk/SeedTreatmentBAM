# The Shiny application.
#
# The application is a user interface over the tested calculation engine. It
# contains no scientific model of its own.

#' @noRd
stbam_ui <- function() {
  bslib::page_navbar(
    title = "Seed-treatment risk model",
    theme = bslib::bs_theme(version = 5, preset = "flatly"),
    fillable = FALSE,

    bslib::nav_panel("Scenario and inputs", shiny::icon("sliders"),
                     mod_inputs_ui("inputs")),
    bslib::nav_panel("Overview", shiny::icon("gauge"),
                     mod_overview_ui("overview")),
    bslib::nav_panel("Exposure through time", shiny::icon("chart-line"),
                     mod_timecourse_ui("timecourse")),
    bslib::nav_panel("Exposure feasibility", shiny::icon("magnifying-glass"),
                     mod_feasibility_ui("feasibility")),
    bslib::nav_panel("Comparison", shiny::icon("chart-column"),
                     mod_comparison_ui("comparison")),
    bslib::nav_panel("Official tables", shiny::icon("table"),
                     mod_tables_ui("tables")),
    bslib::nav_panel("Table 162 support", shiny::icon("clipboard-check"),
                     mod_table162_ui("table162")),
    bslib::nav_panel("Sensitivity", shiny::icon("arrows-left-right"),
                     mod_sensitivity_ui("sensitivity")),

    bslib::nav_spacer(),
    bslib::nav_item(
      shiny::tags$span(class = "navbar-text small",
                       "Calculations run in the tested R engine")
    )
  )
}

#' @noRd
stbam_server <- function(baseline) {
  function(input, output, session) {

    inputs <- mod_inputs_server("inputs", baseline)

    # Single canonical recomputation. Every view reads this, so no view can
    # display a stale or inconsistent result after an input changes.
    results <- shiny::reactive({
      params <- inputs$params()
      selection <- inputs$selection()
      shiny::req(selection$workbook, selection$crops, selection$receptors,
                 selection$methods, selection$rate_levels,
                 length(selection$diet_fractions) > 0)

      scenario_inputs <- build_scenario_inputs(
        params, crops = selection$crops, workbooks = selection$workbook,
        planting_methods = selection$methods,
        rate_levels = selection$rate_levels
      )
      receptors <- resolve_receptors(params, selection$receptors,
                                     selection$msa_term)
      metrics <- resolve_effects_metrics(params, selection$metric_roles)

      summary <- build_scenario_summary(params, scenario_inputs, receptors,
                                        metrics, selection$diet_fractions)

      # The daily time course is expensive at full scale, so it is built for a
      # bounded slice. Summaries are closed-form and always cover everything.
      slice <- scenario_inputs
      if (nrow(slice) > 24L) slice <- slice[seq_len(24L), ]
      timecourse <- build_daily_timecourse(
        params, slice, receptors, metrics, selection$diet_fractions,
        days = selection$days
      )

      list(params = params, selection = selection, inputs = scenario_inputs,
           summary = summary, timecourse = timecourse)
    })

    safe_results <- shiny::reactive({
      out <- try(results(), silent = TRUE)
      if (inherits(out, "try-error")) {
        shiny::validate(shiny::need(
          FALSE,
          paste("The model could not be calculated:",
                conditionMessage(attr(out, "condition")))
        ))
      }
      out
    })

    mod_overview_server("overview", safe_results)
    mod_timecourse_server("timecourse", safe_results)
    mod_feasibility_server("feasibility", safe_results)
    mod_comparison_server("comparison", safe_results)
    mod_tables_server("tables", safe_results)
    mod_table162_server("table162", safe_results)
    mod_sensitivity_server("sensitivity", baseline, safe_results)
  }
}

#' Launch the application
#'
#' @param root Project root.
#' @param ... Passed to [shiny::shinyApp].
#' @return A Shiny app object.
#' @export
run_stbam_app <- function(root = getOption("stbam.project_root", getwd()), ...) {
  baseline <- load_baseline()
  shiny::shinyApp(ui = stbam_ui(), server = stbam_server(baseline), ...)
}
