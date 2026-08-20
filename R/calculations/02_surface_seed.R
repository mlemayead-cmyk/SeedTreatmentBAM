# Surface-seed availability and residue dissipation.
#
# Specification section 6 and 7. Surface-seed disappearance and residue
# dissipation are SEPARATE first-order processes with SEPARATE half-lives.
# They are modelled independently and only combined explicitly.

#' First-order decline factor
#'
#' Returns `2^(-t / DT50)`. A half-life of `Inf` means no decline (used for
#' pelleted seed, ASSUMPTION-006) and returns 1.
#'
#' @param day Days since sowing, >= 0.
#' @param half_life_days Half-life in days, > 0. `Inf` is permitted.
#' @return Remaining fraction, in (0, 1].
#' @export
first_order_remaining <- function(day, half_life_days) {
  check_numeric(day, "day", min = 0)
  check_numeric(half_life_days, "half_life_days", min = 0,
                exclusive_min = TRUE, allow_inf = TRUE)
  check_recyclable(day, half_life_days)
  stbam_ifelse(is.infinite(half_life_days), 1, 2^(-day / half_life_days))
}

#' Surface seed density immediately after sowing
#'
#' @param seeds_per_ha Seeds planted, seeds/ha.
#' @param surface_seed_fraction Proportion remaining on the surface, 0-1.
#' @return Surface seed density, seeds/m2.
#' @export
surface_seed_initial <- function(seeds_per_ha, surface_seed_fraction) {
  check_numeric(seeds_per_ha, "seeds_per_ha", min = 0)
  check_numeric(surface_seed_fraction, "surface_seed_fraction", min = 0, max = 1)
  check_recyclable(seeds_per_ha, surface_seed_fraction)
  (seeds_per_ha / 10000) * surface_seed_fraction
}

#' Surface seed density over time
#'
#' Loss of surface seed by displacement, burial, germination and predation
#' (ASSUMPTION-011, default DT50 14 d). This is NOT residue dissipation.
#'
#' @param initial_surface_seeds_per_m2 Surface seed density at sowing.
#' @param day Days since sowing.
#' @param surface_seed_dt50_days Surface-seed disappearance half-life, days.
#' @return Surface seed density, seeds/m2.
#' @export
surface_seed_over_time <- function(initial_surface_seeds_per_m2, day,
                                   surface_seed_dt50_days) {
  check_numeric(initial_surface_seeds_per_m2, "initial_surface_seeds_per_m2",
                min = 0)
  check_recyclable(initial_surface_seeds_per_m2, day, surface_seed_dt50_days)
  initial_surface_seeds_per_m2 * first_order_remaining(day, surface_seed_dt50_days)
}

#' Mean area per surface seed
#'
#' @param surface_seeds_per_m2 Surface seed density, seeds/m2.
#' @return Area per surface seed, m2/seed. Infinite where density is zero.
#' @export
area_per_surface_seed <- function(surface_seeds_per_m2) {
  check_numeric(surface_seeds_per_m2, "surface_seeds_per_m2", min = 0)
  stbam_ifelse(surface_seeds_per_m2 > 0, 1 / surface_seeds_per_m2, Inf)
}

#' Active ingredient remaining per seed over time
#'
#' Dissipation of the residue on/in a seed that is still present
#' (ASSUMPTION-005, default DT50 10 d). This is NOT surface-seed loss.
#'
#' @param dose_per_seed_mg Dose per seed at sowing, mg a.i./seed.
#' @param day Days since sowing.
#' @param residue_dt50_days Residue half-life, days. `Inf` for pelleted seed.
#' @return Active ingredient per seed, mg a.i./seed.
#' @export
ai_per_seed_over_time <- function(dose_per_seed_mg, day, residue_dt50_days) {
  check_numeric(dose_per_seed_mg, "dose_per_seed_mg", min = 0)
  check_recyclable(dose_per_seed_mg, day, residue_dt50_days)
  dose_per_seed_mg * first_order_remaining(day, residue_dt50_days)
}

#' Active ingredient on the soil surface over time, area basis
#'
#' The product of the two independent processes: how much seed is still on the
#' surface, and how much active ingredient each of those seeds still carries.
#'
#' @param initial_surface_seeds_per_m2 Surface seed density at sowing.
#' @param dose_per_seed_mg Dose per seed at sowing, mg a.i./seed.
#' @param day Days since sowing.
#' @param surface_seed_dt50_days Surface-seed disappearance half-life, days.
#' @param residue_dt50_days Residue dissipation half-life, days.
#' @return Active ingredient on the surface, mg a.i./m2.
#' @export
surface_ai_over_time <- function(initial_surface_seeds_per_m2, dose_per_seed_mg,
                                 day, surface_seed_dt50_days,
                                 residue_dt50_days) {
  seeds <- surface_seed_over_time(initial_surface_seeds_per_m2, day,
                                  surface_seed_dt50_days)
  ai <- ai_per_seed_over_time(dose_per_seed_mg, day, residue_dt50_days)
  seeds * ai
}

#' Combined half-life of the surface active-ingredient loading
#'
#' Two independent first-order processes acting on a product decay with
#' `1/DT50_combined = 1/DT50_a + 1/DT50_b`. Provided for transparency and
#' asserted against the product form in the test suite.
#'
#' @param surface_seed_dt50_days Surface-seed disappearance half-life, days.
#' @param residue_dt50_days Residue dissipation half-life, days.
#' @return Combined half-life, days.
#' @export
combined_surface_ai_dt50 <- function(surface_seed_dt50_days, residue_dt50_days) {
  check_numeric(surface_seed_dt50_days, "surface_seed_dt50_days", min = 0,
                exclusive_min = TRUE, allow_inf = TRUE)
  check_numeric(residue_dt50_days, "residue_dt50_days", min = 0,
                exclusive_min = TRUE, allow_inf = TRUE)
  check_recyclable(surface_seed_dt50_days, residue_dt50_days)
  1 / (1 / surface_seed_dt50_days + 1 / residue_dt50_days)
}
