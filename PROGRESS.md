# Progress

Resume from here and `git log`. Checks: `--headless --path . --script res://tools/sim_checks.gd` and `--headless --path . --editor --quit`. Visual captures: `Godot --path . --position -5000,-5000 --resolution 1920x1080 -- --capture=<scenario> --out=docs/verification/<name>.png [--frames=N]` (debug builds only; the window opens off-screen and never takes focus, at the user's request). Headless cannot capture: Godot 4.2 headless uses a dummy renderer.

## Current milestone

M2 — Hands-on building.

## Done

- M0 Skeleton: data catalogs (`data/*.json`) with `core/data.gd` + `core/validation.gd` (semantic checks, startup error screen), `core/text.gd`, `core/save_store.gd` (staged writes, .bak, .corrupt), title scene (seed, continue, settings, quit), settings screen (sound, display, graphics, key and pad rebinding), empty lit Forward+ main scene, debug capture path, `tools/sim_checks.gd` runner with data and parse scenarios.

- M1 Voxel valley: flat-array `voxel_world`, seeded `world_gen` (valley rim, ridge, river beside the long axis, trees, bushes, grass, boulders, ore, sacred tree, ruined ridge altar, ridge hamlet of two huts and a lean-to), padded-copy `chunk_mesher` with AO (0.9 s single thread, 0.28 s on the thread pool for the full valley), chunk views + concave collision on layer 2, avatar with step-up/jump, spring-arm camera with overlook, sun by hour. Full valley at 1080p: 60 fps (vsync), GPU 5.7 ms. Scripted walk test: climbs a 1-block step, stopped by a 2-block wall.

## Next

M2: voxel_ray, build controller, divine stock, presence zone boundary, hotbar.

## Decisions

- Goals, steps, plans, targets and messages are plain Dictionaries (not RefCounted classes) so agent state saves with `var_to_bytes` without per-class conversion. Goal identity is `kind << 32 | target`.
- Dirt-family blocks (grass, dirt, sand, gravel) yield and cost **soil**, a divine-stock-only resource; settlements never stock it. Keeps "placing consumes one unit" true without making terraforming free.
- A log yields 4 wood (a log makes four planks); tall grass yields 2 thatch. Other blocks yield 1.
- Doors are passable one-block panels; a doorway is two stacked door blocks so a 2-cell-tall person fits. Room probes treat doors as walls.
- `sim_checks` also loads every script under `res://scripts` so presentation parse errors fail headlessly.

- The voxel grid is one flat PackedByteArray (index x + z*W + y*W*D) instead of a dictionary of chunk arrays: far faster in GDScript. Chunks stay the unit of meshing, dirtiness and saving.
- Valley layout: sacred tree at (50,50), ridge ruin at (128,128) (~110 blocks), hamlet at (112,134). The river runs beside the tree-ridge axis so nobody must cross water.

## Known issues

- Window captures at 1920x1080 are clamped by the desktop work area to 1920x1061; layouts are authored against the 1920x1080 stretch base, so this only trims the bottom 19 px of the capture.
