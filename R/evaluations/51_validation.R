# Phase 1: generic schema-driven validation engine.
#
# docs/planning/folder_and_input_schema.md §4 (ADR-006). One validation
# function per table, invoked identically from the Shiny form/grid path and
# the Excel/CSV import path (run_lifecycle_and_validation.md §1's stated
# implementation shape) -- so rules cannot drift between entry paths.
#
# Batch validation: every check below collects into one `errors` character
# vector rather than stopping at the first failure (human instruction: "collect
# useful errors rather than fail on only the first trivial issue"). Callers
# decide what to do with a failed result -- this file never writes to disk.

#' Validate a data.frame against a column schema
#'
#' Checks, in order (all applied, all failures collected): column presence
#' (every schema column must exist; no unrecognized column is silently
#' accepted -- an unexpected column is exactly the kind of undetected
#' data-entry mistake batch validation exists to catch), per-column type,
#' required-value (non-missing) rules, permitted-value sets, numeric range
#' sanity (bounds sourced from `STBAM_OVERRIDABLE` where a column
#' corresponds to an existing overridable parameter -- see
#' `50_schema_registry.R`), and key-column uniqueness.
#'
#' Referential integrity (a value in one table must resolve in another) is
#' deliberately not handled here -- it needs more than one table and is
#' implemented per-relationship (see `validate_use_patterns()` below).
#'
#' @param df A data.frame/tibble.
#' @param schema A schema object from `50_schema_registry.R` (a list with a
#'   `columns` element).
#' @param key_columns Optional character vector of column names whose
#'   combination must be unique. Defaults to whichever column(s) the schema
#'   itself marks `key = TRUE`.
#' @return A list with `valid` (logical) and `errors` (character vector,
#'   possibly empty).
#' @export
validate_table <- function(df, schema, key_columns = NULL) {
  if (!is.data.frame(df)) {
    return(list(valid = FALSE, errors = "Input is not a data.frame/tibble."))
  }
  errors <- character()

  schema_names <- vapply(schema$columns, `[[`, character(1), "name")
  missing_cols <- setdiff(schema_names, names(df))
  if (length(missing_cols) > 0L) {
    errors <- c(errors, sprintf("Missing required column(s): %s.",
                                paste(missing_cols, collapse = ", ")))
  }
  unexpected_cols <- setdiff(names(df), schema_names)
  if (length(unexpected_cols) > 0L) {
    errors <- c(errors, sprintf("Unexpected column(s) not in schema: %s.",
                                paste(unexpected_cols, collapse = ", ")))
  }

  for (col in schema$columns) {
    if (!col$name %in% names(df)) next
    x <- df[[col$name]]

    ok_type <- switch(col$type,
      character = is.character(x) || is.factor(x),
      numeric = is.numeric(x),
      logical = is.logical(x)
    )
    if (!ok_type) {
      errors <- c(errors, sprintf("Column `%s` must be %s; found %s.",
                                  col$name, col$type, class(x)[1]))
      next
    }

    is_na <- is.na(x)
    if (isTRUE(col$required) && any(is_na)) {
      errors <- c(errors, sprintf(
        "Column `%s` has %d missing value(s) but is a required column.",
        col$name, sum(is_na)))
    }

    if (!is.null(col$choices)) {
      observed <- unique(as.character(x[!is_na]))
      bad <- setdiff(observed, col$choices)
      if (length(bad) > 0L) {
        errors <- c(errors, sprintf(
          "Column `%s` has value(s) outside the permitted set (%s): %s.",
          col$name, paste(col$choices, collapse = ", "), paste(bad, collapse = ", ")))
      }
    }

    if (identical(col$type, "numeric") &&
        (is.finite(col$min) || is.finite(col$max))) {
      finite_vals <- x[!is_na & is.finite(x)]
      if (is.finite(col$min) && length(finite_vals) > 0L && any(finite_vals < col$min)) {
        errors <- c(errors, sprintf(
          "Column `%s` has value(s) below the permitted minimum (%s).",
          col$name, col$min))
      }
      if (is.finite(col$max) && length(finite_vals) > 0L && any(finite_vals > col$max)) {
        errors <- c(errors, sprintf(
          "Column `%s` has value(s) above the permitted maximum (%s).",
          col$name, col$max))
      }
    }
  }

  if (is.null(key_columns)) {
    key_columns <- vapply(schema$columns, function(c) {
      if (isTRUE(c$key)) c$name else NA_character_
    }, character(1))
    key_columns <- key_columns[!is.na(key_columns)]
  }
  if (length(key_columns) > 0L && all(key_columns %in% names(df)) && nrow(df) > 0L) {
    key_vals <- do.call(paste, c(as.list(df[key_columns]), sep = "\x1f"))
    dup <- duplicated(key_vals)
    if (any(dup)) {
      errors <- c(errors, sprintf(
        "Duplicate value(s) in key column(s) %s: %s.",
        paste(key_columns, collapse = "+"),
        paste(unique(key_vals[dup]), collapse = ", ")))
    }
  }

  list(valid = length(errors) == 0L, errors = errors)
}

#' Validate a category `_manifest.csv` (folder_and_input_schema.md §2.1)
#' @export
validate_manifest <- function(df) {
  validate_table(df, stbam_manifest_schema())
}

#' Validate `use_patterns.csv`, with optional referential integrity
#'
#' @param df The use_patterns table.
#' @param known_crops Optional character vector of crop names known to
#'   exist in the evaluation's seeding sets (folder_and_input_schema.md §4:
#'   "every `use_patterns.csv` `crop` value must exist in the
#'   currently-selected `seeding_sets` set"). If `NULL`, referential
#'   integrity is not checked (used when validating a table in isolation,
#'   e.g. from an Excel upload with no evaluation context yet).
#' @export
validate_use_patterns <- function(df, known_crops = NULL) {
  schema <- stbam_schema_use_patterns()
  result <- validate_table(df, schema, key_columns = schema$unique_key)
  if (!is.null(known_crops) && "crop" %in% names(df)) {
    used <- unique(df$crop[!is.na(df$crop)])
    unknown <- setdiff(used, known_crops)
    if (length(unknown) > 0L) {
      result$errors <- c(result$errors, sprintf(
        "use_patterns.csv references crop(s) not present in any seeding set: %s.",
        paste(unknown, collapse = ", ")))
      result$valid <- FALSE
    }
  }
  result
}

#' Validate a `reporting_sets/<scheme>.csv` scheme, with optional referential
#' integrity
#'
#' I7 ("a crop-grouping scheme groups crops only") is enforced structurally
#' by `stbam_schema_reporting_sets()`'s fixed column list -- an attempt to
#' add a non-crop grouping dimension (e.g. a `planting_method` column) is
#' rejected by `validate_table()`'s "unexpected column" check, not by a
#' special-cased rule here.
#'
#' @param df The reporting-scheme table.
#' @param known_crops Optional character vector of crop names known to
#'   exist in the evaluation's seeding sets.
#' @export
validate_reporting_set <- function(df, known_crops = NULL) {
  schema <- stbam_schema_reporting_sets()
  result <- validate_table(df, schema)
  if (!is.null(known_crops) && "crop" %in% names(df)) {
    used <- unique(df$crop[!is.na(df$crop)])
    unknown <- setdiff(used, known_crops)
    if (length(unknown) > 0L) {
      result$errors <- c(result$errors, sprintf(
        "Reporting scheme references crop(s) not present in any seeding set: %s.",
        paste(unknown, collapse = ", ")))
      result$valid <- FALSE
    }
  }
  result
}
