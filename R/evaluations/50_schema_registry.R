# Phase 1: schema registry for the evaluation/input-schema redesign.
#
# docs/planning/folder_and_input_schema.md, ADR-004 (assessment_workspace_architecture.md).
# Column lists below are re-checked against the live data/reference/*.csv files
# as of this implementation (docs/planning/folder_and_input_schema.md's own
# "Verification note for implementers"), not copied unverified from the
# planning prose.
#
# Numeric range bounds are sourced from R/inputs/11_parameter_set.R's
# STBAM_OVERRIDABLE wherever a column corresponds to an existing overridable
# scientific parameter (folder_and_input_schema.md §4: "exact bounds sourced
# from existing scientific validation ... not reinvented here"). Columns
# with no existing-validation counterpart are left unconstrained
# (min = -Inf, max = Inf) rather than inventing a new bound.
#
# This file defines *structure only* -- no validation logic (51_validation.R)
# and no I/O (52_named_sets.R, 53_use_patterns.R).

#' One column's schema rule
#' @noRd
stbam_col <- function(name, type = c("character", "numeric", "logical"),
                      required = TRUE, min = -Inf, max = Inf,
                      choices = NULL, key = FALSE) {
  type <- match.arg(type)
  list(name = name, type = type, required = required, min = min, max = max,
       choices = choices, key = key)
}

#' Manifest schema shared by every named-set category
#' (folder_and_input_schema.md §2.1)
#' @noRd
stbam_manifest_schema <- function() {
  list(
    columns = list(
      stbam_col("set_id", "character", required = TRUE, key = TRUE),
      stbam_col("set_name", "character", required = TRUE),
      stbam_col("description", "character", required = FALSE),
      stbam_col("source", "character", required = FALSE),
      stbam_col("date_or_version", "character", required = FALSE),
      stbam_col("status", "character", required = FALSE),
      stbam_col("notes", "character", required = FALSE)
    )
  )
}

#' Schema for `agronomy/seeding_sets/<set_id>.csv`
#'
#' Generalizes `data/reference/crop_seeding_parameters.csv` (verified live:
#' 19 columns, 85 rows, header re-checked this session). Planting-method
#' *availability* booleans stay here (they describe the crop, not the
#' method); the planting-method *surface-seed fraction* constants are their
#' own category (`stbam_schema_planting_method_sets()`) -- see the Phase 1
#' implementation note on why this is not collapsed into one file.
#' @export
stbam_schema_seeding_sets <- function() {
  list(
    columns = list(
      stbam_col("crop", "character", required = TRUE, key = TRUE),
      stbam_col("tkw_low_g_per_1000", "numeric", required = TRUE, min = 1e-6),
      stbam_col("tkw_high_g_per_1000", "numeric", required = TRUE, min = 1e-6),
      stbam_col("seeding_rate_low_seeds_per_ha_direct", "numeric", required = FALSE, min = 0),
      stbam_col("seeding_rate_high_seeds_per_ha_direct", "numeric", required = FALSE, min = 0),
      stbam_col("seeding_rate_low_kg_per_ha_low_tkw", "numeric", required = TRUE, min = 0),
      stbam_col("seeding_rate_low_kg_per_ha_high_tkw", "numeric", required = TRUE, min = 0),
      stbam_col("seeding_rate_high_kg_per_ha_low_tkw", "numeric", required = TRUE, min = 0),
      stbam_col("seeding_rate_high_kg_per_ha_high_tkw", "numeric", required = TRUE, min = 0),
      stbam_col("seeds_per_ha_low", "numeric", required = TRUE, min = 0),
      stbam_col("seeds_per_ha_high", "numeric", required = TRUE, min = 0),
      stbam_col("seeds_per_ha_low_basis", "character", required = TRUE),
      stbam_col("seeds_per_ha_high_basis", "character", required = TRUE),
      stbam_col("spring_seeded", "logical", required = TRUE),
      stbam_col("fall_seeded", "logical", required = TRUE),
      stbam_col("broadcast_seeded", "logical", required = TRUE),
      stbam_col("drill_seeded", "logical", required = TRUE),
      stbam_col("precision_planted", "logical", required = TRUE),
      stbam_col("source", "character", required = TRUE),
      stbam_col("status", "character", required = TRUE)
    ),
    reference_file = "crop_seeding_parameters.csv"
  )
}

#' Schema for `agronomy/planting_method_sets/<set_id>.csv`
#'
#' Generalizes `data/reference/planting_method_parameters.csv` (verified
#' live: 5 columns, 4 rows -- one row per `STBAM_PLANTING_METHODS` value).
#' `source` is intentionally not `required`: the live file's `broadcast` row
#' carries a literal `NA` in this column (verified by reading the raw CSV;
#' `surface_seed_fraction = 1.0` for broadcast is presumably definitional
#' rather than citation-derived), so requiring it would reject this
#' project's own authoritative reference data on the very first evaluation
#' creation -- not a case calling for an invented default value.
#' @export
stbam_schema_planting_method_sets <- function() {
  list(
    columns = list(
      stbam_col("planting_method_label", "character", required = TRUE),
      stbam_col("planting_method", "character", required = TRUE, key = TRUE,
                choices = STBAM_PLANTING_METHODS),
      stbam_col("surface_seed_fraction", "numeric", required = TRUE, min = 0, max = 1),
      stbam_col("source", "character", required = FALSE),
      stbam_col("status", "character", required = TRUE)
    ),
    reference_file = "planting_method_parameters.csv"
  )
}

#' Schema for `receptors/receptor_sets/<set_id>.csv`
#'
#' Generalizes `data/reference/receptor_parameters.csv` (verified live: 13
#' columns, 6 rows). Body weight, food intake, MSA and taxon identity travel
#' together in one row, per ADR-004's explicit correction that a receptor
#' set is a complete definition, not a partial parameter list.
#' @export
stbam_schema_receptor_sets <- function() {
  list(
    columns = list(
      stbam_col("receptor_id", "character", required = TRUE, key = TRUE),
      stbam_col("taxon", "character", required = TRUE),
      stbam_col("size_class", "character", required = TRUE),
      stbam_col("body_weight_g", "numeric", required = TRUE, min = 1e-6),
      stbam_col("fir_regression_name", "character", required = TRUE),
      stbam_col("fir_coefficient_a", "numeric", required = TRUE, min = 0),
      stbam_col("fir_exponent_b", "numeric", required = TRUE, min = 0),
      stbam_col("food_intake_g_dw_per_day", "numeric", required = TRUE, min = 0),
      stbam_col("msa_short_term_m2", "numeric", required = TRUE, min = 1e-6),
      stbam_col("msa_long_term_m2", "numeric", required = TRUE, min = 1e-6),
      stbam_col("surface_seed_only", "logical", required = TRUE),
      stbam_col("source", "character", required = TRUE),
      stbam_col("status", "character", required = TRUE)
    ),
    reference_file = "receptor_parameters.csv"
  )
}

#' Schema for `effects/effects_sets/<set_id>.csv`
#'
#' Generalizes `data/reference/effects_metrics.csv` (verified live: 12
#' columns, 16 rows).
#' @export
stbam_schema_effects_sets <- function() {
  list(
    columns = list(
      stbam_col("metric_id", "character", required = TRUE, key = TRUE),
      stbam_col("active_ingredient", "character", required = TRUE),
      stbam_col("taxon", "character", required = TRUE),
      stbam_col("duration_class", "character", required = TRUE),
      stbam_col("metric_role", "character", required = TRUE),
      stbam_col("endpoint_description", "character", required = TRUE),
      stbam_col("endpoint_value", "numeric", required = TRUE, min = 0),
      stbam_col("uncertainty_factor", "numeric", required = TRUE, min = 0),
      stbam_col("effects_metric", "numeric", required = TRUE, min = 1e-12),
      stbam_col("unit", "character", required = TRUE),
      stbam_col("source", "character", required = TRUE),
      stbam_col("status", "character", required = TRUE)
    ),
    reference_file = "effects_metrics.csv"
  )
}

#' Schema for `fate/fate_sets/<set_id>.csv`
#'
#' Generalizes `data/reference/dissipation_parameters.csv` (verified live: 6
#' columns, 2 rows -- the two DT50 defaults).
#' @export
stbam_schema_fate_sets <- function() {
  list(
    columns = list(
      stbam_col("parameter", "character", required = TRUE, key = TRUE),
      stbam_col("value", "numeric", required = TRUE, min = 1e-6),
      stbam_col("unit", "character", required = TRUE),
      stbam_col("description", "character", required = TRUE),
      stbam_col("source", "character", required = TRUE),
      stbam_col("status", "character", required = TRUE)
    ),
    reference_file = "dissipation_parameters.csv"
  )
}

#' Schema for `reporting/reporting_sets/<scheme_name>.csv`
#'
#' Per `folder_and_input_schema.md` §2.2 (ADR-010): crop-only grouping
#' scheme, partial coverage and singleton groups explicitly permitted
#' (`group_label` is not required). No `reference_file` -- unlike the other
#' four categories, there is no existing single-set default to copy at
#' evaluation creation (the only existing crop-grouping data,
#' `STBAM_WORKBOOK_TO_CROP_FAMILY`, is a hard-coded R constant slated for
#' extraction in Phase 2 ticket 4, not this phase -- ADR-016 point 4,
#' `implementation_phases_proposal.md` Phase 2). A new Phase 1 evaluation's
#' `reporting_sets/` therefore starts with an empty manifest.
#' @export
stbam_schema_reporting_sets <- function() {
  list(
    columns = list(
      stbam_col("crop", "character", required = TRUE, key = TRUE),
      stbam_col("group_label", "character", required = FALSE),
      stbam_col("display_order", "numeric", required = FALSE)
    ),
    reference_file = NULL
  )
}

#' Registry of every named-set category (ADR-004)
#'
#' Each entry's `path` is relative to `inputs/assumptions/` inside an
#' evaluation folder, e.g. `agronomy/seeding_sets`.
#' @export
STBAM_SET_CATEGORIES <- list(
  seeding_sets = list(path = "agronomy/seeding_sets",
                      schema = stbam_schema_seeding_sets),
  planting_method_sets = list(path = "agronomy/planting_method_sets",
                              schema = stbam_schema_planting_method_sets),
  receptor_sets = list(path = "receptors/receptor_sets",
                       schema = stbam_schema_receptor_sets),
  effects_sets = list(path = "effects/effects_sets",
                      schema = stbam_schema_effects_sets),
  fate_sets = list(path = "fate/fate_sets",
                   schema = stbam_schema_fate_sets),
  reporting_sets = list(path = "reporting/reporting_sets",
                        schema = stbam_schema_reporting_sets)
)

#' Schema for `uses/use_patterns.csv` (ADR-005)
#'
#' Single normalized table, one row per atomic use condition. A crop/rate
#' use permitted under several planting methods becomes multiple rows
#' sharing one `use_id` (ADR-005) -- `use_id` is therefore not itself a
#' unique key; the unique key is (`use_id`, `planting_method`).
#' @export
stbam_schema_use_patterns <- function() {
  list(
    columns = list(
      stbam_col("use_id", "character", required = TRUE),
      stbam_col("crop", "character", required = TRUE),
      stbam_col("rate_value", "numeric", required = TRUE, min = 0),
      stbam_col("rate_unit", "character", required = TRUE, choices = STBAM_RATE_UNITS),
      stbam_col("rate_level", "character", required = TRUE),
      stbam_col("planting_method", "character", required = TRUE,
                choices = STBAM_PLANTING_METHODS),
      stbam_col("workbook", "character", required = TRUE),
      stbam_col("product_identifier", "character", required = FALSE),
      stbam_col("region", "character", required = FALSE),
      stbam_col("target_pest", "character", required = FALSE),
      stbam_col("notes", "character", required = FALSE)
    ),
    unique_key = c("use_id", "planting_method")
  )
}

#' The read-only provenance files copied wholesale into every evaluation's
#' `inputs/reference/` (folder_and_input_schema.md §1.1, ADR-018 tiers 2-3).
#'
#' Tier-1 originals (the `.xlsm`/`.docx` source documents) are never copied
#' here -- they are referenced by path+hash only, and that referencing
#' mechanism is Phase 2 migration-provenance work
#' (`migration_plan.md` §0.1/§2.1), not this list.
#' @export
STBAM_REFERENCE_PROVENANCE_FILES <- c(
  "source_manifest.csv",
  "review_core_assumptions.csv",
  "review_effects_metrics.csv",
  "table162_considerations.csv",
  "table162_decision_matrix.csv",
  "copied_register_manifest.csv"
)
