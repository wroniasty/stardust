\# Space sandbox (Godot 4.7, GDScript)



2D arcade space sandbox. Full design: IDEAS.md. Roadmap and current tasks: PLAN.md.

Work strictly milestone by milestone as PLAN.md says. Do not start M2 work while M1 is open.



\## Stack

\- Godot 4.7.2 standard build (no .NET). GDScript only for now.

\- Renderer Forward+, base resolution 640x360 with canvas\_items stretch, Nearest texture filter.

\- Physics: default gravity 0, linear/angular damp 0. All gravity is computed in ship code.



\## Conventions

\- Static typing everywhere (`var x: float`, typed function signatures, `-> void`).

\- snake\_case for files, functions, variables; PascalCase for classes and scenes.

\- One scene per file, script next to its scene with the same name.

\- Layout: scenes/, scripts/, resources/, shaders/, addons/. Autoloads in scripts/autoload/.

\- Use input actions from the Input Map, never raw keycodes.

\- All planet/surface math in the planet's polar frame (angle, radius), not global coordinates.

\- Everything procedural must be reproducible from a seed. No hand-placed planets.

\- Keep it arcade: prefer simple tunable parameters over physically correct formulas.



\## Godot executables

Are in:

* "D:\\Godot\\Godot\_v4.7.2-stable\_win64.exe"
* "D:\\Godot\\Godot\_v4.7.2-stable\_win64\_console.exe"



\## Verify before finishing a task

\- `godot --headless --path . --import` after adding assets.

\- `godot --headless --path . --quit-after 120` must run with no script errors in output.

\- For a single script: `godot --headless --path . --script res://path/to/file.gd --check-only`.

\- Use the godot MCP to run the project and read console output; use godot-docs MCP

&#x20; for any API you are not sure about instead of guessing.



\## Workflow

\- Small commits, one PLAN.md checkbox per commit where possible.

\- After finishing a checkbox, tick it in PLAN.md in the same commit.

\- Decisions discovered during work (units, thresholds, measurements) go into IDEAS.md,

&#x20; section "Otwarte pytania" shrinks, technical sections grow.

\- Talk to me in Polish, code and comments in English.

