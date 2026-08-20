# Word export using officer and flextable.
#
# Tables are generated directly from canonical results so that no copy and
# paste step is required, and so the Word output cannot drift from the
# dashboard.

#' Word output style settings
#' @export
STBAM_WORD_STYLE <- list(
  font_family = "Calibri",
  font_size = 9,
  header_font_size = 9,
  title_font_size = 11,
  note_font_size = 8,
  header_fill = "#D9E2F3",
  border_colour = "#7F7F7F"
)

#' @noRd
stbam_flextable <- function(data, title, notes = character(),
                            style = STBAM_WORD_STYLE) {
  if (!requireNamespace("flextable", quietly = TRUE)) {
    stbam_abort("The 'flextable' package is required for Word export.")
  }
  ft <- flextable::flextable(as.data.frame(data, stringsAsFactors = FALSE))
  ft <- flextable::set_caption(ft, caption = title)
  ft <- flextable::font(ft, fontname = style$font_family, part = "all")
  ft <- flextable::fontsize(ft, size = style$font_size, part = "body")
  ft <- flextable::fontsize(ft, size = style$header_font_size, part = "header")
  ft <- flextable::bold(ft, part = "header")
  ft <- flextable::bg(ft, bg = style$header_fill, part = "header")
  ft <- flextable::border_outer(
    ft, part = "all",
    border = officer::fp_border(color = style$border_colour, width = 1)
  )
  ft <- flextable::border_inner_h(
    ft, part = "body",
    border = officer::fp_border(color = "#BFBFBF", width = 0.5)
  )
  ft <- flextable::border_inner_v(
    ft, part = "all",
    border = officer::fp_border(color = "#BFBFBF", width = 0.5)
  )
  ft <- flextable::align(ft, align = "left", part = "all")
  ft <- flextable::valign(ft, valign = "center", part = "all")
  ft <- flextable::padding(ft, padding = 3, part = "all")

  if (length(notes) > 0L) {
    for (note in rev(notes)) {
      ft <- flextable::add_footer_lines(ft, values = note)
    }
    ft <- flextable::fontsize(ft, size = style$note_font_size, part = "footer")
    ft <- flextable::font(ft, fontname = style$font_family, part = "footer")
    ft <- flextable::italic(ft, part = "footer")
  }

  # Repeat the header row when a table spans pages.
  ft <- flextable::set_table_properties(ft, layout = "autofit", width = 1)
  ft
}

#' @noRd
section_properties <- function(orientation) {
  if (identical(orientation, "landscape")) {
    officer::prop_section(
      page_size = officer::page_size(orient = "landscape"),
      type = "nextPage",
      page_margins = officer::page_mar(top = 0.7, bottom = 0.7, left = 0.7,
                                       right = 0.7)
    )
  } else {
    officer::prop_section(
      page_size = officer::page_size(orient = "portrait"),
      type = "nextPage",
      page_margins = officer::page_mar()
    )
  }
}

#' @noRd
new_document <- function(template = NULL) {
  if (!is.null(template) && file.exists(template)) {
    officer::read_docx(path = template)
  } else {
    officer::read_docx()
  }
}

#' Export a single official table to Word
#'
#' @param table_id A name of [STBAM_TABLES].
#' @param scenario_summary Output of [build_scenario_summary].
#' @param path Destination .docx path.
#' @param template Optional reference .docx supplying styles.
#' @param caption_prefix Text placed before the table title, e.g. `"Table 21."`.
#' @return `path`, invisibly.
#' @export
export_table_docx <- function(table_id, scenario_summary, path,
                              template = NULL, caption_prefix = NULL) {
  spec <- STBAM_TABLES[[table_id]]
  if (is.null(spec)) {
    check_choice(table_id, "table_id", names(STBAM_TABLES))
  }
  data <- build_official_table(table_id, scenario_summary)
  title <- if (is.null(caption_prefix)) {
    spec$title
  } else {
    paste(caption_prefix, spec$title)
  }

  doc <- new_document(template)
  doc <- officer::body_add_par(doc, title, style = "heading 2")
  doc <- flextable::body_add_flextable(
    doc, stbam_flextable(data, title, spec$notes)
  )
  doc <- officer::body_end_block_section(
    doc, officer::block_section(section_properties(spec$orientation))
  )
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  print(doc, target = path)
  invisible(path)
}

#' Export a group of official tables to one Word document
#'
#' @param table_ids Character vector of names of [STBAM_TABLES].
#' @param scenario_summary Output of [build_scenario_summary].
#' @param path Destination .docx path.
#' @param template Optional reference .docx.
#' @param document_title Optional heading placed at the top.
#' @return `path`, invisibly.
#' @export
export_tables_docx <- function(table_ids, scenario_summary, path,
                               template = NULL, document_title = NULL) {
  check_choice(table_ids, "table_ids", names(STBAM_TABLES))
  doc <- new_document(template)
  if (!is.null(document_title)) {
    doc <- officer::body_add_par(doc, document_title, style = "heading 1")
  }
  for (table_id in table_ids) {
    spec <- STBAM_TABLES[[table_id]]
    data <- build_official_table(table_id, scenario_summary)
    doc <- officer::body_add_par(doc, spec$title, style = "heading 2")
    doc <- flextable::body_add_flextable(
      doc, stbam_flextable(data, spec$title, spec$notes)
    )
    doc <- officer::body_end_block_section(
      doc, officer::block_section(section_properties(spec$orientation))
    )
  }
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  print(doc, target = path)
  invisible(path)
}

#' Export a complete quantitative appendix
#'
#' Every official table, plus the scenario inputs and the model provenance
#' block, in one document.
#'
#' @param params An `stbam_parameter_set`.
#' @param scenario_inputs Output of [build_scenario_inputs].
#' @param scenario_summary Output of [build_scenario_summary].
#' @param path Destination .docx path.
#' @param template Optional reference .docx.
#' @return `path`, invisibly.
#' @export
export_quantitative_appendix <- function(params, scenario_inputs,
                                         scenario_summary, path,
                                         template = NULL) {
  doc <- new_document(template)
  doc <- officer::body_add_par(doc, "Quantitative appendix", style = "heading 1")
  doc <- officer::body_add_par(
    doc,
    sprintf("Generated %s from parameter set '%s'.",
            format(Sys.time(), "%Y-%m-%d %H:%M"), params$name),
    style = "Normal"
  )

  manifest <- params$baseline$source_manifest
  doc <- officer::body_add_par(doc, "Source provenance", style = "heading 2")
  doc <- flextable::body_add_flextable(
    doc,
    stbam_flextable(
      tibble::tibble(
        Workbook = manifest$file_name,
        Role = manifest$role,
        `SHA-256` = substr(manifest$sha256, 1, 24)
      ),
      "Source workbooks and hashes",
      "SHA-256 values are truncated for display. Full hashes are in data/reference/source_manifest.csv."
    )
  )

  if (has_overrides(params)) {
    doc <- officer::body_add_par(doc, "Parameter overrides applied",
                                 style = "heading 2")
    doc <- flextable::body_add_flextable(
      doc,
      stbam_flextable(
        tibble::tibble(
          Parameter = params$overrides$parameter,
          Scope = params$overrides$scope,
          `Baseline value` = fmt_sig(params$overrides$baseline_value),
          `Override value` = fmt_sig(params$overrides$value),
          Unit = params$overrides$unit,
          Status = params$overrides$status,
          Source = params$overrides$source
        ),
        "Overrides applied to the assessment baseline",
        "Results in this appendix are NOT the assessment baseline scenario."
      )
    )
  } else {
    doc <- officer::body_add_par(
      doc,
      "No parameter overrides were applied. Results reflect the assessment baseline.",
      style = "Normal"
    )
  }

  doc <- officer::body_end_block_section(
    doc, officer::block_section(section_properties("portrait"))
  )

  for (table_id in names(STBAM_TABLES)) {
    spec <- STBAM_TABLES[[table_id]]
    data <- build_official_table(table_id, scenario_summary)
    doc <- officer::body_add_par(doc, spec$title, style = "heading 2")
    doc <- flextable::body_add_flextable(
      doc, stbam_flextable(data, spec$title, spec$notes)
    )
    doc <- officer::body_end_block_section(
      doc, officer::block_section(section_properties(spec$orientation))
    )
  }

  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  print(doc, target = path)
  invisible(path)
}
