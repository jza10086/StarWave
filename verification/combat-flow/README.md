# Actual renderer evidence

Run with Godot 4.7.2 Compatibility on a display (not `--headless`):

```
CAPTURE_DIR=/tmp/starwave-flow godot --path . --rendering-method gl_compatibility --audio-driver Dummy --script res://tests/capture_flow.gd
CAPTURE_DIR=/tmp/starwave-flow/no-warning godot --path . --rendering-method gl_compatibility --audio-driver Dummy --script res://tests/capture_no_warning.gd
```

`capture_flow.gd` renders 1440×960 role staging, 1920×1080 Boss, 800×1000 portrait and 960×640 small-window views. The 240 animation frames at 12 fps represent 20 seconds of actual deterministic simulation: 8 seconds of the three staged roles, then 12 seconds of Boss phase 2. The scene cut is deliberate; it is not an uninterrupted level playthrough. Capture pilot uses normal movement; no invulnerability or collision overrides, but gallery setup and Boss selection use debug entry points. Full-level normal-rule results are documented separately in `verification/flow/`.

Pause/resume/restart and bounded glyph cache checks run with the actual rendering layer. `capture_no_warning.gd` compares rendered pixels with internal lock/wait fields toggled: these fields must not produce visible warning overlays.

Enemy banking comes directly from simulation rotation. Hostile straight wakes are now straight and sized by actual travel during the last 0.36 seconds; delayed acceleration uses the same integrated distance as physics. Curved wakes reconstruct real circular-arc-then-tangent positions over at most 0.55 seconds, with twelve feathered segments. A crescent projectile has a radius-sized filled collision disc; the thin outer crescent is explicitly non-colliding decoration. The geometry remains colored, translucent, anti-aliased and bounded in complexity.

Captured with Mesa llvmpipe software OpenGL; capture throughput is not gameplay frame-rate evidence. The V-Sync support warning is renderer/platform-specific, not a script failure.

Final result (2026-10-27): **253/253** capture checks and **15/15** no-warning pixel comparisons passed. Actual frames remained in normal `playing` state with 3 lives; 144 of 240 frames had measurable entity translation (stationary attack/rest windows intentionally contribute no translation). Glyph texture cache: 23 entries, below the 128 bound. GIF decoding confirmed 240 frames, 960×640, total 20,000 ms (11,882,650 bytes). Static final Boss preview is the 1920×1080 7.25-second capture; the slow crescent cores, medium arc rounds and fine needles are visible together.
