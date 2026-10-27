# Choreography verification — 2026-10-27

- Godot 4.7.2 (`ed1daf0bf`), Linux; actual render uses Compatibility OpenGL / Mesa llvmpipe software renderer. XDG folders were redirected to writable workspace.
- `test_patterns.gd`: 49 checks pass. Covers roles, warning-before-shot, frozen aim, open lane, retreat cleanup, no point-blank emission, shared blade tip origins, genuinely curved velocity/position, 3-second bend then tangent, eased variable rotation, timestep equivalence, reset, and normal-input full-stage autopilot.
- Autopilot uses movement, fire and limited emergency pulse inputs only; no invulnerability, HP/power/timer edits. Landscape 1440×960 wins at120.00s with3 lives,1 pulse used; portrait1440×1800 wins at135.16s with3 lives,0 pulses used. Peak live bullets80/90 respectively. This is automated evidence, not a human playtest or universal difficulty guarantee.
- Comparing31 integration steps at10Hz with372 at120Hz across the3.0s arc/tangent boundary yields0.00973160937428px difference. Repeated float32 Vector2 velocity rotations/position accumulation explain this subpixel drift. Threshold is0.02px (<0.5% of the4px player hit radius); normal30/120Hz simulation paths are separately checked within0.001px because core subdivides both into120Hz ticks.
- Updated prior assumptions rather than disabling coverage: `test_fullwidth_core`51 pass (teaching singles stay central, mixed formations span width; aimed fire waits for its cue), `test_independent_review`40 pass (ring inspected after its scheduled beat rather than demanding old random-style firing by3s).
- `capture_patterns.gd`:155 checks pass, actual1920×1080 and800×1000 screenshots, input pause/resume/restart, bounded23-entry shape cache,144 actual simulation/render frames at960×640. GIF contains144 frames /12fps /12 seconds; no interpolated or generated animation.
- New-enemy still is explicitly a staged three-role gallery using normal movement and attack logic. Boss motion is a continuous phase2 debug-start demonstration with real simulation and dodging.
- Rendering succeeded with only the expected software-driver V-Sync warning. Performance depends on hardware; these checks do not promise a fixed frame rate.

Reproduce:

```sh
godot --headless --path . --script res://tests/test_patterns.gd
godot --headless --path . --script res://tests/test_fullwidth_core.gd
godot --headless --path . --script res://tests/test_independent_review.gd
CAPTURE_DIR=/absolute/output godot --path . --rendering-method gl_compatibility --audio-driver Dummy --script res://tests/capture_patterns.gd
```
