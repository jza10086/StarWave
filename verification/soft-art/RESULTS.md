# No-outline soft artwork verification

Godot 4.7.2, Compatibility / OpenGL, 2026-10-27.

- 244 headless assertions, 0 failures across seven suites.
- 58 real-render / input assertions, 0 failures. Includes start, pause, resume, restart, focus-loss pause, precise hitpoint, bomb clearing and Boss phases; 1440×960, 1920×1080, 800×1000 and 960×640 output.
- Inspected actual renders and enlarged edge crops. Filled pastel silhouettes and smooth shaded round bullet bodies have no contour stroke, black border or stacked armor rings. Transparent RGB padding prevents dark mipmap fringes. Background stars are filtered continuous discs.
- Full-window adaptive field and compact HUD retained. `game_core.gd` is unchanged from e70b6f8 (blob c9fbd62ae04941a182ab09657de5d38d0876d3c4).
- 84 actual motion frames captured at 12 fps (7 seconds), no mockups/compositing. The player takes one hit in this recording; normal invulnerability animation remains intact.
- Texture cache remains at 23 entries after motion and resizing; texture size, mipmaps, transparent edges, antialiased coverage and full collision-radius body coverage checked.

## Performance scope

A fixed 138-projectile Boss scene at 1920×1080 on this shared CPU-only llvmpipe renderer measured median 58.143 ms, mean 128.454 ms, p95 750.041 ms over 60 rendered frames after 30 warm-up frames. This shared environment showed large scheduling outliers; these are observations, not a hardware FPS guarantee. There is no full-screen blur/bloom chain and no per-moving-entity texture allocation after cache warm-up. Native GPU performance has not been measured.

The real renderer emits a V-Sync-not-supported warning on this virtual display. No script/render assertions failed.
