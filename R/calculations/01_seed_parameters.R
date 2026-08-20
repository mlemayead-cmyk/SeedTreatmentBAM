# Seed and treatment parameter conversions.
#
# Specification section 5. Every conversion is unit-safe and bidirectional so
# the user never has to enter a redundant value.

#' Convert thousand-seed weight to individual seed mass
#'
#' @param tkw_g_per_1000 Thousand-seed weight, g per 1000 seeds.
#' @return Individual seed mass, g per seed.
#' @export
seed_mass_from_tkw <- function(tkw_g_per_1000) {
  check_numeric(tkw_g_per_1000, "tkw_g_per_1000", min = 0, exclusive_min = TRUE)
  tkw_g_per_1000 / 1000
}

#' Convert individual seed mass to thousand-seed weight
#'
#' @param seed_mass_g Individual seed mass, g per seed.
#' @return Thousand-seed weight, g per 1000 seeds.
#' @export
tkw_from_seed_mass <- function(seed_mass_g) {
  check_numeric(seed_mass_g, "seed_mass_g", min = 0, exclusive_min = TRUE)
  seed_mass_g * 1000
}

#' Convert a mass-basis seeding rate to a seed count
#'
#' `N_ha = R_mass * 1e6 / TKW`, algebraically identical to the workbook form
#' `1000 * (R_mass / (TKW / 1000))`.
#'
#' @param seeding_rate_kg_per_ha Seeding rate, kg seed/ha.
#' @param tkw_g_per_1000 Thousand-seed weight, g per 1000 seeds.
#' @return Seeds planted, seeds/ha.
#' @export
seeds_per_ha_from_mass <- function(seeding_rate_kg_per_ha, tkw_g_per_1000) {
  check_numeric(seeding_rate_kg_per_ha, "seeding_rate_kg_per_ha", min = 0)
  check_numeric(tkw_g_per_1000, "tkw_g_per_1000", min = 0, exclusive_min = TRUE)
  check_recyclable(seeding_rate_kg_per_ha, tkw_g_per_1000)
  seeding_rate_kg_per_ha * 1e6 / tkw_g_per_1000
}

#' Convert a seed-count seeding rate to a mass basis
#'
#' @param seeds_per_ha Seeds planted, seeds/ha.
#' @param tkw_g_per_1000 Thousand-seed weight, g per 1000 seeds.
#' @return Seeding rate, kg seed/ha.
#' @export
mass_per_ha_from_seeds <- function(seeds_per_ha, tkw_g_per_1000) {
  check_numeric(seeds_per_ha, "seeds_per_ha", min = 0)
  check_numeric(tkw_g_per_1000, "tkw_g_per_1000", min = 0, exclusive_min = TRUE)
  check_recyclable(seeds_per_ha, tkw_g_per_1000)
  seeds_per_ha * tkw_g_per_1000 / 1e6
}

#' Convert seeds per hectare to seeds per square metre
#'
#' @param seeds_per_ha Seeds planted, seeds/ha.
#' @return Seeds planted, seeds/m2.
#' @export
seeds_per_m2 <- function(seeds_per_ha) {
  check_numeric(seeds_per_ha, "seeds_per_ha", min = 0)
  seeds_per_ha / 10000
}

#' Resolve treatment loading into both canonical forms
#'
#' Accepts a registered rate in either supported unit and returns the seed
#' concentration and the dose per seed. Specification section 5.3.
#'
#' @param application_rate Registered rate, in `application_rate_unit`.
#' @param application_rate_unit One of [STBAM_RATE_UNITS].
#' @param tkw_g_per_1000 Thousand-seed weight, g per 1000 seeds.
#' @return A list with `concentration_mg_per_kg_seed` and `dose_per_seed_mg`.
#' @export
treatment_loading <- function(application_rate, application_rate_unit,
                              tkw_g_per_1000) {
  check_numeric(application_rate, "application_rate", min = 0)
  check_choice(application_rate_unit, "application_rate_unit", STBAM_RATE_UNITS)
  check_numeric(tkw_g_per_1000, "tkw_g_per_1000", min = 0, exclusive_min = TRUE)
  check_recyclable(application_rate, application_rate_unit, tkw_g_per_1000)

  n <- max(length(application_rate), length(application_rate_unit),
           length(tkw_g_per_1000))
  rate <- rep_len(application_rate, n)
  unit <- rep_len(as.character(application_rate_unit), n)
  tkw <- rep_len(tkw_g_per_1000, n)

  per_mass <- unit == "mg a.i./kg seed"
  concentration <- stbam_ifelse(per_mass, rate, rate * 1e6 / tkw)
  dose_per_seed <- stbam_ifelse(per_mass, rate * tkw / 1e6, rate)

  list(
    concentration_mg_per_kg_seed = concentration,
    dose_per_seed_mg = dose_per_seed
  )
}

#' Active ingredient applied to the field
#'
#' @param concentration_mg_per_kg_seed Seed concentration, mg a.i./kg seed.
#' @param seeding_rate_kg_per_ha Seeding rate, kg seed/ha.
#' @return Field loading, g a.i./ha.
#' @export
field_rate_g_ai_per_ha <- function(concentration_mg_per_kg_seed,
                                   seeding_rate_kg_per_ha) {
  check_numeric(concentration_mg_per_kg_seed, "concentration_mg_per_kg_seed",
                min = 0)
  check_numeric(seeding_rate_kg_per_ha, "seeding_rate_kg_per_ha", min = 0)
  check_recyclable(concentration_mg_per_kg_seed, seeding_rate_kg_per_ha)
  (concentration_mg_per_kg_seed / 1000) * seeding_rate_kg_per_ha
}

#' Screening conversion of thiamethoxam to clothianidin
#'
#' Complete molar conversion, screening stage only (ASSUMPTION-003). The
#' refined seed-ingestion assessment excludes quantitative clothianidin
#' exposure (ASSUMPTION-004), so this is never applied inside the refined
#' chain. It is exported as a named, isolated function so its use is always
#' visible.
#'
#' @param value_thiamethoxam Any thiamethoxam quantity, linear in mass.
#' @return The clothianidin-equivalent quantity in the same unit.
#' @export
screening_clothianidin_equivalent <- function(value_thiamethoxam) {
  check_numeric(value_thiamethoxam, "value_thiamethoxam", min = 0)
  value_thiamethoxam * STBAM_CLOTHIANIDIN_MOLAR_RATIO
}
