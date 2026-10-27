# Explicit warning removal — 2026-10-27

- Only the `_attack_cue` draw function and its call were removed. Enemy silhouettes, hit feedback, Boss blade geometry/rotation and all simulation code remain unchanged.
- Godot 4.7.2: all 308 existing headless checks passed, including deterministic aim locking, safe intervals, blade origins, curved trajectories and normal-input landscape/portrait autoplay.
- `capture_no_warning.gd`: 15 actual Compatibility-renderer checks passed. For each of all six enemy roles and the Boss, otherwise identical frames with internal wait flags enabled/disabled are byte-for-byte identical; all seven screenshots saved successfully. The explicit cue method is absent. Screenshots were visually inspected for Boss and sniper.
- Software renderer: Mesa llvmpipe; only its expected V-Sync support warning. No fixed-frame-rate claim.
- Render images are internal QA outputs, not repository binaries. No ZIP created.

Reproduce with Godot 4.7.2 (set writable XDG directories if needed):

```sh
for test in tests/test_*.gd; do godot --headless --path . --script res://$test; done
CAPTURE_DIR=/absolute/output godot --path . --rendering-method gl_compatibility --audio-driver Dummy --script res://tests/capture_no_warning.gd
```
