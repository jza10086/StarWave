# Transparent energy-symbol verification — 2026-10-27

Godot 4.7.2, Compatibility renderer, Mesa llvmpipe software renderer.

- 260 headless checks / 0 failures: core 34, independent logic 40, UI 23, full-width 52, geometric 25, gradient sampling 20, no-black/smooth geometry 41, energy material/invariants 25.
- Existing `game_core.gd` is byte-identical to the prior release: SHA-256 `0cdb941cc87c4cbf3b0a616b7fb5ed1cca67d395d073a360af00dcddd817d17a`. No collision, input, movement, pattern, or rule changes.
- 126 real render/pixel/input/resource checks / 0 failures; 84 motion frames saved.
- Real rendered captures cover 1440×960, 1920×1080, 800×1000 and 960×640, ordinary waves, Boss, precise focus, pause, resume, restart, application focus loss and bomb clearing. PNG/GIF evidence remains outside the source repository; no ZIP produced or changed.
- Real texture checks require transparent colored planes, bright rims, nonblack transparent padding, antialiased coverage and mipmaps. The old opaque volume-shading assertion was intentionally replaced; all gameplay assertions are retained.
- Ribbon construction is bounded to 12 sample intervals and 4 alpha-interpolated strips per visible projectile. No trajectory histories or per-frame texture generation. Offscreen shots/bullets are culled before ribbon drawing. Shape caches are palette/local-geometry keyed and reused.
- Fixed 1080p scene with 138 hostile bullets: cache 27 entries, object delta -2, static-memory delta +716 bytes over the measurement window. These are bounded sample observations, not proof of infinite-run memory behavior.
- Software-render sample (120 frames after 30 warmup frames): mean 100.2 ms, median 98.7 ms, p95 137.5 ms. The first unoptimized redesign measured mean 173.7 ms. The preceding colored-gradient version's historical run measured mean 61.8 ms; added ribbons cost more rendering work. Runs are noisy environment-specific observations, not a controlled cross-hardware benchmark or a fixed-FPS promise.
- Independent visual review checked actual final landscape pixels against official reference pixels before publication. Source art remains original and vertical-STG gameplay is unchanged.

Run headless scripts as documented in README, plus `tests/test_energy_art.gd`.
For actual renderer checks, set `CAPTURE_DIR` to a writable output directory and run `tests/capture_energy.gd` under an available X display with Compatibility rendering. This script saves 84 animation frames at a 12 fps playback cadence, checks resource counts and logs software timing.
