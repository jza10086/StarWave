# Combat-flow verification

Godot 4.7.2, deterministic logical simulation. Run from repository root:

```sh
export XDG_DATA_HOME=/tmp/starfall-flow-xdg/data
export XDG_CONFIG_HOME=/tmp/starfall-flow-xdg/config
export XDG_CACHE_HOME=/tmp/starfall-flow-xdg/cache
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
# Substitute your Godot 4.7.2 executable.
for f in tests/test_*.gd; do godot --headless --path . --script "res://$f"; done
```

`test_routes.gd` samples all six roles on three logical canvases: staged lifecycle, phase-gated emission, finite paths, C1 segment joins, bank bounds, resize remapping and 30/120 Hz consistency. `test_flow.gd` verifies three bullet roles, exact acceleration integration, Boss phrases and held attack position, no rest emissions, 30/120 Hz state, inactive-state freeze, reset, phase/cycle movement continuity Boss arrival residual clearing and no existing-trajectory mutation when the Boss ring hits the bullet cap. Existing tests retain control/collision/bomb/score/UI/art checks. Obsolete assumptions changed explicitly: immediate sniper fire now waits for route entry, initial formation checks permit side entry then inspect attack paths, Boss initial fire waits for reposition, and expiry checks use the new maximum 28 seconds. Fast bullets are tested for emission during their attack rather than assumed still present at seven seconds.

## Normal-rule automated stage observations

The reactive controller uses only movement, fire and limited bomb input; it does not edit health, power, timers, enemies or bullets. It sees actual velocity and projects local danger, so these are automation observations, **not human skill tests or guaranteed fairness**.

| Viewport / logical field | Result | Time | Lives | Bombs used | Peak bullets | Minimum sampled open lanes / 17 | Time near side edges |
|---|---|---:|---:|---:|---:|---:|---:|
| 1920×1080 / 1706.67×960 | won | 114.24 s | 3 | 0 | 43 | 12 | 0 s |
| 800×1000 / 1440×1800 | won | 122.98 s | 3 | 0 | 50 | 13 | 0 s |
| 960×640 / 1440×960 | won | 114.37 s | 3 | 1 | 42 | 11 | 0.32 s |

No point-blank bullet births were observed. Residual bullets coexist with 10 / 10 / 9 normal wave transitions respectively; maximum transition residual was 36 (portrait). The Boss transition had zero residual in all runs. The sampled row test uses 17 points at the player's current Y every 0.5 seconds, with a 0.4-second straight-velocity projection and 12px clearance margin. It finds no fully sealed sampled row in these runs; it does not prove connected escape routes at every frame, predict later acceleration/curvature, or cover every player position. The controller spent almost no time near edges; deliberate edge camping and novice decision-making are not characterized. These low counts (42–50 peak bullets) show deliberately sparse spacing in this controller's runs, not proof of demanding difficulty or expert-level density. Counts stay far below 900; all routes and texture/trail caches remain bounded.

`test_flow.log` includes exact wave-boundary counts and final results. Render capture and visual review are separate from headless simulation; see the capture logs and delivered previews rather than treating headless checks as pixel validation.

No CI workflow is configured in this repository; these are locally executed Godot checks, not a remote CI pass.

The full headless suite comprises 11 scripts and 30,696 assertions. Most (29,199) are repeated per-tick route samples, not that many independent scenarios; counts are reported for reproducibility, not breadth marketing. Coverage combines the scenario descriptions above with historical regression contracts.
