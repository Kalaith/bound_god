# Progress

Resume from here and `git log`. Checks: `--headless --path . --script res://tools/sim_checks.gd` and `--headless --path . --editor --quit`. Visual captures: `Godot --path . --resolution 1920x1080 -- --capture=<scenario> --out=docs/verification/<name>.png` (debug builds only).

## Current milestone

M1 — Voxel valley.

## Done

- M0 Skeleton: data catalogs (`data/*.json`) with `core/data.gd` + `core/validation.gd` (semantic checks, startup error screen), `core/text.gd`, `core/save_store.gd` (staged writes, .bak, .corrupt), title scene (seed, continue, settings, quit), settings screen (sound, display, graphics, key and pad rebinding), empty lit Forward+ main scene, debug capture path, `tools/sim_checks.gd` runner with data and parse scenarios.

## Next

M1: voxel_world, world_gen, chunk_mesher, chunk views + collision, avatar, camera, day/night.

## Decisions

- Goals, steps, plans, targets and messages are plain Dictionaries (not RefCounted classes) so agent state saves with `var_to_bytes` without per-class conversion. Goal identity is `kind << 32 | target`.
- Dirt-family blocks (grass, dirt, sand, gravel) yield and cost **soil**, a divine-stock-only resource; settlements never stock it. Keeps "placing consumes one unit" true without making terraforming free.
- A log yields 4 wood (a log makes four planks); tall grass yields 2 thatch. Other blocks yield 1.
- Doors are passable one-block panels; a doorway is two stacked door blocks so a 2-cell-tall person fits. Room probes treat doors as walls.
- `sim_checks` also loads every script under `res://scripts` so presentation parse errors fail headlessly.

## Known issues

- Window captures at 1920x1080 are clamped by the desktop work area to 1920x1061; layouts are authored against the 1920x1080 stretch base, so this only trims the bottom 19 px of the capture.
