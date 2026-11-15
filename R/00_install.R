# 00_install.R — install the CRAN packages this project needs and record the session.
# Run: Rscript R/00_install.R

lib <- Sys.getenv("R_LIBS_USER")
if (!dir.exists(lib)) dir.create(lib, recursive = TRUE)
.libPaths(c(lib, .libPaths()))

options(repos = c(CRAN = "https://cloud.r-project.org"))

pkgs <- c(
  "sf", "terra",                       # spatial data
  "rayshader", "rayrender", "rayvertex", "rayimage", "rgl",  # 3D + path tracing
  "MetBrewer", "scales",               # colour
  "magick", "ggplot2", "showtext", "sysfonts",  # annotation
  "dplyr", "readxl", "digest", "jsonlite"
)

missing <- setdiff(pkgs, rownames(installed.packages()))
if (length(missing)) {
  message("Installing: ", paste(missing, collapse = ", "))
  install.packages(missing, lib = lib, type = "binary", Ncpus = 8)
}

still_missing <- setdiff(pkgs, rownames(installed.packages()))
if (length(still_missing)) stop("Failed to install: ", paste(still_missing, collapse = ", "))

for (p in pkgs) suppressPackageStartupMessages(library(p, character.only = TRUE))
message("All packages load.")

dir.create("logs", showWarnings = FALSE)
writeLines(capture.output(sessionInfo()), "logs/sessionInfo.txt")
message("Wrote logs/sessionInfo.txt")
