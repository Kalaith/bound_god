# Progress

Resume from here and `git log`. Checks: `--headless --path . --script res://tools/sim_checks.gd` and `--headless --path . --editor --quit`. Visual captures: `Godot --path . --position -5000,-5000 --resolution 1920x1080 -- --capture=<scenario> --out=docs/verification/<name>.png [--frames=N]` (debug builds only; the window opens off-screen and never takes focus, at the user's request). Headless cannot capture: Godot 4.2 headless uses a dummy renderer.

## Current milestone

M8 — Faith (M7 complete).

## Done

- M0 Skeleton: data catalogs (`data/*.json`) with `core/data.gd` + `core/validation.gd` (semantic checks, startup error screen), `core/text.gd`, `core/save_store.gd` (staged writes, .bak, .corrupt), title scene (seed, continue, settings, quit), settings screen (sound, display, graphics, key and pad rebinding), empty lit Forward+ main scene, debug capture path, `tools/sim_checks.gd` runner with data and parse scenarios.

- M1 Voxel valley: flat-array `voxel_world`, seeded `world_gen` (valley rim, ridge, river beside the long axis, trees, bushes, grass, boulders, ore, sacred tree, ruined ridge altar, ridge hamlet of two huts and a lean-to), padded-copy `chunk_mesher` with AO (0.9 s single thread, 0.28 s on the thread pool for the full valley), chunk views + concave collision on layer 2, avatar with step-up/jump, spring-arm camera with overlook, sun by hour. Full valley at 1080p: 60 fps (vsync), GPU 5.7 ms. Scripted walk test: climbs a 1-block step, stopped by a 2-block wall.

- M2 Hands-on building: core `Sim` (calendar, god state, resource sites, logged commands), `voxel_ray` DDA, build controller (break/place/hold-repeat, door orientation, hotbar 1-9 + wheel, red preview with reason), divine stock, presence boundary (lattice wall + ground ring), HUD (clock, stock, hotbar, messages). Captures: `build_test` places 6 blocks, re-mesh 9-11 ms; `zone_edge` avatar stops at 15.6 of radius 16; `walk_test` still passes.

- M2 command verification: four scenarios in `tools/checks/checks_commands.gd`, registered with `sim_checks`: resource yields/costs and immediate mesh dirtiness, rejected edits leaving state unchanged (stock, zone, bounds, protected blocks, occupied cells, dormancy), bush harvest/dismantling/replanting and resource-site state, timed command replay and copied log entries. All 10 scenarios pass, including loading every game script. Standard 4.2.2 headless editor import reports no errors (exit-code caveat below). No presentation changes or new visual run in this verification-only step.

- M3 data slice: bounded room probes, component-driven function rules, edit-driven structures and cause records, trimmed capture, strict import validation, staged library writes and backup recovery. Three new scenarios cover two-bed recognition/roof loss, untrusted fields, and file round-trip/recovery.

- M3 Templates: design tool (two-corner box marked with Break, zone/size/bounds check tinting the outline), design library screen (private list, isometric preview, functions/capacity/bill, save, import/export through `FileDialog`). Shelter floor no longer counts the tops of beds. Captures: `m3_design_box_1080.png`, `m3_library_1080.png` (hand-placed hut: dwelling + shelter, 2 beds, 9 sleepers, worst edit command 9 ms).

- M4 Sim core + survival agents: `nav_grid` (AStar3D over standable cells, local reconnect on edits, 0.9 s full build), spatial buckets, Final Landing BDI port (agent, beliefs, goals, plans, mind, personality, generation, deliberation, cognition with commitment, plan library with last-resort plans, execute with failure learning and backoff, perception, inbox, deferred Effects), body with Shelter replacing Warmth (roof = full cover, foliage = half), settlements with a pile and chests, lifecycle deaths, chronicle, daily hooks (stock broadcast, forgetting, opinion decay, berry regrowth), `sim_driver` (frame budget, busy flag, rest). Two travellers at Tree Hollow and five miners at Ridge Hamlet. Checks: situated beliefs, `should_switch` table, failed forage corrects beliefs and replans, exhausted goals back off, travellers live 5 days (eat, sleep, cover at night; 0.6 ms/tick with 7 people), same seed same hash after 2 days, label coverage.

- M5 Legibility: procedural agent views (capsule and head tinted by archetype and hue, child scale, mood ring, carried cube, ASCII activity glyphs, walk bob and work sway, faded indoors, lying down asleep), screen-space picking with the inspect key (crosshair or free mouse), the inspector (Mind: goal, drive, plan steps with markers, already tried, carrying, reasoning log with setbacks in warning colour, beliefs vs reality; Needs; Bonds with links; Life; Faith), selection ring, path and relation lines, Follow (overlook centre tracks the person, clamped to the zone), speed keys P / . / , with the speed and "the world is busy" in the clock line. Captures: `m5_inspector_mind_1080.png`, `m5_inspector_needs_1080.png`, `m5_inspector_mind_720.png`.

- M6 Settlement and work: job boards (sites with readiness and missing materials, repairs from remembered layouts, gather demand per resource from reserves plus site needs, loose items, threats), work candidates with culture weights instead of player priorities (aptitude, company, pursuing divisor), Gather / Haul / Build / Repair / Scout plans, `FoundHome` and `ProposeProject` (known design with the function, materials believed in stock or known in the world, at most two open sites), `site_finder` (spiral from the centre, four rotations, flatness ≤ 1, spacing, door onto walkable ground with a path to the stores, cobble foundations, tall grass cleared), construction sites (reserved cells, bottom-up order, stand cells the builder can actually walk to), completion (structure gets its template id, founder and partner move in, `home_built`, chronicle with the cause), abandonment after 5 idle days, daily culture drift and settlement growth, migrants by attractiveness (spare beds, food, safety), `offer_template` and `transfer` commands, library Offer button, ghost blocks, store piles and loose items, stores panel (Interact), settlement panel (K). Checks: the cottage moment (2 travellers build 2 offered cottages by day 9, seed 11) and no site without believed means.

- M7 Social layer: Final Landing's social candidates (chat partner score, court, comfort, reconcile, help) and plans; Talk (approach within 2, hold for `chat_ticks`), Send, Give, Wait for help, Treat; conversation resolution (directional compatibility, small talk with friction, gossip, sightings, designs and places passed on, insult and fights, flirt and proposal, reconcile, comfort) with bond changes in the chronicle; help requests and replies, gossip and proposal receivers; hourly mental breaks by temperament (lash out, binge, sulk, wander); births to housed couples; daily ambition progress; low-mood accumulation into Migrate (to a believed settlement) or leaving the valley; settlements seen are remembered as places. Performance pass: site finder 290 ms → a few ms (cached heights, blocked columns, shared footprints, failed searches remembered for a day), local structure re-probing, perception without per-tick allocations: 2.4 ms/tick with 13 people. Checks: bonds form in 20 days and reach the chronicle, a hungry person with empty stores is fed by a friend, breaks override, clashing natures sour talk. Capture: `m7_bonds_day20_1080.png`.

## Next

- M8: faith state, Pray, shrines (support, Favour, condition, radius), renown, prayer feed, Whisper, Bless Growth, Kindle, Mend, Veil of Fog, god identity, Faith tab.

## Decisions

- Goals, steps, plans, targets and messages are plain Dictionaries (not RefCounted classes) so agent state saves with `var_to_bytes` without per-class conversion. Goal identity is `kind << 32 | target`.
- Dirt-family blocks (grass, dirt, sand, gravel) yield and cost **soil**, a divine-stock-only resource; settlements never stock it. Keeps "placing consumes one unit" true without making terraforming free.
- A log yields 4 wood (a log makes four planks); tall grass yields 2 thatch. Other blocks yield 1.
- Doors are passable one-block panels; a doorway is two stacked door blocks so a 2-cell-tall person fits. Room probes treat doors as walls.
- `sim_checks` also loads every script under `res://scripts` so presentation parse errors fail headlessly.

- The voxel grid is one flat PackedByteArray (index x + z*W + y*W*D) instead of a dictionary of chunk arrays: far faster in GDScript. Chunks stay the unit of meshing, dirtiness and saving.
- Plans only use structures the person believes in (`beliefs.structures`, filled by perception); a vanished one fails on arrival and is remembered as failed.
- Agents change the shared world only through `Effects` actions (take/deposit stock, forage, harvest, claim a bed, place blocks); the step reads the result from `agent.step_result` on a later tick, so conflicts resolve deterministically in id order.
- Player-facing text is split into `data/text.json` (UI, blocks, templates) and `data/text_agents.json` (goals, plans, fail reasons, activities, log, chronicle); labels share one namespace and duplicates fail validation.
- Thought texts and trait names stay in their own catalogs (`society.json`, `people.json`) beside their definitions; UI chrome lives in `data/text_ui.json`.
- Offered designs reach the residents of the shrine's settlement (in M8: those who know the god); seeing a finished building whose design was offered also teaches it.
- People keep what they carry through every change of mind; a plan that needs free hands first puts the load in the stores (`PlanHelpers.free_hands`), and Haul includes storing a carried load. Final Landing drops loads on every change of goal, which wasted most loads on the valley's long walks. Using the stores updates the user's belief about them.
- Navigation steps are at most one block up or down so every move can be walked back; harvesting never takes a block someone stands on, and anyone whose floor vanishes settles onto the nearest standable cell.
- World generation adds 154 berry bushes (rings near the tree and the hamlet), daily regrowth (none in winter), four stone outcrops near the tree and quarry faces on the ridge, because two travellers otherwise starved or could not find stone.
- Walking pace is Final Landing's 1 cell per tick; ground sleep restores 170/day; recreation decays 22/day.
- Check scenarios are untyped functions: a runtime error then returns null and fails, where `-> String` returned "" and passed silently.
- Builders never stand on the building they are raising; stand cells must be reachable by path.
- Runtime errors inside the simulation do not fail `sim_checks` (only errors in a check function do), so every check run is also grepped for `SCRIPT ERROR`.
- `tools/scratch/` holds local diagnostic probes and is git-ignored.
- Valley layout: sacred tree at (50,50), ridge ruin at (128,128) (~110 blocks), hamlet at (112,134). The river runs beside the tree-ridge axis so nobody must cross water.

## Questions for the user (decided, revisit if you disagree)

- Who learns an offered design? Decided: residents of the shrine's settlement (from M8, only those who know the god). Alternative: only people inside the presence zone at the moment of offering.
- Should travellers start knowing a vernacular design (the lean-to) so Tree Hollow can build without the god? Decided: no; only migrants sometimes bring the lean-to, so the first homes come from the god's designs.
- Movement pace: 1 cell per tick reads as a brisk walk at 1x. Decided to favour a working economy over a slower on-screen pace.

## Known issues

- Use `exports/tooling/Godot_v4.2.2-stable_win64_console.exe` for checks and exports (standard 4.2.2, official archive SHA512 verified). `Run.ps1` still uses Mono. The standard editor removes the Mono `EditorSettings::_EDITOR_GET` shutdown error. Its `--headless --editor --quit` still returns 1, also reproduced with an empty project and fresh portable editor settings. The pinned engine's automatic-quit path does not set a success exit code ([upstream issue](https://github.com/godotengine/godot/issues/83449)). Do not report this as a zero-exit import pass or suppress arbitrary failures: inspect import output for errors and require sim_checks (including all-script parsing) to exit 0. Current standard-editor output has only headless-cursor and unconfigured-Blender warnings.
- Window captures at 1920x1080 are clamped by the desktop work area to 1920x1061; layouts are authored against the 1920x1080 stretch base, so this only trims the bottom 19 px of the capture.
