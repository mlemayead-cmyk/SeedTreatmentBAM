# Phase 1: the new evaluation-based Shiny application shell.
#
# docs/planning/shiny_information_architecture.md §1. A separate app from
# the legacy override-based application (app/app.R, R/shiny/4*.R) --
# ADR-020 explicitly prohibits retiring or modifying the legacy app at any
# Phase 0-7 gate. This shell only ever shows the picker screen (ADR-014) or
# one open evaluation's Inputs workspace (R/shiny/53_*); it has no
# runs/results/tables/figures navigation yet, per Phase 1's explicit scope
# boundary (implementation_phases_proposal.md Phase 1: "an evaluation
# created in this phase has valid, editable inputs and nothing else yet").

#' @noRd
stbam_evaluations_ui <- function() {
  bslib::page_fluid(
    theme = bslib::bs_theme(version = 5, preset = "flatly"),
    shiny::titlePanel("stbam evaluations (Phase 1)"),
    shiny::uiOutput("main")
  )
}

#' @param evaluations_root The `evaluations/` directory.
#' @noRd
stbam_evaluations_server <- function(evaluations_root) {
  function(input, output, session) {
    picker <- mod_picker_server("picker", evaluations_root)

    workspace_evaluation_path <- shiny::reactive(picker$opened_evaluation())
    mod_evaluation_workspace_server("workspace", workspace_evaluation_path,
                                    on_back = picker$close_evaluation)

    output$main <- shiny::renderUI({
      if (is.null(picker$opened_evaluation())) {
        mod_picker_ui("picker")
      } else {
        mod_evaluation_workspace_ui("workspace")
      }
    })
  }
}

#' Launch the Phase 1 evaluations application
#'
#' @param root Project root. `evaluations/` is created as a sibling of
#'   `data/`, `R/`, `docs/` (ADR-003).
#' @param ... Passed to [shiny::shinyApp].
#' @return A Shiny app object.
#' @export
run_stbam_evaluations_app <- function(root = getOption("stbam.project_root", getwd()), ...) {
  evaluations_root <- file.path(root, "evaluations")
  shiny::shinyApp(ui = stbam_evaluations_ui(),
                  server = stbam_evaluations_server(evaluations_root), ...)
}
