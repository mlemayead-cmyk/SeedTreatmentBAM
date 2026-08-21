# Phase 1: use_patterns.csv editor (ADR-005, ADR-006, ADR-007).
#
# Structurally the same pattern as R/shiny/51_module_named_set_editor.R
# (grid + add/edit form/modal + Excel round trip + validated save), applied
# to the single evaluation-wide `use_patterns.csv` table instead of a
# named-set category -- there is no set selector or "new set" action here,
# since ADR-005 keeps `use_patterns.csv` a single table per evaluation.

#' @noRd
mod_use_patterns_editor_ui <- function(id) {
  ns <- shiny::NS(id)
  bslib::layout_sidebar(
    sidebar = bslib::sidebar(
      width = 300,
      shiny::actionButton(ns("add_row"), "Add row...", icon = shiny::icon("plus"), class = "btn-sm"),
      shiny::actionButton(ns("edit_row"), "Edit selected row...", icon = shiny::icon("pen"), class = "btn-sm"),
      shiny::actionButton(ns("delete_row"), "Delete selected row", icon = shiny::icon("trash"), class = "btn-sm"),
      shiny::hr(),
      shiny::downloadButton(ns("download_excel"), "Download as Excel", class = "btn-sm"),
      shiny::fileInput(ns("upload"), "Upload Excel or CSV", accept = c(".xlsx", ".xls", ".csv")),
      shiny::hr(),
      shiny::actionButton(ns("save"), "Save use patterns", icon = shiny::icon("floppy-disk"),
                          class = "btn-primary btn-sm"),
      shiny::uiOutput(ns("dirty_indicator"))
    ),
    shiny::uiOutput(ns("errors")),
    DT::DTOutput(ns("grid"))
  )
}

#' @param evaluation_path A reactive returning the open evaluation's path.
#' @return A list with `is_dirty()`, `pending_item()`, `mark_saved()` --
#'   same shape as `mod_named_set_editor_server()`'s return, so the
#'   workspace module can aggregate both uniformly.
#' @noRd
mod_use_patterns_editor_server <- function(id, evaluation_path) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns
    schema <- stbam_schema_use_patterns()

    draft <- shiny::reactiveVal(NULL)
    dirty <- shiny::reactiveVal(FALSE)
    errors <- shiny::reactiveVal(character())

    shiny::observeEvent(evaluation_path(), {
      shiny::req(evaluation_path())
      draft(read_use_patterns(evaluation_path()))
      dirty(FALSE)
      errors(character())
    }, ignoreNULL = TRUE)

    output$grid <- DT::renderDT({
      shiny::req(draft())
      DT::datatable(draft(), selection = "single", rownames = FALSE,
                    options = list(scrollX = TRUE, pageLength = 10))
    })

    output$errors <- shiny::renderUI({
      e <- errors()
      if (length(e) == 0L) return(NULL)
      shiny::div(class = "alert alert-danger",
                shiny::tags$strong("use_patterns.csv was not saved -- fix the following and try again:"),
                shiny::tags$ul(lapply(e, shiny::tags$li)))
    })

    output$dirty_indicator <- shiny::renderUI({
      if (isTRUE(dirty())) {
        shiny::tags$span(class = "text-warning", shiny::icon("circle-exclamation"), " Unsaved draft")
      } else {
        shiny::tags$span(class = "text-success", shiny::icon("circle-check"), " Saved")
      }
    })

    editing_index <- shiny::reactiveVal(NULL)

    open_row_modal <- function(row = NULL, index = NULL) {
      editing_index(index)
      shiny::showModal(shiny::modalDialog(
        title = if (is.null(index)) "Add use pattern row" else "Edit use pattern row",
        stbam_schema_form(ns, schema, row),
        footer = shiny::tagList(
          shiny::modalButton("Cancel"),
          shiny::actionButton(ns("submit_row"), "OK", class = "btn-primary")
        ),
        size = "l"
      ))
    }

    shiny::observeEvent(input$add_row, open_row_modal())
    shiny::observeEvent(input$edit_row, {
      idx <- input$grid_rows_selected
      shiny::req(draft(), length(idx) == 1L)
      open_row_modal(draft()[idx, , drop = FALSE], idx)
    })

    shiny::observeEvent(input$submit_row, {
      new_row <- stbam_schema_form_values(input, schema)
      current <- draft() %||% stbam_empty_use_patterns()
      idx <- editing_index()
      updated <- if (is.null(idx)) rbind(current, new_row) else { current[idx, ] <- new_row; current }
      draft(updated)
      dirty(TRUE)
      errors(character())
      shiny::removeModal()
    })

    shiny::observeEvent(input$delete_row, {
      idx <- input$grid_rows_selected
      shiny::req(draft(), length(idx) == 1L)
      draft(draft()[-idx, , drop = FALSE])
      dirty(TRUE)
    })

    output$download_excel <- shiny::downloadHandler(
      filename = function() "use_patterns.xlsx",
      content = function(file) export_table_excel(draft() %||% stbam_empty_use_patterns(), file)
    )

    shiny::observeEvent(input$upload, {
      shiny::req(input$upload$datapath)
      imported <- import_table_file(input$upload$datapath, schema, key_columns = schema$unique_key)
      if (isTRUE(imported$valid)) {
        draft(imported$data)
        dirty(TRUE)
        errors(character())
      } else {
        errors(imported$errors)
      }
    })

    do_save <- function() {
      shiny::req(evaluation_path(), draft())
      result <- save_use_patterns(evaluation_path(), draft())
      if (isTRUE(result$success)) {
        dirty(FALSE)
        errors(character())
      } else {
        errors(result$errors)
      }
      result
    }

    shiny::observeEvent(input$save, do_save())

    list(
      is_dirty = dirty,
      pending_item = function() {
        if (!isTRUE(dirty()) || is.null(draft())) return(NULL)
        list(kind = "use_patterns", df = draft(), check_referential_integrity = TRUE)
      },
      mark_saved = function() dirty(FALSE)
    )
  })
}
