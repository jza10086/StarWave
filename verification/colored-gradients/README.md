# Colored-gradient restoration, 2026-10-27

Godot 4.7.2 Compatibility / Mesa llvmpipe. All 244 headless regression checks pass.
Actual rendering covers 1440×960, 1920×1080, 800×1000 and 960×640 / 84 motion frames.
The render test samples actual cached SVG texture pixels, requiring > 0.12 interior
brightness span and > 24 distinct interior levels for each sampled large polygon.
It also checks opaque collision-radius coverage, antialiased edges, mipmaps, cache
bounds and start/pause/resume/restart/focus-loss/bomb behavior.

Root cause was the previous art decision, not gameplay: removing all colored frames
and replacing deep colors with low-contrast opaque pastel fills flattened apparent
gradients. Restore independently graded colored rims and deeper color stops; make
SVG fill coordinates explicit in pixel space for unambiguous rendering. No black
stroke, nearest-neighbor sampling, gameplay changes or third-party assets added.

Visual review: official SHOOPER NOVA screenshots 0 and 1 compared against old and
new real renders; final wide, portrait, small frames and 3× edge crops reviewed.
Hit flash stays violet instead of desaturating Boss armor to gray. Thin rim remains
inside the original silhouette; opaque bullet radius and 4 px player hit radius
unchanged. Original game_core.gd SHA-256 remains
0cdb941cc87c4cbf3b0a616b7fb5ed1cca67d395d073a360af00dcddd817d17a.

Preview PNG/GIF are actual engine captures delivered separately, not repo source
packages. Source is Git only; no ZIP generated. Software-renderer timings do not
predict hardware performance; see capture.log for measured environment/results.
