# The Bound God project guidance

This repository holds The Bound God, a third-person voxel game in Godot in which the player is the spirit of a sacred tree guarding a cultivation sect that runs itself: `project.godot`, `scenes/`, `scripts/`, `data/`, `assets/`, `tools/`, the export preset and the documents. The shared standards at the end of this file apply as well as everything here.

Read before working:

- `docs/GAME_DESIGN.md`: what the game is. Respect its pillars and its Decision / Leaning / Tuning / Later / Open markings.
- `docs/PROGRESS.md`: where work stands, what is built, decisions taken while building, known issues and what is next. With the code, it is the reference for what is built.

Reference, read when relevant:

- `docs/reference/architecture.md`: the abstract settlement model, data catalogs, performance budget and verification rules. Code comments cite it as "architecture §N".
- `docs/design/art_direction.md`, `docs/design/font_direction.md` and `docs/art/`: the look and the type.
- `docs/reference/npc_system_guide.md`: the Final Landing BDI agent system the people are ported from. Its formulas and values apply unless `PROGRESS.md` or the architecture notes say otherwise. The Rust source is in `D:\WebHatchery\RustGames\finallanding\src` (read only).
- `docs/playtests/`: how to run and record fresh-player sessions.

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

- **GL Compatibility** renderer (WebGL 2 web build plus Windows). No SSAO or normal buffer: the ink shader finds creases from depth alone.
- Godot executable for playing: `C:\Program Files\Godot\Godot_v4.7.2-stable_win64_console.exe` (see `Run.ps1`).
- Built-in engine features to reach for: ArrayMesh, AStar3D, FastNoiseLite, RandomNumberGenerator, WorkerThreadPool.
- The shared WebHatchery Godot toolkit (`../godot_toolkit`) is linked in as `res://addons/hatchery/` by `..\godot_toolkit\tools\Link-Toolkit.ps1 -ProjectDir .` (a junction, ignored by Git). It is plain preloaded GDScript, not an editor plugin. Bound God uses its balance facade (`core/balance.gd`), text catalog, JSON and data-rule helpers, key and pad bindings and the settings store, the slot store for world saves, synth and voice pool, and the check runner. The game keeps its policy in `scripts/core/` (`settings_store.gd`: settings, actions and how they reach the engine; `save_store.gd`: the world-save files; `text.gd`: the catalog list). Change toolkit code in `../godot_toolkit` under its own AGENTS.md, and run its checks as well as these.
- Target resolution **1920×1080** (`canvas_items` stretch, `expand` aspect). Author UI at 1080p; it must stay readable at 1280×720.
- The simulation (`scripts/agents`, `scripts/sim`, `scripts/world`, `scripts/building`) is `RefCounted` data and logic. It also never touches physics. All randomness comes from `sim.rng`. Comparators tie-break on stable ids (`sort_custom` is not stable).
- Agents never mutate the world directly; they push into `Effects`, applied once at the end of the tick.
- Presentation lives in `scripts/presentation`.
- Balance numbers live in `data/balance.json`, read through `res://addons/hatchery/core/balance.gd`; catalogs (`blocks`, `people`, `society`, `templates`, `miracles`, `crops`, `recipes`, and the cultivation catalogs as they land) live in `data/` with `schema_version`.
- All player-facing text lives in JSON text catalogs under `data/`, currently `data/text.json`, `data/text_agents.json` and `data/text_ui.json`. Split text catalogs by responsibility when needed to stay within the file-size limit, updating the loader and validation accordingly.
- Use JSON only for hand-edited data and shareable templates. Simulation saves use `var_to_bytes` on plain dictionaries and arrays.
- The template library also lives under `user://`. Imported templates are untrusted: validate size, palette and shape, and recompute function and bill.
- World collision is layer 2; the avatar is layer 1.

## Project checks

- The checks live in `tools/sim_checks.gd` (on the toolkit's `testing/check_runner.gd`), a headless scenario runner for the simulation (`--headless --path . --script res://tools/sim_checks.gd`). It prints PASS/FAIL and exits non-zero on failure. Add a scenario when a simulation feature lands, in the style of the existing scenarios in `tools/checks/` (architecture §4).

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
- Exports need the **standard (non-mono)** Godot 4.7.2 console editor, matching the installed export templates: pass `-GodotExe`, set `GODOT_EXE`, or install it at `C:\Program Files\Godot`. `Run.ps1` uses the same editor for playing.

## Shared WebHatchery Godot standards

Identical in every WebHatchery Godot project's AGENTS.md; change all together. Project-specific rules go above.

### Working

- Stay inside this project unless the user broadens the task; preserve user changes; never overwrite original art.
- No installing/upgrading Godot, export templates, tools, plugins or GDExtensions without approval; prefer built-in features.

### Code

- Godot **4.7.2** GDScript, statically typed everywhere (variables, parameters, returns). `const X = preload("res://...")`. Tabs, LF, UTF-8, final newline.
- Simulation/rules code never touches the scene tree, `Time`, `OS` or global `randi()`/`randf()`; randomness comes from an owned `RandomNumberGenerator` (same seed, same result). Presentation reads state and sends commands, nothing else.
- Balance and catalogs (upgrades, parts, miracles, blocks, ...) live in JSON under `data/` with stable ids (and `schema_version` where present), validated at startup, holding only implemented effects. Missing or mistyped data fails fast and is reported; never default silently in code.
- Persistent state lives under `user://` with schema validation, staged writes and backup recovery. A failed save never loses progress or spends anything.

### Verification

- No `tests/` directory, frameworks or addons. Any automated checks are headless scripts in `tools/`, kept out of the export.
- Checks don't gate commits. At a major feature or milestone, run all checks (plus `--headless --editor --quit`) and fix findings.
- Headless checks can't verify visuals, audio, input or feel: run the game and look. State plainly what was and wasn't checked.

### Verification images

- Only `docs/verification/` (flat; keep its `.gdignore` and `docs/`'s). Reference art: `docs/reference/` or `docs/art/`.
- Capture via the toolkit's `testing/capture_runner.gd` or `testing/capture_paths.gd` (`CapturePaths.file(label)`); never pass an output directory or write elsewhere (`builds/`, `exports/`, OS temp, `user://`).
- Stable names `<label>.png`: no subfolders, timestamps, run/revision/size suffixes, `-final`/`-fix` variants or backups. Recapturing a screen or state overwrites; new labels only for genuinely new ones.
- One window size and UI scale per game. Look at the image before saying a visual change works.

### Size limits (hard rule)

- **Functions ≤ 400 lines; files ≤ 800 lines** (scripts, scenes, data, docs, catalogs). Check: `git ls-files -co --exclude-standard | grep -E '\.(gd|tscn|json|md)$' | xargs wc -l | sort -n | tail`.
- Split scripts by responsibility before they grow. A change that would cross a limit, or touches something already over, brings it under in the same change: split functions into named helpers; move a cohesive responsibility (HUD, settings wiring, area building, save validation, layout, a catalog section, ...) into its own file the original delegates to or loads. Keep public members other scripts use working.
- **Never shrink by deleting blank lines, joining statements, removing comments, minifying or packing entries onto one line.** Move content; don't squeeze it.

### Commits

- **ALWAYS commit each feature slice and bug fix the moment it works. Mandatory.** One slice per commit; never batch, never leave finished work uncommitted, never end a turn with an uncommitted feature or fix. Don't wait to be asked or offer instead of doing it; a later request ("also tweak X") is a new slice.
- Commit **all pending changes**, including modified, added and deleted files you didn't make: review and preserve them, include them in validation, finish with a clean tree.
- **Before the final reply of any turn that touched files:** run `git status --short`; if it prints anything, commit and rerun until empty. A dirty tree means unfinished; the closing summary says the tree is clean.
- Ignore rules still apply; never force-add ignored files or commit secrets. Don't push or publish unless asked.

Message: one present-tense line, no trailing period, under ~100 characters before the tag, saying what changed **as the player feels it** (for the toolkit, as the games using it feel it), then a plain lowercase tag in parentheses for what it technically is (the system touched, `docs`, `refactor` for structural changes, or a milestone id such as `M25`). Fixes and refactors are still described by effect. Add a body only when the reason isn't obvious.

```
The Lantern Fair opens: be more interesting than the fair (third map)
A prayer at the tree now feeds the god's Favour (shrine favour)
Builders no longer wall themselves into the cottage they are raising (site reservation fix)
No script over 800 lines: split main and the ritual screen (refactor)
Every game's saves now survive a torn write (json save)
Scribes set down the covenant: design and building plan (docs)
```
