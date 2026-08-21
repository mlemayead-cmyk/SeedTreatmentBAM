# Phase 1: generic per-category named-set editor (ADR-006, ADR-007).
#
# One module, driven entirely by a schema from R/evaluations/50_schema_registry.R
# -- this is what "the same mechanism applies uniformly to every named-set
# category" (ADR-006) means in the Shiny layer: there is exactly one
# implementation, instantiated once per category
# (R/shiny/53_module_evaluation_workspace.R), not five bespoke UIs.
#
# All actual reads/writes/validation go through R/evaluations/*.R -- this
# file only wires Shiny inputs/outputs to those already-tested functions. It
# never writes a file itself.

#' Build a form input for one schema column
#' @noRd
stbam_field_input <- function(ns, col, value = NULL) {
  input_id <- ns(paste0("field_", col$name))
  switch(col$type,
    character = shiny::textInput(input_id, col$name, value = value %||% ""),
    numeric = shiny::numericInput(input_id, col$name, value = if (is.null(value)) NA else value),
    logical = shiny::checkboxInput(input_id, col$name, value = isTRUE(value))
  )
}

#' Render the full add/edit form for a schema, one field per column
#' @noRd
stbam_schema_form <- function(ns, schema, row = NULL) {
  shiny::tagList(lapply(schema$columns, function(col) {
    value <- if (!is.null(row) && col$name %in% names(row)) row[[col$name]][[1]] else NULL
    stbam_field_input(ns, col, value)
  }))
}

#' Read the current form inputs back into a one-row tibble matching the schema
#' @noRd
stbam_schema_form_values <- function(input, schema) {
  values <- lapply(schema$columns, function(col) {
    raw <- input[[paste0("field_", col$name)]]
    if (identical(col$type, "character")) {
      out <- if (is.null(raw) || !nzchar(raw)) NA_character_ else raw
    } else if (identical(col$type, "numeric")) {
      out <- if (is.null(raw)) NA_real_ else as.double(raw)
    } else {
      out <- if (is.null(raw)) NA else as.logical(raw)
    }
    out
  })
  names(values) <- vapply(schema$columns, `[[`, character(1), "name")
  tibble::as_tibble(values)
}

#' @noRd
mod_named_set_editor_ui <- function(id) {
  ns <- shiny::NS(id)
  bslib::layout_sidebar(
    sidebar = bslib::sidebar(
      width = 300,
      shiny::selectInput(ns("set_id"), "Named set", choices = NULL),
      shiny::actionButton(ns("new_set"), "New named set...", icon = shiny::icon("plus"),
                          class = "btn-sm"),
      shiny::hr(),
      shiny::actionButton(ns("add_row"), "Add row...", icon = shiny::icon("plus"), class = "btn-sm"),
      shiny::actionButton(ns("edit_row"), "Edit selected row...", icon = shiny::icon("pen"), class = "btn-sm"),
      shiny::actionButton(ns("delete_row"), "Delete selected row", icon = shiny::icon("trash"), class = "btn-sm"),
      shiny::hr(),
      shiny::downloadButton(ns("download_excel"), "Download as Excel", class = "btn-sm"),
      shiny::fileInput(ns("upload"), "Upload Excel or CSV", accept = c(".xlsx", ".xls", ".csv")),
      shiny::hr(),
      shiny::actionButton(ns("save"), "Save this table", icon = shiny::icon("floppy-disk"),
                          class = "btn-primary btn-sm"),
      shiny::uiOutput(ns("dirty_indicator"))
    ),
    shiny::uiOutput(ns("errors")),
    DT::DTOutput(ns("grid"))
  )
}

#' @param evaluation_path A reactive returning the open evaluation's path.
#' @param category One of `names(STBAM_SET_CATEGORIES)`.
#' @return A list of reactives/functions the parent workspace module uses to
#'   aggregate dirty state for whole-evaluation save-all: `is_dirty()`,
#'   `pending_item()` (a `56_save.R`-shaped pending-save item, or `NULL` if
#'   not dirty), `mark_saved()`.
#' @noRd
mod_named_set_editor_server <- function(id, evaluation_path, category) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns
    schema <- STBAM_SET_CATEGORIES[[category]]$schema()

    draft <- shiny::reactiveVal(NULL)
    dirty <- shiny::reactiveVal(FALSE)
    errors <- shiny::reactiveVal(character())
    manifest_tick <- shiny::reactiveVal(0L)

    manifest <- shiny::reactive({
      manifest_tick()
      shiny::req(evaluation_path())
      list_named_sets(evaluation_path(), category)
    })

    shiny::observeEvent(manifest(), {
      choices <- manifest()$set_id
      shiny::updateSelectInput(session, "set_id", choices = choices,
                               selected = if (length(choices) > 0L) choices[[1]] else character())
    })

    shiny::observeEvent(input$set_id, {
      shiny::req(evaluation_path(), input$set_id)
      draft(read_named_set(evaluation_path(), category, input$set_id))
      dirty(FALSE)
      errors(character())
    })

    output$grid <- DT::renderDT({
      shiny::req(draft())
      DT::datatable(draft(), selection = "single", rownames = FALSE,
                    options = list(scrollX = TRUE, pageLength = 10))
    })

    output$errors <- shiny::renderUI({
      e <- errors()
      if (length(e) == 0L) return(NULL)
      shiny::div(class = "alert alert-danger",
                shiny::tags$strong("This table was not saved -- fix the following and try again:"),
                shiny::tags$ul(lapply(e, shiny::tags$li)))
    })

    output$dirty_indicator <- shiny::renderUI({
      if (isTRUE(dirty())) {
        shiny::tags$span(class = "text-warning", shiny::icon("circle-exclamation"), " Unsaved draft")
      } else {
        shiny::tags$span(class = "text-success", shiny::icon("circle-check"), " Saved")
      }
    })

    # --- Add / edit row -----------------------------------------------------
    editing_index <- shiny::reactiveVal(NULL)

    open_row_modal <- function(row = NULL, index = NULL) {
      editing_index(index)
      shiny::showModal(shiny::modalDialog(
        title = if (is.null(index)) "Add row" else "Edit row",
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
      current <- draft() %||% tibble::as_tibble(schema)[0, ]
      idx <- editing_index()
      updated <- if (is.null(idx)) {
        rbind(current, new_row)
      } else {
        current[idx, ] <- new_row
        current
      }
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

    # --- New named set -------------------------------------------------------
    shiny::observeEvent(input$new_set, {
      shiny::showModal(shiny::modalDialog(
        title = "New named set",
        shiny::textInput(ns("new_set_id"), "Set ID (letters, digits, _, - only)"),
        shiny::textInput(ns("new_set_name"), "Set name"),
        shiny::textInput(ns("new_set_description"), "Description"),
        shiny::helpText("Starts as a copy of the currently selected set's rows, if any."),
        footer = shiny::tagList(
          shiny::modalButton("Cancel"),
          shiny::actionButton(ns("create_set"), "Create", class = "btn-primary")
        )
      ))
    })

    shiny::observeEvent(input$create_set, {
      shiny::req(evaluation_path(), nzchar(input$new_set_id))
      starting_data <- draft() %||% tibble::as_tibble(schema)[0, ]
      manifest_row <- tibble::tibble(
        set_id = input$new_set_id, set_name = input$new_set_name %||% input$new_set_id,
        description = input$new_set_description %||% "", source = "", date_or_version = "",
        status = "active", notes = ""
      )
      result <- write_named_set(evaluation_path(), category, input$new_set_id, starting_data, manifest_row)
      if (isTRUE(result$success)) {
        manifest_tick(manifest_tick() + 1L)
        shiny::removeModal()
      } else {
        errors(result$errors)
      }
    })

    # --- Excel round trip ------------------------------------------------------
    output$download_excel <- shiny::downloadHandler(
      filename = function() paste0(category, "-", input$set_id, ".xlsx"),
      content = function(file) export_table_excel(draft() %||% tibble::as_tibble(schema)[0, ], file)
    )

    shiny::observeEvent(input$upload, {
      shiny::req(input$upload$datapath)
      imported <- import_table_file(input$upload$datapath, schema)
      if (isTRUE(imported$valid)) {
        draft(imported$data)
        dirty(TRUE)
        errors(character())
      } else {
        errors(imported$errors)
      }
    })

    # --- Save ------------------------------------------------------------------
    do_save <- function() {
      shiny::req(evaluation_path(), input$set_id, draft())
      row <- manifest()[manifest()$set_id == input$set_id, , drop = FALSE]
      if (nrow(row) == 0L) {
        row <- tibble::tibble(set_id = input$set_id, set_name = input$set_id, description = "",
                              source = "", date_or_version = "", status = "active", notes = "")
      }
      result <- save_named_set(evaluation_path(), category, input$set_id, draft(), row)
      if (isTRUE(result$success)) {
        dirty(FALSE)
        errors(character())
        manifest_tick(manifest_tick() + 1L)
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
        row <- manifest()[manifest()$set_id == input$set_id, , drop = FALSE]
        if (nrow(row) == 0L) {
          row <- tibble::tibble(set_id = input$set_id, set_name = input$set_id, description = "",
                                source = "", date_or_version = "", status = "active", notes = "")
        }
        list(kind = "named_set", category = category, set_id = input$set_id,
            df = draft(), manifest_row = row)
      },
      mark_saved = function() {
        dirty(FALSE)
        manifest_tick(manifest_tick() + 1L)
      }
    )
  })
}
