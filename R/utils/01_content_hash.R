# Phase 0 shared infrastructure: deterministic content-hash/canonicalization
# utility, per run_lifecycle_and_validation.md §2 step 2 and
# reproducibility_and_provenance.md §3 (ADR-008's deduplication
# recommendation).
#
# Purpose (Phase 0 scope only): provide the reusable hashing primitive later
# phases need for frozen-run identity, exact input-state identity,
# duplicate-run detection, and provenance/integrity checks. This file does
# NOT build the run lifecycle, evaluation persistence, or migration logic --
# those are later phases. It hashes tables/files handed to it by a future
# caller; it has no knowledge of evaluations, runs, or named assumption
# sets.
#
# Canonicalization rules (the specification leaves the exact algorithm as an
# implementation choice, run_lifecycle_and_validation.md §5, but requires it
# be deterministic regardless of incidental factors like file-write order or
# floating-point representation -- implementation_dependencies_and_risks.md
# §3). The rules below are the concrete choices made to satisfy that:
#   1. Column order never affects the hash -- columns are sorted
#      alphabetically by name before hashing.
#   2. Row order never affects the hash -- rows are sorted by their full
#      content (all columns, left to right) before hashing.
#   3. Numeric values are formatted with `sprintf("%.17g", x)`, which
#      round-trips an IEEE-754 double exactly. This avoids two
#      representations of the *same* number (e.g. differing print/rounding
#      behaviour) hashing differently, while still hashing two *different*
#      numbers differently no matter how close together they are -- this is
#      a canonical, lossless serialization, not a rounding/precision
#      reduction. Signed zero is normalized (`-0` and `0` format identically),
#      matching R's own `identical(0, -0)` treatment of them as equal.
#   4. NA/NaN/Inf/-Inf, per column type, are encoded as fixed sentinel
#      tokens distinct from any valid formatted value.
#   5. Column names, *column types*, row/column counts, and a per-slot label
#      (see stbam_content_hash()) are embedded structurally in the canonical
#      string, so two tables that coincidentally format to the same value
#      string cannot collide across different column layouts, column types
#      (e.g. a logical `TRUE` column vs. a character `"TRUE"` column), or
#      slots.
#   6. The final string is hashed as raw UTF-8 bytes (`digest::digest(...,
#      serialize = FALSE)`), not via R's own object-serialization format --
#      serialization format can vary across R versions, which would make
#      the hash depend on something other than scientific input identity.
#   7. Every sort/order used for canonicalization (columns, rows, table
#      slots) uses `method = "radix"` explicitly, never the default
#      locale-dependent collation. R's default character sort order depends
#      on `LC_COLLATE`, which varies by machine/OS configuration -- two
#      genuinely identical tables could otherwise sort differently (and
#      therefore hash differently) on two machines with different locales.
#      Radix sort uses C-locale/byte-order collation unconditionally, which
#      is what "deterministic regardless of incidental factors" requires.
#      (Confirmed by independent review this session: the default `sort()`
#      was locale-dependent and produced different hashes for the same
#      mixed-case table under `English_Canada.utf8` vs. a forced `C` locale
#      before this fix.)
#
# Algorithm and canonicalization-rule version are recorded as named
# constants so a future run record can state exactly which rules produced a
# given hash (independent-review requirement: "is hash provenance/algorithm
# identification adequate for later run records?").

#' Content-hash algorithm used throughout this project
#' @export
STBAM_CONTENT_HASH_ALGORITHM <- "sha256"

#' Canonicalization rule-set version
#'
#' Bumped only if the canonicalization rules documented at the top of this
#' file change in a way that could alter a hash for logically unchanged
#' input -- kept distinct from `STBAM_MODEL_VERSION`, which tracks
#' calculation-engine semantics, not this utility.
#' @export
STBAM_CANONICALIZATION_VERSION <- "2"

#' Format a single vector's values as canonical, type-aware strings
#'
#' @param x A vector (numeric, character, logical, or factor).
#' @return A character vector, same length as `x`, with `NA` and (for
#'   numeric input) `NaN`/`Inf`/`-Inf` encoded as fixed sentinel tokens.
#' @noRd
stbam_canonical_values <- function(x) {
  if (is.factor(x)) x <- as.character(x)

  if (is.numeric(x)) {
    out <- character(length(x))
    is_na <- is.na(x) & !is.nan(x)
    is_nan <- is.nan(x)
    is_pos_inf <- is.infinite(x) & x > 0
    is_neg_inf <- is.infinite(x) & x < 0
    finite <- is.finite(x)
    # Normalize signed zero: -0 and 0 are `identical()`-equal in R and must
    # canonicalize to the same string (independent-review finding).
    finite_vals <- x[finite]
    finite_vals[finite_vals == 0] <- 0
    out[finite] <- sprintf("%.17g", finite_vals)
    out[is_nan] <- "<NaN>"
    out[is_pos_inf] <- "<Inf>"
    out[is_neg_inf] <- "<-Inf>"
    out[is_na] <- "<NA>"
    return(out)
  }

  if (is.logical(x)) {
    out <- ifelse(is.na(x), "<NA>", ifelse(x, "TRUE", "FALSE"))
    return(out)
  }

  # Character (or anything else, via as.character() fallback -- this
  # project's input tables are character/numeric/integer/logical/factor
  # only, so this fallback is not expected to be exercised).
  x <- if (is.character(x)) x else as.character(x)
  ifelse(is.na(x), "<NA>", x)
}

#' Canonicalize a table into a single deterministic string
#'
#' Column order and row order never affect the result (§ file header, rules
#' 1-2); the exact value formatting is documented in rules 3-4. This
#' function does not hash -- it produces the canonical string
#' [stbam_content_hash()] hashes, and is exported separately so its output
#' can be inspected/tested directly (e.g. to confirm two differently-ordered
#' but logically identical tables canonicalize identically).
#'
#' @param df A data.frame or tibble.
#' @return A single character string.
#' @export
stbam_canonicalize_table <- function(df) {
  if (!is.data.frame(df)) {
    stbam_abort("`df` must be a data.frame or tibble, not ", class(df)[1], ".")
  }
  df <- as.data.frame(df, stringsAsFactors = FALSE)

  col_order <- order(names(df), method = "radix")
  df <- df[, col_order, drop = FALSE]

  # Column type is embedded alongside its name (e.g. "flag:logical"), not
  # just the name, so a logical TRUE/FALSE column can never canonicalize to
  # the same string as a character "TRUE"/"FALSE" column, or a numeric
  # column to its character digit-string equivalent (independent-review
  # finding). Factors were already coerced to character by
  # stbam_canonical_values(), so they are reported as "character" here too
  # -- factor-vs-character is a storage-mode distinction this project's CSV
  # round trip does not preserve, so it is deliberately not part of
  # scientific content identity.
  col_types <- vapply(df, function(col) {
    if (is.factor(col)) "character" else class(col)[1]
  }, character(1))
  header <- paste0(
    "ncol=", ncol(df), ";nrow=", nrow(df), ";cols=",
    paste(paste0(names(df), ":", col_types), collapse = "\x1f")
  )

  if (nrow(df) == 0L || ncol(df) == 0L) {
    row_strings <- rep("", nrow(df))
  } else {
    formatted <- lapply(df, stbam_canonical_values)
    cell_matrix <- do.call(cbind, formatted)
    row_strings <- apply(cell_matrix, 1L, paste, collapse = "\x1f")
  }

  row_strings <- sort(row_strings, method = "radix")

  paste0(header, "\n", paste(row_strings, collapse = "\x1e"))
}

#' Hash a single already-canonical string deterministically
#'
#' Low-level primitive: hashes raw UTF-8 bytes directly
#' (`digest::digest(..., serialize = FALSE)`), never R's own
#' object-serialization format, so the result does not depend on the R
#' version or session state that produced the string (independent-review
#' requirement: nothing machine/environment-specific should define
#' scientific input identity).
#'
#' @param x A single character string.
#' @param algo Digest algorithm; defaults to [STBAM_CONTENT_HASH_ALGORITHM].
#' @return A single character string (the hex digest).
#' @export
stbam_hash_string <- function(x, algo = STBAM_CONTENT_HASH_ALGORITHM) {
  if (!is.character(x) || length(x) != 1L || is.na(x)) {
    stbam_abort("`x` must be a single, non-missing character string.")
  }
  digest::digest(enc2utf8(x), algo = algo, serialize = FALSE)
}

#' Deterministic content hash over a named set of tables
#'
#' The primitive `run_lifecycle_and_validation.md` §2 step 2 calls for:
#' "a deterministic hash over the canonicalized, concatenated content of
#' everything that would go into `inputs_snapshot/`." A future run-lifecycle
#' caller (Phase 3) supplies one entry per input table actually used (e.g.
#' one entry per selected named set, plus `use_patterns.csv`); this function
#' does not know or care what those entries represent.
#'
#' **Order independence.** `tables` may be assembled in any order -- entries
#' are sorted by name before hashing, so two calls with the same named
#' tables in a different list order always produce the same hash (this is
#' the specific property `run_lifecycle_and_validation.md` §2 requires:
#' hashes must not depend on "incidental factors like file-write order").
#'
#' **Why names are part of the hash.** Each table's canonical string is
#' prefixed with its slot name as a structural label, not as a
#' human-readable description -- this prevents two different slots (e.g. a
#' `seeding_set` and a `receptor_set`) that happen to canonicalize to the
#' same table content from being hashed identically to the case where only
#' one of them held that content. It also means renaming a slot (with
#' unchanged table content) does change the hash -- this is a deliberate,
#' documented choice, not an oversight: which slot a piece of content is
#' filed under is part of "everything that would go into
#' `inputs_snapshot/`," not incidental metadata.
#'
#' @param tables A named list of data.frames/tibbles. Every element must
#'   have a non-empty, unique name.
#' @param algo Digest algorithm; defaults to [STBAM_CONTENT_HASH_ALGORITHM].
#' @return A single character string (the hex digest).
#' @export
stbam_content_hash <- function(tables, algo = STBAM_CONTENT_HASH_ALGORITHM) {
  if (!is.list(tables) || length(tables) == 0L) {
    stbam_abort("`tables` must be a non-empty named list of data.frames.")
  }
  nms <- names(tables)
  if (is.null(nms) || any(!nzchar(nms)) || anyNA(nms)) {
    stbam_abort("Every element of `tables` must have a non-empty name.")
  }
  if (anyDuplicated(nms) != 0L) {
    stbam_abort("`tables` names must be unique; duplicated: ",
                paste(unique(nms[duplicated(nms)]), collapse = ", "), ".")
  }

  ordered_names <- sort(nms, method = "radix")
  slots <- vapply(ordered_names, function(nm) {
    paste0("### ", nm, " ###\n", stbam_canonicalize_table(tables[[nm]]))
  }, character(1))

  combined <- paste0(
    "canonicalization_version=", STBAM_CANONICALIZATION_VERSION, "\n",
    paste(slots, collapse = "\n")
  )
  stbam_hash_string(combined, algo = algo)
}

#' Deterministic content hash over a named set of CSV files
#'
#' Convenience wrapper around [stbam_content_hash()] for the common case of
#' hashing files rather than already-loaded tables. Reads each file with
#' `readr::read_csv()` (the project's existing authoritative input format,
#' ADR-006) and delegates to [stbam_content_hash()] -- so a file's on-disk
#' byte layout (line endings, row order, incidental formatting) never
#' affects the hash, only its parsed content does.
#'
#' @param paths A named character vector of file paths. Every element must
#'   have a non-empty, unique name.
#' @param algo Digest algorithm; defaults to [STBAM_CONTENT_HASH_ALGORITHM].
#' @return A single character string (the hex digest).
#' @export
stbam_file_content_hash <- function(paths, algo = STBAM_CONTENT_HASH_ALGORITHM) {
  if (!is.character(paths) || length(paths) == 0L) {
    stbam_abort("`paths` must be a non-empty named character vector.")
  }
  nms <- names(paths)
  if (is.null(nms) || any(!nzchar(nms)) || anyNA(nms)) {
    stbam_abort("Every element of `paths` must have a non-empty name.")
  }
  missing_files <- paths[!file.exists(paths)]
  if (length(missing_files) > 0L) {
    stbam_abort("File(s) not found: ", paste(missing_files, collapse = ", "), ".")
  }

  tables <- lapply(paths, function(p) readr::read_csv(p, show_col_types = FALSE))
  names(tables) <- nms
  stbam_content_hash(tables, algo = algo)
}
