# Phase 1: Excel export/import with validate-before-replace (ADR-006).
#
# docs/planning/folder_and_input_schema.md §4, assessment_workspace_architecture.md
# ADR-006. CSV remains the authoritative on-disk format; Excel is a bulk
# edit/exchange round-trip on top of it. `readxl` was confirmed already
# installed during the architecture phase (ADR-006's investigation) but was
# not yet a declared dependency -- added to scripts/check_environment.R as
# part of this phase (see that script's diff).

#' Export a table to an XLSX file for external bulk editing
#'
#' @param df The table to export.
#' @param path Destination `.xlsx` path.
#' @return `path`, invisibly.
#' @export
export_table_excel <- function(df, path) {
  if (!requireNamespace("writexl", quietly = TRUE)) {
    stbam_abort("The `writexl` package is required for Excel export.")
  }
  writexl::write_xlsx(df, path)
  invisible(path)
}

#' Import a table from an uploaded Excel or CSV file, with schema validation
#'
#' **Never returns data that has silently replaced anything** -- this
#' function only reads and validates; it does not write anywhere. The
#' caller (e.g. `write_named_set()` / `write_use_patterns()`) is the single
#' place a file on disk is actually replaced, and only after this same
#' validation passes again on the exact data returned here
#' (folder_and_input_schema.md §4: "a failed validation ... never replaces
#' the previously saved, valid file").
#'
#' @param path Path to an uploaded `.xlsx`, `.xls`, or `.csv` file.
#' @param schema A schema object from `50_schema_registry.R`.
#' @param key_columns Optional key-column override, passed to
#'   `validate_table()`.
#' @return A list: `valid` (logical), `errors` (character vector), `data`
#'   (the parsed tibble, coerced to the schema's declared column types where
#'   possible -- present even when `valid` is `FALSE`, so a caller can show
#'   the offending data alongside the error list, but must never be written
#'   to disk when `valid` is `FALSE`).
#' @export
import_table_file <- function(path, schema, key_columns = NULL) {
  if (!file.exists(path)) {
    return(list(valid = FALSE, errors = paste0("File not found: ", path, "."), data = NULL))
  }
  ext <- tolower(tools::file_ext(path))

  parsed <- tryCatch({
    if (ext %in% c("xlsx", "xls")) {
      if (!requireNamespace("readxl", quietly = TRUE)) {
        stbam_abort("The `readxl` package is required for Excel import.")
      }
      readxl::read_excel(path, col_types = "text")
    } else if (identical(ext, "csv")) {
      readr::read_csv(path, col_types = readr::cols(.default = readr::col_character()),
                      progress = FALSE)
    } else {
      stbam_abort("Unsupported file type for import: `.", ext, "`. Use .xlsx, .xls, or .csv.")
    }
  }, error = function(e) e)

  if (inherits(parsed, "error")) {
    return(list(valid = FALSE,
               errors = paste0("Could not read `", path, "`: ", conditionMessage(parsed)),
               data = NULL))
  }
  parsed <- tibble::as_tibble(parsed)

  coerced <- stbam_coerce_to_schema(parsed, schema)
  check <- validate_table(coerced$data, schema, key_columns = key_columns)
  all_errors <- c(coerced$errors, check$errors)

  list(valid = length(all_errors) == 0L, errors = all_errors, data = coerced$data)
}

#' Coerce every text column read from an upload into its schema-declared type
#'
#' Imports are always read as text first (both `readxl` and the CSV path
#' above use `col_types = "text"` / `col_character()` deliberately), then
#' coerced here under an explicit, reported rule -- rather than letting
#' `readxl`/`readr` guess types silently, which is exactly the same
#' incidental-formatting risk `stbam_col_types()` (`52_named_sets.R`) avoids
#' for the authoritative CSV read path. A value that fails to coerce (e.g.
#' `"abc"` in a numeric column) is left as `NA` and reported as a coercion
#' error, never silently dropped or silently zero-filled.
#'
#' @param df A tibble of character columns (an upload, already read as text).
#' @param schema A schema object from `50_schema_registry.R`.
#' @return A list: `data` (the coerced tibble), `errors` (character vector
#'   describing any value that failed to coerce).
#' @noRd
stbam_coerce_to_schema <- function(df, schema) {
  errors <- character()
  for (col in schema$columns) {
    if (!col$name %in% names(df)) next
    x <- df[[col$name]]
    if (!is.character(x)) next
    x_trim <- trimws(x)
    x_trim[!nzchar(x_trim)] <- NA_character_

    if (identical(col$type, "numeric")) {
      coerced <- suppressWarnings(as.numeric(x_trim))
      bad <- !is.na(x_trim) & is.na(coerced)
      if (any(bad)) {
        errors <- c(errors, sprintf(
          "Column `%s` has %d value(s) that are not valid numbers: %s.",
          col$name, sum(bad), paste(unique(x_trim[bad]), collapse = ", ")))
      }
      df[[col$name]] <- coerced
    } else if (identical(col$type, "logical")) {
      coerced <- rep(NA, length(x_trim))
      truthy <- toupper(x_trim) %in% c("TRUE", "T", "1", "YES")
      falsy <- toupper(x_trim) %in% c("FALSE", "F", "0", "NO")
      coerced[truthy] <- TRUE
      coerced[falsy] <- FALSE
      bad <- !is.na(x_trim) & !truthy & !falsy
      if (any(bad)) {
        errors <- c(errors, sprintf(
          "Column `%s` has %d value(s) that are not valid TRUE/FALSE: %s.",
          col$name, sum(bad), paste(unique(x_trim[bad]), collapse = ", ")))
      }
      df[[col$name]] <- coerced
    } else {
      df[[col$name]] <- x_trim
    }
  }
  list(data = df, errors = errors)
}
