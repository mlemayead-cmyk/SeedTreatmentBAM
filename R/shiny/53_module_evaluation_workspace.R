# Phase 1: evaluation workspace -- inputs screens only (ADR-002, ADR-007).
#
# docs/planning/shiny_information_architecture.md §3. Wires one
# mod_named_set_editor instance per named-set category (R/shiny/51_*) plus
# one mod_use_patterns_editor instance (R/shiny/52_*) into tabs, and adds
# the whole-evaluation "Save evaluation" action (ADR-007's second save
# granularity) on top of each tab's own per-table Save.
#
# Explicitly out of scope here, per implementation_phases_proposal.md Phase 1:
# runs, results, tables, figures. This workspace only has an Inputs area.

#' @noRd
mod_evaluation_workspace_ui <- function(id) {
  ns <- shiny::NS(id)
  category_labels <- c(
    seeding_sets = "Seeding assumptions", planting_method_sets = "Planting methods",
    receptor_sets = "Receptors", effects_sets = "Effects", fate_sets = "Fate",
    reporting_sets = "Reporting groups"
  )

  shiny::tagList(
    shiny::fluidRow(
      shiny::column(8, shiny::h4(shiny::textOutput(ns("evaluation_name"), inline = TRUE))),
      shiny::column(4, class = "text-end",
                   shiny::actionButton(ns("back"), "Back to evaluations",
                                       icon = shiny::icon("arrow-left"), class = "btn-sm"),
                   shiny::actionButton(ns("save_all"), "Save evaluation (all dirty tables)",
                                       icon = shiny::icon("floppy-disk"),
                                       class = "btn-primary btn-sm"))
    ),
    shiny::uiOutput(ns("save_all_status")),
    shiny::hr(),
    do.call(bslib::navset_card_tab, c(
      list(bslib::nav_panel("Use patterns", mod_use_patterns_editor_ui(ns("use_patterns")))),
      lapply(names(STBAM_SET_CATEGORIES), function(category) {
        bslib::nav_panel(category_labels[[category]],
                         mod_named_set_editor_ui(ns(category)))
      })
    ))
  )
}

#' @param evaluation_path A reactive returning the open evaluation's path.
#' @param on_back Called when the user clicks "Back to evaluations."
#' @noRd
mod_evaluation_workspace_server <- function(id, evaluation_path, on_back) {
  shiny::moduleServer(id, function(input, output, session) {
    output$evaluation_name <- shiny::renderText({
      shiny::req(evaluation_path())
      paste("Evaluation:", basename(evaluation_path()))
    })

    shiny::observeEvent(input$back, on_back())

    use_patterns_editor <- mod_use_patterns_editor_server("use_patterns", evaluation_path)
    category_editors <- stats::setNames(
      lapply(names(STBAM_SET_CATEGORIES), function(category) {
        mod_named_set_editor_server(category, evaluation_path, category)
      }),
      names(STBAM_SET_CATEGORIES)
    )
    all_editors <- c(list(use_patterns = use_patterns_editor), category_editors)

    save_all_message <- shiny::reactiveVal(NULL)

    shiny::observeEvent(input$save_all, {
      items <- Filter(Negate(is.null), lapply(all_editors, function(e) e$pending_item()))
      if (length(items) == 0L) {
        save_all_message(list(type = "message", text = "Nothing to save -- no tables are dirty."))
        return(invisible(NULL))
      }
      result <- save_all(evaluation_path(), items)
      if (isTRUE(result$success)) {
        for (nm in names(items)) all_editors[[nm]]$mark_saved()
        save_all_message(list(type = "message",
                              text = sprintf("Saved %d table(s).", length(items))))
      } else {
        detail <- vapply(names(result$errors), function(nm) {
          paste0(nm, ": ", paste(result$errors[[nm]], collapse = "; "))
        }, character(1))
        save_all_message(list(
          type = "error",
          text = paste0("Save-all failed -- no table was written. ", paste(detail, collapse = " | "))
        ))
      }
    })

    output$save_all_status <- shiny::renderUI({
      msg <- save_all_message()
      if (is.null(msg)) return(NULL)
      cls <- if (identical(msg$type, "error")) "alert alert-danger" else "alert alert-success"
      shiny::div(class = cls, msg$text)
    })

    invisible(NULL)
  })
}
