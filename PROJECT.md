# map_population — 3D population-density map of Belgium

A very detailed, path-traced 3D map of where Belgium's 11.8 million people live. It is built from
Statbel's 125 m-to-1 km population grid (1 January 2025) with R + rayshader. See README.md for the data,
method and how to reproduce it.

## Status
**Done (2026-11-15).** The final map is in `output/final/`:

| File | Size | In git? |
|---|---|---|
| `belgium_population_density.png` | 7680×4320 (8K master) | no (62 MB) |
| `belgium_population_density_4k.png` | 3840×2160 | no |
| `belgium_population_density_1080p.png` | 1920×1080 | yes |
| `final_Tam_A_cap_up2.png` | raw 8K render, before annotation | no |

**Final render:** Tam palette, camera A (from the south, 35°, orthographic), linear heights with a
60k/km² cap, ×2 nearest-neighbour upsampling, 256 samples, denoised. Path tracing took 44 min
with a 15.2 GB peak. The byline reads "Visualisation with Claude Code by @DennisEssers".

**Interactive 3D web version (2026-11-15):** https://claude.ai/artifact/S6bUaCYEPtcC8vsczze6wf
(a private Claude Artifact; share it from the page's Share menu).
- **Source:** `web/index.html` plus `web/data/be_cells.json` (2.6 MB), exported by `R/06_web_data.R`.
- **Rendering:** three.js 0.170 (jsDelivr importmap). Each populated cell (117,352) is one instance
  of a single `InstancedMesh` box. Clipped border cells use the bounding box of the clipped shape,
  and height = pop / rectangle area, so volume ∝ residents.
- **Scene:** the Belgium outline is extruded as a plinth. Sun shadows come from a 4096 shadow map
  (2048 on small screens).
- **Picking:** hover/tap uses a custom 1 km bin grid with a ray DDA instead of three.js
  raycasting, which would test all 117k instances.
- **Units:** coordinates are stored in 12.5 m units, so every 125 m cell edge is an exact integer.
  10 m units rounded 12.5 and left hairline gaps.

**Possible next steps (not done):**
- A slow orbit video.
- Host the web version on GitHub Pages, as for KORILIO.
- The 1 Jan 2026 sector counts, once Statbel publishes a 2026 grid.

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
7. **Final.**
   - 8K path trace: 44 min, 15.2 GB peak.
   - Annotation: the 8K flat-field takes seconds. `font_add_google()` once stalled for 10 min, so
     the fonts are now stored in `fonts/` (Playfair Display Bold, Inter Regular and Bold; SIL OFL)
     and loaded locally.
   - The map was shifted up 6% in post for balance.
   - Byline added at your request.
