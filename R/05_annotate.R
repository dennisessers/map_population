# 05_annotate.R — title, legend and credits over the render; export 8K / 4K / 1080p.
#
# Usage:
#   Rscript R/05_annotate.R in=output/final/final_....png [out=output/final/belgium_population_density]
# All sizes are relative to the image width, so this works on drafts and on the 8K master.

source("R/config.R")
suppressPackageStartupMessages({ library(magick); library(ggplot2); library(showtext); library(MetBrewer) })

args <- commandArgs(trailingOnly = TRUE)
kv <- setNames(sub("^[^=]+=", "", args), sub("=.*$", "", args))
f_in  <- kv[["in"]]
f_out <- if (!is.na(kv["out"])) kv[["out"]] else sub("\\.png$", "_annotated", f_in)
layout <- if (!is.na(kv["layout"])) kv[["layout"]] else "A"
meta  <- readRDS(sub("\\.png$", "_meta.rds", f_in))   # written by 04_render.R next to the render

img <- image_read(f_in)
W <- image_info(img)$width; H <- image_info(img)$height
log_msg(sprintf("Annotating %s (%d x %d)", f_in, W, H))

# ---- flat-field + white balance -----------------------------------------------------
# The render is deliberately a bit dark and has a gentle light fall-off across the ground
# plane. Fit a smooth quadratic surface per channel to the empty ground in the outer border
# band, then scale every pixel so the ground becomes exactly LOOK$background.
flatten_background <- function(img, target_hex, band = 0.07) {
  target <- as.numeric(col2rgb(target_hex))
  sm <- image_resize(img, "480x")
  a  <- as.integer(image_data(sm, "rgb"))           # h x w x 3
  h <- dim(a)[1]; w <- dim(a)[2]
  yy <- matrix(rep(seq_len(h) / h, w), h); xx <- matrix(rep(seq_len(w) / w, each = h), h)
  border  <- xx < band | xx > 1 - band | yy < band | yy > 1 - band
  lum     <- (a[, , 1] + a[, , 2] + a[, , 3]) / 3
  neutral <- (pmax(a[, , 1], a[, , 2], a[, , 3]) - pmin(a[, , 1], a[, , 2], a[, , 3])) < 14
  keep    <- border & neutral & lum > quantile(lum[border], 0.25)
  d <- data.frame(x = xx[keep], y = yy[keep])
  WW <- image_info(img)$width; HH <- image_info(img)$height
  full <- as.integer(image_data(img, "rgb")) / 255  # 0..1, HH x WW x 3
  gx <- seq_len(WW) / WW; gy <- seq_len(HH) / HH
  for (ch in 1:3) {
    d$v <- a[, , ch][keep]
    m <- lm(v ~ x + I(x^2) + y + I(y^2) + x:y, data = d)
    b <- coef(m)
    pred <- outer(gy, rep(1, WW)) * b["y"] + outer(gy^2, rep(1, WW)) * b["I(y^2)"] +
            outer(rep(1, HH), gx) * b["x"] + outer(rep(1, HH), gx^2) * b["I(x^2)"] +
            outer(gy, gx) * b["x:y"] + b["(Intercept)"]
    full[, , ch] <- pmin(full[, , ch] * (target[ch] / 255) / (pred / 255), 1)
    log_msg(sprintf("  channel %d: ground %.0f..%.0f -> %d", ch, min(pred), max(pred), target[ch]))
  }
  image_read(full)
}
img <- flatten_background(img, LOOK$background)

# Move the model up a little for a balanced composition (more room for the legend and
# credits at the bottom). The background is uniform after flat-fielding, so the freed strip
# can be filled with the background colour seamlessly.
shift_up <- if (!is.na(kv["shift_up"])) as.numeric(kv[["shift_up"]]) else 0.06
if (shift_up > 0) {
  s <- round(shift_up * H)
  img <- image_crop(img, sprintf("%dx%d+0+%d", W, H - s, s))
  img <- image_extent(img, sprintf("%dx%d", W, H), gravity = "north", color = LOOK$background)
}

# ---- fonts (Google Fonts, OFL) ----------------------------------------------------
font_ok <- function(name, family) tryCatch({ font_add_google(name, family); TRUE }, error = function(e) FALSE)
f_title <- if (font_ok("Playfair Display", "title")) "title" else "serif"
f_body  <- if (font_ok("Inter", "body")) "body" else "sans"
showtext_auto()
dpi <- 300
showtext_opts(dpi = dpi)

# px -> ggplot text size (mm)
px2size <- function(px) px * 72 / dpi / .pt
u <- W / 100   # 1 "unit" = 1% of image width

ink   <- "#2B2118"
muted <- "#6E6253"
pal   <- met.brewer(meta$palette, 255, type = "continuous", direction = meta$pal_dir)

# ---- layout ----------------------------------------------------------------------
# positions in pixel coordinates (origin bottom-left); the title block sits in the empty
# space south-west of the map (left of Hainaut), the credits bottom-right.
num <- function(key, default) if (!is.na(kv[key])) as.numeric(kv[[key]]) else default
L <- list(
  title_x = num("title_x", 4.2) * u, title_y = H * num("title_y", 0.50),
  leg_x   = num("title_x", 4.2) * u, leg_y = num("leg_y", 4.6) * u, leg_w = 17 * u, leg_h = 0.75 * u,
  cred_x  = W - 3.2 * u, cred_y = 2.6 * u
)
ts <- num("title_size", 3.6)   # title cap height-ish, in % of width
lh <- ts * 1.18                # line pitch of the stacked title

p <- ggplot() + coord_cartesian(xlim = c(0, W), ylim = c(0, H), expand = FALSE) +
  theme_void() +
  theme(plot.background = element_rect(fill = "transparent", colour = NA),
        panel.background = element_rect(fill = "transparent", colour = NA))

# title block: the country's name in its three official languages, stacked
names3 <- c("België", "Belgique", "Belgien")
for (i in seq_along(names3)) {
  p <- p + annotate("text", x = L$title_x, y = L$title_y - (i - 1) * lh * u, label = names3[i],
                    family = f_title, fontface = "bold", size = px2size(ts * u), colour = ink,
                    hjust = 0, vjust = 1)
}
y_sub <- L$title_y - 3 * lh * u - 0.9 * u
p <- p +
  annotate("segment", x = L$title_x, xend = L$title_x + 6 * u, y = y_sub + 0.35 * u,
           yend = y_sub + 0.35 * u, colour = pal[200], linewidth = max(0.4, 1.6 * W / 7680)) +
  annotate("text", x = L$title_x, y = y_sub - 0.5 * u,
           label = "Where 11.8 million people live",
           family = f_body, fontface = "bold", size = px2size(1.25 * u), colour = ink, hjust = 0, vjust = 1) +
  annotate("text", x = L$title_x, y = y_sub - 2.5 * u,
           label = "Population density on 1 January 2025,\nat up to 125 m resolution",
           family = f_body, size = px2size(0.95 * u), colour = muted, hjust = 0, vjust = 1,
           lineheight = 1.2)

# legend: colour bar on log10 scale + 'unpopulated' swatch
lims <- meta$lims
# one-row raster of the exact 255 palette colours used in the render, smoothly interpolated
bar <- as.raster(matrix(pal, nrow = 1))
p <- p + annotation_raster(bar, xmin = L$leg_x, xmax = L$leg_x + L$leg_w,
                           ymin = L$leg_y, ymax = L$leg_y + L$leg_h, interpolate = TRUE)
ticks <- c(10, 100, 1000, 10000)
ticks <- ticks[log10(ticks) >= lims[1] & log10(ticks) <= lims[2] + 1e-9]
tx    <- L$leg_x + (log10(ticks) - lims[1]) / diff(lims) * L$leg_w
p <- p +
  annotate("segment", x = tx, xend = tx, y = L$leg_y - 0.25 * u, yend = L$leg_y,
           colour = ink, linewidth = max(0.2, W / 7680)) +
  annotate("text", x = tx, y = L$leg_y - 0.55 * u,
           label = format(ticks, big.mark = ",", scientific = FALSE, trim = TRUE),
           family = f_body, size = px2size(0.95 * u), colour = ink, vjust = 1) +
  annotate("text", x = L$leg_x, y = L$leg_y + L$leg_h + 0.6 * u,
           label = "Inhabitants per km²",
           family = f_body, fontface = "bold", size = px2size(0.95 * u), colour = ink,
           hjust = 0, vjust = 0) +
  annotate("text", x = L$leg_x, y = L$leg_y - 2.1 * u,
           label = "Colour on a log scale · column height is linear, so each column's volume is proportional to its population",
           family = f_body, size = px2size(0.68 * u), colour = muted, hjust = 0, vjust = 1) +
  annotate("rect", xmin = L$leg_x + L$leg_w + 2.2 * u, xmax = L$leg_x + L$leg_w + 3.4 * u,
           ymin = L$leg_y, ymax = L$leg_y + L$leg_h, fill = LOOK$ground0,
           colour = muted, linewidth = max(0.1, W / 15000)) +
  annotate("text", x = L$leg_x + L$leg_w + 2.8 * u, y = L$leg_y - 0.55 * u, label = "0",
           family = f_body, size = px2size(0.95 * u), colour = ink, vjust = 1)

# credits
cap_note <- if (meta$height == "cap" && meta$n_capped > 0)
  sprintf(" · Column heights capped at %s inh./km² (affects %d of 1.96 million pixels)",
          format(meta$cap, big.mark = ","), meta$n_capped) else ""
credits <- paste0(
  "Data: Statbel (Statistics Belgium) · population grid with cells of varying size, 1 km to 125 m,\n",
  "reference date 1 January 2025 · CC BY 4.0",
  sub("^ · ", "\n", cap_note),
  "\nRendered with rayshader and rayrender in R · ETRS89-LAEA (EPSG:3035)")
byline <- "Visualisation with Claude Code by @DennisEssers"
p <- p +
  annotate("text", x = L$cred_x, y = L$cred_y + 1.7 * u, label = credits, family = f_body,
           size = px2size(0.68 * u), colour = muted, hjust = 1, vjust = 0, lineheight = 1.3) +
  annotate("text", x = L$cred_x, y = L$cred_y, label = byline, family = f_body,
           fontface = "bold", size = px2size(0.78 * u), colour = ink, hjust = 1, vjust = 0)

f_overlay <- file.path(tempdir(), "overlay.png")
ggsave(f_overlay, p, width = W / dpi, height = H / dpi, dpi = dpi, bg = "transparent")
ov <- image_read(f_overlay)
if (image_info(ov)$width != W) ov <- image_resize(ov, sprintf("%dx%d!", W, H))

out <- image_composite(image_background(img, LOOK$background, flatten = TRUE), ov, operator = "over")

f_main <- paste0(f_out, ".png")
image_write(out, f_main, format = "png")
log_msg("Wrote ", f_main)
if (W >= 7000) {
  image_write(image_resize(out, "3840x", filter = "Lanczos"), paste0(f_out, "_4k.png"), format = "png")
  image_write(image_resize(out, "1920x", filter = "Lanczos"), paste0(f_out, "_1080p.png"), format = "png")
  log_msg("Wrote 4K and 1080p versions")
}
