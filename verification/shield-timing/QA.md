# Shield timing update — 2026-10-27

Godot **4.7.2.stable.official.ed1daf0bf**. Requested timings are now **1.5 s** for the expanding damage shield and **0.5 s** for each harmless bullet dissolve. Production changes are limited to these two constants and an aligned rendering comment. Shared drawing/contact radius, immediate removal of danger on contact, wave-specific birth exemptions, three-second invulnerability and the 384-remnant bound are unchanged.

## Passed

- All **14 headless regression suites / 30,912 assertions**, including **57 shield checks**, pass. Logs are adjacent. The total includes 29,199 repeated route assertions, not that many independent scenarios.
- Timing boundaries verify that the wave remains incomplete at 1.49 s, reaches its full extent at 1.5 s and preserves its final collision interval before retirement. An individual remnant remains active at 0.49 s and expires at 0.5 s. Tests explicitly reject the old 0.58 s / 0.20 s lifetimes.
- Moving-front near/mid/far contacts, shared radius, immediate harmlessness, swept tunnelling, overlapping waves, births behind the front, unchanged protection and pulse behavior, restart/resize and 30/120 Hz state agreement still pass. The timestep fixture samples simultaneous live bullets and dissolves during the slower sweep.
- A 21-second normal-rule phase-three spiral run (ordinary movement, no firing, bombs, life or immunity edits after encounter setup) produces one real hit and finishes with two lives. Peak danger: **293 bullets**; peak dissolves: **205**. **15,753** tracked still-live remnant intervals show **zero premature reuse**. The existing 384-item pool therefore needs no enlargement for this observed normal density.
- Existing landscape, portrait and base-canvas spiral survival regressions remain playing after 30 seconds with two lives and no bombs used. This is automated-controller evidence, not human playtesting.
- The 12 × 900-bullet stress benchmark now spans the whole longer wave plus dissolve: **2,904 ticks**, **0.358 ms median / 6.404 ms p95 / 74.771 ms maximum**, peak remnants 384. Shared-container timings are not hardware FPS guarantees; artificial saturation still intentionally recycles the oldest visual remnant.

## Not verified natively in this update

A brief native Compatibility capture was attempted, but Xorg could not establish local/unix listening sockets, so Godot could not initialize an X11/Wayland display. `capture_shield_stress.log` records that environment failure; no current-timing native frames or new GIF were produced. The capture fixture now samples shared-radius thresholds rather than old fixed tick counts. Historical 0.58 s / 0.20 s native evidence remains in `../shield-cancel/` and is explicitly not presented as current-timing evidence.

## Reproduce

```sh
for f in tests/test_*.gd; do godot --headless --path . --script "res://$f" || exit; done
godot --headless --path . --script res://tests/benchmark_shield.gd
# Requires a working native display:
CAPTURE_DIR=/absolute/output godot --path . --rendering-method gl_compatibility --audio-driver Dummy --script res://tests/capture_shield_stress.gd
```

Local test success is not remote CI. The pushed SHA and its statuses/checks/Actions are checked separately after publication.
