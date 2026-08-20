#!/usr/bin/env Rscript
# Launch the dashboard.
#
#   Rscript scripts/run_app.R [port]

args <- commandArgs(trailingOnly = TRUE)
port <- if (length(args) >= 1L) as.integer(args[[1]]) else 8080L

root <- normalizePath(file.path(dirname(sys.frame(1)$ofile %||% "."), ".."),
                      winslash = "/", mustWork = FALSE)
if (!dir.exists(file.path(root, "R"))) root <- normalizePath(getwd())

source(file.path(root, "R", "load_model.R"))
load_stbam(root, include = c("core", "reporting", "shiny"))

cat(sprintf("Starting the seed-treatment risk model on http://127.0.0.1:%d\n",
            port))
shiny::runApp(run_stbam_app(root), port = port, host = "127.0.0.1",
              launch.browser = FALSE)
