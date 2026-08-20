# Entry point for the Shiny application.
#
# Launch with:
#   Rscript -e "shiny::runApp('app')"
# or from the project root:
#   Rscript scripts/run_app.R

root <- normalizePath(file.path(dirname(getwd()), basename(getwd())),
                      winslash = "/", mustWork = FALSE)
if (!dir.exists(file.path(root, "R"))) {
  root <- normalizePath("..", winslash = "/", mustWork = TRUE)
}

source(file.path(root, "R", "load_model.R"))
load_stbam(root, include = c("core", "reporting", "shiny"))

run_stbam_app(root)
