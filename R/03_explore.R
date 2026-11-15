# 03_explore.R — QA: totals, holes, top cells, 2D map, histogram -> output/qa/
# Run: Rscript R/03_explore.R

source("R/config.R")
suppressPackageStartupMessages({ library(sf); library(terra); library(dplyr); library(ggplot2) })

r     <- rast(F_DENSITY)
be    <- st_read(F_MASK, layer = "belgium", quiet = TRUE)
munis <- st_read(F_MASK, layer = "municipalities", quiet = TRUE)
cells <- st_read(F_CELLS, quiet = TRUE)

px_km2 <- (RES / 1000)^2
v <- values(r, mat = FALSE)
report <- c()
add <- function(...) { line <- sprintf(...); message(line); report <<- c(report, line) }

# ---- totals ---------------------------------------------------------------
tot_r <- sum(v, na.rm = TRUE) * px_km2
add("Raster population:            %s", format(round(tot_r), big.mark = ","))
add("Grid population (sum MS_POP): %s", format(sum(cells$ms_pop), big.mark = ","))
add("Statbel official 1 Jan 2025:  %s  (grid covers %.3f%%; %s not placed on grid)",
    format(STATBEL_TOTAL, big.mark = ","), 100 * tot_r / STATBEL_TOTAL,
    format(STATBEL_TOTAL - round(tot_r), big.mark = ","))
stopifnot(abs(tot_r - STATBEL_TOTAL) / STATBEL_TOTAL < 0.005)

add("Land pixels: %s (%.1f km2); zero-pop pixels: %.1f%%",
    format(sum(!is.na(v)), big.mark = ","), sum(!is.na(v)) * px_km2, 100 * mean(v[!is.na(v)] == 0))

# ---- holes: NA pixels whose centre lies inside the Belgium outline -----------
inside <- rasterize(vect(be), r, touches = FALSE)
holes  <- sum(is.na(v) & !is.na(values(inside, mat = FALSE)))
add("NA pixels inside Belgium outline (holes): %d", holes)

# ---- distribution (area-weighted = per pixel) ----------------------------------
q <- quantile(v[!is.na(v) & v > 0], c(.01, .05, .25, .5, .75, .9, .95, .99, .995, .999, .9999, 1))
add("Pixel density quantiles (inh/km2, >0): %s",
    paste(sprintf("%s=%s", names(q), format(round(q), big.mark = ",")), collapse = "  "))

# ---- top-20 densest pixels with municipality ------------------------------------
top_i  <- order(v, decreasing = TRUE)[1:20]
top_xy <- xyFromCell(r, top_i)
top_pt <- st_as_sf(data.frame(top_xy, density = v[top_i]), coords = c("x", "y"), crs = 3035)
top_pt <- st_join(top_pt, munis[, c("tx_munty_descr_nl", "tx_munty_descr_fr")])
top_tbl <- top_pt |> st_drop_geometry() |>
  mutate(x = top_xy[, 1], y = top_xy[, 2], density = round(density))
print(top_tbl)
write.csv(top_tbl, file.path(PATHS$qa, "top20_pixels.csv"), row.names = FALSE)
add("Top-20 municipalities: %s", paste(unique(top_tbl$tx_munty_descr_fr), collapse = ", "))

# ---- most populous municipalities (from the raster) as a plausibility check ----
mz <- terra::extract(r, vect(munis), fun = sum, na.rm = TRUE)
munis$pop <- mz$density * px_km2
top_m <- munis |> st_drop_geometry() |> arrange(desc(pop)) |> head(10) |>
  mutate(pop = round(pop))
print(top_m)
add("Most populous municipalities: %s",
    paste(sprintf("%s %s", top_m$tx_munty_descr_nl, format(top_m$pop, big.mark = ",")), collapse = "; "))

# ---- 2D QA map (log scale) --------------------------------------------------------
png(file.path(PATHS$qa, "qa_map_log.png"), width = 2400, height = 2050, res = 200)
par(mar = c(1, 1, 3, 1))
lr <- log10(r + 1)
plot(lr, col = hcl.colors(100, "Inferno"), axes = FALSE, legend = TRUE,
     main = "QA: log10(population density + 1), Statbel grid 1 Jan 2025, 125 m")
plot(vect(be), add = TRUE, border = "#00c0ff", lwd = 0.6)
dev.off()

# ---- histogram ---------------------------------------------------------------------
dfh <- data.frame(d = v[!is.na(v) & v > 0])
p <- ggplot(dfh, aes(d)) + geom_histogram(bins = 120, fill = "#c0504d") +
  scale_x_log10(labels = scales::label_comma()) +
  labs(title = "Pixel density distribution (125 m pixels, >0)", x = "inhabitants / km²", y = "pixels") +
  theme_minimal()
ggsave(file.path(PATHS$qa, "qa_hist.png"), p, width = 8, height = 4.5, dpi = 150)

writeLines(report, file.path(PATHS$qa, "qa_report.txt"))
message("QA written to ", PATHS$qa)
