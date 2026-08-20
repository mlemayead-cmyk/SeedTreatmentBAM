# Shiny module: scenario selection and parameter editing.
#
# The application contains NO scientific calculation. Every number displayed
# comes from the tested calculation engine.

#' @noRd
mod_inputs_ui <- function(id) {
  ns <- shiny::NS(id)
  bslib::layout_sidebar(
    sidebar = bslib::sidebar(
      width = 340,
      shiny::selectInput(ns("workbook"), "Crop group (source workbook)",
                         choices = NULL),
      shiny::selectizeInput(ns("crops"), "Crops", choices = NULL,
                            multiple = TRUE),
      shiny::selectizeInput(ns("rate_levels"), "Application rate levels",
                            choices = c("high", "mid", "low"),
                            selected = c("high", "mid", "low"),
                            multiple = TRUE),
      shiny::selectizeInput(ns("methods"), "Planting methods",
                            choices = STBAM_PLANTING_METHODS,
                            selected = STBAM_PLANTING_METHODS,
                            multiple = TRUE),
      shiny::selectizeInput(ns("receptors"), "Receptors", choices = NULL,
                            multiple = TRUE),
      shiny::selectizeInput(ns("metric_roles"), "Effects metric role",
                            choices = c("SCREENING", "REFINED",
                                        "REFINED_ADDITIONAL"),
                            selected = "SCREENING", multiple = TRUE),
      shiny::selectizeInput(ns("diets"), "Dietary fractions (%)",
                            choices = c(100, 50, 25, 10, 5, 1),
                            selected = c(100, 50, 25, 10, 5, 1),
                            multiple = TRUE),
      shiny::radioButtons(ns("msa_term"), "Maximum search area",
                          choices = c("Short term (1 d)" = "short",
                                      "Long term (21 d)" = "long"),
                          selected = "short"),
      shiny::sliderInput(ns("days"), "Simulation length (days)",
                         min = 10, max = 365, value = 60, step = 5),
      shiny::hr(),
      shiny::actionButton(ns("reset"), "Reset to assessment defaults",
                          class = "btn-warning btn-sm",
                          icon = shiny::icon("rotate-left")),
      shiny::helpText(
        "Resetting clears every override. It never changes the assessment ",
        "baseline files."
      )
    ),

    bslib::navset_card_tab(
      bslib::nav_panel(
        "Editable assumptions",
        shiny::div(
          class = "p-2",
          shiny::p(
            shiny::strong("Overrides never modify the assessment baseline."),
            " They are held separately, labelled in every output, and can be ",
            "exported and reloaded. Leave a field blank to keep the ",
            "assessment default."
          ),
          bslib::layout_column_wrap(
            width = 1 / 3,
            bslib::card(
              bslib::card_header("Dissipation"),
              shiny::numericInput(ns("surface_dt50"),
                                  "Surface-seed disappearance DT50 (days)",
                                  value = NA, min = 0.01, step = 1),
              shiny::numericInput(ns("residue_dt50"),
                                  "Residue dissipation DT50 (days)",
                                  value = NA, min = 0.01, step = 1),
              shiny::helpText("Two distinct processes with distinct half-lives.")
            ),
            bslib::card(
              bslib::card_header("Surface seed by planting method"),
              shiny::numericInput(ns("f_broadcast"),
                                  "Broadcast surface fraction", value = NA,
                                  min = 0, max = 1, step = 0.01),
              shiny::numericInput(ns("f_drill_spring"),
                                  "Spring drill surface fraction", value = NA,
                                  min = 0, max = 1, step = 0.001),
              shiny::numericInput(ns("f_drill_fall"),
                                  "Fall drill surface fraction", value = NA,
                                  min = 0, max = 1, step = 0.001),
              shiny::numericInput(ns("f_precision"),
                                  "Precision surface fraction", value = NA,
                                  min = 0, max = 1, step = 0.001)
            ),
            bslib::card(
              bslib::card_header("Crop agronomy"),
              shiny::selectInput(ns("edit_crop"), "Crop to edit",
                                 choices = NULL),
              shiny::numericInput(ns("tkw_low"),
                                  "Low thousand-seed weight (g/1000)",
                                  value = NA, min = 0.001, step = 0.1),
              shiny::numericInput(ns("tkw_high"),
                                  "High thousand-seed weight (g/1000)",
                                  value = NA, min = 0.001, step = 0.1),
              shiny::numericInput(ns("seeds_low"),
                                  "Lower seeding rate (seeds/ha)",
                                  value = NA, min = 0, step = 1000),
              shiny::numericInput(ns("seeds_high"),
                                  "Upper seeding rate (seeds/ha)",
                                  value = NA, min = 0, step = 1000)
            )
          ),
          shiny::hr(),
          shiny::h5("Effect of the current overrides"),
          shiny::helpText(
            "Baseline compared with the current parameter set, for the ",
            "selected scenarios. This is what makes sensitivity to agronomic ",
            "assumptions visible rather than hidden."
          ),
          DT::DTOutput(ns("change_table"))
        )
      ),

      bslib::nav_panel(
        "Override register",
        shiny::div(
          class = "p-2",
          shiny::p("Every override with its provenance and status."),
          DT::DTOutput(ns("override_table")),
          shiny::hr(),
          bslib::layout_column_wrap(
            width = 1 / 2,
            shiny::downloadButton(ns("export_config"),
                                  "Export this scenario configuration"),
            shiny::fileInput(ns("import_config"),
                             "Reload a scenario configuration",
                             accept = ".csv")
          )
        )
      ),

      bslib::nav_panel(
        "Assessment defaults",
        shiny::div(
          class = "p-2",
          shiny::p("The immutable assessment baseline, with its provenance."),
          shiny::h5("Receptors"),
          DT::DTOutput(ns("baseline_receptors")),
          shiny::h5("Planting methods"),
          DT::DTOutput(ns("baseline_methods")),
          shiny::h5("Effects metrics"),
          DT::DTOutput(ns("baseline_metrics")),
          shiny::h5("Source workbooks"),
          DT::DTOutput(ns("baseline_sources"))
        )
      )
    )
  )
}

#' @noRd
mod_inputs_server <- function(id, baseline) {
  shiny::moduleServer(id, function(input, output, session) {

    overrides <- shiny::reactiveVal(parameter_set(baseline, "Working scenario"))

    shiny::observe({
      workbooks <- sort(unique(baseline$scenarios$workbook))
      shiny::updateSelectInput(session, "workbook", choices = workbooks,
                               selected = "small_cereals")
      shiny::updateSelectizeInput(
        session, "receptors",
        choices = baseline$receptors$receptor_id,
        selected = baseline$receptors$receptor_id
      )
    })

    crops_available <- shiny::reactive({
      shiny::req(input$workbook)
      sort(unique(
        baseline$scenarios$crop[baseline$scenarios$workbook == input$workbook]
      ))
    })

    shiny::observeEvent(crops_available(), {
      shiny::updateSelectizeInput(session, "crops", choices = crops_available(),
                                  selected = crops_available())
      shiny::updateSelectInput(session, "edit_crop",
                               choices = crops_available())
    })

    # Rebuild the parameter set from the editing controls. Blank means
    # "keep the assessment default".
    shiny::observe({
      params <- parameter_set(baseline, "Working scenario")

      add <- function(params, parameter, value, scope, default) {
        if (is.null(value) || length(value) != 1L || is.na(value)) {
          return(params)
        }
        if (!is.null(default) && isTRUE(all.equal(value, default))) {
          return(params)
        }
        set_override(params, parameter, value, scope = scope,
                     baseline_value = default %||% NA_real_,
                     status = "USER_OVERRIDE",
                     source = "Interactive session")
      }

      params <- add(params, "surface_seed_dt50_days", input$surface_dt50,
                    "global", dissipation_default(baseline,
                                                  "surface_seed_dt50_days"))
      params <- add(params, "residue_dt50_days", input$residue_dt50, "global",
                    dissipation_default(baseline, "residue_dt50_days"))

      methods <- baseline$planting_methods
      for (spec in list(
        list(id = input$f_broadcast, method = "broadcast"),
        list(id = input$f_drill_spring, method = "drill_spring"),
        list(id = input$f_drill_fall, method = "drill_fall"),
        list(id = input$f_precision, method = "precision")
      )) {
        default <- methods$surface_seed_fraction[
          methods$planting_method == spec$method
        ][1]
        params <- add(params, "surface_seed_fraction", spec$id, spec$method,
                      default)
      }

      if (!is.null(input$edit_crop) && nzchar(input$edit_crop)) {
        crop_row <- baseline$crops[baseline$crops$crop == input$edit_crop, ][1, ]
        if (nrow(crop_row) == 1L) {
          params <- add(params, "tkw_g_per_1000", input$tkw_low,
                        paste0(input$edit_crop, ":low_tkw"),
                        crop_row$tkw_low_g_per_1000)
          params <- add(params, "tkw_g_per_1000", input$tkw_high,
                        paste0(input$edit_crop, ":high_tkw"),
                        crop_row$tkw_high_g_per_1000)
          params <- add(params, "seeds_per_ha", input$seeds_low,
                        paste0(input$edit_crop, ":low"),
                        crop_row$seeds_per_ha_low)
          params <- add(params, "seeds_per_ha", input$seeds_high,
                        paste0(input$edit_crop, ":high"),
                        crop_row$seeds_per_ha_high)
        }
      }

      overrides(params)
    })

    shiny::observeEvent(input$reset, {
      for (control in c("surface_dt50", "residue_dt50", "f_broadcast",
                        "f_drill_spring", "f_drill_fall", "f_precision",
                        "tkw_low", "tkw_high", "seeds_low", "seeds_high")) {
        shiny::updateNumericInput(session, control, value = NA)
      }
      overrides(parameter_set(baseline, "Working scenario"))
      shiny::showNotification(
        "Reset to assessment defaults. The baseline files were not modified.",
        type = "message"
      )
    })

    shiny::observeEvent(input$import_config, {
      shiny::req(input$import_config)
      result <- try(
        import_scenario_config(baseline, input$import_config$datapath),
        silent = TRUE
      )
      if (inherits(result, "try-error")) {
        shiny::showNotification(paste("Could not load configuration:",
                                      conditionMessage(attr(result, "condition"))),
                                type = "error", duration = NULL)
      } else {
        overrides(result)
        shiny::showNotification(
          paste0("Loaded scenario configuration '", result$name, "'."),
          type = "message"
        )
      }
    })

    output$override_table <- DT::renderDT({
      data <- overrides()$overrides
      if (nrow(data) == 0L) {
        data <- tibble::tibble(
          Message = "No overrides. Results reflect the assessment baseline."
        )
      }
      DT::datatable(data, rownames = FALSE, options = list(dom = "tip",
                                                           pageLength = 10))
    })

    output$change_table <- DT::renderDT({
      DT::datatable(change_summary(), rownames = FALSE,
                    options = list(dom = "t", pageLength = 25)) |>
        DT::formatStyle("Change", color = DT::styleEqual(
          c("no change"), c("grey")
        ))
    })

    output$baseline_receptors <- DT::renderDT(
      DT::datatable(baseline$receptors, rownames = FALSE,
                    options = list(dom = "t", scrollX = TRUE))
    )
    output$baseline_methods <- DT::renderDT(
      DT::datatable(baseline$planting_methods, rownames = FALSE,
                    options = list(dom = "t", scrollX = TRUE))
    )
    output$baseline_metrics <- DT::renderDT(
      DT::datatable(baseline$effects_metrics, rownames = FALSE,
                    options = list(dom = "tip", scrollX = TRUE,
                                   pageLength = 8))
    )
    output$baseline_sources <- DT::renderDT(
      DT::datatable(baseline$source_manifest, rownames = FALSE,
                    options = list(dom = "t", scrollX = TRUE))
    )

    output$export_config <- shiny::downloadHandler(
      filename = function() {
        paste0("stbam_scenario_", format(Sys.Date(), "%Y%m%d"), ".csv")
      },
      content = function(file) export_scenario_config(overrides(), file)
    )

    selection <- shiny::reactive({
      list(
        workbook = input$workbook,
        crops = input$crops,
        rate_levels = input$rate_levels,
        methods = input$methods,
        receptors = input$receptors,
        metric_roles = input$metric_roles,
        diet_fractions = sort(as.numeric(input$diets) / 100, decreasing = TRUE),
        msa_term = input$msa_term,
        days = 0:input$days
      )
    })

    # Baseline versus current parameter set, side by side.
    change_summary <- shiny::reactive({
      current <- overrides()
      if (!has_overrides(current)) {
        return(tibble::tibble(
          Quantity = "No overrides applied",
          Baseline = "-", Current = "-", Change = "no change"
        ))
      }
      selected <- selection()
      shiny::req(selected$crops, selected$receptors)

      compare_one <- function(params) {
        inputs <- build_scenario_inputs(
          params, crops = selected$crops, workbooks = selected$workbook,
          planting_methods = selected$methods,
          rate_levels = selected$rate_levels
        )
        summary <- build_scenario_summary(
          params, inputs,
          receptors = resolve_receptors(params, selected$receptors,
                                        selected$msa_term),
          effects_metrics = resolve_effects_metrics(params,
                                                    selected$metric_roles),
          diet_fractions = selected$diet_fractions
        )
        list(inputs = inputs, summary = summary)
      }

      base <- compare_one(parameter_set(baseline, "Assessment baseline"))
      now <- compare_one(current)

      quantity <- function(label, base_value, new_value, digits = 4) {
        change <- if (isTRUE(all.equal(base_value, new_value))) {
          "no change"
        } else if (base_value == 0) {
          "changed"
        } else {
          sprintf("%+.1f%%", 100 * (new_value - base_value) / abs(base_value))
        }
        tibble::tibble(
          Quantity = label,
          Baseline = fmt_sig(base_value, digits),
          Current = fmt_sig(new_value, digits),
          Change = change
        )
      }

      dplyr::bind_rows(
        quantity("Mean seed mass (g/seed)",
                 mean(base$inputs$seed_mass_g), mean(now$inputs$seed_mass_g)),
        quantity("Mean seeds planted (seeds/m2)",
                 mean(base$inputs$seeds_per_m2), mean(now$inputs$seeds_per_m2)),
        quantity("Mean initial surface seed (seeds/m2)",
                 mean(base$inputs$initial_surface_seeds_per_m2),
                 mean(now$inputs$initial_surface_seeds_per_m2)),
        quantity("Mean field rate (g a.i./ha)",
                 mean(base$inputs$field_rate_g_ai_per_ha),
                 mean(now$inputs$field_rate_g_ai_per_ha)),
        quantity("Maximum initial dose (mg a.i./kg bw/d)",
                 max(base$summary$initial_dose_mg_kg_bw_day),
                 max(now$summary$initial_dose_mg_kg_bw_day)),
        quantity("Maximum peak risk quotient",
                 max(base$summary$peak_rq), max(now$summary$peak_rq)),
        quantity("Maximum days above the metric",
                 max(base$summary$days_above_loc),
                 max(now$summary$days_above_loc)),
        quantity("Maximum days a full diet is available",
                 max(base$summary$days_at_full_diet_available),
                 max(now$summary$days_at_full_diet_available))
      )
    })

    list(params = overrides, selection = selection)
  })
}
