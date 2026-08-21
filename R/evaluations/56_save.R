# Phase 1: dirty-state tracking + per-table save and whole-evaluation
# save-all (ADR-007, run_lifecycle_and_validation.md §1).
#
# Two coexisting save granularities, never live/immediate save:
#   - per-table save: validates and writes exactly one table
#     (`save_named_set()` / `save_use_patterns()`, thin wrappers over
#     52_named_sets.R / 53_use_patterns.R's validate-before-replace writers).
#   - whole-evaluation save-all: validates every currently-dirty table
#     first; if *any* fails, *none* are written (`save_all()`).
#
# Dirty-state tracking is implemented as pure functions over a named
# character vector (table_key -> "dirty" | "saved"), not tied to Shiny --
# so it is directly unit-testable (human instruction: "Backend behaviour
# should be independently testable without requiring browser interaction").
# The Shiny layer (R/shiny/) wraps this vector in a `reactiveValues` and
# renders it; it adds no additional state-transition logic of its own.

#' A fresh dirty-state tracker
#'
#' @param table_keys Character vector identifying every editable table in
#'   scope (e.g. `"seeding_sets:default"`, `"use_patterns"`).
#' @return A named character vector, every entry `"saved"` (a freshly loaded
#'   table matches what is on disk).
#' @export
new_dirty_state <- function(table_keys = character()) {
  state <- rep("saved", length(table_keys))
  names(state) <- table_keys
  state
}

#' Mark one table dirty (an in-session edit not yet saved)
#' @export
mark_dirty <- function(state, table_key) {
  if (!table_key %in% names(state)) {
    state[table_key] <- "dirty"
  } else {
    state[[table_key]] <- "dirty"
  }
  state
}

#' Mark one table saved (its in-session content now matches disk)
#' @export
mark_saved <- function(state, table_key) {
  if (table_key %in% names(state)) state[[table_key]] <- "saved"
  state
}

#' Is any tracked table currently dirty?
#' @export
any_dirty <- function(state) {
  length(state) > 0L && any(state == "dirty")
}

#' Which tracked table keys are currently dirty?
#' @export
dirty_tables <- function(state) {
  names(state)[state == "dirty"]
}

#' Save one named set (per-table save)
#'
#' @param evaluation_path Path to an evaluation folder.
#' @param category One of `names(STBAM_SET_CATEGORIES)`.
#' @param set_id The set's identifier.
#' @param df The set's complete data.
#' @param manifest_row A one-row manifest tibble (see `write_named_set()`).
#' @return A list: `success` (logical), `errors` (character vector).
#' @export
save_named_set <- function(evaluation_path, category, set_id, df, manifest_row) {
  write_named_set(evaluation_path, category, set_id, df, manifest_row)
}

#' Save `use_patterns.csv` (per-table save)
#'
#' @inheritParams write_use_patterns
#' @export
save_use_patterns <- function(evaluation_path, df, check_referential_integrity = TRUE) {
  write_use_patterns(evaluation_path, df, check_referential_integrity)
}

#' Validate one pending save item without writing anything
#'
#' @param evaluation_path Path to an evaluation folder.
#' @param item A list describing one pending write: either
#'   `list(kind = "named_set", category = ..., set_id = ..., df = ..., manifest_row = ...)`
#'   or `list(kind = "use_patterns", df = ..., check_referential_integrity = ...)`.
#' @return A list: `valid` (logical), `errors` (character vector).
#' @noRd
stbam_validate_pending_item <- function(evaluation_path, item) {
  if (identical(item$kind, "named_set")) {
    info <- STBAM_SET_CATEGORIES[[item$category]]
    if (is.null(info)) {
      return(list(valid = FALSE, errors = paste0("Unknown named-set category: ", item$category, ".")))
    }
    validate_table(item$df, info$schema())
  } else if (identical(item$kind, "use_patterns")) {
    known_crops <- if (isTRUE(item$check_referential_integrity %||% TRUE)) {
      stbam_known_crops(evaluation_path)
    } else {
      NULL
    }
    validate_use_patterns(item$df, known_crops = known_crops)
  } else {
    list(valid = FALSE, errors = paste0("Unknown pending-save item kind: ", item$kind %||% "<missing>", "."))
  }
}

#' `%||%` -- fallback for NULL/zero-length values
#' @noRd
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x

#' Whole-evaluation save-all: validate every dirty table, write only if all
#' pass (ADR-007's all-or-nothing rule)
#'
#' @param evaluation_path Path to an evaluation folder.
#' @param items A named list of pending-save items (see
#'   `stbam_validate_pending_item()`), one per currently-dirty table. Names
#'   are used only to report which item(s) failed.
#' @return A list: `success` (logical), `errors` (a named list, one element
#'   per item that failed validation; empty list on success), `results` (on
#'   success only: the per-item write results).
#' @export
save_all <- function(evaluation_path, items) {
  if (length(items) == 0L) {
    return(list(success = TRUE, errors = list(), results = list()))
  }
  checks <- lapply(items, function(item) stbam_validate_pending_item(evaluation_path, item))
  failed <- vapply(checks, function(c) !c$valid, logical(1))

  if (any(failed)) {
    errors <- lapply(checks[failed], `[[`, "errors")
    names(errors) <- names(items)[failed]
    return(list(success = FALSE, errors = errors, results = list()))
  }

  results <- lapply(items, function(item) {
    if (identical(item$kind, "named_set")) {
      write_named_set(evaluation_path, item$category, item$set_id, item$df, item$manifest_row)
    } else {
      write_use_patterns(evaluation_path, item$df,
                         check_referential_integrity = item$check_referential_integrity %||% TRUE)
    }
  })
  names(results) <- names(items)

  list(success = TRUE, errors = list(), results = results)
}
