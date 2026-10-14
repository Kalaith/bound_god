# The Bound God project guidance

This repository holds The Bound God, a third-person voxel game in Godot in which the player is the spirit of a sacred tree guarding a cultivation sect that runs itself: `project.godot`, `scenes/`, `scripts/`, `data/`, `assets/`, `tools/`, the export preset and the documents. The shared standards at the end of this file apply as well as everything here.

Read before working:

- `GAME_DESIGN.md`: what the game is. Respect its pillars and its Decision / Leaning / Tuning / Later / Open markings.
- `IMPLEMENTATION_PLAN.md`: definition of done, conventions, architecture changes and milestones (the cultivation slice M15–M18 in detail, M19–M25 outlined) with exit criteria. Work milestone by milestone. For what is already built, the code and `PROGRESS.md` are the reference.
- `PROGRESS.md`: where work stands, decisions taken while building, known issues.

Reference, read when relevant:

- `docs/design/sacred_tree_cultivation_design.md`: the brief for the cultivation-sect direction. The GDD carries its decisions.
- `docs/design/bound_god_game_concept.md`: the original concept. Do not edit it.
- `docs/design/art_direction.md`, `docs/design/font_direction.md` and `docs/art/`: the look and the type.
- `docs/reference/npc_system_guide.md`: the Final Landing BDI agent system the people are ported from. Its formulas and values apply unless the plan or `PROGRESS.md` says otherwise. The Rust source is in `D:\WebHatchery\RustGames\finallanding\src` (read only).
- `docs/playtests/`: how to run and record fresh-player sessions, and past findings.

`docs/` carries a `.gdignore`: Godot does not import it and the export excludes it. Keep design notes, reference images and captures there, not in the project root.

## Product invariants

- The god is bound. The avatar can never leave the presence zone of the shrine it is manifested at, and can be manifested at only one shrine at a time.
- Influence, not obedience. No feature may command an NPC, assign jobs, set work priorities or choose a sect's leaders. Whispers, requests, offered templates, blueprints, blessings and miracles only change what NPCs know, want or can do; the BDI cycle always decides. Scripted beats enter as messages or candidates, never by bypassing deliberation.
- Templates are knowledge, not commands. Offering a design or laying a blueprint never queues construction.
- The god cannot grant advancement. Blessings and miracles change odds or avert one specific failure at a cost; no feature gives a realm, and following a person gives them nothing.
- A structure's function comes from its components, never from its name or a player label.
- The world does not wait. Settlements and sects keep simulating when the god is elsewhere, meditating or dormant.
- Every outcome has a reason. Every NPC change of course is written to its decision log; significant world events are written to the chronicle with their cause.
- No game-over screen. Losing every shrine makes the god dormant and recovery depends on people.
- Hands-on building stays immediate: block edits apply between ticks and re-mesh within a frame.
- The miracle, request, block, realm, tribulation and tree-unlock catalogs stay bounded to implemented effects.

## Project engineering

- **Forward+** renderer. Windows only; no web export.
- Godot executable for playing: `C:\Program Files\Godot\Godot_v4.2.2-stable_mono_win64_console.exe` (see `Run.ps1`).
- Built-in engine features to reach for: ArrayMesh, AStar3D, FastNoiseLite, RandomNumberGenerator, WorkerThreadPool.
- The shared WebHatchery Godot toolkit (`../godot_toolkit`) is linked in as `res://addons/hatchery/` by `..\godot_toolkit\tools\Link-Toolkit.ps1 -ProjectDir .` (a junction, ignored by Git). It is plain preloaded GDScript, not an editor plugin. Bound God uses its balance facade (`core/balance.gd`), text catalog, JSON and data-rule helpers, key and pad bindings and the settings store, the slot store for world saves, synth and voice pool, and the check runner. The game keeps its policy in `scripts/core/` (`settings_store.gd`: settings, actions and how they reach the engine; `save_store.gd`: the world-save files; `text.gd`: the catalog list). Change toolkit code in `../godot_toolkit` under its own AGENTS.md, and run its checks as well as these.
- Target resolution **1920×1080** (`canvas_items` stretch, `expand` aspect). Author UI at 1080p; it must stay readable at 1280×720.
- Soft script target: ≤ 600 lines.
- The simulation (`scripts/agents`, `scripts/sim`, `scripts/world`, `scripts/building`) is `RefCounted` data and logic. It also never touches physics. All randomness comes from `sim.rng`. Comparators tie-break on stable ids (`sort_custom` is not stable).
- Agents never mutate the world directly; they push into `Effects`, applied once at the end of the tick.
- Presentation lives in `scripts/presentation`.
- Balance numbers live in `data/balance.json`, read through `res://addons/hatchery/core/balance.gd`; catalogs (`blocks`, `people`, `society`, `templates`, `miracles`, `crops`, `recipes`, and the cultivation catalogs as they land) live in `data/` with `schema_version`.
- All player-facing text lives in JSON text catalogs under `data/`, currently `data/text.json`, `data/text_agents.json` and `data/text_ui.json`. Split text catalogs by responsibility when needed to stay within the file-size limit, updating the loader and validation accordingly.
- Use JSON only for hand-edited data and shareable templates. Simulation saves use `var_to_bytes` on plain dictionaries and arrays.
- The template library also lives under `user://`. Imported templates are untrusted: validate size, palette and shape, and recompute function and bill.
- World collision is layer 2; the avatar is layer 1.

## Project checks

- The checks live in `tools/sim_checks.gd` (on the toolkit's `testing/check_runner.gd`), a headless scenario runner for the simulation (`--headless --path . --script res://tools/sim_checks.gd`). It prints PASS/FAIL and exits non-zero on failure. Add a scenario when a simulation feature lands, in the style of the existing scenarios in `tools/checks/` (plan §5).

## Commit voice

Commit lines speak in the voice of the bound god: what changed as it is felt in the valley. Milestone commits take the milestone id as their tag, e.g. `(M25)`.

```
The valley rises from the seed, the same hills every time (voxel world generation)
Villagers remember berries they have seen and forget the ones that are gone (agent beliefs)
The ridge shrine falls when raiders break its altar, and the chronicle remembers why (desecration)
```

## Publishing

Publishing requires separate authorisation.

- `publish.ps1` and `publish-itch.ps1` are the shared templates from `../godot_toolkit/templates/`; the work lives in `../godot_toolkit/publishing/Publisher.ps1` (override the location with `-ToolkitDir`). The download page comes from the toolkit's `publishing/download.html`; a `tools/publishing/download.html` here would override it.
- `publish.ps1` exports the Windows build and deploys `bound_god_windows.zip` plus a download page to `PREVIEW_ROOT/games/bound_god` (or production / FTP), then records the deployment in Project Roost. `-DryRun` changes nothing; `-BuildOnly` only builds and is fine for verification.
- `publish-itch.ps1` pushes the last build to the itch Windows channel set in `publish.json`.
- Exports need the **standard (non-mono)** Godot 4.2.2 console editor, matching the installed export templates: pass `-GodotExe`, set `GODOT_EXE`, or place it at `exports/tooling/Godot_v4.2.2-stable_win64_console.exe`. `Run.ps1` uses the installed mono editor for playing.

## Shared WebHatchery Godot standards

This section is identical in the AGENTS.md of every WebHatchery Godot project (`bound_god`, `small_following`, `spiritwright`, `godot_toolkit`). Change it in all four together; project-specific rules go in the sections above.

### Working

- Work only inside this project unless the user explicitly broadens the task. Preserve any user changes.
- Do not install or upgrade Godot, export templates, tools, plugins or GDExtensions without approval. Prefer built-in engine features.
- Do not overwrite original art.

### Code

- Godot **4.2.2** GDScript. The renderer is set per project (see above).
- Static typing everywhere: variables, parameters and return types.
- Load dependencies with `const X = preload("res://...")`.
- Tabs, LF, UTF-8, final newline (`.editorconfig`).
- Split scripts by responsibility before they grow; each project sets its soft target above. The hard limit is below.
- Simulation and rules code never touches the scene tree, `Time`, `OS` or the global `randi()`/`randf()`. All randomness comes from an owned `RandomNumberGenerator`, so the same seed gives the same result. Presentation reads that state and sends commands; it never changes it any other way.
- Balance numbers and catalogs live in JSON under `data/` with stable ids (and `schema_version` where a catalog has one), validated at startup. Missing or mistyped data fails fast: report it, never silently default in code.
- Keep every catalog (upgrades, parts, miracles, blocks and so on) bounded to implemented effects. Do not add entries the code does not support.
- Persistent state lives under `user://` with schema validation, staged writes and backup recovery. A failed save must never lose progress or spend anything.

### Verification

- Do not create a `tests/` directory, test frameworks or test addons. Automated checks, where a project has them, are headless scripts in `tools/`, kept out of the exported game.
- Before every commit that touches scripts or data, run the project's checks (if any) and a parse/import check (`--headless --editor --quit`).
- Headless checks do not verify visuals, audio, input or feel. Verify anything visual by running the game (`Run.ps1`) and looking at it.
- Say plainly what was and was not checked.

### File size limit (hard rule)

- **No file may exceed 800 lines**: scripts, scenes, data, docs and text catalogs. Check before every commit with `git ls-files -co --exclude-standard | grep -E '\.(gd|tscn|json|md)$' | xargs wc -l | sort -n | tail`.
- When a change would push a file past 800 lines, or a file is already over, **bring it below 800 in the same change** by moving a cohesive responsibility (HUD, settings wiring, area building, save validation, layout, a catalog section and so on) into its own file and having the original delegate to or load it.
- **Never shrink a file by deleting blank lines, joining statements, removing comments, minifying or packing several entries onto one line.** Blank lines between functions and the existing comment density stay as they are. Line count comes down by moving content, not by squeezing it.
- Keep public members that other scripts use working, either in place or through a delegating function.

### Commits

- Commit early and often: after every complete, working step (a system, a fix, a data pass), not at the end of a milestone. Each commit leaves the project booting and its checks passing.
- Commit **all pending project changes**, including modified, added and deleted files you did not make yourself. Do not leave user changes or another agent's changes uncommitted because you did not touch them: review and preserve their contents, include them in the validation, and finish with a clean working tree.
- Existing ignore rules still apply to generated files, local tooling and credentials. Never force-add ignored files or commit secrets.
- Do not push or publish unless the user asks.

Message style: one line describing what changed **as it is felt by the player** (for the toolkit, by the games that use it), then a short plain tag in parentheses saying what it is technically.

```
Neris raises a ward whenever she is struck (spirit trait)
A prayer at the tree now feeds the god's Favour (shrine favour)
The Lantern Fair opens: be more interesting than the fair (third map)
Every game's saves now survive a torn write (json save)
Scribes set down the covenant: design and building plan (docs)
```

- Present tense, no trailing period, under ~100 characters before the tag where possible.
- Fixes and refactors are still described by their effect: `Builders no longer wall themselves into the cottage they are raising (site reservation fix)`, `No script over 800 lines: split main and the ritual screen (refactor)`.
- Tags are lowercase and plain: the system touched, `docs`, `refactor`, or a milestone id such as `M25`.
- Add a body only when the reason is not obvious from the line.
