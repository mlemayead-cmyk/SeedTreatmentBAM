library(testthat)

root <- normalizePath(file.path(dirname(sys.frame(1)$ofile %||% "."), ".."),
                      winslash = "/", mustWork = FALSE)
if (!dir.exists(file.path(root, "R"))) {
  root <- normalizePath(getwd(), winslash = "/")
}
if (!dir.exists(file.path(root, "R")) && dir.exists(file.path(root, "..", "R"))) {
  root <- normalizePath(file.path(root, ".."), winslash = "/")
}

source(file.path(root, "R", "load_model.R"))
load_stbam(root, include = c("core", "reporting"))

test_dir(file.path(root, "tests", "testthat"), stop_on_failure = TRUE)
