# Entry point for the Phase 1 evaluation-based Shiny application.
#
# This is a SEPARATE app from app/app.R (the legacy, override-based
# application), which remains untouched (ADR-020). Launch with:
#   Rscript -e "shiny::runApp('app_evaluations')"
# or from the project root:
#   Rscript scripts/run_evaluations_app.R

root <- normalizePath(file.path(dirname(getwd()), basename(getwd())),
                      winslash = "/", mustWork = FALSE)
if (!dir.exists(file.path(root, "R"))) {
  root <- normalizePath("..", winslash = "/", mustWork = TRUE)
}

source(file.path(root, "R", "load_model.R"))
load_stbam(root, include = c("core", "reporting", "shiny"))

run_stbam_evaluations_app(root)
