# Precompile the vignettes.
#
# Every vignette in this package talks to a live service, and the GUGiK half of
# it refuses connections from outside Poland. Evaluating them at build or check
# time would make the package unbuildable for most people and flaky for the
# rest, so they are precompiled here instead: the *.Rmd.orig sources are run
# once, by hand, against the real services, and the resulting *.Rmd carry the
# outputs as static text. `R CMD build` then only has to lay them out.
#
# Run this from the package root, with a working connection (VPN to Poland for
# anything touching geoportal.gov.pl):
#
#   source("vignettes/precompile.R")
#   precompile()
#
# Knitting needs no pandoc. Turning the results into vignette HTML at
# `R CMD build` time does; if pandoc is not on the PATH but a copy ships with
# an IDE, point R at it first, for example
#
#   Sys.setenv(RSTUDIO_PANDOC = ".../Positron/resources/app/quarto/bin/tools")
#
# It writes vignettes/*.Rmd, the figures under vignettes/figures/, and a
# GitHub-readable copy of each vignette under docs/.

precompile <- function(names = NULL, cache_dir = NULL) {
  stopifnot(dir.exists("vignettes"))
  if (!is.null(cache_dir)) options(rgeopl.cache_dir = cache_dir)

  sources <- list.files("vignettes", pattern = "\\.Rmd\\.orig$", full.names = TRUE)
  if (!is.null(names)) {
    sources <- sources[basename(sources) %in% paste0(names, ".Rmd.orig")]
  }
  if (length(sources) == 0L) stop("No .Rmd.orig sources found.")

  dir.create("docs/figures", recursive = TRUE, showWarnings = FALSE)
  .root <- setwd("vignettes")
  on.exit(setwd(.root), add = TRUE)

  for (src in basename(sources)) {
    out <- sub("\\.orig$", "", src)
    message("knitting ", src, " -> ", out)
    knitr::opts_chunk$set(fig.path = "figures/")
    # Each vignette is knitted in its own environment. knitr evaluates chunks
    # in the caller's frame by default, so a vignette that happens to define a
    # variable this function also uses would silently overwrite it -- which is
    # exactly what one of them did, replacing the saved working directory with
    # an sf object.
    knitr::knit(src, out, quiet = FALSE, envir = new.env(parent = globalenv()))
  }

  setwd(.root)
  file.copy(list.files("vignettes/figures", full.names = TRUE),
            "docs/figures", overwrite = TRUE)
  for (src in basename(sources)) {
    to_markdown(file.path("vignettes", sub("\\.orig$", "", src)))
  }
  invisible(TRUE)
}

# The knitted .Rmd is already static, so a GitHub-readable copy is just the
# same file without the vignette front matter.
to_markdown <- function(rmd) {
  x <- readLines(rmd, warn = FALSE)
  ends <- which(x == "---")
  if (length(ends) >= 2L) {
    yaml <- x[(ends[1] + 1L):(ends[2] - 1L)]
    title <- sub('^title:\\s*"?(.*?)"?\\s*$', "\\1", grep("^title:", yaml, value = TRUE)[1])
    x <- x[-(ends[1]:ends[2])]
    x <- c(paste("#", title), "", x)
  }
  out <- file.path("docs", sub("\\.Rmd$", ".md", basename(rmd)))
  writeLines(x, out)
  message("wrote ", out)
  invisible(out)
}
