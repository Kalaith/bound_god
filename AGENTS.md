# The Bound God project guidance

This repository holds The Bound God, a third-person voxel god game in Godot: `project.godot`, `scenes/`, `scripts/`, `data/`, `assets/`, `tools/`, the export preset and the design documents. Work only inside this project unless the user explicitly broadens the task. Preserve any user changes.

Read before working:

- `GAME_DESIGN.md`: what the game is. Respect its pillars and its Decision / Later / Open markings.
- `IMPLEMENTATION_PLAN.md`: architecture, file layout, data, milestones and their exit criteria. Work milestone by milestone.
- `NPC System Implementation Guide.md`: the Final Landing BDI agent system being ported. Its formulas and values apply unless the plan says otherwise. The Rust source is in `D:\WebHatchery\RustGames\finallanding\src` (read only).
- `bound_god_game_concept.md`: the original concept. Do not edit it.

## Verification and checks

- The only automated checks live in `tools/sim_checks.gd`, a headless scenario runner for the simulation (`--headless --path . --script res://tools/sim_checks.gd`). It prints PASS/FAIL and exits non-zero on failure. Add a scenario when a simulation feature lands, in the style of the plan's §12. Do not create a `tests/` directory, other test frameworks or test addons. Keep `tools/` out of the exported game.
- Run the checks and a parse/import check (`--headless --editor --quit`) before every commit that touches scripts or data.
- Verify anything visual by running the game (`Run.ps1`) and looking at it. Say plainly what was and was not checked.

## Product invariants

- The god is bound. The avatar can never leave the presence zone of the shrine it is manifested at, and can be manifested at only one shrine at a time.
- Influence, not obedience. No feature may command an NPC, assign jobs or set work priorities. Whispers, requests, offered templates and miracles only change what NPCs know, want or can do; the BDI cycle always decides. Scripted beats enter as messages or candidates, never by bypassing deliberation.
- Templates are knowledge, not commands. Offering a design never queues construction.
- A structure's function comes from its components, never from its name or a player label.
- The world does not wait. Settlements keep simulating when the god is elsewhere, resting or dormant.
- Every outcome has a reason. Every NPC change of course is written to its decision log; significant world events are written to the chronicle with their cause.
- No game-over screen. Losing every shrine makes the god dormant and recovery depends on people.
- Hands-on building stays immediate: block edits apply between ticks and re-mesh within a frame.
- Keep the miracle, request and block catalogs bounded to implemented effects. Do not add fake entries.

## Engineering

- Godot **4.2.2** GDScript with the **Forward+** renderer. Windows only; no web export. Do not install or upgrade tools without approval.
- Godot executable: `C:\Program Files\Godot\Godot_v4.2.2-stable_mono_win64_console.exe` (see `Run.ps1`).
- Prefer built-in engine features (ArrayMesh, AStar3D, FastNoiseLite, RandomNumberGenerator, WorkerThreadPool). No plugins or GDExtensions without approval.
- Target resolution **1920×1080** (`canvas_items` stretch, `expand` aspect). Author UI at 1080p; it must stay readable at 1280×720.
- **No file over 800 lines**, including scripts, scenes, data and docs. Aim for ≤ 600 lines in scripts and split by responsibility before a file reaches the limit. Never meet the limit by removing whitespace, minifying, packing multiple entries onto one line, or otherwise making a file less readable. Keep readable formatting and split oversized files into cohesive files instead; this applies to JSON catalogs and text as well as code.
- The simulation (`scripts/agents`, `scripts/sim`, `scripts/world`, `scripts/building`) is `RefCounted` data and logic. It never touches the scene tree, physics, `Time`, `OS` or the global `randi()`/`randf()`. All randomness comes from `sim.rng`. Comparators tie-break on stable ids (`sort_custom` is not stable).
- Agents never mutate the world directly; they push into `Effects`, applied once at the end of the tick.
- Presentation (`scripts/presentation`) reads sim state and sends commands; it never changes sim state any other way.
- Static typing everywhere. Load dependencies with `const X = preload("res://...")`. Tabs, LF, UTF-8 (`.editorconfig`).
- Balance numbers live in `data/balance.json`; catalogs (`blocks`, `people`, `society`, `templates`, `miracles`) live in `data/` with stable ids and `schema_version`, validated at startup. Missing or mistyped data fails fast; no silent defaults in code.
- All player-facing text lives in JSON text catalogs under `data/`, currently `data/text.json`. Split text catalogs by responsibility (for example, UI text) when needed to stay within the file-size limit, updating the loader and validation accordingly. Do not compact formatting to avoid a split.
- Use JSON only for hand-edited data and shareable templates. Simulation saves use `var_to_bytes` on plain dictionaries and arrays.
- Store saves and the template library under `user://` with schema validation, staged writes and backup recovery. Imported templates are untrusted: validate size, palette and shape, and recompute function and bill.
- World collision is layer 2; the avatar is layer 1.
- Do not overwrite original art.

## Commits

Commit early and often: after every complete, working step (a system, a fix, a data pass), not at the end of a milestone. Each commit must leave the game booting and the checks passing.

Message style, following `small_following` but in the voice of the bound god: one line describing what changed **as it is felt in the world**, followed by a short plain tag in parentheses saying what it is technically.

```
The valley rises from the seed, the same hills every time (voxel world generation)
Villagers remember berries they have seen and forget the ones that are gone (agent beliefs)
A prayer at the tree now feeds the god's Favour (shrine favour)
The ridge shrine falls when raiders break its altar, and the chronicle remembers why (desecration)
Scribes set down the covenant: design and building plan (docs)
```

- Present tense, no trailing period, under ~100 characters before the tag where possible.
- Plain fixes still speak in-world: `Builders no longer wall themselves into the cottage they are raising (site reservation fix)`.
- Add a body only when the reason is not obvious from the line.

## Publishing

Publishing requires separate authorisation.

- `publish.ps1` exports the Windows build and deploys `bound_god_windows.zip` plus a download page generated from `tools/publishing/download.html` to `PREVIEW_ROOT/games/bound_god` (or production / FTP), then records the deployment in Project Roost. `-DryRun` changes nothing; `-BuildOnly` only builds.
- `publish-itch.ps1` pushes the last build to the itch Windows channel set in `publish.json`.
- Exports need the **standard (non-mono)** Godot 4.2.2 console editor, matching the installed export templates: pass `-GodotExe`, set `GODOT_EXE`, or place it at `exports/tooling/Godot_v4.2.2-stable_win64_console.exe`. `Run.ps1` uses the installed mono editor for playing.
