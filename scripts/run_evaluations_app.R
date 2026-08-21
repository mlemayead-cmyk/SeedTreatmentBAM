#!/usr/bin/env Rscript
# Launch the Phase 1 evaluation-based dashboard (separate from the legacy
# app -- see scripts/run_app.R for that one).
#
#   Rscript scripts/run_evaluations_app.R [port]

args <- commandArgs(trailingOnly = TRUE)
port <- if (length(args) >= 1L) as.integer(args[[1]]) else 8081L

root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
if (!dir.exists(file.path(root, "R"))) {
  stbam_abort_root <- function() {
    stop("Run this script from the project root (the directory containing R/).",
        call. = FALSE)
  }
  stbam_abort_root()
}

source(file.path(root, "R", "load_model.R"))
load_stbam(root, include = c("core", "reporting", "shiny"))

cat(sprintf("Starting the stbam evaluations app on http://127.0.0.1:%d\n", port))
shiny::runApp(run_stbam_evaluations_app(root), port = port, host = "127.0.0.1",
              launch.browser = FALSE)
