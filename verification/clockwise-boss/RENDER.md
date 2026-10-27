# Native rendering and motion evidence

Godot 4.7.2 Compatibility renderer, Mesa llvmpipe software OpenGL. `tests/capture_boss_animation.gd` runs the actual main scene and core at 120 Hz, saving at 12 fps. No generated artwork, interpolated animation, hand-placed bullets, or mock render is used.

- **684 native capture/input/cache assertions passed.** Capture sizes: 1440×960, 1920×1080, 800×1000 and 960×640. Pause freezes the complete articulated Boss state; resume advances it; restart clears it. The widened blade silhouette stays below the HUD during established combat poses.
- **648 gameplay frames / 54 seconds:** three explicitly separated phase fixtures, 18 seconds each. Each contains the 1.2-second debug entry and two 8.4-second phrases. All five phrase labels occur in every phase. A movement-only normal-input reactive controller avoids bullets; it does not fire, so these captures show the complete animation without killing or skipping a phase. These are deterministic QA fixtures, not a claimed continuous normal-play boss kill or human playtest.
- All 648 recorded frames contain actual simulated rotor movement. Three phase fixtures remain playing; final lives 3, maximum active bullets 46. Fixed-profile texture cache is **13 entries** after all poses, phases, sizes and restarts; dynamic opening does not generate a texture per frame.
- **15 no-warning pixel checks passed:** all six ordinary enemy roles and the Boss produce identical pixels when internal warning/wait timers are toggled without advancing simulation. No attack rays, gap guides or countdown arcs are rendered.
- The 30-second delivered GIF selects the first 120 frames from each of the three phase segments (360 total frames). Thus each segment includes a full first score plus its entry. The phase cuts are intentional. The PNG contact sheet shows enlarged native crops of folded, opened, surge and recovery poses in all phases. Crop labels are annotations outside the game, not new HUD elements.
- Full 54-second frame sequence and a local H.264 recording were retained for QA. Preview images/videos are not committed to source or packaged as a ZIP.

Reproduce on a machine with a working graphics display:

```sh
CAPTURE_DIR=/tmp/starwave-boss-capture godot --path . --rendering-method gl_compatibility --audio-driver Dummy --script res://tests/capture_boss_animation.gd
CAPTURE_DIR=/tmp/starwave-no-warning godot --path . --rendering-method gl_compatibility --audio-driver Dummy --script res://tests/capture_no_warning.gd
```

The container used a dedicated dummy Xorg display, `LIBGL_ALWAYS_SOFTWARE=1`, and isolated writable XDG directories. Unsupported VSync and shader-cache recompilation warnings are recorded in the logs; neither was a failed test. Running several software-render/headless processes concurrently caused severe scheduling contention, so the evidence is **not a hardware performance benchmark or frame-rate guarantee**. GIF palette quantization does not reflect the continuous RGBA gradients in the live renderer.
