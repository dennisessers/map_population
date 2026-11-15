# 01_download.R — fetch Statbel open data into data/raw/<dataset>/, unzip, write MANIFEST.csv
# Run: Rscript R/01_download.R  [--force]

source("R/config.R")
force <- "--force" %in% commandArgs(trailingOnly = TRUE)
options(timeout = 1800)

manifest <- list()
for (nm in names(SOURCES)) {
  s    <- SOURCES[[nm]]
  dir  <- file.path(PATHS$raw, s$dir)
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  dest <- file.path(dir, utils::URLdecode(basename(s$url)))

  if (force || !file.exists(dest)) {
    log_msg("Downloading ", nm, " <- ", s$url)
    utils::download.file(s$url, dest, mode = "wb", method = "libcurl", quiet = TRUE)
  } else {
    log_msg("Already present: ", dest)
  }

  if (grepl("\\.zip$", dest, ignore.case = TRUE)) {
    exdir <- file.path(dir, "unzipped")
    if (force || !dir.exists(exdir)) utils::unzip(dest, exdir = exdir)
    log_msg("  contents: ", paste(list.files(exdir, recursive = TRUE), collapse = ", "))
  }

  manifest[[nm]] <- data.frame(
    dataset    = nm,
    url        = s$url,
    file       = dest,
    bytes      = file.size(dest),
    sha256     = digest::digest(file = dest, algo = "sha256"),
    downloaded = format(file.mtime(dest), "%Y-%m-%d %H:%M:%S")
  )
}

manifest <- do.call(rbind, manifest)
utils::write.csv(manifest, file.path(PATHS$raw, "MANIFEST.csv"), row.names = FALSE)
print(manifest[, c("dataset", "bytes", "sha256")])
log_msg("Wrote ", file.path(PATHS$raw, "MANIFEST.csv"))
