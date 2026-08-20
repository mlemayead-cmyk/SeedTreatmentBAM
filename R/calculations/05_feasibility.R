# Exposure feasibility: maximum search area analysis.
#
# Specification section 10.
#
# IMPORTANT. These functions answer "could an animal realistically obtain this
# much treated seed?". They are a diagnostic, not a cap on the regulatory
# exposure calculation. Nothing in this file modifies dose or RQ.

#' Treated seeds available within the maximum search area
#'
#' @param surface_seeds_per_m2 Surface seed density, seeds/m2.
#' @param msa_m2 Maximum search area, m2.
#' @return Seeds available within the search area.
#' @export
available_seed_within_msa <- function(surface_seeds_per_m2, msa_m2) {
  check_numeric(surface_seeds_per_m2, "surface_seeds_per_m2", min = 0)
  check_numeric(msa_m2, "msa_m2", min = 0, exclusive_min = TRUE)
  check_recyclable(surface_seeds_per_m2, msa_m2)
  surface_seeds_per_m2 * msa_m2
}

#' Search area required to obtain a required number of seeds
#'
#' @param seeds_required_per_day Seeds required, seeds/day.
#' @param surface_seeds_per_m2 Surface seed density, seeds/m2.
#' @return Required search area, m2. `Inf` where no surface seed remains and
#'   seed is still required; 0 where no seed is required.
#' @export
required_search_area <- function(seeds_required_per_day, surface_seeds_per_m2) {
  check_numeric(seeds_required_per_day, "seeds_required_per_day", min = 0)
  check_numeric(surface_seeds_per_m2, "surface_seeds_per_m2", min = 0)
  check_recyclable(seeds_required_per_day, surface_seeds_per_m2)
  stbam_ifelse(
    seeds_required_per_day == 0, 0,
    stbam_ifelse(
      surface_seeds_per_m2 > 0,
      seeds_required_per_day / pmax(surface_seeds_per_m2, .Machine$double.xmin),
      Inf
    )
  )
}

#' Maximum dietary fraction physically obtainable within the search area
#'
#' Expressed as a fraction of the full daily diet. Values above 1 mean more
#' than a full daily diet of treated seed is available.
#'
#' @param surface_seeds_per_m2 Surface seed density, seeds/m2.
#' @param msa_m2 Maximum search area, m2.
#' @param food_intake_g_dw_per_day Food ingestion rate, g dry weight/day.
#' @param seed_mass_g Individual seed mass, g/seed.
#' @return Maximum feasible dietary fraction, dimensionless (not capped at 1).
#' @export
maximum_feasible_diet_fraction <- function(surface_seeds_per_m2, msa_m2,
                                           food_intake_g_dw_per_day,
                                           seed_mass_g) {
  check_numeric(food_intake_g_dw_per_day, "food_intake_g_dw_per_day", min = 0,
                exclusive_min = TRUE)
  check_numeric(seed_mass_g, "seed_mass_g", min = 0, exclusive_min = TRUE)
  available <- available_seed_within_msa(surface_seeds_per_m2, msa_m2)
  check_recyclable(available, food_intake_g_dw_per_day, seed_mass_g)
  seeds_for_full_diet <- food_intake_g_dw_per_day / seed_mass_g
  available / seeds_for_full_diet
}

#' Number of days for which a given dietary fraction remains obtainable
#'
#' Uses the SURFACE-SEED half-life, because this is an availability question,
#' not a residue question.
#'
#' @param initial_max_feasible_diet_fraction Maximum feasible dietary fraction
#'   at sowing.
#' @param target_diet_fraction Dietary fraction of interest, 0-1. A target of
#'   0 requires no seed at all and is trivially obtainable for as long as the
#'   scenario is modelled (specification invariant 6 names `p_diet = 0` as a
#'   valid input; this function must accept it on the same terms as every
#'   other function in the exposure chain).
#' @param surface_seed_dt50_days Surface-seed disappearance half-life, days.
#' @return Days until the target fraction is no longer obtainable. 0 if it is
#'   never obtainable; `Inf` if surface seed does not decline, or if the
#'   target dietary fraction is 0.
#' @export
days_diet_fraction_feasible <- function(initial_max_feasible_diet_fraction,
                                        target_diet_fraction,
                                        surface_seed_dt50_days) {
  check_numeric(initial_max_feasible_diet_fraction,
                "initial_max_feasible_diet_fraction", min = 0)
  check_numeric(target_diet_fraction, "target_diet_fraction", min = 0, max = 1)
  check_numeric(surface_seed_dt50_days, "surface_seed_dt50_days", min = 0,
                exclusive_min = TRUE, allow_inf = TRUE)
  check_recyclable(initial_max_feasible_diet_fraction, target_diet_fraction,
                   surface_seed_dt50_days)

  zero_target <- target_diet_fraction == 0
  # Divide by 1 instead of 0 for a zero target so the ratio is always
  # well-defined; the zero_target branch below discards it regardless.
  ratio <- initial_max_feasible_diet_fraction /
    stbam_ifelse(zero_target, 1, target_diet_fraction)
  result <- stbam_ifelse(
    ratio > 1,
    stbam_ifelse(is.infinite(surface_seed_dt50_days), Inf,
                 surface_seed_dt50_days * log2(pmax(ratio, 1))),
    0
  )
  stbam_ifelse(zero_target, Inf, result)
}

#' Is the assumed dietary fraction physically attainable?
#'
#' @param diet_fraction Assumed dietary fraction, 0-1.
#' @param max_feasible_diet_fraction Maximum feasible dietary fraction.
#' @return Logical vector.
#' @export
diet_fraction_is_feasible <- function(diet_fraction,
                                      max_feasible_diet_fraction) {
  check_numeric(diet_fraction, "diet_fraction", min = 0, max = 1)
  check_numeric(max_feasible_diet_fraction, "max_feasible_diet_fraction",
                min = 0)
  check_recyclable(diet_fraction, max_feasible_diet_fraction)
  max_feasible_diet_fraction >= diet_fraction
}
