# The Bound God — Implementation Plan

> Version 0.1 · 2026-10-09 · companion to `GAME_DESIGN.md`
>
> Engine baseline and conventions follow `../small_following` (Godot 4.2.2, GDScript), except the renderer: this project uses **Forward+** and targets Windows only. The NPC system is a port of Final Landing's BDI agents (`D:\WebHatchery\RustGames\finallanding\src\agents`, `src\sim`), documented in `NPC System Implementation Guide.md` — referred to below as **the NPC guide**. Where this plan says "as Final Landing", the formula, value and behaviour in the NPC guide apply unchanged.

## 1. Baseline and conventions

Carried over from `small_following` (its `AGENTS.md`, `project.godot`, `scripts/balance.gd`, `scripts/progression.gd`):

| Topic | Rule |
| --- | --- |
| Engine | Godot **4.2.2**, GDScript only, **Forward+** (`renderer/rendering_method="forward_plus"`, `config/features` `"4.2", "Forward Plus"`). Differs from `small_following` (Compatibility) by decision, for 3D lighting. No upgrade, plugin or GDExtension without approval. |
| Platform | **Windows only.** One Windows Desktop preset in `export_presets.cfg`; the Web preset and HTML5 steps from `small_following`'s publish scripts are dropped. |
| Built-ins first | `ArrayMesh`/`SurfaceTool`, `ConcavePolygonShape3D`, `AStar3D`, `FastNoiseLite`, `RandomNumberGenerator`, `WorkerThreadPool`, `FileAccess`/`DirAccess`. |
| Scripts | `extends RefCounted` for pure logic, `Node`/`Node3D` only for presentation. Dependencies by `const X = preload("res://…")`, as `small_following` does (no global `class_name` sprawl). Static typing everywhere (`var x: int`, typed arrays). Tabs, LF, UTF-8 (`.editorconfig` copied). |
| Data | All tuning in `data/*.json`, read through a `Balance`-style static loader (copy `small_following/scripts/balance.gd` and generalise to several files). Missing or mistyped keys `push_error` + `assert(false)`: fail fast. Catalog files carry `schema_version` and are validated on load like `progression.gd::load_catalog`. |
| File size | **Hard limit: no file over 800 lines** (scripts, scenes, data, docs). Aim for ≤ 600 in scripts and split by responsibility like Final Landing's `plan_library/*`, `execute_*`. `small_following/main.gd` at 965 lines is the counter-example. |
| Resolution | Designed for **1920×1080**: `viewport_width=1920`, `viewport_height=1080`, `stretch/mode="canvas_items"`, `stretch/aspect="expand"`. UI layouts and font sizes are authored at 1080p and must stay readable when scaled down to 1280×720. |
| Saves | Under `user://`, schema-validated, staged writes (`.tmp` → rename), `.bak` recovery, `.corrupt` quarantine — copy the `_write_snapshot`/`_read_snapshot` pattern from `progression.gd`. |
| Project files | `project.godot`, `Run.ps1`, `publish.ps1`, `publish-itch.ps1`, `publish.json` (`slug: bound_god`, Windows itch channel only), `export_presets.cfg`, `tools/publishing/` copied from `small_following`, renamed, and trimmed to the Windows export. |
| Commits | Regular local commits after complete, working changes. Publishing needs separate authorisation. |

GDScript-specific rules this project adds (they matter because the simulation must be deterministic and headless):

1. **Simulation code never touches the scene tree, physics, `Time`, `randi()`/`randf()` globals or `OS`.** It reads `Calendar` and draws randomness from `sim.rng` only.
2. **`Array.sort_custom` is not stable.** Every comparator tie-breaks on a stable id.
3. **Dictionary iteration is insertion-ordered** (deterministic, unlike Rust `HashMap`), so Final Landing's `BTreeMap` becomes a plain `Dictionary` — but erase-and-reinsert changes order. When order affects outcomes, iterate sorted keys.
4. **JSON loses types** (ints become floats, `Vector3i` and int keys become strings). Use JSON only for human-edited data and shareable templates. Simulation saves use `var_to_bytes` on plain `Dictionary`/`Array`/packed-array snapshots (never `var_to_bytes_with_objects`).
5. Godot 4.2 has **no typed dictionaries**; document key/value types in a comment on each `Dictionary` field.

## 2. Architecture

```
┌──────────────────────────── Presentation (Nodes, per frame) ─────────────────────────────┐
│ main.tscn: WorldView (chunk meshes, collision) · Avatar · CameraRig · AgentViews · UI     │
│ reads sim state, interpolates positions, sends player Commands                            │
└───────────────▲──────────────────────────────────────────────┬────────────────────────────┘
                │ dirty chunks / events (polled)               │ commands (applied between ticks)
┌───────────────┴──────────────── Simulation (RefCounted, per tick) ────────────────────────┐
│ Sim: Calendar · rng · VoxelWorld · NavGrid · Structures · Settlements · Faith · Agents    │
│      Threats · Director · Chronicle · Effects                                             │
│ agents/ = pure reasoning (reads views, writes Effects)   sim/ = all side effects          │
└──────────────────────────────────────────────────────────────────────────────────────────┘
                ▲
          data/*.json (validated once at startup)
```

- **`Sim` owns all game state** and can run with no scene (`Sim.new(seed).run_ticks(n)`), which is what makes rest/fast-forward, determinism checks and headless verification possible.
- **The voxel world is part of the simulation.** NPCs place blocks; the player's edits are commands. The presentation keeps meshes in sync by polling `voxel_world.take_dirty_chunks()`.
- **Agents never mutate the world directly** (as Final Landing): they read immutable views and push into `Effects`; `sim/effects_apply.gd` applies voxel edits, messages, conversations, gifts, attacks and chronicle entries once at the end of the tick.

### 2.1 Clock

`scripts/presentation/sim_driver.gd` (a `Node`):

- In `_physics_process(delta)` accumulate `delta × ticks_per_second (6) × speed`.
- Run whole ticks while the accumulator ≥ 1 and the frame budget (4 ms; 12 ms while resting) is not spent. If the budget runs out, carry the remainder and show "the world is busy" instead of spiralling.
- After the ticks, store an interpolation alpha so `AgentView`s lerp between each agent's previous and current position.
- **Rest:** `sim_driver.rest(days)` switches to the large budget, hides the world behind an overlay with a progress bar, and on completion shows the "While you rested…" chronicle summary.
- Player commands (block edits, miracles, offers, requests, transfer) go through `sim.apply_command(cmd)` **between ticks**, and are appended to `sim.command_log` with the tick number. Same seed + same command log ⇒ same world.

### 2.2 Per-tick order

Final Landing's `Sim::step`, extended:

1. `calendar.advance()`; day/hour hooks (`sim/daily.gd`: stock broadcast, belief forgetting, opinion decay, mood breaks, births, faith drift, shrine support, migrants, raid roll, decay).
2. Every 10 ticks: refresh each settlement's `JobBoard`.
3. Move threats (`sim/threats.gd`: wolves, raiders).
4. `update_agents()` — for each present agent in id order: snapshot → body → perception → inbox → cognition → execute → movement (NPC guide "Per-tick order", steps 1–8).
5. `effects_apply.apply(effects)` — deliver messages, resolve interactions, **apply voxel edits** (then `nav_grid.update_cells`, `structures.reevaluate`), chronicle entries; `lifecycle.resolve_deaths()`.

## 3. Project layout

```
bound_god/
├── AGENTS.md                    # project guidance for agents (M0)
├── GAME_DESIGN.md · IMPLEMENTATION_PLAN.md
├── project.godot · export_presets.cfg · .editorconfig
├── Run.ps1 · publish.ps1 · publish-itch.ps1 · publish.json
├── assets/
│   ├── blocks_atlas.png         # 16 px tiles, nearest filtering
│   ├── icon.svg
│   └── audio/
├── data/
│   ├── balance.json             # time, needs, agents, social, mood, health, faith, world, threats
│   ├── blocks.json              # block registry
│   ├── people.json              # traits, ambitions, names (from Final Landing, extended)
│   ├── society.json             # thoughts
│   ├── templates.json           # function rules, starter vernacular templates
│   ├── miracles.json            # miracle catalog
│   └── text.json                # every player-facing label and template
├── scenes/
│   ├── title.tscn · main.tscn · avatar.tscn · agent_view.tscn
└── scripts/
    ├── core/          balance.gd · data.gd · validation.gd · save_store.gd · text.gd
    ├── world/         block_registry.gd · voxel_world.gd · world_gen.gd · chunk_mesher.gd
    │                  nav_grid.gd · voxel_ray.gd · room_probe.gd · structures.gd
    ├── building/      template.gd · template_capture.gd · template_library.gd
    │                  function_rules.gd · site_finder.gd · construction_site.gd
    ├── agents/        agent.gd · personality.gd · skills.gd · needs.gd · health.gd · mind.gd
    │                  beliefs.gd · faith_state.gd · goals.gd · plans.gd · intention.gd
    │                  decision_log.gd · messages.gd · generation.gd · deliberation.gd
    │                  deliberation_work.gd · deliberation_faith.gd
    │                  plan_library.gd · plan_library_needs.gd · plan_library_work.gd
    │                  plan_library_faith.gd · plan_library_social.gd
    ├── sim/           sim.gd · calendar.gd · effects.gd · effects_apply.gd · commands.gd
    │                  body.gd · perception.gd · inbox.gd · cognition.gd · movement.gd
    │                  execute.gd · execute_life.gd · execute_work.gd · execute_social.gd
    │                  execute_faith.gd · social.gd · lifecycle.gd · daily.gd
    │                  settlements.gd · job_board.gd · director.gd · threats.gd
    │                  faith.gd · miracles.gd · requests.gd · god_state.gd · chronicle.gd
    └── presentation/  main.gd · sim_driver.gd · world_view.gd · chunk_view.gd · avatar.gd
                       camera_rig.gd · build_controller.gd · design_tool.gd · agent_view.gd
                       agent_views.gd · threat_view.gd · overlays.gd · picking.gd
                       ui/hud.gd · ui/inspector.gd · ui/inspector_tabs.gd · ui/shrine_menu.gd
                       ui/template_library_screen.gd · ui/settlement_panel.gd
                       ui/chronicle_screen.gd · ui/rest_overlay.gd · ui/settings_screen.gd
                       ui/title_screen.gd
```

`small_following` keeps all scripts in one folder; this project is several times larger, so it uses the subfolders above with the same flat-file, preload-by-path style.

## 4. Data files

| File | Contents | Validation |
| --- | --- | --- |
| `balance.json` | Final Landing sections `time`, `needs` (warmth → shelter), `agents`, `social`, `mood`, `health` with shipped values; new `faith`, `shrines`, `miracle_costs`, `world`, `construction`, `threats`, `migration` | Every path read by code exists (fail fast through `Balance.value`) |
| `blocks.json` | `{id, name, resource, solid, opaque, passable, atlas: [x, y], component?, orientable?, breakable}` | Unique ids < 256; atlas in range; components from a known list |
| `people.json` | Final Landing's 22 traits + `pious`, `sceptic`; 7 ambitions with `decode_spire` → `raise_shrine`, `map_the_wilds` kept; names | As Final Landing: unique ids, `excludes`/`clashes_with`/`bonds_with` resolve |
| `society.json` | Final Landing's 39 thoughts + `saw_the_god`, `prayer_answered`, `prayer_unheard`, `witnessed_miracle`, `whispered_to`, `shrine_fell`, `home_built`, `raided` | `REQUIRED_THOUGHTS` list as Final Landing, extended |
| `templates.json` | Function rules (§6.2) and 2–3 vernacular starter templates (lean-to, hut) for the ridge hamlet | Rules reference known components |
| `miracles.json` | `{id, tier, cost, radius, aspect, renown_required, effect}` with `effect` from a fixed supported set | Effect types implemented in `sim/miracles.gd` only (no fake catalog entries, as `small_following`'s upgrade rule) |
| `text.json` | Labels for every goal, plan id, fail reason, activity, message, chronicle kind, log template | Coverage check: every enum value has a label |

`scripts/core/data.gd` loads all files once into a static cache (same shape as `balance.gd`), and `validation.gd` runs all semantic checks at startup and in headless checks.

## 5. Voxel world

### 5.1 Storage — `world/voxel_world.gd`

- Fixed bounds for the prototype: 160×48×160 (`world.size` in balance). Chunks of 16³ stored as `PackedByteArray(4096)` in `chunks: Dictionary # Vector3i -> PackedByteArray`. Index `x + z*16 + y*256`.
- Sparse per-cell state in `meta: Dictionary # Vector3i -> int` (orientation, bush ripeness, construction-site ownership).
- API used by everything else: `get_block(cell)`, `set_block(cell, id, meta := 0)`, `is_solid`, `is_passable`, `top_solid_y(x, z)`, `take_dirty_chunks()`, `generated_chunk_hash(chunk)` (to save only edited chunks).
- `set_block` marks the chunk (and the neighbour when on a boundary) dirty, records the edit for nav and structure updates, and never touches nodes.

### 5.2 Generation — `world/world_gen.gd`

Deterministic from the world seed using `FastNoiseLite` instances seeded from `sim.rng`-derived integers:

1. Height map (two octaves of simplex) shaped by a valley profile: low centre, raised rim, ridge on the far side.
2. River: a noise-perturbed spline across the valley carved to water level.
3. Layers: grass/sand top, 3 dirt, stone below, ore pockets in ridge stone, bedrock floor.
4. Placement passes (Poisson-disc with seeded RNG): trees (log + leaves structures), berry bushes, tall grass, rock outcrops. Each registers a **resource site** (`{id, kind, cells, amount}`) in `sim.resource_sites`.
5. Fixed features: sacred tree at the valley centre (registered as the origin shrine), ridge ruin (broken altar ring) and the ridge hamlet stamped from the vernacular starter templates.

### 5.3 Meshing — `world/chunk_mesher.gd`, `presentation/chunk_view.gd`

- Face-culled meshing per chunk: emit a quad for each solid face whose neighbour is non-opaque; separate surface for transparent blocks (water, glass, leaves).
- Vertex attributes: position, normal, UV into `blocks_atlas.png`, vertex colour for per-vertex ambient occlusion (classic 3-neighbour AO, which keeps block edges crisp; SSAO adds soft contact shadows on top) and slight per-block tint.
- One `StandardMaterial3D` (unshaded = false, vertex colour as albedo multiplier, `texture_filter = NEAREST`) per surface.
- Collision: `ConcavePolygonShape3D` from the opaque solid faces on a `StaticBody3D` per chunk, layer 2 (world), as `small_following`'s collision layering.
- Initial load: mesh arrays are computed on `WorkerThreadPool` tasks (pure data, no nodes), meshes and shapes are created on the main thread behind a loading screen. Edits re-mesh synchronously (one chunk ≈ a few ms); at most 4 dirty chunks per frame, the rest queue.
- **Later:** greedy meshing if profiling demands it.

### 5.4 Ray picking — `world/voxel_ray.gd`

Voxel DDA traversal from the camera through the crosshair up to the reach distance returns `{cell, normal}`. This is exact and independent of physics, and used for the build controller and the design tool.

### 5.5 Navigation — `world/nav_grid.gd`

NPCs move on a cell grid like Final Landing's tiles, lifted to 3D:

- A cell is **standable** when it and the cell above are passable (air, door, open fence gate) and the cell below is solid.
- `AStar3D` point id = `x + z*W + y*W*D`; neighbours are the 8 horizontal directions with `dy ∈ {−1, 0, +1}` (and `−2` for drops), diagonals only when both orthogonal moves are open; costs 1 / 1.41, +0.5 for climbing.
- After voxel edits, `update_cells(edits)` recomputes standability for the 3×3 columns around each edited cell and reconnects only those points.
- World contract functions for the agent code: `find_path(from, to) -> Array[Vector3i]`, `is_walkable(cell)`, `nearest_walkable(cell, radius)`, `move_cost(cell)`.
- Path requests are capped per tick (balance `agents.paths_per_tick`); agents over the cap wait a tick (`Running`).

### 5.6 Spatial index

`sim/spatial.gd` buckets agents, threats, resource sites and structures into 16×16 xz cells, rebuilt for agents each tick and updated incrementally for the rest. Perception, "who is nearby", chat partner search and earshot all query buckets instead of scanning lists.

## 6. Building and templates

### 6.1 Player building — `presentation/build_controller.gd`

- Uses `voxel_ray` from the camera; actions `break_block`, `place_block`, `rotate_block`, `select_block_1..9`, scroll to cycle. Reach 5 (play camera), 24 (overlook).
- Validity check: inside the active presence zone (horizontal distance to the shrine ≤ radius), not intersecting the avatar or an NPC, enough divine stock. Invalid targets tint the highlight red with a reason in the HUD.
- Emits `Command.EditBlock{cell, id}`; the sim applies it immediately between ticks, updates `god_state.divine_stock`, and records the resource gain or cost.

### 6.2 Structures and function recognition — `world/room_probe.gd`, `world/structures.gd`, `building/function_rules.gd`

Two ways a structure is registered:

1. **Template instance:** a construction site completing registers a structure with its template id, origin, rotation and cell set.
2. **Freehand:** when a functional block (bed, chest, altar, hearth, workbench) is placed, or a block is edited within 16 cells of a known component, `room_probe` runs a bounded flood fill of air from the component (limit 16×12×16 = 3072 cells). If the fill closes, the enclosed volume plus its shell is a room; if it escapes, the structure is "open-air" (enough for a shrine).

`function_rules.gd` evaluates the rules from `templates.json` on the component list (bed covered by roof within 4, door in the shell, chest count…) and sets `functions` and `capacity`. Structures are re-evaluated when any of their cells changes; a structure that loses all functions is unregistered and its residents become homeless (a chronicle entry records the cause).

### 6.3 Template capture and file format — `building/template_capture.gd`, `template.gd`, `template_library.gd`

Capture reads the marked box, trims empty margins, normalises to an origin at min corner, detects components with `room_probe` in the captured copy, and runs `function_rules`.

```json
{
  "schema_version": 1,
  "id": "willow_cottage_3f9a",
  "name": "Willow Cottage",
  "author": "local",
  "size": [7, 6, 6],
  "palette": ["air", "planks", "log", "thatch", "door", "bed", "storage_chest"],
  "blocks": "<base64 of a PackedByteArray, palette indices, x + z*sx + y*sx*sz>",
  "meta": {"12": 1, "40": 2},
  "entrance": [3, 1, 0],
  "functions": ["dwelling"],
  "capacity": {"beds": 2},
  "bill": {"wood": 64, "thatch": 30}
}
```

- Block names, not numeric ids, so files survive registry changes. `functions`, `capacity` and `bill` are **recomputed on import**, never trusted.
- Limits: size ≤ 16×12×16, palette entries must exist in `blocks.json`, size of `blocks` must match. Invalid files are rejected with a reason.
- Library: `user://templates/*.json` for the player library (private). Offered templates are stored in the world save (copied in, so a save does not depend on the library folder). Import/export use `FileDialog` (`ACCESS_FILESYSTEM`) on desktop.

### 6.4 NPC construction — `building/site_finder.gd`, `construction_site.gd`, `sim/job_board.gd`

- `site_finder.find(agent_beliefs, settlement, template, rotation_options)` samples candidate origins in the settlement area on a spiral from the settlement centre (deterministic order), scores flatness, distance to centre and road access (entrance side faces a walkable cell with a path to the centre), rejects overlaps and footprint height variance > 1. Returns the best or none (`FailReason.NoSite`).
- `ConstructionSite {id, template_id, origin, rotation, settlement_id, founder, order: PackedInt32Array, cursor, delivered: Dictionary # resource -> int, last_progress_tick}`. `order` is the template's non-air cells sorted bottom-up, then outer walls before interior, so the structure rises visibly. Site cells carry a meta flag so the player sees ghost blocks and other sites avoid them.
- Job board entries: `Build(site)` when the next block's resource is delivered or believed available; `Haul` for delivered-but-loose materials. Final Landing's caps (≤ 4 builds offered) and the "others pursuing" divisor apply.
- `PlaceBlock` step: standing within reach of the next cell, consumes one delivered unit, waits `construction.ticks_per_block / skill speed`, pushes a voxel edit into `Effects`. If the cell is now occupied by something else, the block is skipped and logged.
- Completion registers the structure (§6.2), assigns residents (founder household for dwellings), adds the `home_built` thought, writes a chronicle entry with the cause the founder logged.
- Abandonment: no progress for `construction.abandon_days`; delivered resources drop as loose items.

## 7. Simulation core

### 7.1 `sim/sim.gd`

```gdscript
extends RefCounted
## Owns all world state. No nodes, no physics, no global RNG.
var world_seed: int
var rng := RandomNumberGenerator.new()
var calendar: Calendar
var voxels: VoxelWorld
var nav: NavGrid
var resource_sites: Dictionary   # int -> ResourceSite
var structures: Structures
var settlements: Settlements
var agents: Array                # Array[Agent], index == id
var threats: Threats
var god: GodState
var chronicle: Chronicle
var effects: Effects
var command_log: Array           # Array[Dictionary] {tick, command}

func step() -> void: ...
func run_ticks(count: int) -> void: ...
func apply_command(command: Dictionary) -> bool: ...
func to_dict() -> Dictionary: ...
static func from_dict(state: Dictionary) -> Sim: ...
```

`rng.state` is saved and restored so a loaded game continues the same random stream.

### 7.2 Representing Final Landing's types in GDScript

| Rust | GDScript |
| --- | --- |
| `enum Goal` (25 variants, `Copy`) | `goals.gd`: `enum Kind { EAT, SLEEP, … }` and a lightweight `Goal` (`RefCounted` with `kind: int`, `target: int`, `extra: int`); `key() -> int` = `kind << 32 \| target` replaces `GoalKey` |
| `enum Step` with payloads | `plans.gd`: `enum Op { GO_TO, TAKE_STOCK, … }`; a step is `{op, …args}` Dictionary built by small constructor functions (`Steps.go_to(target)`), dispatched by `match` in `execute*.gd` |
| `Target` | `{type: TargetType, id: int, cell: Vector3i}` |
| `PlanOption {id: &'static str, steps, preference}` | Dictionary `{id: String, steps: Array, preference: float}` |
| `FailReason`, `StepOutcome` | enums; `StepOutcome` returned as int, fail reason stored on the agent for the log |
| `Needs [f32; 6]` | `PackedFloat32Array` indexed by `Need` enum |
| `BTreeMap<K, V>` | `Dictionary` + sorted-key iteration where order matters |
| `VecDeque` (path, log) | `Array` with `push_front`/`pop_back` (paths are short) |
| `OnceLock<GameData>` | static vars in `core/data.gd` |
| `SeededRng` | `sim.rng` (`RandomNumberGenerator`, seeded) |
| `serde` derive | explicit `to_dict()` / `from_dict()` per class; a validation helper checks types on load |
| `split_at_mut` / `pair_mut` | not needed: agents are references |

### 7.3 Port map: Final Landing → Bound God

| Final Landing | Bound God | Notes |
| --- | --- | --- |
| `agents.rs` | `agents/agent.gd` | `tile` → `cell: Vector3i`, `position: Vector3`, `inside` → `structure_id`; add `faith: FaithState`, `settlement_id`, `quest_id` |
| `agents/personality.rs` | `personality.gd`, `skills.gd` | Skills: Construction, Gathering, Social, Defence, Medicine, Exploration, Devotion, Crafting (8, same shape) |
| `agents/body.rs` | `needs.gd`, `health.gd`, `mind.gd` | Warmth → Shelter |
| `agents/beliefs.rs` | `beliefs.gd` | `nodes` → resource sites; add `structures` (known buildings incl. instances of templates), `places` (known settlements and shrines with last-seen state), `known_templates` |
| `agents/goals.rs` | `goals.gd` | Goal list in GDD §6.3 |
| `agents/deliberation.rs` | `deliberation.gd` (needs, social, leisure) + `deliberation_work.gd` + `deliberation_faith.gd` | Work weight: player priority → settlement culture weight |
| `agents/plans.rs`, `plan_library*.rs` | `plans.gd`, `plan_library*.gd` | New steps: `PLACE_BLOCK`, `MARK_SITE`, `PRAY`, `TEND_SHRINE`, `TRAVEL`, `TALK{topic: STORY}` |
| `agents/intention.rs` | `intention.gd`, `decision_log.gd` | New log kinds: `WHISPERED{goal}`, `QUEST_TAKEN`, `PRAYED{intent}` |
| `agents/messages.rs` | `messages.gd` | New kinds: `STORY`, `WHISPER`, `DIVINE_REQUEST`, `TEMPLATE_INFO` |
| `agents/generation.rs` | `generation.gd` | Travellers, migrants, hamlet miners, children |
| `sim/perception.rs` | `perception.gd` | Also perceives the avatar, miracles (from the effects of the previous tick), completed structures (learns template), shrines |
| `sim/inbox.rs` | `inbox.gd` | Receivers for the new messages (§8.3) |
| `sim/cognition.rs` | `cognition.gd` | `should_switch` unchanged; whisper bonus applied inside candidate scoring |
| `sim/execute*.rs` | `execute.gd`, `execute_life.gd`, `execute_work.gd`, `execute_social.gd`, `execute_faith.gd` | 3D `GoTo` via `nav` |
| `sim/body.rs`, `daily.rs` | `body.gd`, `daily.gd` | Shelter decay; faith drift; shrine support |
| `sim/social.rs` | `social.gd` + `effects_apply.gd` | Story topic resolution |
| `sim/jobs.rs` | `job_board.gd` | Per settlement |
| `sim/creatures.rs` | `threats.gd` | Wolves + raider band |
| `sim/director.rs` | `director.gd` | Migrants, raids |
| `sim/expeditions.rs` | `requests.gd` | Quests replace expeditions; agents stay `Present` and travel on the map |
| `sim/movement.rs` | `movement.gd` | Fractional move budget, `position` lerp in 3D |
| `sim/lifecycle.rs` | `lifecycle.gd` | Births, deaths, departure → Migrate |
| `ui/inspector_agent.rs` | `presentation/ui/inspector*.gd` | + Faith tab |
| `ui/world_view/actors.rs` | `presentation/agent_view.gd` | 3D procedural figures |

### 7.4 The world contract (NPC guide "Integration steps") mapped

| Need | Bound God provider |
| --- | --- |
| Grid positions | `Vector3i` cells; `Cells.distance` (xz Euclidean + `abs(dy)`), `Cells.steps` |
| Pathfinding | `nav.find_path`, `nav.is_walkable`, `nav.nearest_walkable`, `nav.move_cost` |
| Places | `structures.built()` with `functions` flags: `dwelling, storehouse, workshop, shrine, shelter`, `beds`, `free_beds`, `access_cell(id, from)`, `is_operational` (condition and not under construction) |
| Resources in the world | `sim.resource_sites`, `site_access_cell`, loose items in `sim.items` |
| Danger | `threats.list()` with `aggressive` and `targets_altar` flags |
| Shared economy | `settlement.stock`, `settlement.jobs`, `settlement.culture_weight(work_type)` |
| Time | `calendar` with `hour()`, `day()`, `season()`, `is_daylight()`, `ticks_per_day()`, `per_tick(x)` |
| Environment | `calendar.season()`, `voxels.is_roofed(cell)` (column scan up to 8) |
| Text | `Text.label(key)`, `Text.fill(template, args)` |

## 8. Faith, shrines, requests

### 8.1 Data — `agents/faith_state.gd`, `sim/faith.gd`, `sim/god_state.gd`

- `FaithState {knows: bool, devotion: float, aspects: PackedFloat32Array (5), shrine_id: int, last_prayer_tick: int, last_intent: Dictionary, stories_heard: int}`.
- `Shrine {structure_id, settlement_id, condition, favour, support, below_threshold_days, state: ACTIVE|DORMANT|FALLEN, prayers: Array (recent, capped 20)}` held in `sim/faith.gd`.
- `GodState {renown, active_shrine_id, divine_stock: Dictionary, dormant: bool, offered_templates, requests, grace_until_tick}`.
- Renown = number of agents with `knows == true` (recomputed daily).

### 8.2 Faith goals (`deliberation_faith.gd`)

| Goal | Utility | Gate |
| --- | --- | --- |
| Pray | `0.25 × devotion/100 × (1 + 0.5 × spiritual + 0.5 × pious)` + `0.5 × deficit(lowest need)²` (desperation) + 0.15 at dawn/dusk | Believer+ or (Curious and a need < 25) |
| TendShrine | `0.3 × devotion/100 × (1 − condition/100) × 2` | Believer+, attends a shrine with condition < 80 |
| RestoreShrine | `0.6 × devotion/100` (+0.3 if `raise_shrine` ambition) | Devout or quest; knows a fallen/ruined shrine |
| Preach | `0.2 × devotion/100 × (1 + sociability)` + 0.3 if quest | Believer+, an Unaware/Curious person believed within 30 cells |
| Quest | `0.4 + devotion/200 + boon value`, × risk term `(1 − 0.5 × believed danger × (1 − bravery))` | Accepted request |

Whisper bonus: `cognition` adds `whisper.bonus` to the matching goal kind's candidate utility until it expires and appends "(the god urged it)" to the reason string.

### 8.3 New message receivers (`inbox.gd`)

| Message | Receiver does |
| --- | --- |
| `STORY{devotion, aspects}` | If `!knows`: `knows = true`, chronicle "first heard of the god" for notable firsts. Else devotion += `faith.story_gain × trust × (speaker devotion − own)/100` (clamped up), aspects lerp toward the speaker's by `0.1 × trust` |
| `WHISPER{goal_kind, target}` | Believer+: store bonus `0.4 × devotion/100` for one day, thought `whispered_to`, log `WHISPERED`. Aware/Curious: Safety −5, curiosity-weighted devotion +2 |
| `DIVINE_REQUEST{request_id}` | Accept rule (modelled on Final Landing's `RequestHelp`): not a child, not in crisis, `devotion/100 + 0.3 × bravery + 0.2 × curiosity + boon − danger > balance.faith.request_accept` and the request still has free slots → `quest_id`, force deliberation, reply via `requests.gd` |
| `TEMPLATE_INFO{template_id}` | Add to `beliefs.known_templates` if trust > 0.3 |

### 8.4 Miracles — `sim/miracles.gd`

`cast(id, at_cell, args)` validates (active shrine, inside the zone, renown tier, Favour after identity discount), deducts Favour, applies the effect, and records a **miracle event** `{id, cell, radius, aspect, tick}` that `perception` delivers to agents with the cell in sight next tick (each witness adds `witnessed_miracle`, devotion and aspect, interpreted per GDD §6.4). Answered prayers: `faith.gd` matches recent prayer intents in the area against the miracle's relief type within one day.

### 8.5 Shrine lifecycle — `sim/faith.gd` (hourly and daily)

Hourly: recompute support from congregations' recent prayers; update presence radius. Daily: condition decay, threshold counters, ACTIVE ↔ DORMANT transitions, FALLEN when the altar block is gone. On loss of the god's current shrine: expel the avatar (command to presentation through `god.events`), or set `dormant`. Chronicle entries record the cause (low support, untended, raid).

### 8.6 Requests — `sim/requests.gd`

`Request {id, kind, shrine_id, target (place/resource/settlement), amount, boon, slots, takers, state, posted_tick, deadline_tick}`. The shrine menu posts it; `requests.broadcast()` sends `DIVINE_REQUEST` to the congregation. Completion checks run daily and on relevant effects; outcomes become prayers ("Brannoc returns: the ridge folk have heard your name") and chronicle entries; boons are paid from the shrine's Favour on success.

## 9. Settlements, director, threats

- **`sim/settlements.gd`:** `Settlement {id, name, center, radius, residents, structure_ids, stock, culture: Dictionary # work_type -> float, known_templates, site_ids, shrine_ids}`. Membership follows home ownership; homeless newcomers join the nearest settlement they believe in. Stock = Σ storage chests (each chest caps 40 units); with no storehouse, a 60-unit "pile" at the centre (as early Final Landing).
- **Culture drift (daily):** each weight moves 2% toward `need_signal(work_type)` (e.g. housing deficit → Build) and 1% toward what the top-3 opinion-weighted residents spent the day doing; clamp 0.4–1.6.
- **`sim/director.gd`:** migrants (attractiveness = spare beds + food days + safety + shrine renown, roll every 3 days), raids (§9.2 of the GDD: from day 12, every 4 days, target score = wealth / defenders), grace period for the tree shrine.
- **`sim/threats.gd`:** wolves (wander, chase, flee when outnumbered) and raiders (simple state machine: approach → loot nearest storage → smash altar if `targets_altar` → retreat with loot), all pathing on `nav`. Raiders are not BDI agents in the prototype. **Later:** raiders as BDI agents of a bandit faction.

## 10. Presentation

### 10.1 Scenes

- **`title.tscn`:** new world (seed field), continue, load, settings, quit (pattern of `small_following/scripts/title_screen.gd`).
- **`main.tscn`:** `Main` (Node3D) → `SimDriver`, `WorldView` (chunk views), `Avatar` (CharacterBody3D, capsule, layer 1 / mask 2), `CameraRig` (SpringArm3D + Camera3D, overlook mode), `AgentViews`, `ThreatViews`, `Overlays`, `DirectionalLight3D` with shadows, driven by the calendar hour, `WorldEnvironment` (Forward+: ProceduralSky, SSAO, distance fog, glow for the avatar and miracles, tonemap; volumetric fog reserved for Veil of Fog), `UI` (CanvasLayer). A graphics setting toggles SSAO, shadows quality and glow for weaker GPUs. SDFGI is off (cost not justified for a mutable voxel world).

### 10.2 Avatar and camera

- `avatar.gd`: input-relative movement on `_physics_process`, `move_and_slide`, step-up of 1 block via a short forward shape test, jump. After moving, clamp the horizontal position to the presence radius around the active shrine (soft push-back + boundary shader on a cylinder mesh in `overlays.gd`).
- Movement is independent of the sim and the UI (the `small_following` invariant "player can always move" is kept, except in modal screens that take focus).
- `camera_rig.gd`: mouse/right-stick orbit, zoom, and an `overlook` toggle that tweens to an elevated orbit around the shrine and widens build reach.

### 10.3 NPC views — `agent_view.gd`

Final Landing's procedural actors in 3D, no art pipeline needed: capsule body tinted by `hue` and portrait archetype, sphere head, child scale 0.7; a flat mood ring under the feet; carried item as a small cube; `Label3D` billboard glyph for activity (Zs, "…", "!", ×, ring, +, a "^" glyph for praying and a hammer glyph for building, all plain characters because the default font has no emoji); walk bob and work sway; hidden or faded when inside a structure. Positions lerp between ticks with the driver's alpha.

### 10.4 Picking and inspector

- `picking.gd`: on click/tap, project agent positions to screen and pick the nearest within a zoom-aware radius (Final Landing's rule), then threats, then structures (via `voxel_ray` cell → structure id).
- `ui/inspector*.gd`: Final Landing's Mind / Needs / Bonds / Life tabs + Faith tab; Follow and Close buttons; strings from `text.json`. The **beliefs vs reality** block now includes believed stock vs actual, believed templates, believed shrine state.
- Selection overlay: pulsing ring, current path as a line mesh, lines to strong relations.

### 10.5 Input map (`project.godot`)

`move_*`, `jump`, `sprint`, `camera_orbit`, `zoom_in/out`, `overlook`, `break_block`, `place_block`, `rotate_block`, `hotbar_1..9`, `design_tool`, `interact`, `inspect`, `speed_pause`, `speed_up`, `speed_down`, `toggle_chronicle`, `toggle_settlement`, `toggle_settings`, `toggle_fullscreen`, `quick_save`. Keyboard + gamepad bindings like `small_following`, with its key/pad rebinding scripts reused.

## 11. Save and load — `core/save_store.gd`

```
user://worlds/<slot>/
  meta.json        # {schema_version, name, seed, day, created, played_seconds}
  sim.bin          # var_to_bytes(sim.to_dict()) — agents, settlements, structures, faith, god, chronicle, rng.state, calendar
  chunks.bin       # var_to_bytes({Vector3i: PackedByteArray.compress(ZSTD)}) for edited chunks only
  templates.json   # offered templates (copies)
```

- Written with the `progression.gd` pattern: `.tmp` files, rename current to `.bak`, rename `.tmp` into place; on read failure fall back to `.bak`, quarantine as `.corrupt`.
- Load = regenerate the world from the seed, overwrite edited chunks, then `Sim.from_dict`. Every `from_dict` validates types and ranges and fails with a clear message.
- Autosave at each dawn and before rest; quick save on demand.

## 12. Verification

`small_following`'s game-only branch forbids test files and verifies by running the game. This project relies on determinism and emergent behaviour that a playthrough cannot check reliably, so this project uses a **headless scenario runner** kept outside the shipped game (approved 2026-10-09):

- `tools/sim_checks.gd` (`extends SceneTree`), run with `Godot_v4.2.2-stable_mono_win64_console.exe --headless --path . --script res://tools/sim_checks.gd`. It builds small sims and asserts properties, printing PASS/FAIL and exiting non-zero on failure. Not exported (excluded in `export_presets.cfg`).
- Scenarios are the NPC guide's property list, adapted: situated (only perceived sites believed), reactive (wolf sighting interrupts and warns), robust (failed forage → different plan, site forgotten), proactive (`should_switch` table), social (knowledge sharing, help requests), determinism (same seed and command log → same `var_to_bytes` hash after 2 days), save round-trip, backoff on exhausted plans, labour spread (≤ 3 per build), mental break override, text coverage.
- Bound God additions: a settlement with an offered dwelling template and a housing deficit builds at least one copy in 10 days; a site with missing materials is not started; a story chain makes a stranger Aware; whispers change utility but never force an adoption below commitment; a shrine below threshold for 3 days goes dormant and expels the avatar; a raid that destroys the altar marks the shrine fallen and writes a chronicle cause.
- Always also: `--headless --editor --quit` parse/import check, and a manual run through `Run.ps1` for anything visual. Visual captures of the inspector and construction go in `docs/verification/` as Final Landing does.

## 13. Milestones

Each milestone ends with a runnable game and a local commit. Order follows the NPC guide's advice: agent core on a small world contract first, **presentation before tuning**.

| # | Milestone | Deliverables | Exit criteria |
| --- | --- | --- | --- |
| M0 | Skeleton | `project.godot` (3D, Forward+, input map), Windows export preset, `tools/sim_checks.gd` stub, `Run.ps1`, `publish*`, `AGENTS.md`, `core/data.gd` + validation, empty title and main scenes | Game boots to title and an empty 3D scene; data validation runs at startup and fails loudly on a broken key |
| M1 | Voxel valley | `voxel_world`, `world_gen`, `chunk_mesher`, chunk views + collision, avatar, camera, day/night light | Same seed → same valley; avatar walks, jumps, steps up blocks; 60 fps on the full valley on the dev PC |
| M2 | Hands-on building | `voxel_ray`, build controller, divine stock, presence zone and boundary, block hotbar | Break/place feels immediate; edits re-mesh within a frame; avatar cannot leave the zone |
| M3 | Templates | Design tool, capture, `room_probe`, `function_rules`, structures registry, library screen, import/export | A cottage built by hand is recognised as Dwelling (2 beds); a roofless one is not; exported file re-imports identically; invalid files are rejected with a reason |
| M4 | Sim core + survival agents | `sim`, `calendar`, `effects`, `nav_grid`, spatial index, agent model, body, generation, perception, inbox, cognition, survival plans (Eat, Sleep, TakeShelter, Flee, Idle), execute, movement, `sim_driver` | Two travellers live through 5 days at 10×: eat berries, sleep, seek shelter at night; same seed → same hash |
| M5 | Legibility | Agent views, picking, inspector (all tabs), decision log text, selection overlay, speed controls | Clicking any NPC shows goal, reason, plan steps, tried plans, log and beliefs vs reality — readable at 1920×1080 and still legible at 1280×720 |
| M6 | Settlement and work | Settlements, stockpile and chests, job board, Gather/Haul/Build/Repair, construction sites, `site_finder`, FoundHome, ProposeProject, culture weights, migrants | **The cottage moment:** offer a dwelling template, rest 10 days, find ≥ 2 copies built by NPCs without any command |
| M7 | Social layer | Talk topics, compatibility, gossip, knowledge and template sharing, courtship, help requests, comfort, reconcile, births, breaks, departure/Migrate | Relationships form over 20 days and are visible in the Bonds tab; a hungry NPC with an empty store gets food from a friend |
| M8 | Faith | Faith state, Pray, shrines (support, Favour, condition, radius), renown, prayer feed, Whisper, Bless Growth, Kindle, Mend, Veil of Fog, god identity, Faith tab | Prayers raise Favour; Bless Growth in front of a hungry believer raises devotion and the harvest aspect; a whisper shows in the decision log |
| M9 | Expansion | Requests, quests, Preach/Story spreading, ridge hamlet, RestoreShrine, transfer, expulsion, dormancy | A follower carries the name to the ridge, miners restore the altar, the ridge shrine becomes active and the avatar transfers there |
| M10 | Threats and change | Wolves, raider band and director, desecration, structure decay, abandonment and overgrowth | An undefended, wealthy ridge hamlet is eventually raided and its shrine can fall; the chronicle names the cause |
| M11 | Time and history | Rest overlay, chronicle screen, "While you rested…" summary, save/load, autosave | Save → quit → load continues identically (hash check); rest of a full season completes in under a minute |
| M12 | Vertical slice polish | Title flow, settings (reuse `small_following` settings/rebinding), audio pass, tuning, export | The GDD §14 proof-of-concept moment is reproducible from a new world by a fresh player in under an hour |

Rough sizing (GDScript lines, for planning only): M1–M3 ≈ 2,500; M4–M7 agent port ≈ 5,000 (Final Landing's 4,500 Rust lines plus construction and 3D movement); M8–M10 ≈ 2,500; UI ≈ 2,500.

## 14. Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| GDScript too slow for meshing or 30 agents at 10× | Mesh arrays on `WorkerThreadPool`; spatial buckets; staggered perception/deliberation (as Final Landing); path request cap; profile at M4 and M6 with 30 agents; greedy meshing; reduce `ticks_per_day` and scale per-day rates (rates are per day, so retuning is free) |
| 3D pathfinding across a mutable voxel world | Local `AStar3D` updates per edit; NPC failure learning already handles `NoPath`; construction blocks never fill the cell an agent stands in |
| Agents building nonsense (blocked doors, overlaps) | `site_finder` checks entrance access and overlaps; sites reserve cells; structures re-evaluated after completion; failed sites logged with reasons |
| The god feels powerless | Hands-on building is always available in the zone; Whisper is cheap; prayer feed gives clear things to fix; tune Favour so a small miracle is affordable most days |
| Remote losses feel arbitrary | Raids only after day 12 with cooldowns; prayers warn before raids ("strangers watch the ridge"); dormancy and restoration instead of deletion; every loss has a chronicle cause |
| Determinism breaks silently | Rules in §1; the hash scenario in §12 runs after every milestone; no `randf()` in sim code (grep check) |
| Template files as an attack surface | Strict validation, size caps, block names resolved against the registry, no code or scene data in templates |
| Scope creep (the concept is vast) | Every "Later" item stays out until M12 passes; new block types need a system that uses them |

## 15. Decisions (2026-10-09)

| Question | Decision |
| --- | --- |
| Headless scenario runner | Accepted: `tools/sim_checks.gd`, outside the exported game (§12) |
| Renderer | **Forward+** (not `small_following`'s Compatibility); environment and graphics settings in §10.1 |
| Platforms | Windows only at this stage; no web export |
| Art | Simple procedural shapes for NPCs and creatures, 16 px block texture atlas |
