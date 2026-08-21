#!/usr/bin/env Rscript
# Verify that the R environment can run the model, and record the versions.
#
#   Rscript scripts/check_environment.R          # verify against the lock file
#   Rscript scripts/check_environment.R --write  # regenerate the lock file
#
# `renv` is the preferred dependency manager, but it is not installable in this
# environment because there is no CRAN access. This script provides the
# equivalent guarantee: it pins the exact package versions the model was
# validated against and fails if the current environment differs.

args <- commandArgs(trailingOnly = TRUE)
write_lock <- "--write" %in% args

root <- getwd()
lock_path <- file.path(root, "dependencies.lock.json")

REQUIRED <- c(
  # Calculation engine
  "readr", "dplyr", "tibble", "tidyr", "rlang", "vctrs",
  # Reporting
  "ggplot2", "scales", "officer", "flextable", "writexl", "svglite",
  "rmarkdown", "knitr", "digest",
  # Interface
  "shiny", "bslib", "DT", "htmltools",
  # Evaluation input editing (Phase 1: Excel round-trip, ADR-006)
  "readxl",
  # Testing
  "testthat", "withr"
)

OPTIONAL <- c(
  renv = "Preferred dependency manager. Not installable without CRAN access; this script is the substitute.",
  plotly = "Interactive plots. The dashboard uses static ggplot2 output instead, which keeps the dependency footprint small.",
  openxlsx = "Alternative XLSX writer. writexl is used instead.",
  quarto = "Alternative reporting engine. rmarkdown is used instead.",
  shinytest2 = "Browser-level Shiny tests. Reactive logic is covered by shiny::testServer."
)

installed <- rownames(utils::installed.packages())
missing <- REQUIRED[!REQUIRED %in% installed]

cat("R version:", R.version.string, "\n")
cat("Platform: ", R.version$platform, "\n\n")

if (length(missing) > 0L) {
  cat("MISSING REQUIRED PACKAGES:\n")
  for (package in missing) cat("  -", package, "\n")
  cat("\nInstall them, then re-run this script.\n")
  quit(status = 1L)
}

versions <- vapply(REQUIRED, function(package) {
  as.character(utils::packageVersion(package))
}, character(1))

if (write_lock) {
  lock <- list(
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    r_version = paste(R.version$major, R.version$minor, sep = "."),
    platform = R.version$platform,
    specification_version = "1.0.0",
    note = paste(
      "Equivalent to an renv lock file. renv itself is not installable in this",
      "environment because CRAN is unreachable. Verify with",
      "'Rscript scripts/check_environment.R'."
    ),
    packages = as.list(versions),
    optional_not_installed = as.list(OPTIONAL)
  )
  writeLines(jsonlite::toJSON(lock, auto_unbox = TRUE, pretty = TRUE),
             lock_path)
  cat("Wrote", lock_path, "\n")
  quit(status = 0L)
}

if (!file.exists(lock_path)) {
  cat("No lock file found. Create one with:\n")
  cat("  Rscript scripts/check_environment.R --write\n")
  quit(status = 1L)
}

lock <- jsonlite::fromJSON(lock_path)
locked <- unlist(lock$packages)

cat("Package versions (locked -> current):\n")
mismatches <- character()
for (package in REQUIRED) {
  current <- versions[[package]]
  expected <- locked[[package]]
  status <- if (is.null(expected)) {
    "not in lock file"
  } else if (identical(current, expected)) {
    "ok"
  } else {
    mismatches <- c(mismatches, package)
    "DIFFERS"
  }
  cat(sprintf("  %-12s %-10s -> %-10s %s\n", package,
              expected %||% "-", current, status))
}

cat("\nOptional packages not required by the model:\n")
for (package in names(OPTIONAL)) {
  state <- if (package %in% installed) "installed" else "not installed"
  cat(sprintf("  %-12s %-14s %s\n", package, state, OPTIONAL[[package]]))
}

if (length(mismatches) > 0L) {
  cat("\nWARNING: ", length(mismatches), " package version(s) differ from the ",
      "validated environment: ", paste(mismatches, collapse = ", "), "\n",
      "Re-run the test suite before relying on results.\n", sep = "")
  quit(status = 2L)
}

cat("\nEnvironment matches the validated lock file.\n")

`%||%` <- function(x, y) if (is.null(x)) y else x
