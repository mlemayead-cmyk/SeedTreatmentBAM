# CSV and XLSX export of canonical results.

#' Export canonical datasets to CSV
#'
#' @param datasets A named list of data frames.
#' @param dir Destination directory.
#' @param prefix Optional file-name prefix.
#' @return The paths written, invisibly.
#' @export
export_csv <- function(datasets, dir = "outputs", prefix = "") {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  paths <- character()
  for (name in names(datasets)) {
    path <- file.path(dir, paste0(prefix, name, ".csv"))
    readr::write_csv(datasets[[name]], path, na = "")
    paths <- c(paths, path)
  }
  invisible(paths)
}

#' Export canonical datasets to a single workbook
#'
#' Sheet names are truncated to Excel's 31-character limit.
#'
#' @param datasets A named list of data frames.
#' @param path Destination .xlsx path.
#' @return `path`, invisibly.
#' @export
export_xlsx <- function(datasets, path) {
  if (!requireNamespace("writexl", quietly = TRUE)) {
    stbam_abort("The 'writexl' package is required for XLSX export.")
  }
  names(datasets) <- substr(names(datasets), 1, 31)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writexl::write_xlsx(datasets, path)
  invisible(path)
}

#' Assemble the standard export bundle
#'
#' @param params An `stbam_parameter_set`.
#' @param scenario_inputs Output of [build_scenario_inputs].
#' @param scenario_summary Output of [build_scenario_summary].
#' @param daily_timecourse Optional output of [build_daily_timecourse].
#' @param table162 Optional output of [build_table162_support].
#' @return A named list of data frames.
#' @export
export_bundle <- function(params, scenario_inputs, scenario_summary,
                          daily_timecourse = NULL, table162 = NULL) {
  bundle <- list(
    scenario_inputs = scenario_inputs,
    scenario_summary = scenario_summary,
    parameter_overrides = params$overrides,
    source_manifest = params$baseline$source_manifest
  )
  if (!is.null(daily_timecourse)) {
    bundle$daily_timecourse <- daily_timecourse
  }
  if (!is.null(table162)) {
    bundle$table162_support <- table162
  }
  for (table_id in names(STBAM_TABLES)) {
    bundle[[paste0("table_", table_id)]] <-
      build_official_table(table_id, scenario_summary)
  }
  bundle
}
