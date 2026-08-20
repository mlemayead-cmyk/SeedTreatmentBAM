# Canonical dataset 1: scenario_inputs.
#
# One row per crop x application rate x planting method x seeding-rate bound x
# seed-mass bound. Specification sections 4 and 11.1.

#' Which planting methods are agronomically available for a crop
#' @noRd
available_planting_methods <- function(crop_row) {
  methods <- character()
  if (isTRUE(crop_row$broadcast_seeded)) methods <- c(methods, "broadcast")
  if (isTRUE(crop_row$drill_seeded) && isTRUE(crop_row$spring_seeded)) {
    methods <- c(methods, "drill_spring")
  }
  if (isTRUE(crop_row$drill_seeded) && isTRUE(crop_row$fall_seeded)) {
    methods <- c(methods, "drill_fall")
  }
  if (isTRUE(crop_row$precision_planted)) methods <- c(methods, "precision")
  methods
}

#' Resolve seeds/ha and mass seeding rate for one bound combination
#'
#' Reproduces the source workbook exactly:
#'
#'  * where a seed count is supplied directly, it is the primary datum and the
#'    mass rate is derived from it using the chosen TKW;
#'  * where a mass rate is supplied, it is the primary datum and the seed count
#'    is derived from it using the chosen TKW.
#'
#' @noRd
resolve_seeding <- function(crop_row, rate_bound, tkw) {
  direct <- if (rate_bound == "low") {
    crop_row$seeding_rate_low_seeds_per_ha_direct
  } else {
    crop_row$seeding_rate_high_seeds_per_ha_direct
  }
  mass_column <- if (rate_bound == "low") {
    crop_row$seeding_rate_low_kg_per_ha_low_tkw
  } else {
    crop_row$seeding_rate_high_kg_per_ha_low_tkw
  }

  if (!is.na(direct)) {
    list(seeds_per_ha = direct,
         seeding_rate_kg_per_ha = mass_per_ha_from_seeds(direct, tkw),
         basis = "SEED_COUNT_SUPPLIED")
  } else if (!is.na(mass_column)) {
    list(seeds_per_ha = seeds_per_ha_from_mass(mass_column, tkw),
         seeding_rate_kg_per_ha = mass_column,
         basis = "MASS_RATE_SUPPLIED")
  } else {
    list(seeds_per_ha = NA_real_, seeding_rate_kg_per_ha = NA_real_,
         basis = "UNAVAILABLE")
  }
}

#' Build the scenario input table
#'
#' @param params An `stbam_parameter_set`.
#' @param crops Optional character vector of crop names to include.
#' @param workbooks Optional character vector of workbook keys to include.
#' @param planting_methods Optional subset of [STBAM_PLANTING_METHODS].
#' @param rate_levels Optional subset of `"high"`, `"mid"`, `"low"`.
#' @return A tibble of fully resolved, time-independent scenario inputs.
#' @export
build_scenario_inputs <- function(params, crops = NULL, workbooks = NULL,
                                  planting_methods = NULL, rate_levels = NULL) {
  if (!inherits(params, "stbam_parameter_set")) {
    stbam_abort("`params` must be an stbam_parameter_set.")
  }
  baseline <- params$baseline

  scenarios <- baseline$scenarios
  if (!is.null(workbooks)) {
    scenarios <- scenarios[scenarios$workbook %in% workbooks, ]
  }
  if (!is.null(crops)) {
    scenarios <- scenarios[scenarios$crop %in% crops, ]
  }
  if (!is.null(rate_levels)) {
    check_choice(rate_levels, "rate_levels", c("high", "mid", "low"))
    scenarios <- scenarios[scenarios$rate_level %in% rate_levels, ]
  }
  if (nrow(scenarios) == 0L) {
    stbam_abort("No crop x rate scenarios matched the requested filters.")
  }

  if (!is.null(planting_methods)) {
    check_choice(planting_methods, "planting_methods", STBAM_PLANTING_METHODS)
  }

  method_lookup <- baseline$planting_methods
  rows <- vector("list", 0L)

  unmatched <- setdiff(unique(scenarios$crop), baseline$crops$crop)
  if (length(unmatched) > 0L) {
    stbam_abort("Crops present in scenario definitions but absent from the ",
                "agronomic parameter table: ",
                paste(sQuote(unmatched), collapse = ", "))
  }

  for (i in seq_len(nrow(scenarios))) {
    scenario <- scenarios[i, ]
    crop_row <- baseline$crops[baseline$crops$crop == scenario$crop, ][1, ]

    methods <- available_planting_methods(crop_row)
    if (!is.null(planting_methods)) {
      methods <- intersect(methods, planting_methods)
    }
    if (length(methods) == 0L) next

    tkw_low <- effective_value(params, "tkw_g_per_1000",
                               scope = paste0(scenario$crop, ":low_tkw"),
                               default = crop_row$tkw_low_g_per_1000)
    tkw_high <- effective_value(params, "tkw_g_per_1000",
                                scope = paste0(scenario$crop, ":high_tkw"),
                                default = crop_row$tkw_high_g_per_1000)
    rate <- effective_value(params, "application_rate",
                            scope = paste0(scenario$crop, ":", scenario$rate_level),
                            default = scenario$application_rate)

    for (method in methods) {
      method_row <- method_lookup[method_lookup$planting_method == method, ][1, ]
      fraction <- effective_value(params, "surface_seed_fraction",
                                  scope = method,
                                  default = method_row$surface_seed_fraction)

      for (rate_bound in c("low", "high")) {
        for (mass_bound in c("low_tkw", "high_tkw")) {
          tkw_entry <- if (mass_bound == "low_tkw") tkw_low else tkw_high
          tkw <- tkw_entry$value
          if (is.na(tkw) || tkw <= 0) next

          seeding <- resolve_seeding(crop_row, rate_bound, tkw)
          if (seeding$basis == "UNAVAILABLE") next

          seeds_ha <- effective_value(
            params, "seeds_per_ha",
            scope = paste0(scenario$crop, ":", rate_bound),
            default = seeding$seeds_per_ha
          )
          # A seeds_per_ha override must propagate into the mass-basis
          # seeding rate, otherwise the row's own round-trip identity
          # (seeds_per_ha x TKW / 1e6 = seeding_rate_kg_per_ha, specification
          # section 5.2) would be silently violated -- the same reasoning
          # that makes resolve_receptors() recompute food intake whenever
          # body weight is overridden, rather than leaving it stale. Only
          # applies when seeding_rate_kg_per_ha has NOT also been overridden
          # directly at this scope; an explicit override of the mass rate
          # itself still wins via effective_value() below.
          mass_default <- if (identical(seeds_ha$status, "ASSESSMENT_DEFAULT")) {
            seeding$seeding_rate_kg_per_ha
          } else {
            mass_per_ha_from_seeds(seeds_ha$value, tkw)
          }
          mass_ha <- effective_value(
            params, "seeding_rate_kg_per_ha",
            scope = paste0(scenario$crop, ":", rate_bound),
            default = mass_default
          )

          loading <- treatment_loading(rate$value, scenario$application_rate_unit,
                                       tkw)
          initial_surface <- surface_seed_initial(seeds_ha$value, fraction$value)

          rows[[length(rows) + 1L]] <- tibble::tibble(
            # Numeric rate and unit are part of the stable identifier. Several
            # legume crops have both mg/kg-seed and mg/seed uses sharing the
            # same rate_level; omitting these fields silently produced duplicate
            # identifiers for scientifically different scenarios.
            scenario_id = paste(
              scenario$workbook, scenario$crop, scenario$rate_level,
              format(rate$value, scientific = FALSE, trim = TRUE,
                     digits = 15),
              scenario$application_rate_unit, method, rate_bound, mass_bound,
              sep = "|"
            ),
            workbook = scenario$workbook,
            crop = scenario$crop,
            rate_level = scenario$rate_level,
            application_rate = rate$value,
            application_rate_unit = scenario$application_rate_unit,
            planting_method = method,
            planting_method_label = method_row$planting_method_label,
            seeding_rate_bound = rate_bound,
            seed_mass_bound = mass_bound,
            seeding_basis = seeding$basis,
            tkw_g_per_1000 = tkw,
            seed_mass_g = seed_mass_from_tkw(tkw),
            seeds_per_ha = seeds_ha$value,
            seeds_per_m2 = seeds_per_m2(seeds_ha$value),
            seeding_rate_kg_per_ha = mass_ha$value,
            concentration_mg_per_kg_seed = loading$concentration_mg_per_kg_seed,
            dose_per_seed_mg = loading$dose_per_seed_mg,
            field_rate_g_ai_per_ha = field_rate_g_ai_per_ha(
              loading$concentration_mg_per_kg_seed, mass_ha$value
            ),
            surface_seed_fraction = fraction$value,
            initial_surface_seeds_per_m2 = initial_surface,
            area_per_surface_seed_m2 = area_per_surface_seed(initial_surface),
            tkw_status = tkw_entry$status,
            rate_status = rate$status,
            seeding_status = seeds_ha$status,
            surface_fraction_status = fraction$status,
            parameter_set = params$name
          )
        }
      }
    }
  }

  if (length(rows) == 0L) {
    stbam_abort("No scenarios could be built. Check the crop, planting-method ",
                "and rate filters.")
  }
  out <- dplyr::bind_rows(rows)
  out$provenance_class <- "CALCULATED"
  out
}
