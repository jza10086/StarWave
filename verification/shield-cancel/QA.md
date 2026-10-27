# Damage shield sweep and individual cancellation — verification

Engine: **Godot 4.7.2** (`4.7.2.stable.official.ed1daf0bf`), native GL Compatibility. Source and test changes were independently reviewed. The primary actual-gameplay stills were visually approved before commit/push.

## Reproduce

```sh
for f in tests/test_*.gd; do godot --headless --path . --script "res://$f"; done
godot --headless --path . --script res://tests/benchmark_shield.gd
CAPTURE_DIR=/absolute/output godot --path . --rendering-method gl_compatibility --audio-driver Dummy --script res://tests/capture_shield_cancel.gd
CAPTURE_DIR=/absolute/stress godot --path . --rendering-method gl_compatibility --audio-driver Dummy --script res://tests/capture_shield_stress.gd
```

Native capture needs a display server. This container used Xorg with the dummy driver and Mesa llvmpipe, writable XDG cache/config/data directories and the bundled 4.7.2 binary (the system binary is older).

## Behavior and scope

- Previously `_hit_player()` immediately called `bullets.clear()`, while its generic death ring had an unrelated small radius. Now a damage wave is fixed at the **hit position before respawn**, expands for **0.58 s**, and reaches the farthest retained offscreen corner. The shader-free visible bright ring and collision use the same `damage_wave_radius()` smoothstep. Moving the respawned player cannot tow the wave.
- Each maximum-120-Hz physics interval analytically solves segment versus growing-disc contact, with hostile core radius included. Outside-to-outside high-speed crossings, tangent and degenerate quadratic cases are covered. The earliest of overlapping waves wins. The contact immediately removes the bullet from the dangerous collection; its **0.20 s** cool glint, shrinking center, two short arcs and three fragments exist only in a separate presentation pool.
- The striking bullet becomes harmless in the hit tick. A second near-origin sweep handles bullets processed before the triggering bullet, avoiding array-order-dependent live residue. The final wave interval is tested before removal.
- A shot born entirely behind an already-passed front is exempt from that particular wave only; newly born shots ahead are swept normally. This is not a persistent screen-sized absorber. Three-second hit protection, respawn, life/power changes and terminal-loss simulation freeze remain unchanged. Restart clears active wave IDs and remnants; resize remaps origins and maintains shared radius.
- X/pulse scoring and immediate clearing, Boss transitions and victory clearing are intentionally unchanged. The full-angle spiral, clockwise blade articulation, colored borders, transparent energy style and absence of attack-warning overlays are preserved.
- Cancellation storage is recycled and capped at **384**; a saturated pool reuses the oldest visual remnant, never postpones or skips gameplay cancellation. Waves are capped at four, more than can normally overlap under three-second immunity.

## Logic checks

All **14 headless suites / 30,899 assertions pass**. Most assertions (29,199) are repeated existing route samples, not independent scenarios. The new `test_shield_independent.gd` contains **44** independent boundary checks: time-ordered near/mid/far contacts, fixed origin and respawn, terminal interval reaching retained offscreen bullets, continuous tunnelling, analytic roots, earliest overlapping wave, both hit-array orders, birth exemptions and later wave IDs, resuming damage after protection, remnant noncollision/graze, four 900-cancellation pool cycles, resize/reset, invalid/large deltas, 30/120 Hz identical state and unchanged pulse behavior.

Two old `test_core.gd` fixtures manually removed immunity immediately after a previous hit. They now wait 0.7 seconds for the preceding shield to end before testing a separate fast collision or final life. Otherwise the newly correct wave would intercept their artificial follow-up bullet. Production immunity is still three seconds; no gameplay rules were relaxed to satisfy the fixture.

The existing normal-input full-stage controller still wins the base and portrait cases with three lives; its results are in `test_patterns.log`. This is automated control, not human difficulty/accessibility testing.

## Native actual-gameplay evidence

`capture_shield_cancel.log`: **1,933 checks / 0 failures**. The GIF contains **360 actual 660×440 native frames at 20 fps = 18.000 seconds**, starting three seconds into a phase-3 encounter. `debug_set_boss(3)` initializes the encounter; after that the recorded sequence uses ordinary movement/collision, no firing, no bombs, no invulnerability/HP/life edits and no timer jumps. The movement-only controller ends the clip still playing with **two lives**. Later controlled pause/resume/restart fixtures and a high-resolution replay are separately identified in the capture script; they are not part of the GIF.

The real hit occurs at encounter time **10.1667 s** (7.1667 s into the clip), at `(463.3275, 926)`, leaving **277** other dangerous bullets immediately after impact. The shield is visible over 12 recorded frames; danger and harmless remnants coexist in all 12:

| Wave age | Shared radius | Dangerous bullets | Harmless remnants |
|---:|---:|---:|---:|
| 0.0833 s | 98.17 | 284 | 4 |
| 0.1833 s | 369.60 | 249 | 42 |
| 0.2833 s | 739.64 | 149 | 148 |
| 0.3833 s | 1115.84 | 31 | 235 |
| 0.4833 s | 1405.76 | 21 | 141 |
| 0.5800 s | 1517.10 | 21 | 16 |

The remaining 21 shots were born behind the front; they demonstrate that the finite sweep does not continuously absorb new fire. The clip peaks at **286 dangerous bullets** and **238 active remnants**. It is not represented as a 900-bullet natural encounter. Per-frame checks confirm no non-exempt dangerous core remains inside the swept radius. High-resolution 1440×960 replay stills show the individual shrinking/arc forms, and near-expiry rendering is exercised without degenerate polygons.

Delivered GIF: `starwave-shield-cancel-18s.gif`, **14,960,974 bytes**, 660×440, 360 frames, 20 fps, 18 seconds, decoded and verified with Pillow and ffprobe. `starwave-shield-contact.png` is a four-panel arrangement of unchanged native gameplay PNGs with time/count labels outside each frame, not composited gameplay artwork. These preview files are delivered separately, not committed as source assets.

## Separate native density stress

`capture_shield_stress.gd` explicitly labels a **controlled density fixture**, not an authored Boss attack: 384 bullets form 48 angles × 8 radial layers, plus one real collision-triggering projectile. After the actual hit there are still 384 dangerous bullets; the partial native frame has **192 dangerous / 192 harmless**; the final sample has **0 dangerous / 384 simultaneous remnants**, then all remnants recycle. **12,136 assertions / 0 failures** pass (mostly per-tick/per-bullet checks, not independent scenarios). All four frames use the real 1440×960 renderer. The peak-remnant image has 0.0614% near-white pixels (minimum RGB component >0.75), versus 0.0652% before impact; direct visual review likewise finds no white flood or obscured background. This covers 320+ concurrent cancellation feedback separately from the normal-gameplay clip. The native labels remain in those stress PNGs.

## Performance and limits

The isolated stress benchmark initializes 900 bullets and sweeps them in each of 12 fixtures, measuring 960 physics ticks: **1.121 ms median / 5.667 ms p95 / 17.568 ms maximum**, peak remnants 384. It is a shared-container diagnostic, not a target-device guarantee.

Native render/readback across the recording and stills measured **49.516 ms median / 249.309 ms p95** in llvmpipe, including render scheduling but excluding PNG write time. Recording runs slower than real time in this software-only environment; the GIF shows the actual deterministic simulation at its correct 20-fps time scale, without interpolation or fabricated gameplay. No hardware FPS or novice survivability claim is made.

Reference observations and original implementation boundaries are documented in `ART_SOURCES.md`. Source is delivered through Git only; no ZIP is created. Remote SHA and actual checks/Actions are verified separately after the authorized main push; passing local tests is not remote CI.
