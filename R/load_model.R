# Load the calculation engine.
#
# The project is a source tree rather than an installed package so that it runs
# in a restricted environment with no package-build toolchain. Sourcing order
# matters: validation helpers first, then calculations, inputs, summaries and
# finally the reporting and interface layers.

#' Load the model into an environment
#'
#' @param root Project root directory. Defaults to the working directory, or
#'   the `stbam.project_root` option if set.
#' @param include Which layers to load. The calculation engine alone is enough
#'   for scripted use and tests.
#' @return The project root, invisibly.
#' @export
load_stbam <- function(root = getOption("stbam.project_root", getwd()),
                       include = c("core", "reporting", "shiny")) {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  options(stbam.project_root = root)
  options(stbam.source_dir = file.path(root, "R"))

  required <- c("readr", "dplyr", "tibble", "tidyr", "rlang", "digest")
  missing <- required[!vapply(required, requireNamespace, logical(1),
                              quietly = TRUE)]
  if (length(missing) > 0L) {
    stop("Required packages are not installed: ", paste(missing, collapse = ", "),
         "\nRun: Rscript scripts/check_environment.R", call. = FALSE)
  }

  layers <- list(
    core = c("R/calculations", "R/inputs", "R/summaries", "R/validation",
             "R/utils", "R/evaluations", "R/migration"),
    reporting = "R/reporting",
    shiny = "R/shiny"
  )

  for (layer in include) {
    for (dir in layers[[layer]]) {
      path <- file.path(root, dir)
      if (!dir.exists(path)) next
      files <- sort(list.files(path, pattern = "[.][Rr]$", full.names = TRUE))
      for (file in files) {
        source(file, local = globalenv(), echo = FALSE)
      }
    }
  }

  invisible(root)
}
