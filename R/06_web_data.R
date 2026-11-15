# 06_web_data.R — export the Statbel cells for the interactive three.js viewer (web/).
#
# Writes web/data/be_cells.json:
#   cells: base64 typed arrays, one entry per populated cell
#     x0, y0, w, h : Uint16, the cell's rectangle in 12.5 m units from the grid origin (EPSG:3035).
#                    Full cells are their square; cells clipped by the border use the bounding
#                    box of the clipped shape.
#     pop          : Uint16, residents (MS_POP)
#     muni         : Uint16, index into `munis`
#     dens         : Float32, official density MS_POP / MS_KM2 (shown in the tooltip)
#   The column height uses pop / rectangle area, so each column's volume = its population.
#   outline: Belgium (2025 sectors dissolved, simplified to ~50 m), same 12.5 m units
#   munis, cities, palette (the 255 Tam colours of the render), colour limits, height cap.
#
# Run: Rscript R/06_web_data.R

source("R/config.R")
suppressPackageStartupMessages({ library(sf); library(dplyr); library(jsonlite); library(MetBrewer) })

meta <- readRDS(file.path(PATHS$final, "final_Tam_A_cap_up2_meta.rds"))
cells <- st_read(F_CELLS, quiet = TRUE)
be    <- st_read(F_MASK, layer = "belgium", quiet = TRUE)
munis <- st_read(F_MASK, layer = "municipalities", quiet = TRUE)

ORIGIN <- c(x = floor(min(cells$x_3035) / 1000) * 1000, y = floor(min(cells$y_3035) / 1000) * 1000)
U <- 12.5   # metres per unit: every Statbel cell edge (multiples of 125 m) is an exact integer

cells <- cells[cells$ms_pop > 0, ]
log_msg("Populated cells: ", nrow(cells))

bb <- do.call(rbind, lapply(st_geometry(cells), st_bbox))
x0 <- round((bb[, "xmin"] - ORIGIN["x"]) / U); y0 <- round((bb[, "ymin"] - ORIGIN["y"]) / U)
w  <- pmax(1, round((bb[, "xmax"] - bb[, "xmin"]) / U)); h <- pmax(1, round((bb[, "ymax"] - bb[, "ymin"]) / U))
stopifnot(max(x0 + w) < 65535, max(y0 + h) < 65535, max(cells$ms_pop) < 65535)

# municipality of each cell (point on surface, nearest polygon as fallback)
pts <- st_point_on_surface(st_geometry(cells))
mi  <- st_intersects(pts, munis)
mi  <- vapply(seq_along(mi), function(i) if (length(mi[[i]])) mi[[i]][1] else NA_integer_, 1L)
if (anyNA(mi)) mi[is.na(mi)] <- st_nearest_feature(pts[is.na(mi)], munis)

b64 <- function(v, type, size) gsub("\n", "", base64_enc(writeBin(v, raw(), size = size, endian = "little")), fixed = TRUE)
enc_u16 <- function(v) b64(as.integer(v), "int", 2)
enc_f32 <- function(v) b64(as.numeric(v), "double", 4)

name_of <- function(nl, fr) ifelse(nl == fr, nl, paste(nl, "/", fr))
mun_names <- name_of(munis$tx_munty_descr_nl, munis$tx_munty_descr_fr)

# outline: simplified, in 12.5 m units, rings as flat [x,y,x,y,...] integer arrays
be_s <- st_simplify(st_union(be), dTolerance = 50) |> st_cast("MULTIPOLYGON") |> st_cast("POLYGON")
rings <- lapply(st_geometry(be_s), function(poly) {
  lapply(poly, function(ring) {
    xy <- round(cbind((ring[, 1] - ORIGIN["x"]) / U, (ring[, 2] - ORIGIN["y"]) / U))
    as.integer(t(xy))
  })
})
log_msg("Outline polygons: ", length(rings), ", vertices: ", sum(sapply(rings, function(p) sum(lengths(p)) / 2)))

# city labels (WGS84 centres -> 12.5 m units)
cities <- data.frame(
  name = c("Brussel · Bruxelles", "Antwerpen", "Gent", "Charleroi", "Liège", "Brugge", "Namur",
           "Leuven", "Mons", "Hasselt", "Mechelen", "Kortrijk", "Oostende", "Genk", "Aalst",
           "Tournai", "Verviers", "Sint-Niklaas", "Arlon", "Eupen"),
  lat  = c(50.8467, 51.2194, 51.0543, 50.4108, 50.6326, 51.2093, 50.4674, 50.8798, 50.4542, 50.9307,
           51.0259, 50.8279, 51.2154, 50.9650, 50.9378, 50.6056, 50.5891, 51.1650, 49.6833, 50.6300),
  lon  = c(4.3525, 4.4025, 3.7174, 4.4446, 5.5797, 3.2247, 4.8720, 4.7005, 3.9567, 5.3378,
           4.4776, 3.2649, 2.9286, 5.5008, 4.0403, 3.3878, 5.8624, 4.1430, 5.8167, 6.0310),
  rank = c(1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3)
)
cxy <- st_coordinates(st_transform(st_as_sf(cities, coords = c("lon", "lat"), crs = 4326), 3035))
cities$x <- round((cxy[, 1] - ORIGIN["x"]) / U); cities$y <- round((cxy[, 2] - ORIGIN["y"]) / U)

pal <- as.character(unclass(met.brewer(meta$palette, 255, type = "continuous", direction = meta$pal_dir)))

out <- list(
  source  = "Statbel, population grid with cells of varying size, 1 January 2025 (CC BY 4.0)",
  origin_3035 = unname(ORIGIN), unit_m = U, n = nrow(cells),
  total_pop = sum(cells$ms_pop),
  cells = list(x0 = enc_u16(x0), y0 = enc_u16(y0), w = enc_u16(w), h = enc_u16(h),
               pop = enc_u16(cells$ms_pop), muni = enc_u16(mi - 1L), dens = enc_f32(cells$ms_pop / cells$ms_km2)),
  munis   = mun_names,
  outline = rings,
  cities  = cities[, c("name", "x", "y", "rank")],
  palette = pal,
  colour_lims = 10^meta$lims,
  height_cap = meta$cap
)
dir.create("web/data", recursive = TRUE, showWarnings = FALSE)
f <- "web/data/be_cells.json"
write_json(out, f, auto_unbox = TRUE, digits = NA)
log_msg(sprintf("Wrote %s (%.2f MB)", f, file.size(f) / 1e6))
