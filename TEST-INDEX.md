# Test index

Every check we run. Times were measured headless on this machine on 2026-10-10
(Godot 4.7.2); treat them as rough.

## Regular checks (run before finishing a task)

`powershell -File tools/check.ps1` runs import, idle run and smoke test in
order (~35 s in all) and fails on any engine error in their output.

| Name | Command | What it checks | Time |
|---|---|---|---|
| Asset import | `godot --headless --path . --import` | Assets import cleanly. `check.ps1` kills it after 25 s if a script tab is open in the editor session. | ~3–10 s |
| Idle run | `godot --headless --path . --quit-after 120` | The game boots and runs 120 frames with no script errors. | ~2 s |
| Smoke test | `godot --headless --fixed-fps 60 --path . --script res://tools/smoke_test.gd` | The big one: gravity, atmosphere, terrain, flight phases, landing, weapons, energy, engines, cargo, galaxy, jumps, streaming, save, the editor docks and more. Prints `smoke test: OK`. | ~25 s |
| Fire check | `godot --headless --path . res://tools/fire_check.tscn` | Each armed hardpoint fires from its own position, not a fixed point on the hull. | ~1 s |
| Menu check | `godot --headless --path . res://tools/menu_check.tscn` | Walks the main menu like a player and checks the world it produces. | ~1 s |
| Sound check | `godot --headless --path . tools/soundcheck.tscn --quit-after 2` | Plays every sound and prints the vacuum/atmosphere rule table (read the output; it does not assert). | ~1 s |

## Benchmarks and measurements (run on demand)

| Name | Command | What it measures | Time |
|---|---|---|---|
| Terrain bench | `godot --headless --path . --script res://tools/terrain_bench.gd` | Terrain sampling and collision cost per planet size. | ~1 s |
| Distance bench | `godot --headless --path . --script res://tools/distance_bench.gd` | Float32 error at 0–1000k px from the origin (floating-origin decision). | ~2 min |
| Orbit endurance | `godot --headless --fixed-fps 60 --path . --script res://tools/orbit_endurance.gd` | Orbit drift over minutes of simulated flight. Not timed today. | several minutes (not measured) |
| Frame bench | autoload `tools/frame_bench.gd`, then `godot --path . --fixed-fps 60 --quit-after 30000` | Per-frame cost of world objects (e.g. projectiles). | ~8 min of simulated frames (not measured) |

## Visual tools (look at the output, no pass/fail)

| Name | Command | What it shows |
|---|---|---|
| Art gallery | `godot --path . tools/art_gallery.tscn [-- <png dir>]` | Every sprite strip with its pivot marked. |
| Cloud preview | `godot --path . tools/cloud_preview.tscn -- <out dir>` | PNG of one planet per cloud archetype. |
| Widget gallery | `godot --path . tools/widget_gallery.tscn [-- <png dir>]` | Every UI primitive, calm and in warning states. |

## Smoke test contents

`smoke_test.gd` is one script with these check groups (`_check_*`):
gravity field, atmosphere shells, terrain, weather, landing sites, determinism,
weapons, weapon arcs, weapon types, scanner, reach vs. screen, foe markers,
cargo, crate physics, ejection, editor, pause gate, panels releasing the mouse,
camera, chords, energy, shot mods, energy balance, engine failures, hull
outline, allocator, gimbal, gear module, ship fit-outs, workbench, creative
tool, galaxy, jump (arming, balks, clearance, lane, kit, HUD, sequence,
misjump), transit veil, save, system model, streaming, system tour, star,
boost, input bindings.

## Failures vs. warnings

The smoke test separates code from content:

- **FAIL** (exit 1): the code is wrong. Flight, physics, UI and systems checks
  fly a built-in **reference hull** (`_reference_hull()` in `smoke_test.gd`, the
  stock dart's numbers frozen in code) wearing the real stock fitout, so a
  half-edited `resources/hulls/*.tres` cannot fail them.
- **WARN** (exit 0): the shipped resources break a rule: a hull whose torque
  jets leave a side force, legs hanging below the hull, mounts not where the
  hull says, a preset out of step. `check.ps1` lists them again in yellow at the
  end. Fix before shipping, not before continuing.

New check on a resource: use `_warn`. New check on code: use `_expect`, and
spawn the ship with `_spawn_ship()` so it gets the reference hull.

## Why `--fixed-fps 60`

The flight phases are counted in physics ticks. Without the flag a headless
loop runs them in real time (the smoke test took ~290 s). With it the physics
step is still 1/60 s, but the loop runs as fast as the CPU allows. Verified:
same 1875 passing assertions either way.
