# map_population — 3D population-density map of Belgium

A very detailed, path-traced 3D map of where Belgium's 11.8 million people live. It is built from
Statbel's 125 m-to-1 km population grid (1 January 2025) with R + rayshader. See README.md for the data,
method and how to reproduce it.

## Status
_Work in progress, last updated 2026-11-15._

## How we got here (chronological)

1. **Plan (2026-11-15).** You chose:
   - Statbel's *variable-cell grid 2025* used as published. It was the newest grid on 15 Nov 2026;
     the 1 Jan 2026 numbers exist only per statistical sector.
   - R + rayshader.
   - A high-quality digital image (not print), in a "bold colour on light" style.
2. **Environment.**
   - R 4.6.2 installed via winget; packages go to the per-user library (`%LOCALAPPDATA%\R\win-library\4.6`).
   - Windows **Smart App Control is on**. On first load it blocked `proxy.dll` ("An Application
     Control policy has blocked this file"). Loading the packages one at a time a few minutes later
     worked, presumably once the reputation check had finished. If a package DLL is blocked again,
     load it once on its own and retry.
   - `Rscript -e` with **multi-line** code segfaults (exit 139) before running anything on this
     machine. Always use script files.
3. **Data and QA.**
   - 124,669 cells; 11,817,897 people (99.935% of the official 11,825,551).
   - Rasterised to 125 m without losing anyone (see README).
   - Municipality totals and the locations of the densest pixels check out.
4. **Look development.**
   - Software snapshots, then path-traced drafts (~2 min each, mostly scene setup).
   - Fixes along the way:
     - `render_highquality` only adds a ground plane when `plot_3d(shadow = TRUE)`.
     - The background went black until `ambient_light = TRUE`.
     - The first renders were overexposed. Fixed by rendering dim with a grey ambient fill, then
       applying a flat-field and white-balance step in post (05_annotate.R).
     - The colour clamp was raised to the 25th–99.9th percentile to calm the rural mosaic.
     - Heights stay linear; 8 pixels above 60k/km² are capped.
5. **Memory incident and fix.**
   - Claude Code stopped a background palette run because the PC ran critically low on memory.
     A single draft peaked at **19.6 GB**.
   - Cause: `plot_3d()` silently turns **triangulation off when the heightmap has NA values**
     (outside Belgium), so the full ×2 mesh (~30M triangles) went through rgl, OBJ and rayrender.
   - Fix: the outside is no longer NA. It becomes a flat white plate one plinth-height down, lying
     flush on the white ground plane so it can't be seen. A 1-px dark ring along the border gives
     the plinth wall and outline. With `max_error = 1` inh./km² the mesh is 1.7M triangles.
   - Result: peak about 6.5 GB, and path tracing in seconds instead of minutes.
6. **Palette.** Compared Tam, OKeeffe2, Hokusai2 and Greek (reversed) at identical settings
   (`output/drafts/palette_comparison.png`). You chose **Tam**.
