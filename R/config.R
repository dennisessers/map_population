# config.R — every tunable in one place. Sourced by all other scripts.

.libPaths(c(Sys.getenv("R_LIBS_USER"), .libPaths()))

# ---- paths ---------------------------------------------------------------
PATHS <- list(
  raw       = "data/raw",
  processed = "data/processed",
  qa        = "output/qa",
  drafts    = "output/drafts",
  final     = "output/final",
  fonts     = "fonts",
  logs      = "logs"
)
for (p in PATHS) dir.create(p, showWarnings = FALSE, recursive = TRUE)

# ---- data sources (Statbel open data, CC BY 4.0) --------------------------
STATBEL <- "https://statbel.fgov.be/sites/default/files/files/opendata"
SOURCES <- list(
  grid = list(
    dir = "grid_2025",
    url = paste0(STATBEL, "/SH_VARYING_CELL_SIZE_GRID/TF_POP_VARYING_CELL_SIZE_GRID_2025_3035.zip")
  ),
  grid_vars = list(
    dir = "grid_2025_vars",
    url = paste0(STATBEL, "/SH_VARYING_CELL_SIZE_GRID/VAR_SH_VARYING_CELL_SIZE_GRID.xlsx")
  ),
  sectors = list(
    dir = "sectors_2025",
    url = paste0(STATBEL, "/Statistische%20sectoren/sh_statbel_statistical_sectors_3812_20250101.sqlite.zip")
  )
)

REF_DATE        <- "2025-01-01"
STATBEL_TOTAL   <- 11825551   # official population of Belgium on 1 Jan 2025
CRS_GRID        <- "EPSG:3035"
RES             <- 125        # metres; the finest Statbel cell size

F_DENSITY <- file.path(PATHS$processed, "be_popdens_125m_20250101.tif")
F_MASK    <- file.path(PATHS$processed, "belgium_3035.gpkg")
F_CELLS   <- file.path(PATHS$processed, "grid_cells_2025.gpkg")

# ---- look ----------------------------------------------------------------
LOOK <- list(
  background = "#F6F1E7",       # warm off-white
  ground0    = "#E9E2D3",       # colour for zero-population land
  palette    = "Tam",           # MetBrewer; compared against OKeeffe2, Hokusai2, Greek (reversed)
  palette_dir = 1,              # 1 or -1 (reverse)
  col_q      = c(0.25, 0.999),  # quantile clamp for colour mapping (on log10 density)
  height_fun = "linear",        # "linear" or "sqrt"
  peak_frac  = 0.14,            # tallest spike as fraction of map width
  plinth     = 8                # plinth height under the map, in (upsampled) pixel units
)

# ---- camera presets (rayshader render_camera) ------------------------------
# theta: rotation around vertical axis (0 = looking from south toward north)
# phi: elevation angle above horizon; zoom < 1 = closer
CAMERAS <- list(
  A = list(theta = 0,   phi = 35, zoom = 0.50, fov = 0),
  B = list(theta = -40, phi = 32, zoom = 0.60, fov = 0),
  C = list(theta = 0,   phi = 58, zoom = 0.66, fov = 0)
)

# ---- render settings ------------------------------------------------------
RENDER <- list(
  window    = c(1600, 1000),
  draft     = list(width = 1600, height = 900,  samples = 64),
  final     = list(width = 7680, height = 4320, samples = 256),   # ~45 min, ~15 GB peak (denoised)
  max_error = 1     # mesh simplification tolerance, in inhabitants/km² (invisible at this scale)
)

# keep Windows from sleeping while a long job runs (no power settings are changed;
# the request ends with the R process)
keep_awake <- function() {
  if (.Platform$OS.type != "windows") return(invisible(FALSE))
  ps1 <- file.path(tempdir(), "keep_awake.ps1")
  writeLines(c(
    "param([int]$WatchPid)",
    "$sig = '[DllImport(\"kernel32.dll\")] public static extern uint SetThreadExecutionState(uint esFlags);'",
    "$t = Add-Type -MemberDefinition $sig -Name K -Namespace W -PassThru",
    "while (Get-Process -Id $WatchPid -ErrorAction SilentlyContinue) {",
    "  [void]$t::SetThreadExecutionState([uint32]'0x80000001')",  # ES_CONTINUOUS | ES_SYSTEM_REQUIRED
    "  Start-Sleep -Seconds 50",
    "}"
  ), ps1)
  system2("powershell", c("-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden",
                          "-File", shQuote(ps1), "-WatchPid", Sys.getpid()),
          wait = FALSE, stdout = FALSE, stderr = FALSE)
  log_msg("keep-awake helper started for PID ", Sys.getpid())
  invisible(TRUE)
}

log_msg <- function(...) message(format(Sys.time(), "%H:%M:%S"), "  ", ...)
