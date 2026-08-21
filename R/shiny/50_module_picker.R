# Phase 1: evaluation picker/landing screen (ADR-014).
#
# docs/planning/shiny_information_architecture.md §1-2. A thin view over
# R/evaluations/54_evaluation_folder.R -- every action here (Create, Open,
# Clone, Rename, Delete) is a direct call to that layer's already-tested
# functions, not a second implementation of evaluation lifecycle logic.
#
# This module contains NO scientific calculation and no direct file I/O of
# its own beyond what R/evaluations/*.R already provides.

#' @noRd
mod_picker_ui <- function(id) {
  ns <- shiny::NS(id)
  bslib::layout_sidebar(
    sidebar = bslib::sidebar(
      width = 320,
      shiny::h5("Create a new evaluation"),
      shiny::textInput(ns("new_name"), "Evaluation name", placeholder = "e.g. thiamethoxam_bam_2026"),
      shiny::actionButton(ns("create"), "Create", icon = shiny::icon("plus"),
                          class = "btn-primary btn-sm"),
      shiny::hr(),
      shiny::h5("Selected evaluation"),
      shiny::uiOutput(ns("selection_actions"))
    ),
    shiny::h4("Evaluations"),
    shiny::helpText("Select a row, then Open it, or use the actions in the sidebar."),
    DT::DTOutput(ns("table"))
  )
}

#' @noRd
mod_picker_server <- function(id, evaluations_root) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    refresh_tick <- shiny::reactiveVal(0L)
    opened_evaluation <- shiny::reactiveVal(NULL)  # path, or NULL if on the picker screen

    listing <- shiny::reactive({
      refresh_tick()
      list_evaluations(evaluations_root)
    })

    output$table <- DT::renderDT({
      DT::datatable(listing(), selection = "single", rownames = FALSE,
                    options = list(dom = "tp", pageLength = 15))
    })

    selected_name <- shiny::reactive({
      idx <- input$table_rows_selected
      if (is.null(idx) || length(idx) == 0L) return(NULL)
      listing()$name[[idx]]
    })

    output$selection_actions <- shiny::renderUI({
      name <- selected_name()
      if (is.null(name)) {
        return(shiny::helpText("No evaluation selected."))
      }
      shiny::tagList(
        shiny::strong(name),
        shiny::br(), shiny::br(),
        shiny::actionButton(ns("open"), "Open", icon = shiny::icon("folder-open"),
                            class = "btn-success btn-sm"),
        shiny::br(), shiny::br(),
        shiny::textInput(ns("clone_name"), "Clone as", placeholder = "New evaluation name"),
        shiny::actionButton(ns("clone"), "Clone", icon = shiny::icon("copy"), class = "btn-sm"),
        shiny::br(), shiny::br(),
        shiny::textInput(ns("rename_name"), "Rename to", placeholder = "New name"),
        shiny::actionButton(ns("rename"), "Rename", icon = shiny::icon("pen"), class = "btn-sm"),
        shiny::br(), shiny::br(),
        shiny::actionButton(ns("delete"), "Delete", icon = shiny::icon("trash"),
                            class = "btn-danger btn-sm")
      )
    })

    report_error <- function(e) {
      shiny::showNotification(conditionMessage(e), type = "error", duration = 8)
    }

    shiny::observeEvent(input$create, {
      tryCatch({
        shiny::req(nzchar(input$new_name))
        create_evaluation(evaluations_root, input$new_name)
        shiny::updateTextInput(session, "new_name", value = "")
        refresh_tick(refresh_tick() + 1L)
        shiny::showNotification(paste0("Created evaluation \"", input$new_name, "\"."), type = "message")
      }, error = report_error)
    })

    shiny::observeEvent(input$open, {
      name <- selected_name()
      shiny::req(name)
      tryCatch({
        path <- open_evaluation(evaluations_root, name)
        opened_evaluation(path)
      }, error = report_error)
    })

    shiny::observeEvent(input$clone, {
      name <- selected_name()
      shiny::req(name, nzchar(input$clone_name))
      tryCatch({
        clone_evaluation(evaluations_root, name, input$clone_name)
        shiny::updateTextInput(session, "clone_name", value = "")
        refresh_tick(refresh_tick() + 1L)
        shiny::showNotification(paste0("Cloned \"", name, "\" as \"", input$clone_name, "\"."), type = "message")
      }, error = report_error)
    })

    shiny::observeEvent(input$rename, {
      name <- selected_name()
      shiny::req(name, nzchar(input$rename_name))
      tryCatch({
        rename_evaluation(evaluations_root, name, input$rename_name)
        shiny::updateTextInput(session, "rename_name", value = "")
        refresh_tick(refresh_tick() + 1L)
        shiny::showNotification(paste0("Renamed \"", name, "\" to \"", input$rename_name, "\"."), type = "message")
      }, error = report_error)
    })

    shiny::observeEvent(input$delete, {
      name <- selected_name()
      shiny::req(name)
      shiny::showModal(shiny::modalDialog(
        title = "Delete evaluation",
        sprintf("Permanently delete \"%s\" and everything inside it? This cannot be undone.", name),
        footer = shiny::tagList(
          shiny::modalButton("Cancel"),
          shiny::actionButton(ns("delete_confirm"), "Delete", class = "btn-danger")
        )
      ))
    })

    shiny::observeEvent(input$delete_confirm, {
      name <- selected_name()
      shiny::req(name)
      tryCatch({
        delete_evaluation(evaluations_root, name, confirm = TRUE)
        refresh_tick(refresh_tick() + 1L)
        shiny::removeModal()
        shiny::showNotification(paste0("Deleted \"", name, "\"."), type = "message")
      }, error = function(e) {
        shiny::removeModal()
        report_error(e)
      })
    })

    #' Return to the picker screen from the workspace
    #' @noRd
    close_evaluation <- function() {
      opened_evaluation(NULL)
      refresh_tick(refresh_tick() + 1L)
    }

    list(
      opened_evaluation = opened_evaluation,
      close_evaluation = close_evaluation
    )
  })
}
