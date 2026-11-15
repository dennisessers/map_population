# 04_render.R — 3D population-density render with rayshader.
#
# Usage:
#   Rscript R/04_render.R stage=snapshot [palette=Tam] [camera=A] [height=cap] [tag=x]
#   Rscript R/04_render.R stage=draft    ...
#   Rscript R/04_render.R stage=final    ...
# Any LOOK/RENDER key from config.R can be overridden as key=value.

source("R/config.R")
options(rgl.useNULL = TRUE)   # headless: the rgl scene is built in memory only
suppressPackageStartupMessages({ library(terra); library(rayshader); library(rayrender); library(MetBrewer) })

# ---- arguments -----------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
kv <- setNames(sub("^[^=]+=", "", args), sub("=.*$", "", args))
opt <- function(key, default) if (!is.na(kv[key])) type.convert(kv[[key]], as.is = TRUE) else default

stage    <- opt("stage", "snapshot")
camera   <- opt("camera", "A")
palette  <- opt("palette", LOOK$palette)
pal_dir  <- opt("palette_dir", LOOK$palette_dir)
height   <- opt("height", "cap")            # linear | cap | sqrt
cap_val  <- opt("cap", 60000)               # inh/km2, used when height = cap
peak     <- opt("peak", LOOK$peak_frac)
upsample <- opt("upsample", 2L)
samples  <- opt("samples", RENDER[[if (stage == "final") "final" else "draft"]]$samples)
width    <- opt("width",  RENDER[[if (stage == "final") "final" else "draft"]]$width)
height_px<- opt("height_px", RENDER[[if (stage == "final") "final" else "draft"]]$height)
tag      <- opt("tag", "")
cam      <- CAMERAS[[camera]]
for (k in c("theta", "phi", "zoom", "fov")) cam[[k]] <- opt(k, cam[[k]])

out_dir <- if (stage == "final") PATHS$final else PATHS$drafts
stem <- sprintf("%s_%s_%s_%s_up%d%s", stage, palette, camera, height, upsample,
                if (nzchar(tag)) paste0("_", tag) else "")
log_msg("Stage=", stage, " palette=", palette, " camera=", camera, " height=", height,
        " theta/phi/zoom=", cam$theta, "/", cam$phi, "/", cam$zoom)
if (stage == "final") keep_awake()

# ---- data -> matrices ------------------------------------------------------
r <- rast(F_DENSITY)
r <- trim(r)                                   # drop all-NA margins
dens <- raster_to_matrix(r, verbose = FALSE)   # rayshader orientation

# height transform (colour is always mapped on the untransformed density)
h <- switch(height,
  linear = dens,
  cap    = pmin(dens, cap_val),
  sqrt   = sqrt(dens),
  stop("unknown height transform: ", height))
n_capped <- if (height == "cap") sum(dens > cap_val, na.rm = TRUE) else 0
if (n_capped) log_msg("Pixels above cap (", cap_val, "): ", n_capped)

# colour index: 0 = unpopulated, 1..255 = log10 density clamped to quantiles of populated pixels
pos   <- dens[!is.na(dens) & dens > 0]
lims  <- log10(quantile(pos, LOOK$col_q, names = FALSE))
idx   <- (log10(pmax(dens, 1e-9)) - lims[1]) / diff(lims)
idx   <- 1 + round(254 * pmin(pmax(idx, 0), 1))
idx[!is.na(dens) & dens == 0] <- 0
log_msg(sprintf("Colour range: %.0f – %.0f inh/km2", 10^lims[1], 10^lims[2]))
meta <- list(lims = lims, palette = palette, pal_dir = pal_dir, height = height, cap = cap_val,
             n_capped = n_capped, col_q = LOOK$col_q, camera = cam, peak = peak, upsample = upsample)

# nearest-neighbour upsampling -> crisp vertical walls instead of tent-shaped peaks
if (upsample > 1) {
  k  <- matrix(1, upsample, upsample)
  h  <- kronecker(h, k)
  idx <- kronecker(idx, k)
}

# vertical scale: tallest column = peak * map width (in pixel units)
zscale <- max(h, na.rm = TRUE) / (peak * max(dim(h)))
log_msg(sprintf("Matrix %d x %d, zscale %.2f", nrow(h), ncol(h), zscale))

# ---- plinth instead of NA ---------------------------------------------------------
# plot_3d() silently disables mesh triangulation when the heightmap contains NA, which made
# the mesh ~30 M triangles (~20 GB RAM). Instead, everything outside Belgium becomes a flat
# white plate one plinth-height below the map, lying flush on the (white) ground plane, so it
# is invisible; a 1-pixel dark ring just outside the border gives the plinth wall and outline.
inside <- !is.na(h)
grow <- function(m) {                     # 4-neighbour dilation of a logical matrix
  n <- m; nr <- nrow(m); nc <- ncol(m)
  n[-1, ] <- n[-1, ] | m[-nr, ]; n[-nr, ] <- n[-nr, ] | m[-1, ]
  n[, -1] <- n[, -1] | m[, -nc]; n[, -nc] <- n[, -nc] | m[, -1]
  n
}
ring <- !inside & grow(inside)
out_level <- -LOOK$plinth * zscale
h[!inside] <- out_level

# texture: 0 = outside (white = ground albedo), 1 = plinth ring, 2 = unpopulated land,
#          3..257 = palette
pal  <- met.brewer(palette, 255, type = "continuous", direction = pal_dir)
base_col <- pal[255]
idx  <- idx + 2
idx[!inside] <- 0
idx[ring]    <- 1
tex  <- height_shade(idx, texture = c("#FFFFFF", base_col, LOOK$ground0, pal), range = c(0, 257))
rm(inside, ring); invisible(gc())

# ---- scene ------------------------------------------------------------------
t0 <- Sys.time()
plot_3d(tex, h, zscale = zscale, solid = FALSE,
        shadow = TRUE, shadowdepth = out_level - 0.05 * zscale,   # = the ground plane, just below the plate
        shadowcolor = LOOK$background, shadow_darkness = 0.5,
        background = LOOK$background, windowsize = RENDER$window,
        theta = cam$theta, phi = cam$phi, zoom = cam$zoom, fov = cam$fov,
        triangulate = TRUE, max_error = RENDER$max_error, verbose = FALSE)
log_msg(sprintf("plot_3d built in %.1f s", as.numeric(difftime(Sys.time(), t0, units = "secs"))))
render_camera(theta = cam$theta, phi = cam$phi, zoom = cam$zoom, fov = cam$fov)

# the scene now lives inside rgl; release the large matrices before path tracing
rm(r, dens, h, idx, tex, pos); invisible(gc())

f_out <- file.path(out_dir, paste0(stem, ".png"))
saveRDS(meta, sub("\\.png$", "_meta.rds", f_out))   # read by 05_annotate.R for the legend

if (stage == "snapshot") {
  render_snapshot(f_out, software_render = TRUE, width = 1600, height = 900,
                  background = LOOK$background, plot = FALSE)
} else {
  t0 <- Sys.time()
  # warm low key light from the WSW (0 = north, 90 = east) casting long shadows away from the
  # camera, plus a uniform ambient sky in the background colour as soft fill
  render_highquality(
    filename        = f_out,
    samples         = samples,
    sample_method   = "sobol_blue",
    width           = width,
    height          = height_px,
    lightdirection  = opt("light_dir", 240),
    lightaltitude   = opt("light_alt", 28),
    lightintensity  = opt("light_int", 250),
    lightcolor      = "#FFF1DD",
    lightsize       = opt("light_size", NULL),
    ground_material = rayrender::diffuse(color = opt("ground_col", "#FFFFFF")),
    ground_size     = 1e6,
    clamp_value     = 10,
    min_variance    = 0,
    ambient_light   = TRUE,   # uniform grey sky = soft fill; the ground hides it from view.
    backgroundhigh  = opt("amb_col", "#9C9C9C"),   # Rendered dim on purpose: 05_annotate maps
    backgroundlow   = opt("amb_col", "#9C9C9C"),   # the lit ground to the exact background colour.
    denoise         = TRUE,
    plot            = FALSE,
    preview         = FALSE,
    interactive     = FALSE,
    progress        = stage == "final"
  )
  log_msg(sprintf("render_highquality done in %.1f min",
                  as.numeric(difftime(Sys.time(), t0, units = "mins"))))
}
rgl::close3d()
log_msg("Wrote ", f_out)
peak_mem <- tryCatch(system2("powershell", c("-NoProfile", "-Command",
  sprintf("[math]::Round((Get-Process -Id %d).PeakWorkingSet64/1GB,2)", Sys.getpid())), stdout = TRUE),
  error = function(e) NA)
log_msg("Peak memory of this R process: ", peak_mem, " GB")
