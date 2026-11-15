# 02_prepare.R — Statbel variable-cell grid (1 Jan 2025) -> 125 m population-density raster
#
# Method (mass-preserving):
#   1. Rasterise the cell ID of every Statbel cell onto a 125 m template aligned to the
#      LAEA (EPSG:3035) lattice; a pixel belongs to the cell that contains its centre.
#   2. Each cell's population is spread evenly over the pixels it owns:
#         density_pixel = MS_POP / (n_pixels * 0.015625 km²)
#      For a full (unclipped) cell this equals MS_POP / MS_KM2 exactly. For cells clipped by
#      the national border it uses the pixel-approximated area, so tiny border slivers can't
#      create spurious spikes and the raster's total population equals the grid's total.
#   3. Cells too small to own a pixel centre add their population to the pixel under their
#      centroid (so nobody is dropped).
#   Pixels inside Belgium with zero population stay 0; pixels outside Belgium are NA.
#
# Run: Rscript R/02_prepare.R

source("R/config.R")
suppressPackageStartupMessages({ library(sf); library(terra); library(dplyr) })

f_grid <- list.files(file.path(PATHS$raw, SOURCES$grid$dir), pattern = "\\.sqlite$",
                     recursive = TRUE, full.names = TRUE)[1]
f_sec  <- list.files(file.path(PATHS$raw, SOURCES$sectors$dir), pattern = "\\.sqlite$",
                     recursive = TRUE, full.names = TRUE)[1]

# ---- 1. read + validate ---------------------------------------------------
log_msg("Reading grid: ", f_grid)
g <- st_read(f_grid, quiet = TRUE)
geom_col <- attr(g, "sf_column")
names(g) <- tolower(names(g))
st_geometry(g) <- tolower(geom_col)

stopifnot(
  identical(st_crs(g)$epsg, 3035L),
  all(c("x_3035", "y_3035", "ms_len", "ms_pop", "ms_km2") %in% names(g)),
  all(g$ms_len %in% c(125, 250, 500, 1000)),
  all(g$ms_pop >= 0),
  all(g$x_3035 %% 125 == 0), all(g$y_3035 %% 125 == 0),
  !anyDuplicated(paste(g$x_3035, g$y_3035))
)
g$cell_id <- seq_len(nrow(g))
tot_grid <- sum(g$ms_pop)
log_msg(sprintf("Cells: %s  population: %s  area: %.1f km2",
                format(nrow(g), big.mark = ","), format(tot_grid, big.mark = ","), sum(g$ms_km2)))
print(st_drop_geometry(g) |> group_by(ms_len) |>
        summarise(cells = n(), pop = sum(ms_pop), km2 = round(sum(ms_km2), 1),
                  clipped = sum(abs(ms_km2 - (ms_len / 1000)^2) > 1e-6)))

# geometry must lie within each cell's nominal square (sanity check on X/Y semantics)
bb <- do.call(rbind, lapply(st_geometry(g), st_bbox))
tol <- 1
bad <- which(bb[, "xmin"] < g$x_3035 - tol | bb[, "ymin"] < g$y_3035 - tol |
             bb[, "xmax"] > g$x_3035 + g$ms_len + tol | bb[, "ymax"] > g$y_3035 + g$ms_len + tol)
log_msg("Cells whose geometry leaves their nominal square: ", length(bad))
if (length(bad) > 0.001 * nrow(g)) stop("X/Y are not lower-left corners as documented")

# ---- 2. template raster aligned to the 1 km LAEA lattice ----------------------
ext_xy <- c(floor(min(bb[, "xmin"], g$x_3035) / 1000) * 1000,
            ceiling(max(bb[, "xmax"], g$x_3035 + g$ms_len) / 1000) * 1000,
            floor(min(bb[, "ymin"], g$y_3035) / 1000) * 1000,
            ceiling(max(bb[, "ymax"], g$y_3035 + g$ms_len) / 1000) * 1000)
tmpl <- rast(xmin = ext_xy[1], xmax = ext_xy[2], ymin = ext_xy[3], ymax = ext_xy[4],
             resolution = RES, crs = CRS_GRID)
log_msg(sprintf("Template: %d cols x %d rows at %d m", ncol(tmpl), nrow(tmpl), RES))

# ---- 3. cell id per pixel (pixel-centre rule) --------------------------------
v <- vect(g[, c("cell_id")])
id_r <- rasterize(v, tmpl, field = "cell_id", touches = FALSE)
ids  <- values(id_r, mat = FALSE)

npix <- tabulate(ids[!is.na(ids)], nbins = nrow(g))
px_km2 <- (RES / 1000)^2

# each pixel gets cell pop / (pixels owned by that cell * pixel area)
dens <- rep(NA_real_, ncell(tmpl))
own  <- !is.na(ids)
dens[own] <- g$ms_pop[ids[own]] / (npix[ids[own]] * px_km2)

# cells that own no pixel: add their people to the pixel under their centroid
orphans <- which(npix == 0)
lost_pop <- 0
if (length(orphans)) {
  ctr  <- st_coordinates(st_point_on_surface(st_geometry(g)[orphans]))
  cell <- cellFromXY(tmpl, ctr)
  for (k in seq_along(orphans)) {
    c_k <- cell[k]; p_k <- g$ms_pop[orphans[k]]
    if (is.na(c_k) || p_k == 0) { lost_pop <- lost_pop + p_k; next }
    dens[c_k] <- ifelse(is.na(dens[c_k]), 0, dens[c_k]) + p_k / px_km2
  }
}
log_msg(sprintf("Orphan cells (own no pixel centre): %d holding %s people; unplaceable: %s",
                length(orphans), format(sum(g$ms_pop[orphans]), big.mark = ","), lost_pop))

dens_r <- setValues(tmpl, dens)
names(dens_r) <- "density"

tot_r <- sum(dens, na.rm = TRUE) * px_km2
log_msg(sprintf("Population in raster: %s  vs grid: %s  (diff %.4f%%)",
                format(round(tot_r), big.mark = ","), format(tot_grid, big.mark = ","),
                100 * (tot_r - tot_grid) / tot_grid))
stopifnot(abs(tot_r - tot_grid) / tot_grid < 0.005)

writeRaster(dens_r, F_DENSITY, overwrite = TRUE,
            gdal = c("COMPRESS=DEFLATE", "PREDICTOR=3", "TILED=YES"))
log_msg("Wrote ", F_DENSITY)

# keep cell attributes (for QA / top-cell lookup)
st_write(g, F_CELLS, delete_dsn = TRUE, quiet = TRUE)

# ---- 4. Belgium outline from the 2025 statistical sectors ----------------------
log_msg("Reading sectors: ", f_sec)
s <- st_read(f_sec, quiet = TRUE)
names(s) <- tolower(names(s))
st_geometry(s) <- "geometry"
s <- st_transform(s, 3035)
be <- vect(s) |> aggregate() |> st_as_sf()
be <- st_sf(name = "Belgium", geometry = st_geometry(be))
st_write(be, F_MASK, layer = "belgium", delete_dsn = TRUE, quiet = TRUE)
munis <- s |> group_by(cd_munty_refnis, tx_munty_descr_nl, tx_munty_descr_fr) |>
  summarise(.groups = "drop")
st_write(munis, F_MASK, layer = "municipalities", append = TRUE, quiet = TRUE)
log_msg(sprintf("Belgium area from sectors: %.1f km2; wrote %s", as.numeric(st_area(be)) / 1e6, F_MASK))
log_msg("Done.")
