#!/usr/bin/env Rscript
# Phase 2: one-time migration of the current project into a complete
# evaluation (ADR-015, docs/planning/migration_plan.md).
#
#   Rscript scripts/migrate_to_evaluation.R [name]
#
# Re-runnable: running again with a different `name` reproduces an
# identical inputs/ tree (migration_plan.md §4 point 9); running again with
# the SAME `name` fails cleanly via create_evaluation()'s own
# already-exists guard rather than overwriting anything.

args <- commandArgs(trailingOnly = TRUE)
name <- if (length(args) >= 1L) args[[1]] else "thiamethoxam_bam_2026"

root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
if (!dir.exists(file.path(root, "R"))) {
  stop("Run this script from the project root (the directory containing R/).",
       call. = FALSE)
}

source(file.path(root, "R", "load_model.R"))
load_stbam(root, include = c("core", "reporting"))

evaluations_root <- file.path(root, "evaluations")
cat(sprintf("Migrating the current project into evaluations/%s ...\n", name))
path <- migrate_to_evaluation(evaluations_root, name)
cat(sprintf("Migration complete: %s\n", path))
