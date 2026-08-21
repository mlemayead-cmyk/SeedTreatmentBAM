# Phase 0: peak-finder and content-hash shared infrastructure utilities.
# docs/planning/implementation_phases_proposal.md "Phase 0"; invariants I9
# (peak) and I5/I10 (content hash), docs/planning/invariants_and_test_plan.md.
#
# These tests exercise only R/utils/*.R. They do not touch, and must not
# require changing, anything under R/calculations/.

# ---------------------------------------------------------------------------
# Peak finder: synthetic non-monotonic case (I9)
# ---------------------------------------------------------------------------

test_that("the peak finder identifies a true argmax, not day 0, on a synthetic non-monotonic series", {
  day <- 0:4
  value <- c(2, 5, 9, 6, 3)
  peak <- stbam_find_peak(day, value)
  expect_equal(peak$day, 2)
  expect_equal(peak$value, 9)
  expect_false(peak$tied)
  expect_equal(peak$n_tied, 1L)
})

test_that("the peak finder does not assume the series starts at day 0", {
  day <- c(10, 11, 12, 13, 14)
  value <- c(1, 4, 8, 5, 2)
  peak <- stbam_find_peak(day, value)
  expect_equal(peak$day, 12)
  expect_equal(peak$value, 8)
})

test_that("the peak finder is not fooled by an out-of-order day vector", {
  day <- c(3, 0, 1, 4, 2)
  value <- c(6, 2, 5, 3, 9)
  peak <- stbam_find_peak(day, value)
  expect_equal(peak$day, 2)
  expect_equal(peak$value, 9)
})

test_that("a monotonically decreasing series still correctly resolves to day 0 -- not special-cased, just the correct argmax", {
  day <- 0:10
  value <- 100 * 0.9^day
  peak <- stbam_find_peak(day, value)
  expect_equal(peak$day, 0)
  expect_equal(peak$value, 100)
})

# ---------------------------------------------------------------------------
# Peak finder: ties
# ---------------------------------------------------------------------------

test_that("a tied maximum returns the earliest tied day, deterministically, and reports the tie", {
  day <- 0:3
  value <- c(5, 9, 9, 3)
  peak <- stbam_find_peak(day, value)
  expect_equal(peak$day, 1)
  expect_equal(peak$value, 9)
  expect_true(peak$tied)
  expect_equal(peak$n_tied, 2L)
})

test_that("repeated calls on a tied series return the identical result (deterministic tie-break)", {
  day <- c(2, 0, 1, 3)
  value <- c(7, 7, 3, 7)
  first <- stbam_find_peak(day, value)
  second <- stbam_find_peak(day, value)
  expect_identical(first, second)
  expect_equal(first$day, 0)
  expect_equal(first$n_tied, 3L)
})

# ---------------------------------------------------------------------------
# Peak finder: non-finite / boundary cases
# ---------------------------------------------------------------------------

test_that("non-finite values are ignored, not treated as the maximum", {
  day <- 0:4
  value <- c(NA, Inf, 9, NaN, -Inf)
  peak <- stbam_find_peak(day, value)
  expect_equal(peak$day, 2)
  expect_equal(peak$value, 9)
})

test_that("an entirely non-finite series returns NA throughout, not an arbitrary day", {
  day <- 0:3
  value <- c(NA, NaN, Inf, -Inf)
  peak <- stbam_find_peak(day, value)
  expect_true(is.na(peak$day))
  expect_true(is.na(peak$value))
  expect_false(peak$tied)
  expect_equal(peak$n_tied, 0L)
})

test_that("a single-point series resolves to that point without error", {
  peak <- stbam_find_peak(5, 42)
  expect_equal(peak$day, 5)
  expect_equal(peak$value, 42)
  expect_false(peak$tied)
})

test_that("mismatched day/value lengths are rejected", {
  expect_error(stbam_find_peak(0:3, c(1, 2)), "same length")
})

test_that("a missing day value is rejected (days must be well-defined)", {
  expect_error(stbam_find_peak(c(0, NA, 2), c(1, 2, 3)), "missing values")
})

# ---------------------------------------------------------------------------
# Peak finder: function-evaluation wrapper
# ---------------------------------------------------------------------------

test_that("stbam_peak_over_function evaluates a supplied function and finds its true peak", {
  f <- function(d) -(d - 3)^2 + 20  # parabola peaking at day 3
  peak <- stbam_peak_over_function(f, days = 0:10)
  expect_equal(peak$day, 3)
  expect_equal(peak$value, 20)
})

test_that("stbam_peak_over_function requires an actual function", {
  expect_error(stbam_peak_over_function("not a function", 0:5),
               "must be a function")
})

test_that("stbam_peak_over_function fails loudly if f() returns something non-numeric, instead of silently coercing to NA", {
  # Independent-review regression test: this must not swallow a malformed
  # f() return value into a silent NA via as.numeric() coercion.
  expect_error(stbam_peak_over_function(function(d) "not a number", 0:2),
               "must return a single numeric value")
  expect_error(stbam_peak_over_function(function(d) c(1, 2), 0:2),
               "must return a single numeric value")
  # A genuine logical TRUE/FALSE (not NA) is still rejected -- only the
  # bare-NA carve-out below is an exception.
  expect_error(stbam_peak_over_function(function(d) TRUE, 0:2),
               "must return a single numeric value")
})

test_that("stbam_peak_over_function accepts a bare NA return, treating it as a not-evaluated sentinel -- second-review-pass regression test", {
  # R's own untyped `NA` literal is class "logical", not "numeric" -- an
  # idiomatic way to write "not evaluated for this day"
  # (`if (nrow(row) == 0) NA else row$rq`) that must not be rejected as
  # malformed input.
  f <- function(d) if (d == 2) NA else 9 - abs(d - 2)
  peak <- stbam_peak_over_function(f, days = 0:4)
  # day 2 itself is NA (ignored); the true peak is the highest surviving
  # finite value, tied between days 1 and 3 (both value 8) -- the
  # deterministic earliest-day tie-break picks day 1.
  expect_equal(peak$day, 1)
  expect_equal(peak$value, 8)
  expect_true(peak$tied)
  expect_equal(peak$n_tied, 2L)
})

test_that("n_tied counts distinct tied DAYS, not rows -- two rows for the same day at the maximum is not a two-way tie", {
  # Independent-review regression test.
  day <- c(0, 0, 1)
  value <- c(9, 9, 3)  # day 0 appears twice, both at the maximum
  peak <- stbam_find_peak(day, value)
  expect_equal(peak$day, 0)
  expect_equal(peak$n_tied, 1L)
  expect_false(peak$tied)
})

# ---------------------------------------------------------------------------
# Peak finder: current, real, validated model -- must remain unchanged
# ---------------------------------------------------------------------------

test_that("the general peak-search mechanism reproduces the current model's own day-0 peak, without any special-casing", {
  # This is the Phase 0 acceptance requirement stated in
  # docs/planning/implementation_phases_proposal.md: "generic peak
  # detection works without changing current scientific behaviour." It
  # calls the UNCHANGED engine (build_scenario_inputs/resolve_receptors/
  # resolve_effects_metrics/build_daily_timecourse) exactly as the existing
  # test suite does elsewhere (tests/testthat/test-07-scenario-builders.R),
  # then hands its output to the Phase 0 utility -- no engine file is
  # touched by this test or by R/utils/00_peak_finder.R.
  baseline <- load_baseline()
  params <- parameter_set(baseline)

  barley <- build_scenario_inputs(params, crops = "Barley",
                                  workbooks = "small_cereals",
                                  rate_levels = "high",
                                  planting_methods = "broadcast")
  scenario <- barley[barley$seeding_rate_bound == "high" &
                       barley$seed_mass_bound == "high_tkw", ]
  expect_equal(nrow(scenario), 1L)

  receptors <- resolve_receptors(params, "bird_small")
  metrics <- resolve_effects_metrics(params, "SCREENING", taxa = "bird")

  timecourse <- build_daily_timecourse(
    params, scenario, receptors = receptors, effects_metrics = metrics,
    diet_fractions = 1, days = 0:60
  )
  row <- timecourse[timecourse$metric_id == metrics$metric_id[1], ]
  expect_true(nrow(row) == length(unique(timecourse$day)))
  row <- row[order(row$day), ]

  peak <- stbam_find_peak(row$day, row$rq)

  # Independently confirms invariant 1-2 from test-06-invariants.R (both
  # decay processes are non-increasing) implies a day-0 RQ peak for THIS
  # model -- the general search finds day 0 because day 0 truly is the
  # argmax, not because anything assumes it.
  expect_equal(peak$day, 0)
  expect_equal(peak$value, row$rq[row$day == 0])
  expect_true(all(diff(row$rq) <= 1e-9))

  # Cross-check against the engine's own existing (unchanged,
  # hard-coded-for-this-model) peak_rq/peak_rq_day columns in
  # scenario_summary -- the general utility and the existing shortcut must
  # agree for the current model.
  summary <- build_scenario_summary(params, scenario, receptors = receptors,
                                    effects_metrics = metrics,
                                    diet_fractions = 1)
  summary_row <- summary[summary$metric_id == metrics$metric_id[1], ]
  expect_equal(nrow(summary_row), 1L)
  expect_equal(summary_row$peak_rq_day, 0)
  expect_equal(peak$value, summary_row$peak_rq, tolerance = 1e-12)
})

# ===========================================================================
# Content hash
# ===========================================================================

# ---------------------------------------------------------------------------
# Canonicalization: order independence
# ---------------------------------------------------------------------------

test_that("canonicalizing a table is invariant to row order", {
  df1 <- data.frame(crop = c("Barley", "Oat", "Rye"),
                    rate = c(300, 200, 100), stringsAsFactors = FALSE)
  df2 <- df1[c(3, 1, 2), ]
  expect_identical(stbam_canonicalize_table(df1), stbam_canonicalize_table(df2))
})

test_that("canonicalizing a table is invariant to column order", {
  df1 <- data.frame(crop = c("Barley", "Oat"), rate = c(300, 200),
                    stringsAsFactors = FALSE)
  df2 <- df1[, c("rate", "crop")]
  expect_identical(stbam_canonicalize_table(df1), stbam_canonicalize_table(df2))
})

test_that("canonicalizing a table detects a genuine content difference", {
  df1 <- data.frame(crop = "Barley", rate = 300)
  df2 <- data.frame(crop = "Barley", rate = 301)
  expect_false(identical(stbam_canonicalize_table(df1),
                         stbam_canonicalize_table(df2)))
})

test_that("canonicalizing a table distinguishes different column names even with matching values", {
  df1 <- data.frame(a = 1, b = 2)
  df2 <- data.frame(x = 1, y = 2)
  expect_false(identical(stbam_canonicalize_table(df1),
                         stbam_canonicalize_table(df2)))
})

test_that("NA, NaN, Inf, and -Inf canonicalize to distinct tokens, not to each other or to a real value", {
  df <- data.frame(v = c(NA_real_, NaN, Inf, -Inf, 0))
  canon <- stbam_canonicalize_table(df)
  tokens <- c("<NA>", "<NaN>", "<Inf>", "<-Inf>")
  for (t in tokens) expect_true(grepl(t, canon, fixed = TRUE))
  expect_equal(length(unique(c(tokens, "0"))), 5L)
})

test_that("full double precision is retained -- two nearly-equal but distinct doubles canonicalize differently", {
  df1 <- data.frame(v = 0.1 + 0.2)
  df2 <- data.frame(v = 0.3)
  # 0.1 + 0.2 != 0.3 at full double precision; the canonical form must
  # preserve that distinction rather than rounding both to "0.3".
  expect_false(isTRUE(all.equal(0.1 + 0.2, 0.3, tolerance = 0)))
  expect_false(identical(stbam_canonicalize_table(df1),
                         stbam_canonicalize_table(df2)))
})

test_that("canonicalizing rejects a non-data-frame input", {
  expect_error(stbam_canonicalize_table(list(a = 1)), "data.frame or tibble")
})

test_that("positive and negative zero canonicalize identically -- independent-review regression test", {
  df1 <- data.frame(v = 0)
  df2 <- data.frame(v = -0)
  expect_identical(stbam_canonicalize_table(df1), stbam_canonicalize_table(df2))

  # Same property must survive a full CSV write/read round trip.
  dir <- withr::local_tempdir()
  path1 <- file.path(dir, "pos_zero.csv")
  path2 <- file.path(dir, "neg_zero.csv")
  readr::write_csv(df1, path1)
  readr::write_csv(df2, path2)
  expect_identical(
    stbam_file_content_hash(c(v = path1)),
    stbam_file_content_hash(c(v = path2))
  )
})

test_that("column type is part of the canonical identity -- a logical and a character column of the same-looking values must not collide", {
  # Independent-review regression test.
  logical_df <- data.frame(flag = c(TRUE, FALSE))
  character_df <- data.frame(flag = c("TRUE", "FALSE"))
  expect_false(identical(stbam_canonicalize_table(logical_df),
                         stbam_canonicalize_table(character_df)))

  numeric_df <- data.frame(v = 45)
  character_digit_df <- data.frame(v = "45")
  expect_false(identical(stbam_canonicalize_table(numeric_df),
                         stbam_canonicalize_table(character_digit_df)))
})

test_that("canonicalization sorts by byte order (radix), not locale-dependent collation -- independent-review regression test", {
  # R's default sort()/order() collation depends on LC_COLLATE and can order
  # mixed-case strings differently across machines/locales -- exactly the
  # kind of incidental, environment-specific factor the spec requires this
  # utility to be immune to. Byte-order (radix) sorting places all uppercase
  # ASCII letters before all lowercase ones ('B' = 66 < 'a' = 97); many
  # locale-aware collations instead fold case and would order these the
  # other way. This test locks in that radix, not locale, ordering is
  # actually in effect, regardless of the session's locale.
  df <- data.frame(crop = c("apple", "Banana"), stringsAsFactors = FALSE)
  canon <- stbam_canonicalize_table(df)
  rows <- strsplit(sub("^[^\n]*\n", "", canon), "\x1e", fixed = TRUE)[[1]]
  expect_equal(rows, c("Banana", "apple"))
})

# ---------------------------------------------------------------------------
# stbam_content_hash: order independence, determinism, sensitivity
# ---------------------------------------------------------------------------

test_that("stbam_content_hash is invariant to the order tables are supplied in", {
  seeding <- data.frame(crop = c("Barley", "Oat"), tkw = c(45, 32))
  receptors <- data.frame(receptor_id = "bird_small", body_weight_g = 20)

  h1 <- stbam_content_hash(list(seeding_set = seeding, receptor_set = receptors))
  h2 <- stbam_content_hash(list(receptor_set = receptors, seeding_set = seeding))
  expect_identical(h1, h2)
})

test_that("stbam_content_hash is invariant to row order within a table (simulated file-write-order difference)", {
  seeding_a <- data.frame(crop = c("Barley", "Oat", "Rye"), tkw = c(45, 32, 28))
  seeding_b <- seeding_a[c(2, 3, 1), ]

  h1 <- stbam_content_hash(list(seeding_set = seeding_a))
  h2 <- stbam_content_hash(list(seeding_set = seeding_b))
  expect_identical(h1, h2)
})

test_that("stbam_content_hash is deterministic across repeated calls", {
  tables <- list(seeding_set = data.frame(crop = "Barley", tkw = 45))
  h1 <- stbam_content_hash(tables)
  h2 <- stbam_content_hash(tables)
  h3 <- stbam_content_hash(tables)
  expect_identical(h1, h2)
  expect_identical(h2, h3)
})

test_that("stbam_content_hash changes when a scientifically meaningful value changes", {
  base <- list(seeding_set = data.frame(crop = "Barley", tkw = 45))
  changed <- list(seeding_set = data.frame(crop = "Barley", tkw = 45.001))
  expect_false(identical(stbam_content_hash(base), stbam_content_hash(changed)))
})

test_that("stbam_content_hash detects content swapped between two named slots", {
  set_x <- data.frame(v = 1)
  set_y <- data.frame(v = 2)
  original <- list(a = set_x, b = set_y)
  swapped <- list(a = set_y, b = set_x)
  # Documented, deliberate design choice: which slot holds which content is
  # part of scientific input identity, so swapping slot content must change
  # the hash even though the *set* of values used is unchanged.
  expect_false(identical(stbam_content_hash(original), stbam_content_hash(swapped)))
})

test_that("stbam_content_hash rejects unnamed or duplicate-named entries", {
  expect_error(stbam_content_hash(list(data.frame(v = 1))), "non-empty name")
  expect_error(
    stbam_content_hash(list(a = data.frame(v = 1), a = data.frame(v = 2))),
    "must be unique"
  )
})

test_that("stbam_content_hash produces a well-formed sha256 hex digest by default", {
  h <- stbam_content_hash(list(a = data.frame(v = 1)))
  expect_equal(STBAM_CONTENT_HASH_ALGORITHM, "sha256")
  expect_match(h, "^[0-9a-f]{64}$")
})

# ---------------------------------------------------------------------------
# stbam_file_content_hash: real files, on-disk order/formatting independence
# ---------------------------------------------------------------------------

test_that("stbam_file_content_hash is invariant to on-disk row order and file path order (I5/I10)", {
  dir <- withr::local_tempdir()

  seeding_a <- data.frame(crop = c("Barley", "Oat", "Rye"),
                          tkw = c(45, 32, 28))
  seeding_b <- seeding_a[c(3, 1, 2), ]  # same content, different row order
  receptors <- data.frame(receptor_id = "bird_small", body_weight_g = 20)

  path_seeding_a <- file.path(dir, "seeding_a.csv")
  path_seeding_b <- file.path(dir, "seeding_b.csv")
  path_receptors <- file.path(dir, "receptors.csv")
  readr::write_csv(seeding_a, path_seeding_a)
  readr::write_csv(seeding_b, path_seeding_b)
  readr::write_csv(receptors, path_receptors)

  h1 <- stbam_file_content_hash(c(seeding_set = path_seeding_a,
                                  receptor_set = path_receptors))
  h2 <- stbam_file_content_hash(c(receptor_set = path_receptors,
                                  seeding_set = path_seeding_b))
  expect_identical(h1, h2)
})

test_that("stbam_file_content_hash changes when the underlying file content changes", {
  dir <- withr::local_tempdir()
  path <- file.path(dir, "seeding.csv")

  readr::write_csv(data.frame(crop = "Barley", tkw = 45), path)
  h1 <- stbam_file_content_hash(c(seeding_set = path))

  readr::write_csv(data.frame(crop = "Barley", tkw = 46), path)
  h2 <- stbam_file_content_hash(c(seeding_set = path))

  expect_false(identical(h1, h2))
})

test_that("stbam_file_content_hash rejects a missing file rather than silently proceeding", {
  expect_error(
    stbam_file_content_hash(c(seeding_set = "does_not_exist_12345.csv")),
    "not found"
  )
})

# ---------------------------------------------------------------------------
# stbam_hash_string: low-level primitive
# ---------------------------------------------------------------------------

test_that("stbam_hash_string is deterministic and rejects non-scalar input", {
  expect_identical(stbam_hash_string("abc"), stbam_hash_string("abc"))
  expect_false(identical(stbam_hash_string("abc"), stbam_hash_string("abd")))
  expect_error(stbam_hash_string(c("a", "b")), "single, non-missing")
  expect_error(stbam_hash_string(NA_character_), "single, non-missing")
})
