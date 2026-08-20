# Shiny module: bounded sensitivity analysis.
#
# Varies one parameter across a user-defined range and reports the effect on
# key outputs. Results are deterministic scenario variants, NOT an uncertainty
# distribution, and are labelled accordingly.

#' Parameters exposed to sensitivity analysis
#' @export
STBAM_SENSITIVITY_PARAMETERS <- c(
  "Thousand-seed weight (low bound)" = "tkw_low",
  "Thousand-seed weight (high bound)" = "tkw_high",
  "Seeding rate (lower bound, seeds/ha)" = "seeds_low",
  "Seeding rate (upper bound, seeds/ha)" = "seeds_high",
  "Surface-seed fraction" = "surface_seed_fraction",
  "Surface-seed disappearance DT50" = "surface_seed_dt50_days",
  "Residue dissipation DT50" = "residue_dt50_days",
  "Maximum search area" = "msa_m2"
)

#' Run a one-at-a-time sensitivity sweep
#'
#' @param baseline An `stbam_baseline`.
#' @param selection The current scenario selection.
#' @param parameter One of [STBAM_SENSITIVITY_PARAMETERS].
#' @param values Numeric vector of values to evaluate.
#' @param scope Scope the override applies to.
#' @return A tibble, one row per swept value.
#' @export
run_sensitivity <- function(baseline, selection, parameter, values,
                            scope = "global") {
  check_numeric(values, "values")
  out <- vector("list", length(values))

  for (i in seq_along(values)) {
    params <- parameter_set(baseline, sprintf("Sensitivity: %s = %g",
                                              parameter, values[i]))
    mapped <- switch(
      parameter,
      tkw_low = list(name = "tkw_g_per_1000",
                     scope = paste0(scope, ":low_tkw")),
      tkw_high = list(name = "tkw_g_per_1000",
                      scope = paste0(scope, ":high_tkw")),
      seeds_low = list(name = "seeds_per_ha", scope = paste0(scope, ":low")),
      seeds_high = list(name = "seeds_per_ha", scope = paste0(scope, ":high")),
      list(name = parameter, scope = scope)
    )
    params <- set_override(params, mapped$name, values[i], scope = mapped$scope,
                           status = "PROVISIONAL",
                           source = "Sensitivity analysis")

    inputs <- try(build_scenario_inputs(
      params, crops = selection$crops, workbooks = selection$workbook,
      planting_methods = selection$methods, rate_levels = selection$rate_levels
    ), silent = TRUE)
    if (inherits(inputs, "try-error")) next

    summary <- build_scenario_summary(
      params, inputs,
      receptors = resolve_receptors(params, selection$receptors,
                                    selection$msa_term),
      effects_metrics = resolve_effects_metrics(params, selection$metric_roles),
      diet_fractions = selection$diet_fractions
    )

    out[[i]] <- tibble::tibble(
      parameter = parameter,
      value = values[i],
      peak_rq = max(summary$peak_rq),
      days_above_loc = max(summary$days_above_loc),
      initial_surface_seeds_per_m2 = max(summary$initial_surface_seeds_per_m2),
      field_rate_g_ai_per_ha = max(summary$field_rate_g_ai_per_ha),
      max_feasible_diet_pct = max(summary$initial_max_feasible_diet_fraction) * 100,
      days_at_full_diet_available = max(summary$days_at_full_diet_available),
      required_search_area_m2 = min(summary$initial_required_search_area_m2)
    )
  }
  dplyr::bind_rows(out)
}

#' @noRd
mod_sensitivity_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::div(
    class = "p-2",
    shiny::div(
      class = "alert alert-warning py-2",
      shiny::strong("These are deterministic scenario variants. "),
      "They are not an uncertainty distribution and must not be presented as ",
      "one. No probabilistic assumptions have been supplied."
    ),
    bslib::layout_column_wrap(
      width = 1 / 4,
      shiny::selectInput(ns("parameter"), "Parameter",
                         choices = STBAM_SENSITIVITY_PARAMETERS),
      shiny::selectInput(ns("scope"), "Applies to", choices = NULL),
      shiny::numericInput(ns("from"), "From", value = NA),
      shiny::numericInput(ns("to"), "To", value = NA)
    ),
    bslib::layout_column_wrap(
      width = 1 / 4,
      shiny::numericInput(ns("steps"), "Steps", value = 9, min = 2, max = 40),
      shiny::selectInput(ns("response"), "Response",
                         choices = c("peak_rq", "days_above_loc",
                                     "initial_surface_seeds_per_m2",
                                     "field_rate_g_ai_per_ha",
                                     "max_feasible_diet_pct",
                                     "days_at_full_diet_available",
                                     "required_search_area_m2")),
      shiny::actionButton(ns("run"), "Run sweep", class = "btn-primary",
                          icon = shiny::icon("play")),
      shiny::downloadButton(ns("download"), "Download results")
    ),
    shiny::hr(),
    shiny::plotOutput(ns("plot"), height = 420),
    DT::DTOutput(ns("table"))
  )
}

#' @noRd
mod_sensitivity_server <- function(id, baseline, results) {
  shiny::moduleServer(id, function(input, output, session) {

    shiny::observe({
      selection <- results()$selection
      choices <- if (grepl("^tkw|^seeds", input$parameter %||% "")) {
        selection$crops
      } else if (identical(input$parameter, "surface_seed_fraction")) {
        selection$methods
      } else if (identical(input$parameter, "msa_m2")) {
        selection$receptors
      } else {
        "global"
      }
      shiny::updateSelectInput(session, "scope", choices = choices)
    })

    # Suggest a sensible sweep range centred on the current default.
    shiny::observe({
      shiny::req(input$parameter)
      default <- switch(
        input$parameter,
        surface_seed_dt50_days = dissipation_default(baseline,
                                                     "surface_seed_dt50_days"),
        residue_dt50_days = dissipation_default(baseline, "residue_dt50_days"),
        msa_m2 = 70,
        surface_seed_fraction = 0.033,
        NA_real_
      )
      if (!is.na(default)) {
        shiny::updateNumericInput(session, "from", value = default * 0.5)
        shiny::updateNumericInput(session, "to", value = default * 2)
      }
    })

    swept <- shiny::eventReactive(input$run, {
      shiny::req(input$from, input$to, input$steps)
      shiny::validate(
        shiny::need(is.finite(input$from) && is.finite(input$to),
                    "Enter a numeric range."),
        shiny::need(input$to > input$from, "'To' must exceed 'From'.")
      )
      values <- seq(input$from, input$to, length.out = input$steps)
      shiny::withProgress(message = "Running sensitivity sweep", value = 0.3, {
        run_sensitivity(baseline, results()$selection, input$parameter, values,
                        scope = input$scope %||% "global")
      })
    })

    output$plot <- shiny::renderPlot({
      data <- swept()
      shiny::validate(shiny::need(nrow(data) > 0,
                                  "No results. Widen the range or the selection."))
      data$.y <- data[[input$response]]
      label <- names(STBAM_SENSITIVITY_PARAMETERS)[
        STBAM_SENSITIVITY_PARAMETERS == input$parameter
      ]
      p <- ggplot2::ggplot(data, ggplot2::aes(.data$value, .data$.y)) +
        ggplot2::geom_line(colour = STBAM_PALETTE[1], linewidth = 0.9) +
        ggplot2::geom_point(colour = STBAM_PALETTE[1], size = 2) +
        ggplot2::labs(
          title = sprintf("Sensitivity of %s to %s", input$response, label),
          subtitle = wrap_text(paste(
            "Deterministic one-at-a-time variation over the requested range;",
            "not an uncertainty distribution"
          )),
          x = label, y = input$response
        ) +
        theme_stbam()
      if (identical(input$response, "peak_rq")) {
        p <- p + ggplot2::geom_hline(yintercept = 1, linetype = "dashed",
                                     colour = "grey25")
      }
      p
    })

    output$table <- DT::renderDT({
      DT::datatable(swept(), rownames = FALSE,
                    options = list(scrollX = TRUE, dom = "tip")) |>
        DT::formatSignif(
          columns = which(vapply(swept(), is.numeric, logical(1))), digits = 4
        )
    })

    output$download <- shiny::downloadHandler(
      filename = function() "stbam_sensitivity.csv",
      content = function(file) readr::write_csv(swept(), file)
    )
  })
}
