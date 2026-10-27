# Clockwise articulated Boss: independent logic QA

Engine: Godot 4.7.2 (`4.7.2.stable.official.ed1daf0bf`). Run from the repository root:

```sh
godot --headless --path . --script res://tests/test_boss_animation.gd
for f in tests/test_*.gd; do godot --headless --path . --script "res://$f"; done
```

## New focused coverage

`test_boss_animation.gd` has 76 aggregate assertions over the following samples:

- All three phases, 20 seconds per phase at 120 Hz: two complete 8.4-second phrases plus entry and part of the next phrase. Positive angular travel is checked not just for the outer rotor, iris, and hub, but for every articulated **blade tip relative to the moving center**, including hinge motion and banking.
- Both phase transitions (1→2 and 2→3) are interrupted at 85 score positions each, then observed for two seconds. The test covers interruption during folded, opening, fully open, fast-spin, recovery and cycle-wrap poses; there is no reverse tip movement or position discontinuity at these sampled times.
- Live bullets are inspected immediately after the real Boss update, before bullet integration. Every birth is exactly at one current articulated tip. Separate direct-emitter fixtures cover all six blades, three opening values and nonzero banking. The renderer is checked to consume the same profile and transform, including the named `BOSS_BLADE_TIP` vertex.
- Independent layer ratios, large opening/radial range, opposite-pair timing stagger, delayed iris response, attack/rest speed contrast, bounded acceleration, no fresh rest emissions and bounded batches are measured.
- Identical 20-second stationary-input fixtures at 30, 60 and 120 Hz compare the complete articulated pose, Boss path and bullet trajectories. Inactive-state freezing and restart/reset are tested.

The isolated kinematic fixture deliberately places its target beyond the playfield so collisions do not stop the clock; its peak bullet counts are **not gameplay difficulty claims**. The frame-rate fixture uses extended invulnerability for the same reason. Ordinary playability observations use the unchanged normal-input controller in `test_flow.gd` and `test_patterns.gd`, and are reported separately below.

## Measured kinematics

| Measure | Phase 1 | Phase 2 | Phase 3 |
|---|---:|---:|---:|
| Peak rotor speed (rad/s) | 3.631 | 4.067 | 4.503 |
| Minimum tip advance per 120 Hz tick (rad) | 0.002333 | 0.002363 | 0.002363 |
| Maximum normal-score angular acceleration (rad/s²) | 10.130 | 11.346 | 12.561 |
| Maximum sampled blade-tip step (logical px) | 4.057 | 4.539 | 5.023 |
| Exact birth-to-tip error (logical px) | 0 | 0 | 0 |

Blade-tip radius changes from 109.397 to 133.599 logical px. Opening ranges from 0.04 to 0.9939; maximum opposite-pair opening difference is 0.3954; maximum iris lag is 0.5804. Through the 170 phase-interruption fixtures, minimum tip advance remains positive at 0.001099 rad/tick and maximum tip step is 6.556 px.

The original fixed `0.05 rad/s per 60 Hz frame` speed-delta test described the former subdued animation. It is replaced by a time-normalized `<16 rad/s²` normal-score bound; the new interruption sweep separately bounds forced recovery. This deliberately allows stronger eased spin surges without accepting jumps or reversal.

## Limits

These are deterministic logic and source-contract checks, not a rendered-pixel proof, human difficulty test or guarantee for every external timestep/driver. Native render captures, no-warning pixel comparisons, cache bounds and visual direction review are separate evidence. The ordinary controller sees velocities and chooses reactive movement; it does not establish novice accessibility, every possible escape route or all edge-camping cases. No remote CI is implied by local logs.

## Final full-suite result and ordinary play observations

All 12 headless test scripts pass, totaling 30,772 assertions. Most assertions (29,199) are repeated route samples from the existing suite, not independent scenarios.

| Normal-input controller run | Result | Time | Lives | Bombs used | Peak bullets | Minimum sampled open lanes / 17 |
|---|---|---:|---:|---:|---:|---:|
| 1920×1080 / logical 1706.67×960 | won | 110.78 s | 3 | 0 | 40 | 12 |
| 800×1000 / logical 1440×1800 | won | 121.25 s | 3 | 0 | 50 | 14 |
| 960×640 / logical 1440×960 | won | 113.43 s | 3 | 1 | 40 | 11 |

No point-blank births were observed in these three normal-rule runs. The open-lane sampler and controller limitations are unchanged from `verification/flow/README.md`.

The first UI-only fixture run passed 23/23 assertions but warned about active audio objects at immediate shutdown. A verbose diagnostic identified `AudioStreamWAV` / `AudioStreamPlaybackWAV`; no Boss is instantiated in that test. The control/layout fixture now explicitly mutes audio before input (as the other UI/art fixtures already do), and its rerun exits cleanly. No game audio behavior was changed. `test_independent_ui_verbose.log` retains the original diagnostic; `test_independent_ui.log` is the final muted-fixture result.
