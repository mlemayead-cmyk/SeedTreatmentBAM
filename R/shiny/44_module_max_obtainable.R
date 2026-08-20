# Shiny module: maximum obtainable exposure.
#
# Distinguishes the conventional conditional (assumed-dietary-fraction) RQ
# view, already available on "Exposure through time", from the
# availability-constrained maximum-obtainable view added here. This module
# runs its own bounded computation (one scenario, all receptor sizes of one
# taxon, one effects metric) rather than reading the shared results()
# reactive's timecourse slice, because that slice is capped at 24 scenario
# rows for the whole dashboard and is not guaranteed to include every
# receptor size for the specific scenario/metric this view needs. It reads
# the same inputs$params() as every other tab, so overrides are always
# respected and nothing here can go stale relative to the rest of the app.

#' @noRd
mod_max_obtainable_ui <- function(id) {
  ns <- shiny::NS(id)
  bslib::layout_sidebar(
    sidebar = bslib::sidebar(
      width = 340,
      shiny::div(
        class = "alert alert-info py-2",
        shiny::strong("Two different questions. "),
        "\"100% treated-seed diet\" is the conventional conditional RQ. ",
        "\"Maximum obtainable within MSA\" is what the receptor could ",
        "actually get, capped by surface seed available and its own food ",
        "requirement. Neither replaces the other."
      ),
      shiny::selectInput(ns("scenario_id"), "Scenario", choices = NULL),
      shiny::selectInput(ns("metric_id"), "Effects metric", choices = NULL),
      shiny::checkboxInput(ns("free_y"), "Independent y-axis scale per panel",
                           value = TRUE),
      shiny::hr(),
      shiny::h6("Current assumptions"),
      shiny::uiOutput(ns("assumptions_panel"))
    ),

    shiny::uiOutput(ns("override_banner")),
    shiny::plotOutput(ns("principal_plot"), height = 380),

    shiny::hr(),
    shiny::h6("Summary"),
    shiny::helpText(
      "Both crossing days are exact closed-form results, not read off a ",
      "plotting grid: while seed is abundant the maximum-obtainable curve ",
      "declines with the conditional curve; once availability binds it ",
      "declines at the combined surface-seed/residue rate."
    ),
    DT::DTOutput(ns("summary_table")),

    shiny::hr(),
    bslib::navset_card_tab(
      bslib::nav_panel("Seed availability vs. requirement",
                       shiny::selectInput(ns("diag_receptor"), "Receptor",
                                          choices = NULL, width = "260px"),
                       shiny::plotOutput(ns("availability_plot"), height = 360)),
      bslib::nav_panel("Surface seed", shiny::plotOutput(ns("surface_plot"),
                                                         height = 360)),
      bslib::nav_panel("Residue per seed", shiny::plotOutput(ns("residue_plot"),
                                                             height = 360)),
      bslib::nav_panel("Surface loading", shiny::plotOutput(ns("loading_plot"),
                                                            height = 360))
    ),

    shiny::hr(),
    bslib::layout_column_wrap(
      width = 1 / 2,
      shiny::downloadButton(ns("download_png"),
                            "Download the principal figure (PNG)"),
      shiny::downloadButton(ns("download_svg"),
                            "Download the principal figure (SVG)")
    ),
    shiny::helpText(
      "The downloaded figure includes its own title, panel labels, legend ",
      "and a full assumptions/footnote block. It is designed to be ",
      "interpretable without this Shiny page -- suitable for direct use ",
      "in a Word report or peer-review material."
    )
  )
}

#' @noRd
mod_max_obtainable_server <- function(id, baseline, inputs, results) {
  shiny::moduleServer(id, function(input, output, session) {

    shiny::observe({
      scenarios <- unique(results()$inputs$scenario_id)
      shiny::updateSelectInput(
        session, "scenario_id", choices = scenarios,
        selected = if (length(scenarios) > 0) scenarios[[1]] else character()
      )
    })

    all_metrics <- shiny::reactive({
      resolve_effects_metrics(inputs$params(),
                              c("SCREENING", "REFINED", "REFINED_ADDITIONAL"))
    })

    shiny::observe({
      metrics <- all_metrics()
      choices <- stats::setNames(
        metrics$metric_id,
        vapply(seq_len(nrow(metrics)), function(i) {
          format_metric_label(metrics$taxon[[i]], metrics$duration_class[[i]],
                              metrics$metric_role[[i]],
                              metrics$effects_metric[[i]])
        }, character(1))
      )
      shiny::updateSelectInput(session, "metric_id", choices = choices)
    })

    scenario_row <- shiny::reactive({
      shiny::req(input$scenario_id)
      row <- results()$inputs[
        results()$inputs$scenario_id == input$scenario_id,
      ][1, ]
      shiny::validate(shiny::need(nrow(row) == 1L, "Scenario not found."))
      row
    })

    metric_row <- shiny::reactive({
      shiny::req(input$metric_id)
      row <- all_metrics()[all_metrics()$metric_id == input$metric_id, ]
      shiny::validate(shiny::need(nrow(row) == 1L,
                                  "Effects metric not found."))
      row
    })

    # One scenario, every receptor size of the metric's taxon, one metric,
    # 100%-diet basis, over the currently selected day range. Deliberately
    # NOT the shared results()$timecourse slice -- see file header.
    panel_data <- shiny::reactive({
      params <- inputs$params()
      scen <- scenario_row()
      metric <- metric_row()
      taxon <- metric$taxon[[1]]
      receptor_ids <- baseline$receptors$receptor_id[
        baseline$receptors$taxon == taxon
      ]
      receptors <- resolve_receptors(params, receptor_ids)
      days <- results()$selection$days
      tc <- build_daily_timecourse(params, scen, receptors, metric,
                                   diet_fractions = 1, days = days)
      shiny::validate(shiny::need(nrow(tc) > 0,
                                  "No results for this scenario/metric."))
      tc
    })

    metadata_list <- shiny::reactive({
      params <- inputs$params()
      metric <- metric_row()
      pd <- panel_data()
      day0 <- pd[pd$day == min(pd$day), ]
      ids <- unique(day0$receptor_id)
      stats::setNames(
        lapply(ids, function(id) {
          row <- day0[day0$receptor_id == id, ][1, ]
          build_figure_metadata(row, metric, params)
        }),
        ids
      )
    })

    shiny::observe({
      meta_list <- metadata_list()
      choices <- stats::setNames(names(meta_list),
                                 vapply(meta_list, function(m) m$receptor_label,
                                       character(1)))
      shiny::updateSelectInput(session, "diag_receptor", choices = choices)
    })

    output$override_banner <- shiny::renderUI({
      params <- inputs$params()
      if (!has_overrides(params)) {
        shiny::div(class = "alert alert-success py-2", shiny::icon("check"),
                  " Assessment baseline. No overrides applied.")
      } else {
        shiny::div(
          class = "alert alert-warning py-2", shiny::icon("triangle-exclamation"),
          shiny::strong(sprintf(" %d override(s) applied. ",
                                nrow(params$overrides))),
          "These results are NOT the assessment baseline scenario."
        )
      }
    })

    output$assumptions_panel <- shiny::renderUI({
      meta_list <- metadata_list()
      shiny::req(length(meta_list) > 0)
      m <- meta_list[[1]]   # scenario/agronomy/fate/metric shared across panels
      # MSA, body weight and food requirement are NOT shared across panels
      # (large birds use 140 m2 while small/medium use 70 m2; mammal
      # acute/chronic differ too) -- listing every receptor explicitly
      # here, rather than reading only meta_list[[1]], is the fix for
      # independent review finding A7 (the sidebar previously understated
      # the large-bird MSA by half).
      msa_items <- lapply(meta_list, function(x) {
        shiny::tags$li(sprintf(
          "%s: MSA %s m2 (%s-term%s) | Body weight %s g | Food requirement %s g dw/day",
          x$receptor_label, fmt_sig(x$msa_m2), x$msa_term,
          if (isTRUE(x$msa_is_overridden)) ", OVERRIDDEN" else "",
          fmt_sig(x$body_weight_g), fmt_sig(x$food_intake_g_dw_per_day)
        ))
      })
      pool_note <- if (identical(m$accessible_pool_basis, "SURFACE_PLUS_BURIED")) {
        sprintf(
          paste("Initial surface seed %s seeds/m2, but this receptor group",
                "accesses the FULL sown density (%s seeds/m2, ASSUMPTION-020)",
                "-- the figure is built on %s seeds/m2, not the surface figure."),
          fmt_sig(m$initial_surface_seeds_per_m2),
          fmt_sig(m$accessible_seeds_per_m2), fmt_sig(m$accessible_seeds_per_m2)
        )
      } else {
        sprintf("Initial surface seed: %s seeds/m2",
               fmt_sig(m$initial_surface_seeds_per_m2))
      }
      shiny::tagList(
        shiny::p(shiny::strong(m$scenario_label)),
        shiny::p(m$metric_label),
        shiny::tags$ul(
          class = "small",
          shiny::tags$li(sprintf("Treatment: %s %s (%s g a.i./ha)",
                                 fmt_sig(m$application_rate),
                                 m$application_rate_unit,
                                 fmt_sig(m$field_rate_g_ai_per_ha))),
          shiny::tags$li(pool_note),
          shiny::tags$li(sprintf(
            "Surface-seed DT50: %s d | Residue DT50: %s d",
            fmt_sig(m$surface_seed_dt50_days), fmt_sig(m$residue_dt50_days)
          )),
          msa_items,
          shiny::tags$li(sprintf("LOC: RQ = %s", fmt_sig(m$loc)))
        ),
        shiny::helpText(m$msa_policy_note)
      )
    })

    principal_plot <- shiny::reactive({
      plot_max_obtainable_small_multiple(panel_data(), metadata_list(),
                                         free_y = input$free_y,
                                         detail = "concise")
    })
    output$principal_plot <- shiny::renderPlot(principal_plot())

    output$summary_table <- DT::renderDT({
      summary <- summarise_max_obtainable_exposure(panel_data())
      meta_list <- metadata_list()
      display <- tibble::tibble(
        Receptor = vapply(summary$receptor_id, function(id) {
          md <- meta_list[[id]]
          if (is.null(md)) id else md$receptor_label
        }, character(1)),
        `Peak conditional RQ` = fmt_sig(summary$peak_conditional_rq),
        `Peak max-obtainable RQ` = fmt_sig(summary$peak_max_obtainable_rq),
        `Day conditional < LOC` = fmt_sig(summary$day_conditional_below_loc),
        `Day max-obtainable < LOC` = fmt_sig(summary$day_max_obtainable_below_loc),
        `Day 100% diet unobtainable` = fmt_sig(summary$day_100pct_diet_unobtainable),
        `Day 50% diet unobtainable` = fmt_sig(summary$day_50pct_diet_unobtainable),
        `Day 25% diet unobtainable` = fmt_sig(summary$day_25pct_diet_unobtainable)
      )
      DT::datatable(display, rownames = FALSE,
                   options = list(dom = "t", scrollX = TRUE))
    })

    output$surface_plot <- shiny::renderPlot(plot_surface_seeds(panel_data()))
    output$residue_plot <- shiny::renderPlot(plot_ai_per_seed(panel_data()))
    output$loading_plot <- shiny::renderPlot(plot_surface_ai(panel_data()))

    output$availability_plot <- shiny::renderPlot({
      shiny::req(input$diag_receptor)
      meta_list <- metadata_list()
      shiny::validate(shiny::need(input$diag_receptor %in% names(meta_list),
                                  "Receptor not available for this metric."))
      one <- panel_data()[panel_data()$receptor_id == input$diag_receptor, ]
      plot_seed_availability_vs_requirement(one, meta_list[[input$diag_receptor]])
    })

    output$download_png <- shiny::downloadHandler(
      filename = function() "stbam_max_obtainable_exposure.png",
      content = function(file) {
        p <- plot_max_obtainable_small_multiple(panel_data(), metadata_list(),
                                                free_y = input$free_y,
                                                detail = "full")
        ggplot2::ggsave(file, p, width = 13, height = 11, dpi = 300,
                        bg = "white")
      }
    )
    output$download_svg <- shiny::downloadHandler(
      filename = function() "stbam_max_obtainable_exposure.svg",
      content = function(file) {
        p <- plot_max_obtainable_small_multiple(panel_data(), metadata_list(),
                                                free_y = input$free_y,
                                                detail = "full")
        if (requireNamespace("svglite", quietly = TRUE)) {
          ggplot2::ggsave(file, p, width = 13, height = 11,
                          device = svglite::svglite, bg = "white")
        } else {
          ggplot2::ggsave(file, p, width = 13, height = 11, bg = "white")
        }
      }
    )
  })
}
