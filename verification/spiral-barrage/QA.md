# Full-angle Boss and six-arm spiral — verification

Engine: Godot **4.7.2** (`4.7.2.stable.official.ed1daf0bf`). The system `godot` binary in the test container was an older 4.6.3; all reported passing checks use the bundled 4.7.2 executable and writable XDG cache/data directories.

## Reproduce

```sh
for f in tests/test_*.gd; do godot --headless --path . --script "res://$f"; done
CAPTURE_DIR=/absolute/output godot --path . --rendering-method gl_compatibility --audio-driver Dummy --script res://tests/capture_spiral_barrage.gd
CAPTURE_DIR=/absolute/no-warning godot --path . --rendering-method gl_compatibility --audio-driver Dummy --script res://tests/capture_no_warning.gd
```

A display server is required for native captures. Capture scripts drive the real scene and renderer; they do not draw simulated mockups. `debug_set_boss(3)` initializes the requested encounter, then the 27.9-second clip uses ordinary movement and collision rules, with firing held off so the Boss survives long enough to show two spiral casts. No extended invulnerability, HP edits, bomb clears or timer jumps are used during the recording.

## Diagnosis and intentional behavior changes

1. The old Boss ring removed every direction within ±0.74 radians of the player. Since the player is usually below the Boss, this removed the lower central sector. The old filtered helper has been removed. New ring volleys contain every sampled angle (30 / 36 / 42, by phase); their discrete spacing is the escape space. Near-tip protection and capacity admission suppress an entire volley, never a selected sector.
2. The unwanted blade diagonal was a separate `_glyph_edge` polyline across the blade interior. Only that line was removed. The shared scythe polygon and its clipped, colored SVG border remain.
3. A 14.4-second score replaces the previous 8.4-second score. Three complete radial rings precede a six-arm spiral. The spiral emits 420 projectiles per cast, with 0.70-second emission / 0.20-second breathing pulses. All births use the same full articulated tip transform as rendering. The actual velocity turns +0.16 rad/s for three seconds, then continues along its tangent. No direction is inferred only from a decorative tail.
4. The outer rotor reaches 6.20 / 6.944 / 7.688 rad/s, with delayed iris and slower hub. All three phases remain clockwise, including tips under hinge motion and all sampled phase interruptions. Phase interruption angular acceleration is capped at 16 rad/s².
5. Native recording exposed an existing almost-expired hit fragment degenerating into a zero-area triangle. Invisible fragments below 1% remaining alpha are now omitted; the native epsilon-lifetime fixture verifies this path. The visible effect and collision rules are unchanged.

## Logic coverage

All **13 headless test scripts / 30,855 aggregate assertions** pass. The majority (29,199) are existing repeated route samples, not independent scenarios. Final per-script logs are in this directory.

The new independent suite (`test_spiral_barrage.gd`, 83 assertions) checks:

- A complete 36-angle ring has maximum angular gap 0.174534 rad, 17 strictly downward directions plus the horizontal endpoints, and an exact vertical-down projectile. Downward projectiles persist into the lower field in normal, wide and portrait logical canvases.
- Thirty seconds per phase gives **840 spiral births** across two casts, with exactly **420 initially downward**, every one of 24 angular bins and all 12 sampled lower-field columns occupied. Peaks are 329 / 316 / 307 bullets, far below the unchanged 900 cap. Lower-half spiral occupancy peaks at 116 / 109 / 105.
- Exact tip-to-birth error is zero. A tracked projectile differs by more than 30 px from straight travel after two seconds and matches the analytic curved/tangent model within 0.02 px.
- Complete 28-second 30 / 60 / 120 Hz fixtures have identical counts and zero measured trajectory error. Core simulation subdivides render frames at 120 Hz.
- Capacity and near-player admission preserve complete six-tip volleys. Rest creates no new projectiles; all six measured inter-pulse breathing pauses appear over two casts.
- A **time-connected** route search uses swept relative projectile/player segments, not disconnected safe positions. It finds a continuous route from the center across 30 seconds at **128 logical px/s**, slower than the 155 px/s focus speed, with both physical radii plus 2 px clearance. It passes wide, portrait and small-screen logical canvases and encounters projectiles at the player row in 146 / 95 / 133 sampled intervals. Targeting is held at center in this geometry fixture; this is not a proof that every starting position or every input is safe.

The expanded articulation suite observes 30 seconds per phase and interrupts each phase transition at 145 score positions. Minimum sampled tip advance remains positive (0.001099 rad/tick), maximum sampled interrupted tip step is 9.845 logical px, and maximum rotation-speed change is 0.133334 rad/s per 120 Hz tick.

## Normal-input observations (not human playtesting)

| Full-stage controller | Result | Time | Lives | Bombs used | Peak bullets | Minimum open sampled lanes / 17 |
|---|---|---:|---:|---:|---:|---:|
| 1920×1080 / logical 1706.67×960 | won | 110.99 s | 3 | 2 | 291 | 12 |
| 800×1000 / logical 1440×1800 | won | 116.35 s | 3 | 1 | 262 | 14 |
| 960×640 / logical 1440×960 | won | 118.05 s | 3 | 3 | 320 | 9 |

No point-blank births were observed. Separate phase-3 movement-only trials survive 30 seconds on all three canvases with **2 lives and all 3 bombs** remaining, without firing or extended invulnerability. This is measurably more demanding than the prior sparse encounter. Reactive-controller and lane-sampling results do not guarantee novice accessibility or every possible dodge route.

## Native rendering and delivery

The full original 28-second native capture is retained in `capture_28s_pilot_limit.log`; it reports two failed **controller-survival expectations**, not rendering errors: its 20 Hz reactive pilot loses the last life at 27.95 seconds, then the rotor correctly freezes on the loss screen. We do not call that original recording all-green. The delivered clip uses the first 558 unchanged frames (27.9 seconds, ending with one life). A fast native replay compares selected existing frames—including the final delivered frame—without regenerating the recording; see `capture_spiral_barrage.log`. Separate no-warning pixel comparisons pass 15/15 in `capture_no_warning.log`. The output GIF is 558 actual 960×640 frames at 20 fps, representing **27.9 continuous simulated seconds**. Still captures cover 1440×960, 1920×1080, 800×1000 and 960×640, including late downfield occupancy, clean blade geometry, pause/resume/restart and final-lifetime hit effects.

Twenty frames per second also keeps peak per-frame rotor advance below half the six-blade symmetry period, avoiding a misleading counterclockwise stroboscopic alias. No interpolated frames are used.

The renderer uses Mesa llvmpipe software rendering in this container. Timings are diagnostic only, not a target-device FPS claim. There are no unbounded particle histories or shape-cache keys; projectile cleanup and the 900 hard cap remain enforced. An isolated 30-second core benchmark (769 ticks with more than 200 bullets, peak 307) measured 0.768 ms median / 1.917 ms p95 per 120 Hz simulation tick on this shared container; see `benchmark_spiral.log`. Across all 560 original rendered frames, software-render readback measured 70.003 ms median / 175.622 ms p95 (including render scheduling, not simulation or PNG encoding). This is slower than real-time in this software-only container; the clip presents the actual deterministic simulation at its correct time scale, not a hardware FPS claim.

Git source only; no ZIP is produced. Local test results do not imply remote CI. Exact remote SHA and actual checks/Actions are verified separately after the authorized main push.
