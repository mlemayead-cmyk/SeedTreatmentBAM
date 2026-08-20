# Shiny modules: overview, time course, feasibility, comparison, tables,
# Table 162 support and sensitivity.

# --------------------------------------------------------------------------
# Scenario overview
# --------------------------------------------------------------------------

#' @noRd
mod_overview_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::div(
    class = "p-2",
    shiny::uiOutput(ns("override_banner")),
    bslib::layout_column_wrap(
      width = 1 / 4, heights_equal = "row",
      bslib::value_box("Scenarios modelled", shiny::textOutput(ns("n_scenarios")),
                       theme = "primary"),
      bslib::value_box("Maximum field rate", shiny::textOutput(ns("field_rate")),
                       shiny::span("g a.i./ha"), theme = "secondary"),
      bslib::value_box("Maximum screening RQ", shiny::textOutput(ns("screening_rq")),
                       theme = "danger"),
      bslib::value_box("Maximum days above metric", shiny::textOutput(ns("days")),
                       shiny::span("days"), theme = "warning")
    ),
    shiny::br(),
    bslib::layout_column_wrap(
      width = 1 / 4, heights_equal = "row",
      bslib::value_box("Initial surface seed", shiny::textOutput(ns("surface")),
                       shiny::span("seeds/m2"), theme = "info"),
      bslib::value_box("Dose per seed", shiny::textOutput(ns("dose_per_seed")),
                       shiny::span("mg a.i./seed"), theme = "info"),
      bslib::value_box("Diet at the metric", shiny::textOutput(ns("threshold")),
                       shiny::span("% of daily diet"), theme = "info"),
      bslib::value_box("Days a full diet is available",
                       shiny::textOutput(ns("feasible_days")),
                       shiny::span("days"), theme = "info")
    ),
    shiny::hr(),
    shiny::h5("Scenario inputs"),
    shiny::helpText(
      "One row per crop, rate, planting method and agronomic bound ",
      "combination. The seeding-rate and seed-mass bounds are independent ",
      "axes, as they are in the source workbook."
    ),
    DT::DTOutput(ns("inputs"))
  )
}

#' @noRd
mod_overview_server <- function(id, results) {
  shiny::moduleServer(id, function(input, output, session) {
    output$override_banner <- shiny::renderUI({
      params <- results()$params
      if (!has_overrides(params)) {
        shiny::div(
          class = "alert alert-success py-2",
          shiny::icon("check"),
          " Assessment baseline. No overrides applied."
        )
      } else {
        shiny::div(
          class = "alert alert-warning py-2",
          shiny::icon("triangle-exclamation"),
          shiny::strong(sprintf(" %d override(s) applied. ",
                                nrow(params$overrides))),
          "These results are NOT the assessment baseline scenario."
        )
      }
    })

    output$n_scenarios <- shiny::renderText(
      format(nrow(results()$inputs), big.mark = ",")
    )
    output$field_rate <- shiny::renderText(
      fmt_sig(max(results()$inputs$field_rate_g_ai_per_ha))
    )
    output$screening_rq <- shiny::renderText(
      fmt_sig(max(results()$summary$screening_rq))
    )
    output$days <- shiny::renderText(
      fmt_sig(max(results()$summary$days_above_loc))
    )
    output$surface <- shiny::renderText(
      fmt_range(min(results()$inputs$initial_surface_seeds_per_m2),
                max(results()$inputs$initial_surface_seeds_per_m2))
    )
    output$dose_per_seed <- shiny::renderText(
      fmt_range(min(results()$inputs$dose_per_seed_mg),
                max(results()$inputs$dose_per_seed_mg))
    )
    output$threshold <- shiny::renderText(
      fmt_sig(min(results()$summary$threshold_diet_fraction_pct))
    )
    output$feasible_days <- shiny::renderText(
      fmt_sig(max(results()$summary$days_at_full_diet_available))
    )

    output$inputs <- DT::renderDT({
      data <- results()$inputs
      DT::datatable(
        dplyr::select(
          data, "crop", "rate_level", "application_rate", "planting_method",
          "seeding_rate_bound", "seed_mass_bound", "tkw_g_per_1000",
          "seeds_per_ha", "seeding_rate_kg_per_ha", "dose_per_seed_mg",
          "field_rate_g_ai_per_ha", "surface_seed_fraction",
          "initial_surface_seeds_per_m2", "area_per_surface_seed_m2"
        ),
        rownames = FALSE, filter = "top",
        options = list(scrollX = TRUE, pageLength = 15)
      ) |>
        DT::formatSignif(columns = c("tkw_g_per_1000", "seeds_per_ha",
                                     "seeding_rate_kg_per_ha",
                                     "dose_per_seed_mg",
                                     "field_rate_g_ai_per_ha",
                                     "initial_surface_seeds_per_m2",
                                     "area_per_surface_seed_m2"), digits = 4)
    })
  })
}

# --------------------------------------------------------------------------
# Exposure through time
# --------------------------------------------------------------------------

#' @noRd
mod_timecourse_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::div(
    class = "p-2",
    bslib::layout_column_wrap(
      width = 1 / 3,
      shiny::selectInput(ns("scenario"), "Scenario", choices = NULL),
      shiny::selectInput(ns("receptor"), "Receptor", choices = NULL),
      shiny::selectInput(ns("metric"), "Effects metric", choices = NULL)
    ),
    shiny::checkboxInput(ns("log_y"), "Logarithmic y axis", value = FALSE),
    bslib::navset_card_tab(
      bslib::nav_panel("Process separation",
                       shiny::plotOutput(ns("separation"), height = 460),
                       shiny::helpText(
                         "Surface-seed disappearance and residue dissipation ",
                         "are separate processes with separate half-lives. ",
                         "The surface loading declines faster than either."
                       )),
      bslib::nav_panel("Surface seed",
                       shiny::plotOutput(ns("seeds"), height = 460)),
      bslib::nav_panel("Residue per seed",
                       shiny::plotOutput(ns("ai"), height = 460)),
      bslib::nav_panel("Surface loading",
                       shiny::plotOutput(ns("surface_ai"), height = 460)),
      bslib::nav_panel("Dose", shiny::plotOutput(ns("dose"), height = 460)),
      bslib::nav_panel("Risk quotient",
                       shiny::plotOutput(ns("rq"), height = 460)),
      bslib::nav_panel("Daily data", DT::DTOutput(ns("table")))
    ),
    shiny::hr(),
    bslib::layout_column_wrap(
      width = 1 / 2,
      shiny::downloadButton(ns("download_plot"), "Download the current plot"),
      shiny::downloadButton(ns("download_data"), "Download the daily time course")
    )
  )
}

#' @noRd
mod_timecourse_server <- function(id, results) {
  shiny::moduleServer(id, function(input, output, session) {

    shiny::observe({
      timecourse <- results()$timecourse
      shiny::req(nrow(timecourse) > 0)
      shiny::updateSelectInput(session, "scenario",
                               choices = sort(unique(timecourse$scenario_id)))
      shiny::updateSelectInput(session, "receptor",
                               choices = sort(unique(timecourse$receptor_id)))
      shiny::updateSelectInput(session, "metric",
                               choices = sort(unique(timecourse$metric_id)))
    })

    filtered <- shiny::reactive({
      timecourse <- results()$timecourse
      shiny::req(input$scenario, input$receptor, input$metric)
      out <- timecourse[
        timecourse$scenario_id == input$scenario &
          timecourse$receptor_id == input$receptor &
          timecourse$metric_id == input$metric,
      ]
      shiny::validate(shiny::need(
        nrow(out) > 0,
        "No results for this combination. Effects metrics are matched to the receptor taxon."
      ))
      out
    })

    output$separation <- shiny::renderPlot(plot_process_separation(filtered()))
    output$seeds <- shiny::renderPlot(
      plot_surface_seeds(filtered(), colour_by = "crop", log_y = input$log_y)
    )
    output$ai <- shiny::renderPlot(
      plot_ai_per_seed(filtered(), colour_by = "crop", log_y = input$log_y)
    )
    output$surface_ai <- shiny::renderPlot(
      plot_surface_ai(filtered(), colour_by = "crop", log_y = input$log_y)
    )
    output$dose <- shiny::renderPlot(plot_dose(filtered(), log_y = input$log_y))
    output$rq <- shiny::renderPlot(
      plot_risk_quotient(filtered(), log_y = input$log_y)
    )

    output$table <- DT::renderDT({
      DT::datatable(
        dplyr::select(filtered(), "day", "diet_fraction",
                      "surface_seeds_per_m2", "ai_per_seed_mg",
                      "surface_ai_mg_per_m2", "dose_mg_kg_bw_day", "rq",
                      "above_loc", "required_search_area_m2",
                      "max_feasible_diet_fraction",
                      "diet_fraction_is_feasible"),
        rownames = FALSE, filter = "top",
        options = list(scrollX = TRUE, pageLength = 20)
      ) |>
        DT::formatSignif(
          columns = c("surface_seeds_per_m2", "ai_per_seed_mg",
                      "surface_ai_mg_per_m2", "dose_mg_kg_bw_day", "rq",
                      "required_search_area_m2", "max_feasible_diet_fraction"),
          digits = 4
        )
    })

    output$download_plot <- shiny::downloadHandler(
      filename = function() "stbam_risk_quotient.png",
      content = function(file) {
        ggplot2::ggsave(file, plot_risk_quotient(filtered()), width = 10,
                        height = 6, dpi = 300, bg = "white")
      }
    )
    output$download_data <- shiny::downloadHandler(
      filename = function() "stbam_daily_timecourse.csv",
      content = function(file) readr::write_csv(results()$timecourse, file)
    )
  })
}

# --------------------------------------------------------------------------
# Exposure feasibility
# --------------------------------------------------------------------------

#' @noRd
mod_feasibility_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::div(
    class = "p-2",
    shiny::div(
      class = "alert alert-info py-2",
      shiny::strong("This view is a plausibility check, not an exposure cap. "),
      "The dose and risk quotients reported elsewhere are the calculated ",
      "regulatory exposure and are not reduced to the feasible dietary ",
      "fraction."
    ),
    bslib::layout_column_wrap(
      width = 1 / 2,
      shiny::selectInput(ns("scenario"), "Scenario", choices = NULL),
      shiny::selectInput(ns("receptor"), "Receptor", choices = NULL)
    ),
    bslib::layout_column_wrap(
      width = 1 / 2,
      bslib::card(bslib::card_header("Search area required against the maximum"),
                  shiny::plotOutput(ns("area"), height = 420)),
      bslib::card(bslib::card_header("Maximum obtainable dietary fraction"),
                  shiny::plotOutput(ns("diet"), height = 420))
    ),
    shiny::hr(),
    shiny::h5("Could an animal realistically obtain this much treated seed?"),
    DT::DTOutput(ns("table"))
  )
}

#' @noRd
mod_feasibility_server <- function(id, results) {
  shiny::moduleServer(id, function(input, output, session) {
    shiny::observe({
      timecourse <- results()$timecourse
      shiny::req(nrow(timecourse) > 0)
      shiny::updateSelectInput(session, "scenario",
                               choices = sort(unique(timecourse$scenario_id)))
      shiny::updateSelectInput(session, "receptor",
                               choices = sort(unique(timecourse$receptor_id)))
    })

    filtered <- shiny::reactive({
      timecourse <- results()$timecourse
      shiny::req(input$scenario, input$receptor)
      metric <- sort(unique(timecourse$metric_id))[1]
      out <- timecourse[
        timecourse$scenario_id == input$scenario &
          timecourse$receptor_id == input$receptor &
          timecourse$metric_id == metric,
      ]
      shiny::validate(shiny::need(nrow(out) > 0, "No results for this combination."))
      out
    })

    output$area <- shiny::renderPlot(plot_search_area(filtered()))
    output$diet <- shiny::renderPlot(
      plot_feasible_diet(filtered(), colour_by = "receptor_id")
    )
    output$table <- DT::renderDT({
      DT::datatable(
        build_official_table("exposure_feasibility", results()$summary),
        rownames = FALSE, filter = "top",
        options = list(scrollX = TRUE, pageLength = 15)
      )
    })
  })
}

# --------------------------------------------------------------------------
# Crop and rate comparison
# --------------------------------------------------------------------------

#' @noRd
mod_comparison_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::div(
    class = "p-2",
    bslib::layout_column_wrap(
      width = 1 / 3,
      shiny::selectInput(ns("x"), "Compare across",
                         choices = c("crop", "rate_level", "planting_method",
                                     "size_class", "receptor_id")),
      shiny::selectInput(ns("facet"), "Split panels by",
                         choices = c("size_class", "planting_method",
                                     "rate_level", "duration_class", "none")),
      shiny::selectInput(ns("metric"), "Effects metric", choices = NULL)
    ),
    bslib::navset_card_tab(
      bslib::nav_panel("Peak risk quotient",
                       shiny::plotOutput(ns("rq"), height = 520)),
      bslib::nav_panel("Duration above the metric",
                       shiny::plotOutput(ns("duration"), height = 520)),
      bslib::nav_panel("Summary table", DT::DTOutput(ns("table")))
    )
  )
}

#' @noRd
mod_comparison_server <- function(id, results) {
  shiny::moduleServer(id, function(input, output, session) {
    shiny::observe({
      shiny::updateSelectInput(session, "metric",
                               choices = sort(unique(results()$summary$metric_id)))
    })

    filtered <- shiny::reactive({
      summary <- results()$summary
      shiny::req(input$metric)
      out <- summary[summary$metric_id == input$metric &
                       summary$diet_fraction == max(summary$diet_fraction), ]
      shiny::validate(shiny::need(nrow(out) > 0, "No results for this metric."))
      out
    })

    facet <- shiny::reactive(if (input$facet == "none") NULL else input$facet)

    output$rq <- shiny::renderPlot(
      plot_rq_comparison(filtered(), x = input$x, facet = facet())
    )
    output$duration <- shiny::renderPlot(
      plot_duration_comparison(filtered(), x = input$x, facet = facet())
    )
    output$table <- DT::renderDT({
      DT::datatable(summarise_across_bounds(filtered()), rownames = FALSE,
                    filter = "top",
                    options = list(scrollX = TRUE, pageLength = 15)) |>
        DT::formatSignif(
          columns = which(vapply(summarise_across_bounds(filtered()),
                                 is.numeric, logical(1))),
          digits = 4
        )
    })
  })
}

# --------------------------------------------------------------------------
# Official tables
# --------------------------------------------------------------------------

#' @noRd
mod_tables_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::div(
    class = "p-2",
    shiny::div(
      class = "alert alert-secondary py-2",
      "The table shown here and the table exported to Word or CSV are ",
      "produced by the same function from the same canonical results, so they ",
      "cannot differ."
    ),
    bslib::layout_column_wrap(
      width = 1 / 2,
      shiny::selectInput(
        ns("table_id"), "Table",
        choices = stats::setNames(names(STBAM_TABLES),
                                  vapply(STBAM_TABLES, function(x) x$title,
                                         character(1)))
      ),
      shiny::textInput(ns("caption_prefix"), "Caption prefix (optional)",
                       placeholder = "e.g. Table 27.")
    ),
    DT::DTOutput(ns("table")),
    shiny::hr(),
    shiny::h6("Table notes"),
    shiny::uiOutput(ns("notes")),
    shiny::hr(),
    bslib::layout_column_wrap(
      width = 1 / 4,
      shiny::downloadButton(ns("docx_one"), "This table (Word)"),
      shiny::downloadButton(ns("docx_all"), "All tables (Word)"),
      shiny::downloadButton(ns("appendix"), "Quantitative appendix (Word)"),
      shiny::downloadButton(ns("csv"), "This table (CSV)")
    )
  )
}

#' @noRd
mod_tables_server <- function(id, results) {
  shiny::moduleServer(id, function(input, output, session) {
    current <- shiny::reactive({
      shiny::req(input$table_id)
      build_official_table(input$table_id, results()$summary)
    })

    output$table <- DT::renderDT(
      DT::datatable(current(), rownames = FALSE, filter = "top",
                    options = list(scrollX = TRUE, pageLength = 15))
    )

    output$notes <- shiny::renderUI({
      shiny::req(input$table_id)
      shiny::tags$ul(
        lapply(STBAM_TABLES[[input$table_id]]$notes, shiny::tags$li)
      )
    })

    output$docx_one <- shiny::downloadHandler(
      filename = function() paste0(input$table_id, ".docx"),
      content = function(file) {
        export_table_docx(
          input$table_id, results()$summary, file,
          caption_prefix = if (nzchar(input$caption_prefix %||% "")) {
            input$caption_prefix
          } else {
            NULL
          }
        )
      }
    )
    output$docx_all <- shiny::downloadHandler(
      filename = function() "stbam_all_tables.docx",
      content = function(file) {
        export_tables_docx(names(STBAM_TABLES), results()$summary, file,
                           document_title = "Model output tables")
      }
    )
    output$appendix <- shiny::downloadHandler(
      filename = function() "stbam_quantitative_appendix.docx",
      content = function(file) {
        export_quantitative_appendix(results()$params, results()$inputs,
                                     results()$summary, file)
      }
    )
    output$csv <- shiny::downloadHandler(
      filename = function() paste0(input$table_id, ".csv"),
      content = function(file) readr::write_csv(current(), file)
    )
  })
}

# --------------------------------------------------------------------------
# Table 162 decision support
# --------------------------------------------------------------------------

#' @noRd
mod_table162_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::div(
    class = "p-2",
    shiny::div(
      class = "alert alert-danger py-2",
      shiny::icon("user"),
      shiny::strong(" The application does not make the scientific decision. "),
      "Peer-review consensus and its rationale are human-controlled fields ",
      "and are never populated by this software."
    ),
    shiny::h5("Coverage"),
    shiny::helpText(
      "Crop families with no supplied calculation workbook have no ",
      "quantitative backbone. They are reported, not hidden."
    ),
    DT::DTOutput(ns("coverage")),
    shiny::hr(),
    bslib::layout_column_wrap(
      width = 1 / 2,
      shiny::selectInput(ns("decision"), "Decision record", choices = NULL),
      shiny::downloadButton(ns("download"), "Download Table 162 support (CSV)")
    ),
    shiny::uiOutput(ns("detail")),
    shiny::hr(),
    shiny::h5("All decision records"),
    DT::DTOutput(ns("table"))
  )
}

#' @noRd
mod_table162_server <- function(id, results) {
  shiny::moduleServer(id, function(input, output, session) {

    support <- shiny::reactive({
      out <- build_table162_support(results()$params, results()$summary)
      assert_human_fields_empty(out)
      out
    })

    shiny::observe({
      available <- support()
      available <- available[available$quantitative_backbone_available, ]
      shiny::updateSelectInput(session, "decision",
                               choices = unique(available$decision_id))
    })

    output$coverage <- DT::renderDT(
      DT::datatable(table162_coverage(support()), rownames = FALSE,
                    options = list(dom = "t"))
    )

    output$detail <- shiny::renderUI({
      shiny::req(input$decision)
      row <- support()[support()$decision_id == input$decision, ][1, ]
      shiny::req(nrow(row) == 1)

      block <- function(title, body, class = "secondary") {
        bslib::card(
          bslib::card_header(title),
          bslib::card_body(
            if (is.na(body) || !nzchar(body)) {
              shiny::em("Not recorded")
            } else {
              shiny::p(body)
            }
          ),
          class = paste0("border-", class)
        )
      }

      shiny::tagList(
        shiny::h5(sprintf("%s: %s, %s, %s %s, %s", row$decision_id,
                          row$crop_family, row$application_rate,
                          row$receptor_size, tolower(row$taxon),
                          row$effect_window)),
        bslib::layout_column_wrap(
          width = 1 / 4, heights_equal = "row",
          bslib::value_box("Current recorded position",
                           row$current_table162_position,
                           shiny::span("PEER_REVIEW_DECISION, read only"),
                           theme = "dark"),
          bslib::value_box("Screening RQ", fmt_sig(row$screening_rq_max),
                           shiny::span("CALCULATED"), theme = "danger"),
          bslib::value_box("Days above metric",
                           fmt_sig(row$days_above_loc_at_full_diet),
                           shiny::span("at a 100% treated-seed diet"),
                           theme = "warning"),
          bslib::value_box("Max obtainable diet",
                           paste0(fmt_sig(row$max_feasible_diet_pct), "%"),
                           shiny::span("at sowing, within the search area"),
                           theme = "info")
        ),
        shiny::br(),
        bslib::layout_column_wrap(
          width = 1 / 2,
          block("Factors increasing concern (SOURCE_EVIDENCE)",
                row$factors_increasing_concern, "danger"),
          block("Factors decreasing concern (SOURCE_EVIDENCE)",
                row$factors_decreasing_concern, "success")
        ),
        bslib::layout_column_wrap(
          width = 1 / 2,
          block("Biological and contextual evidence", row$contextual_evidence),
          block("Important uncertainty", row$important_uncertainty)
        ),
        bslib::layout_column_wrap(
          width = 1 / 2,
          block("Scenario applicability", row$scenario_applicability),
          block("Current narrative reasoning (REVIEWER_INTERPRETATION)",
                row$current_narrative_reasoning)
        ),
        bslib::layout_column_wrap(
          width = 1 / 2,
          block("Peer-review questions", row$peer_review_question_ids),
          bslib::card(
            bslib::card_header("Peer-review consensus"),
            bslib::card_body(
              shiny::em("Human-controlled. Never populated by this software."),
              shiny::br(),
              shiny::span(class = "text-muted",
                          "Record the consensus and its rationale outside the ",
                          "application.")
            ),
            class = "border-dark"
          )
        )
      )
    })

    output$table <- DT::renderDT({
      DT::datatable(
        dplyr::select(support(), "decision_id", "crop_family", "model_crop",
                      "application_rate", "planting_method", "taxon",
                      "receptor_size", "effect_window",
                      "current_table162_position", "screening_rq_max",
                      "days_above_loc_at_full_diet", "max_feasible_diet_pct",
                      "quantitative_backbone_available"),
        rownames = FALSE, filter = "top",
        options = list(scrollX = TRUE, pageLength = 15)
      ) |>
        DT::formatSignif(
          columns = c("screening_rq_max", "days_above_loc_at_full_diet",
                      "max_feasible_diet_pct"), digits = 4
        )
    })

    output$download <- shiny::downloadHandler(
      filename = function() "stbam_table162_support.csv",
      content = function(file) readr::write_csv(support(), file)
    )
  })
}
