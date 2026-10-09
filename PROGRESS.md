# Progress

Resume from here and `git log`. Checks: `--headless --path . --script res://tools/sim_checks.gd` and `--headless --path . --editor --quit`. Visual captures: `Godot --path . --position -5000,-5000 --resolution 1920x1080 -- --capture=<scenario> --out=docs/verification/<name>.png [--frames=N]` (debug builds only; the window opens off-screen and never takes focus, at the user's request). Headless cannot capture: Godot 4.2 headless uses a dummy renderer.

## Current milestone

M3 — Templates (next milestone; M2 command verification complete).

## Done

- M0 Skeleton: data catalogs (`data/*.json`) with `core/data.gd` + `core/validation.gd` (semantic checks, startup error screen), `core/text.gd`, `core/save_store.gd` (staged writes, .bak, .corrupt), title scene (seed, continue, settings, quit), settings screen (sound, display, graphics, key and pad rebinding), empty lit Forward+ main scene, debug capture path, `tools/sim_checks.gd` runner with data and parse scenarios.

- M1 Voxel valley: flat-array `voxel_world`, seeded `world_gen` (valley rim, ridge, river beside the long axis, trees, bushes, grass, boulders, ore, sacred tree, ruined ridge altar, ridge hamlet of two huts and a lean-to), padded-copy `chunk_mesher` with AO (0.9 s single thread, 0.28 s on the thread pool for the full valley), chunk views + concave collision on layer 2, avatar with step-up/jump, spring-arm camera with overlook, sun by hour. Full valley at 1080p: 60 fps (vsync), GPU 5.7 ms. Scripted walk test: climbs a 1-block step, stopped by a 2-block wall.

- M2 Hands-on building: core `Sim` (calendar, god state, resource sites, logged commands), `voxel_ray` DDA, build controller (break/place/hold-repeat, door orientation, hotbar 1-9 + wheel, red preview with reason), divine stock, presence boundary (lattice wall + ground ring), HUD (clock, stock, hotbar, messages). Captures: `build_test` places 6 blocks, re-mesh 9-11 ms; `zone_edge` avatar stops at 15.6 of radius 16; `walk_test` still passes.

- M2 command verification: four scenarios in `tools/checks/checks_commands.gd`, registered with `sim_checks`: resource yields/costs and immediate mesh dirtiness, rejected edits leaving state unchanged (stock, zone, bounds, protected blocks, occupied cells, dormancy), bush harvest/dismantling/replanting and resource-site state, timed command replay and copied log entries. All 10 scenarios pass, including loading every game script. Standard 4.2.2 headless editor import reports no errors (exit-code caveat below). No presentation changes or new visual run in this verification-only step.

- M3 data slice: bounded room probes, component-driven function rules, edit-driven structures and cause records, trimmed capture, strict import validation, staged library writes and backup recovery. Three new scenarios cover two-bed recognition/roof loss, untrusted fields, and file round-trip/recovery.

## Next

- M3: design tool, capture, room_probe, function_rules, structures registry, library screen, import/export.

## Decisions

- Goals, steps, plans, targets and messages are plain Dictionaries (not RefCounted classes) so agent state saves with `var_to_bytes` without per-class conversion. Goal identity is `kind << 32 | target`.
- Dirt-family blocks (grass, dirt, sand, gravel) yield and cost **soil**, a divine-stock-only resource; settlements never stock it. Keeps "placing consumes one unit" true without making terraforming free.
- A log yields 4 wood (a log makes four planks); tall grass yields 2 thatch. Other blocks yield 1.
- Doors are passable one-block panels; a doorway is two stacked door blocks so a 2-cell-tall person fits. Room probes treat doors as walls.
- `sim_checks` also loads every script under `res://scripts` so presentation parse errors fail headlessly.

- The voxel grid is one flat PackedByteArray (index x + z*W + y*W*D) instead of a dictionary of chunk arrays: far faster in GDScript. Chunks stay the unit of meshing, dirtiness and saving.
- Valley layout: sacred tree at (50,50), ridge ruin at (128,128) (~110 blocks), hamlet at (112,134). The river runs beside the tree-ridge axis so nobody must cross water.

## Known issues

- Use `exports/tooling/Godot_v4.2.2-stable_win64_console.exe` for checks and exports (standard 4.2.2, official archive SHA512 verified). `Run.ps1` still uses Mono. The standard editor removes the Mono `EditorSettings::_EDITOR_GET` shutdown error. Its `--headless --editor --quit` still returns 1, also reproduced with an empty project and fresh portable editor settings. The pinned engine's automatic-quit path does not set a success exit code ([upstream issue](https://github.com/godotengine/godot/issues/83449)). Do not report this as a zero-exit import pass or suppress arbitrary failures: inspect import output for errors and require sim_checks (including all-script parsing) to exit 0. Current standard-editor output has only headless-cursor and unconfigured-Blender warnings.
- Window captures at 1920x1080 are clamped by the desktop work area to 1920x1061; layouts are authored against the 1920x1080 stretch base, so this only trims the bottom 19 px of the capture.
