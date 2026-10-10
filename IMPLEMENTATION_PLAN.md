# The Bound God — Implementation Plan, Phase 2: from vertical slice to full game

> Version 0.2 · 2026-10-10 · companion to `GAME_DESIGN.md`
>
> Phase 1 (M0–M12, the vertical slice) is complete: the GDD §14 moment is built, checked headlessly and captured (see `PROGRESS.md` and `git log`). Phase 1's detailed specifications have been retired from this file; **the code and `PROGRESS.md` "Decisions" are now the reference for everything already built.** This plan covers what turns the slice into a complete, releasable game: milestones M13–M24.
>
> The NPC system remains a port of Final Landing's BDI agents (`NPC System Implementation Guide.md`, **the NPC guide**). Its formulas and values still apply unless this plan or `PROGRESS.md` says otherwise.

## 1. What "fully playable" means

Version 1.0 is done when all of these hold:

1. **A new player needs no outside help.** From the title screen, a player who has never seen the game reaches the cottage moment, a remote shrine and a transfer within the first two hours, guided only by the game.
2. **A campaign lasts.** A world plays for at least **3 in-game years (120 days)** across **at least 3 regions and 5 settlements** without running out of meaningful decisions, and keeps producing caused, readable change: prosperity, famine, raids, occupation, schism, recovery.
3. **The god has a shape.** Different play styles (nurturing, protective, feared, outlaw) produce different identities, miracles and people's responses, and each style can be played to an epilogue.
4. **People feed themselves.** Food has an economy and seasons have teeth: fields, winter stores, weather. Ore and crafts have a use, and settlements trade.
5. **The world is bigger than one valley.** Multiple regions, with only the god's region simulated in full detail and the rest advancing at lower fidelity in a consistent way.
6. **It holds together.** 60 fps at 1080p on the dev PC with the active region populated; saves survive game updates; no known crash or soft-lock; a long headless soak (5 in-game years) finishes without script errors.
7. **It looks and sounds finished.** Coherent art, animation, effects, music and UI, with accessibility and full gamepad navigation.

Out of scope for 1.0 (kept as **Later**): online template sharing and moderation, multiplayer, rival gods as competing players, mod support beyond templates, a web build, platforms other than Windows.

## 2. Baseline and conventions (unchanged from Phase 1)

| Topic | Rule |
| --- | --- |
| Engine | Godot **4.2.2**, GDScript only, **Forward+**. No upgrade, plugin or GDExtension without approval. A Godot upgrade is a separate, explicitly approved decision, not part of any milestone. |
| Platform | **Windows only.** One Windows Desktop export preset. |
| Built-ins first | `ArrayMesh`/`SurfaceTool`, `ConcavePolygonShape3D`, `AStar3D`, `FastNoiseLite`, `RandomNumberGenerator`, `WorkerThreadPool`, `GPUParticles3D`, `AudioStreamGenerator`, `FileAccess`/`DirAccess`. |
| Scripts | `extends RefCounted` for pure logic, `Node`/`Node3D` only for presentation. `const X = preload("res://…")`, no `class_name` sprawl. Static typing everywhere. Tabs, LF, UTF-8. |
| Data | All tuning in `data/*.json` with `schema_version`, validated at startup by `core/validation.gd`. Missing or mistyped keys fail fast; no silent defaults. New catalogs below follow the same pattern. |
| File size | **Hard limit 800 lines per file** (scripts, scenes, data, docs); aim ≤ 600 in scripts. Split by responsibility; never compact formatting to fit. |
| Resolution | Authored at **1920×1080** (`canvas_items`, `expand`), readable at 1280×720. |
| Saves | `user://`, staged writes, `.bak` recovery, `.corrupt` quarantine; `var_to_bytes` on plain data for sim state, JSON only for hand-edited data and templates. |
| Commits | Commit after every complete, working step; each commit boots and passes checks. Publishing needs separate authorisation. |

Determinism rules (still binding): simulation code never touches the scene tree, physics, `Time`, `OS` or global `randi()`/`randf()`; all randomness from `sim.rng` (or a sub-stream seeded from it); every comparator tie-breaks on a stable id; iterate sorted keys when dictionary order affects outcomes; Godot 4.2 has no typed dictionaries, so document key and value types in a comment.

## 3. Architecture changes in Phase 2

The Phase 1 architecture stays: `Sim` owns all state and runs headless; presentation polls it and sends logged commands between ticks; agents write only to `Effects`. Phase 2 changes four things.

### 3.1 Regions (M18)

```
World (sim/world_state.gd)
├── regions: Dictionary          # int region id -> Region
│   ├── Region (detailed)        # VoxelWorld + NavGrid + Structures + agents in full BDI (the Phase 1 Sim body)
│   └── Region (abstract)        # RegionSummary: settlements, population records, stock, faith, projects, events
├── travellers: Array            # people between regions: {agent record, from, to, arrive_tick}
├── god, chronicle, calendar, rng, command_log, factions
```

- Exactly **one region is detailed**: the one the avatar is manifested in. Every other region is **abstract** and advances once per in-game hour by `sim/region_abstract.gd`.
- **Abstracting** a region (the god leaves): agents are frozen into records (needs, beliefs, faith, bonds, current goal kind), construction sites into `{template, origin, rotation, cursor}`, edited chunks are kept compressed, nav and meshes are dropped.
- **Materialising** a region (the god arrives): regenerate from the region seed, apply edited chunks, **stamp projects completed while abstract** at their reserved sites, advance partial sites to their cursor, apply recorded decay and overgrowth, rebuild nav, then thaw agents at plausible places (home by night, work site or stores by day). Arrival happens behind the transfer effect, which also hides the load.
- **Consistency rule:** an abstract region may only produce outcomes the detailed simulation could also produce: building only known templates on sites found by `site_finder` (run at abstraction time, reserved), consuming stock at detailed-sim rates, rolling the same event kinds (births, deaths, migrations, raids, shrine state) from the same balance numbers. Each abstract outcome writes a chronicle entry with a cause, exactly like the detailed sim.
- **Determinism:** each region draws from its own `RandomNumberGenerator` seeded from `(world_seed, region_id)`, and abstract steps run in region id order. Detailed vs abstract continuation will *not* hash-match; the check is statistical (§5, M18).

### 3.2 Save schema migrations (M13)

Players will carry campaigns across updates from Phase 2 onward.

- `sim_state` writes `schema_version` (starting at 2 for the first Phase 2 format). `core/save_migrations.gd` holds one pure function per step (`_v2_to_v3(state: Dictionary) -> Dictionary`) applied in order on load.
- Each migration ships with a **fixture save** under `tools/fixtures/` produced by the previous version, and a `sim_checks` scenario that loads it, migrates, and runs a day without errors.
- A save from a *newer* version is refused with a clear message, never half-loaded.

### 3.3 New data catalogs

| File | Contents | Milestone |
| --- | --- | --- |
| `crops.json` | Crops `{id, stages, days_per_stage, seasons, yield, rain_need}` | M14 |
| `recipes.json` | `{id, station, inputs, outputs, ticks, skill}` for meals, tools and goods | M14, M16 |
| `weather.json` | Weather kinds per season with weights, durations and modifiers | M15 |
| `regions.json` | Region archetypes `{id, terrain profile, resources, features, settlement kinds}` | M18 |
| `factions.json` | Faction kinds (village, mining town, bandits, traders) with culture biases and relations | M19 |
| `saga.json` | Optional deeds and age-naming rules | M22 |
| `miracles*.json` | Split by tier when the catalog grows (M20); effects remain a closed, implemented set | M20 |

Every new catalog gets validation and label coverage (every id has player-facing text in a text catalog).

### 3.4 Performance budget

| Measure | Target |
| --- | --- |
| Detailed region | 60 people at 3× within the 4 ms sim budget per frame; 10× may show "the world is busy" |
| Abstract regions | All of them together < 2 ms per in-game hour |
| Rest | One season of rest across a full world (9 regions) < 30 s |
| Materialise a region | < 3 s behind the transfer effect (world gen + chunks + nav on the thread pool) |
| Frame | 60 fps at 1080p, GPU < 10 ms with weather and particles |

## 4. Phase 2 milestones

Each milestone ends with a runnable game, new `sim_checks` scenarios for its simulation features, captures in `docs/verification/` for anything visual, and local commits throughout. Order: make the slice hold up first, then deepen the local economy (it is the content every later system distributes across regions), then widen the world, then the god's identity, then finish and ship.

| Stage | Milestones |
| --- | --- |
| A. Hold up | M13 Playtest, balance and foundations |
| B. A living economy | M14 Fields and meals · M15 Seasons and weather · M16 Crafts and tools |
| C. Living architecture | M17 Designs that grow |
| D. A wider world | M18 Regions · M19 Peoples, factions and trade |
| E. The god's many faces | M20 Identity and miracles · M21 Followers and requests |
| F. A whole game | M22 Campaign shape · M23 Look, sound and feel · M24 Release |

---

### M13 — Playtest, balance and foundations

**Goal:** the slice survives contact with players, and the foundations for a long campaign are in place before content is added.

- **Fresh-player playtests** (at least three people who have not seen the game) of the GDD §14 moment, observed without help. Record where each stalls and for how long in `docs/playtests/`.
- **Balance pass** from the findings: Favour income vs miracle costs, travellers' starting conditions, the Ridge Hamlet hostility (enemies at −100 within days, listed in `PROGRESS.md` Questions), raid timing after the ridge shrine is raised.
- **Onboarding v2:** the first-steps guide line becomes a short sequence of contextual prompts tied to world state (hungry person in view → "Someone is hungry. Bless Growth or bring berries to the stores"), each dismissible and remembered in settings. The guide never acts for the player.
- **Profiling at scale:** a 60-person detailed population (raised cap behind a debug flag) at 1×, 3× and 10×. Fix the top costs (likely perception, job boards, social candidate search, nav path requests).
- **Region feasibility spike:** measure world gen, meshing, nav build and memory for one region on the thread pool, and freeze/thaw of 40 agent records. This fixes the region size used in M18 (default 160×48×160).
- **Save migrations** (§3.2) and a version stamp in `meta.json` and on the title screen.

**Playtest round 1 (2026-10-10): the first village.** Fresh players enjoyed the slice but found too little to build and too few people to build a real settlement with. Before the wider economy (M14+), M13 makes one settlement grow into a self-sustaining village, and lets that village found a second one as the campaign's first "final push". Everything stays influence, not obedience.

- **Settlement standing** (`sim/standing.gd`, daily): each settlement is a **camp**, **hamlet** or **village**, judged only from what it has (residents, people housed, food days in its chests, and the functions standing in its area). Criteria live in `balance.json` (`standing`). A rise or fall is chronicled with what changed. The settlement panel lists what the place has and still lacks; once the first believer exists, the guide points at the next thing the settlement lacks, then at founding and at a shrine for the new place, before the ridge steps. A **village** is the self-sustaining state: 10 people, everyone housed, a day of food in its chests, four homes, a storehouse, a hall, a garden and a living shrine.
- **Builders make do:** a site that waits a day for stone nobody has or knows where to find raises its remaining plain stone walling in planks (components stay stone), and a founder who believes in no stone lays the site out in timber from the start. Found in the playtest-round probe: the three home outcrops hold about two cottages' worth of stone, so building stopped at four cottages with five people homeless. (A first step of M17's material substitution.)
- **Food:** in autumn people want food put by (berry reserve per person rises), food work pulls harder while the chests hold under a day of food, and a settlement going hungry draws no migrants.
- **More people:** migrants judge safety by threats near the settlement (not wolves anywhere in the valley), roll more often, come in larger groups to a hamlet or village, and bring designs of their own (a cottage, a lean-to, a hall), so a settlement's building knowledge grows without the player. Population cap rises to 45.
- **More to build** (new components with implemented effects, closed catalog):
  - `table` and `bench` (wood): a **Hall** (table, ≥ 2 benches, roofed floor ≥ 12; no hearth, so it needs no stone). Relaxing or talking in a hall restores recreation twice as fast and gives the `gathered_in_hall` thought. Leaders propose a hall once 6 people live in a settlement without one.
  - `planter` (wood): a **Garden** (≥ 4 connected planters). Berry bushes on planters regrow twice as fast and still bear in winter; a `Garden` work goal picks ripe garden bushes into the stores and plants a berry in an empty planter, working from within reach (a fenced garden is worked from outside). Leaders propose a garden (one per 5 people) when food days are low. The M14 field reuses this path.
  - `lantern` (stone): light. Wolves will not enter lantern light, and people near a lantern at night keep their full sight. A lit settlement counts as safe for migrants.
  - A function reference in the design library shows what each function needs, so a player can design for it.
- **Founding a second settlement:** world generation marks three **founding grounds** (flat land ≥ 45 blocks from the tree and the hamlet). From a **village**, the god may post **Found a settlement at** *ground* (up to 3 takers). Takers take provisions from the stores, walk there, set down a chest and camp, and become residents of a new settlement that carries their designs; the request is done when the settlers live there. Each ground has a few berry bushes and a knuckle of stone. Settlers sleep near their own camp, pray where they live when the shrine they know is far, and do not wait by day for cover they do not know of: they build. They then found homes and, as believers, raise an altar by their own choice or by a Raise a shrine request, which makes the new place a transfer destination.

**Exit:** two of three playtesters reach the §14 moment in under an hour unaided; 60 detailed people hold 60 fps at 3× on the dev PC; a fixture save from the slice loads through the migration path. **Village:** on seed 11, with a cottage, a store shed, a hall and a garden offered, the stores supplied once and the first residents believing, Tree Hollow reaches village standing within 40 days headless, and a Found a settlement request then produces a second settlement with residents and a chest within 10 days. Checks: standing criteria, migrant safety near home, hall recreation, garden regrowth and tending, lantern keeps wolves out, founding a settlement.

---

### M14 — Fields and meals

**Goal:** food becomes an economy that people plan for, with stores to see a settlement through winter.

- **Blocks:** `farmland` (made from dirt with a hoe or by hand), `crop` (one block, growth stage in cell meta), `hearth` already exists, `granary_bin` (storage for grain only, larger capacity).
- **Resources:** `grain` (keeps), `seed` (from harvest; sowing consumes it), `meal` (cooked; spoils after 3 days). Berries now **spoil after 6 days** in stock, so they no longer carry a settlement through winter.
- **Functions** (`templates.json`): **Field** (≥ 6 connected farmland blocks, open sky), **Kitchen** (hearth, roofed, worktop: a workbench or a chest), **Granary** (≥ 2 granary bins, roofed, door).
- **Crop growth** (`sim/crops.gd`, daily): stage advances by `days_per_stage` in growing seasons when tended; untended fields gain weeds that halve yield; winter kills unharvested crops. Bless Growth advances every crop in its radius by one stage.
- **Goals and plans:** `Farm(field)` (sow in spring, tend, harvest in late summer and autumn; job board entries per field), `Cook` (meals at a Kitchen from grain and berries; recipe in `recipes.json`). Eating prefers meals (Food +60, thought `ate_a_meal`) over grain (+35) over berries (+25).
- **Planning ahead:** each settlement tracks **food days** = stored food ÷ daily consumption. Below 20 food days in autumn, `ProposeProject(field)` and `ProposeProject(granary)` gain utility, Farm culture weight drifts up, and prayers carry the intent "fear of winter".
- **Templates:** a field is a capturable template (flat), so the player can offer a field layout, and NPCs build fields through the normal construction path (fences and farmland as blocks).
- **Presentation:** crop stages in the block atlas, field ghosts, food days on the settlement panel, a sowing/harvest glyph.

**Exit:** a settlement of 10 people offered a field template sows in spring, harvests, stores grain and gets through its first winter without starving in a 40-day headless run (seed 11), and the chronicle records the first harvest. Checks: spoilage, winter crop death, food-days-driven project, meal preference.

---

### M15 — Seasons and weather

**Goal:** seasons and weather change what people need and give the god new ways to help or harm.

- **Weather per region** (`sim/weather.gd`, from `weather.json`): clear, overcast, rain, storm, snow, drought, each with seasonal weights and durations rolled from the region's RNG at dawn. Forecast-free: people only know the weather they see.
- **Effects:** rain waters fields (drought stalls growth after 3 dry days in summer); storms damage exposed thatch and crops (chronicle cause); snow slows walking (nav cost ×1.5 outdoors) and doubles Shelter decay; winter nights cost health when Shelter is at 0 (exposure), so housing matters in winter in a way it does not in summer.
- **People react** through existing goals: TakeShelter weights rise with weather, Farm avoids storms, prayers carry weather intents ("rain for the fields").
- **Miracles** (closed catalog additions, implemented in `sim/miracles.gd`): **Call Rain** (harvest, medium, ends a drought locally for a day) and **Still the Storm** (protection, medium). Kindle gains value in winter.
- **Presentation:** sky and light by weather, rain and snow particles (`GPUParticles3D`, culled to the camera), wet-ground tint, snow cover as a shader overlay on top faces (no block edits), wind audio by weather.

**Exit:** a year in the valley shows a visible seasonal rhythm in the chronicle (a drought summer and a hard winter on seed 11), people die of exposure only when homeless in winter, and Call Rain after a drought prayer counts as an answered prayer. Checks: weather determinism, drought growth stall, exposure rule, weather intents.

---

### M16 — Crafts and tools

**Goal:** ore and workshops matter, and the ridge has something to trade.

- **Workshop function** becomes useful: `Craft(recipe)` work goal at a workbench, job board entries driven by settlement demand (tools wearing out, missing goods).
- **Tools** (`recipes.json`): axe, pick, hoe from wood + ore. A worker with the right tool works ×1.5 at the matching task; tools wear (40 uses) and are stocked like resources. A **Smithy** function (hearth + workbench + stone floor, roofed) is required for ore tools.
- **Goods** for trade and comfort: furniture (planks), pottery (stone + hearth), a small set kept within the closed-catalog rule. Furnished dwellings give the `comfortable_home` thought.
- **Skills:** Crafting skill gains use; apprentices learn faster near a skilled crafter (social layer reuse).
- **The ridge economy:** the hamlet's culture biases toward mining and smithing, so it accumulates tools and ore and lacks food: the precondition for trade in M19.

**Exit:** the ridge hamlet produces tools within 15 days and Tree Hollow's gatherers work visibly faster with them; a settlement without a smithy never makes ore tools. Checks: tool wear and restock demand, smithy gating, tool speed bonus.

---

### M17 — Designs that grow

**Goal:** architecture becomes a living tradition that no longer depends on the player's library (GDD §5.4 Later items).

- **Vernacular designs** (`building/vernacular.gd`): a builder with a need and no fitting known design can **devise one**: a small parametric generator (footprint 3×3 to 7×7, wall material from settlement stock, roof style, bed or chest count by need) that produces a normal template, validated by `function_rules` before use. Devised designs spread like offered ones and appear in the chronicle ("Edda devised a hut of her own"). The player can **learn** a design from any building they can see (capture it with the design tool), so knowledge flows both ways.
- **Material substitution:** substitution groups in `blocks.json` (walls: planks ↔ cobble ↔ cut stone; roofs: thatch ↔ planks). Builders substitute by settlement stock; a substituted building keeps its template id and function. The settlement panel and inspector show "built from Willow Cottage, in stone".
- **Mirroring and orientation:** `site_finder` tries 8 orientations (4 rotations × mirror) and prefers facing the nearest path.
- **Renovation and repurposing:** residents move into empty dwellings before building new ones; a structure whose function changes is chronicled as converted; `Salvage(structure)` dismantles ruins and abandoned sites for materials when stock is short.
- **Roads by use:** foot traffic is counted per column; after a threshold the top block wears into a `path` block (lower nav cost; grass regrows on unused paths). The chronicle and the settlement panel can answer "why does this road exist" ("worn by haulers between the ridge quarry and the stores since day 31").
- **Traditions:** each settlement weights designs by how many it has built (preference in FoundHome/ProposeProject), and the library shows adoption counts per settlement.

**Exit:** a settlement never offered a design still builds homes within 15 days by devising them; on seed 11 a worn path forms between Tree Hollow and its quarry within 20 days; a stone-rich settlement builds the offered wooden cottage in stone. Checks: devised designs pass function rules, substitution keeps function, path wear and regrowth, empty dwellings adopted first.

---

### M18 — Regions

**Goal:** the world grows beyond one valley, and only the god's region runs in full detail (§3.1). This is the largest technical risk in Phase 2; M13's spike de-risks it.

- **World layout:** a world of **3×3 regions** (standard; small 2×2, large 4×4 in M22), each a bounded voxel volume of the M13 size, joined by **passes** at the edges. Region archetypes from `regions.json`: home valley (Phase 1 generator), highlands (mining town), forest (wolves, outlaws), coast or lake (fishing, a later food source if scope allows), each with a ruined altar or standing stone.
- **Detailed/abstract switching** as §3.1, triggered by transfer, expulsion and loading.
- **Abstract model** (`sim/region_abstract.gd`, hourly): per settlement — food produced and eaten from population, culture and fields; construction progress from labour-hours on reserved sites; births, deaths, migrants and departures from detailed-sim rates; faith drift, prayers (Favour and support still accrue at abstract shrines, so shrines can go dormant or wake while the god is away); raids rolled by the director with the same wealth/defender score.
- **Travel between regions:** quest takers, migrants, traders and raiders leaving a region become `travellers` with a travel time from distance through passes; they arrive as BDI agents if the target is detailed, as records otherwise.
- **World map screen** (M key): regions and known places as the god believes them, with the **age of each report** ("last heard of 6 days ago, from Brannoc"). Places are revealed by followers' reports and prayers, never by default (GDD §7.4 imperfect information).
- **Prayer summaries** from other active shrines arrive delayed, as designed in GDD §7.4.

**Exit:** a follower carries the name from the home valley through a pass to the highland mining town while the god stays home; the town (abstract) raises a shrine; the god transfers and finds the shrine, its builders and the town's projects materialised in place, and the chronicle explains them. Statistical check: a settlement run 20 days abstract vs 20 days detailed from the same state ends within tolerance on population, stock, built structures and believers (tolerances written in the check). Performance targets in §3.4 met.

---

### M19 — Peoples, factions and trade

**Goal:** settlements have allegiances and interests, outlaws are people rather than a raid timer, and goods and stories travel by trade.

- **Factions** (`factions.json`, `sim/factions.gd`): every settlement belongs to a faction (villages, the mining town, an outlaw band, travelling traders); faction relations come from accumulated events (trades, raids, help, insults between members) and set default trust between strangers.
- **Outlaws as BDI agents** (replacing the scripted raider band, Phase 1 Later): an outlaw camp in the forest region with its own people, needs and goals: `Raid(settlement)`, `Loot`, `Camp`, `Recruit`. Raids are decided by outlaw leaders from believed wealth and defenders, instead of a director roll. The director keeps only pacing guards (no raid before day 12, cooldowns, warnings via prayers).
- **Occupation and change of hands:** outlaws can occupy an abandoned or defeated settlement; a starving, low-mood settlement with outlaw sympathisers can **turn outlaw** itself (culture drift toward raiding). Occupied buildings keep their history in the chronicle.
- **Trade:** `Trade(settlement)` goal for traders and believers with the Merchant leaning: carry surplus to a settlement believed to lack it, exchange at prices from relative scarcity, return. Trade raises faction relations, spreads stories and designs (the concept's Year 6 beat), and wears roads (M17).
- **Mutual aid:** allied settlements send defenders or food in a crisis through the existing help-request path, scaled to settlements.
- **Abstract support:** factions, trade runs and raids all have abstract versions in `region_abstract.gd`.

**Exit:** over 60 days on seed 11 at least one trade route forms between the ridge (tools) and Tree Hollow (food) and appears in the chronicle; the outlaw camp raids by its own decision and can be driven off or reconciled; a settlement left to starve can turn outlaw, with the chronicle explaining why. Checks: outlaw raid decision from beliefs, price from scarcity, occupation of an empty settlement, faction relation drift.

---

### M20 — Identity and miracles

**Goal:** reciprocal belief: what people believe the god is shapes what the god can do, and both benevolent and malevolent paths are fully playable (concept principle 7).

- **Identity-gated miracles:** each miracle requires renown *and* a minimum share of its aspect in the identity of the shrine's congregation (local identity, so two communities can unlock different miracles). Tiers by renown: small 0, medium 15, **large 40**, **exceptional 80**.
- **New miracles** (each implemented before it enters the catalog):

| Tier | Miracle | Aspect | Effect |
| --- | --- | --- | --- |
| Small | Guide Animals | travel | Wolves in range wander away for a day |
| Small | Ease Hardship | harvest | One person's lowest need +30 |
| Large | Bless Settlement | harvest | A season of faster crop growth and +mood for residents |
| Large | Awaken Guardian | protection | A guardian creature defends the shrine area against threats for a season; it is a world actor with its own simple behaviour, not commanded |
| Large | Divert Water | travel | Carve or fill a drawn channel of water blocks inside the zone |
| Large | Summon Storm | wrath | A storm (M15) over a chosen settlement area, damaging thatch, crops and morale |
| Exceptional | Raise the Land | protection | Lift or sink a large area of terrain inside the zone |
| Exceptional | Calamity | wrath | A blight and storm together over a settlement |
| Malevolent (small) | Smite | wrath | Injure one person or threat; witnesses' devotion follows GDD §6.4 fear worship |
| Malevolent (medium) | Blight | wrath | Crops and bushes in range wither |

- **Fear worship** extended: a god whose wrath identity dominates gains devotion from the cautious through fear, and fearful believers pray to avert harm rather than ask for help (new prayer intents). A feared god's people tend shrines out of fear.
- **Outlaw faith:** the shadow aspect read by outlaws makes the god a protector of the unwanted; an outlaw camp can build an altar and become a congregation (concept Year 10).
- **Schisms:** when two congregations' identities diverge beyond a threshold, they become **sects** of the same god: friction in talk between members, rival preaching, and in extreme cases desecration of the other sect's shrine. Chronicled with the cause.
- **The god's look:** avatar colour, glow and particle style, and shrine dressing follow the identity, so a player sees what the god has become.

**Exit:** two scripted runs on the same seed, one using harvest and protection miracles and one using wrath, end 40 days later with different dominant identities, different unlocked miracles, and different behaviour from the cautious; a schism forms when two shrines are driven to opposite identities. Checks: aspect gating, fear-worship devotion, guardian not obeying commands, schism threshold.

---

### M21 — Followers and requests

**Goal:** followers are the god's hands in the wider world; requests cover the concept's list, and stories of named followers carry the campaign.

- **Requests** (closed catalog, each with an implemented completion rule): Carry my name, Bring, Raise a shrine, Restore (Phase 1), plus **Protect** (no successful raid on a settlement for 5 days), **Investigate** (reach a place or danger and report), **Trade with** (complete a trade run with a settlement), **Recruit** (persuade migrants to come), **Convert** (reach N believers in a settlement), **Found an outpost** (build a dwelling and an altar at a place).
- **Reports:** a returning follower's beliefs about a place become the god's knowledge of it on the world map, including stale or wrong beliefs, marked with their source and age.
- **Relics:** a fallen shrine's altar leaves a relic item; believers may hide it, carry it, and use it to found a new shrine elsewhere with a support bonus (concept: survivors hide sacred objects). Raiders may take relics as loot.
- **Notable followers:** Devout people with long service gain titles (Voice, Keeper, Wanderer) by what they did; titles add weight to their stories and preaching; their deeds and deaths are chronicle highlights and feed the epilogue.
- **Request UI:** stays in the shrine menu, with a requests journal listing open, taken, completed and failed requests and who took them.

**Exit:** each request kind can be completed by NPCs in a headless scenario; a relic carried from a fallen ridge shrine founds a new shrine elsewhere; a world map entry shows a wrong report that is corrected when a second follower returns. Checks per request kind, relic chain, report staleness.

---

### M22 — Campaign shape

**Goal:** a run has a beginning, a shape over years, and an end the player can choose (GDD §15 "formal endgame": open-ended with an epilogue).

- **New world screen:** seed; world size (small 2×2, standard 3×3, large 4×4 regions); **harshness** (gentle / standard / hard: raid start and frequency, winter severity, outlaw strength); **starting anchor**: sacred tree (harvest bias), standing stone (protection bias), spring (travel bias), each with its own shrine look and starting zone shape; starting people (two travellers or a small family).
- **Ages:** the chronicle divides the run into named ages from its dominant events ("The Age of Founding", "The Hungry Years", "The Ashen Wars"), shown in the chronicle and the rest summary.
- **Saga** (`saga.json`): optional deeds tracked in a journal (a street of ten homes from one design, shrines in three regions, a settlement through a famine without a death, a schism healed, an outlaw camp converted). No victory screen; deeds frame long-term goals.
- **Epilogue:** when the god fades (no believers) or when the player chooses "Close the book", an epilogue summarises the world: settlements and their fates, the god's identity, notable followers, ages and deeds. The player may continue watching.
- **Chronicle export:** the chronicle and epilogue export to a readable HTML file through `FileDialog` (shareable story).
- **Statistics:** population, believers, shrines, Favour, food days over time, shown as simple charts in the chronicle screen.

**Exit:** each starting anchor and harshness level starts a valid world; a 3-year headless run produces at least three named ages and an epilogue; "Close the book" and continuing to watch both work. Checks: new-world options produce valid sims, age naming is deterministic, epilogue covers every settlement.

---

### M23 — Look, sound and feel

**Goal:** the game looks and sounds like one coherent, finished work.

- **Blocks:** atlas v2 at 16 px with per-block variants and seasonal tints; crops, paths, granary and smithy blocks; consistent palette across regions.
- **People and creatures:** procedural figures gain simple limbs with code-driven walk, work, pray, sleep and fight poses (still no art pipeline); wolves, outlaws and the guardian get distinct silhouettes; clothing tint by faction and role.
- **Effects:** miracle VFX per aspect, transfer effect, shrine states (active glow, dormant fade, fallen), weather (M15).
- **Music and sound:** an ambient score by region and season, stingers for births, deaths, shrines and raids, and a mix pass. Whether music is synthesised or recorded tracks is an open decision (§6).
- **UI pass:** one consistent theme across all screens, readable at 1280×720, icons for resources and needs, a tooltip pass.
- **Accessibility:** UI scale, colour-blind-safe mood and state colours, reduced motion (camera bob, flashes), hold or toggle for held inputs, subtitles for sound cues, **full gamepad navigation** of every screen.
- **Localisation readiness:** every string from text catalogs, no sentence assembly by concatenation, a pseudo-locale check that finds hard-coded text.

**Exit:** a capture set of every screen at 1080p and 720p in `docs/verification/`; every screen usable with a gamepad only; pseudo-locale run shows no untranslated strings.

---

### M24 — Release

**Goal:** a stable 1.0 Windows release.

- **Stability:** a 5-year headless soak on the three world sizes with no script errors and stable memory; crash-safe autosave rotation (3 autosaves); an error log file under `user://logs/`.
- **Saves:** fixture saves from every Phase 2 schema version migrate and run (§3.2).
- **Performance:** the §3.4 targets on the dev PC and on a lower-spec reference machine (graphics settings tested).
- **Onboarding final:** the contextual guide (M13) extended to Phase 2 systems (fields, weather, regions, map, requests), still optional.
- **Release build:** version numbering, credits and licences screen, `publish.ps1` build, download page, itch page and channel (publishing only with authorisation), release notes from the chronicle of changes.
- **Closed beta:** a small group plays a full campaign; fixes from their reports before 1.0.

**Exit:** §1's definition of "fully playable" holds, each point verified and recorded in `PROGRESS.md`.

## 5. Verification in Phase 2

Phase 1's approach stays: `tools/sim_checks.gd` (headless scenarios, PASS/FAIL, non-zero exit), the parse/import check, every check run grepped for `SCRIPT ERROR`, off-screen window captures for visuals, and plain reporting of what was and was not checked. Additions:

- **Long-run scenarios** (`tools/checks/checks_campaign.gd`): a 120-day standard world with no player commands must not empty every settlement, must produce shrines in more than one region, and must keep all invariants (no agent stuck in one plan for more than 2 days, no unreachable construction cell, stock never negative).
- **Statistical checks** for abstract vs detailed regions (M18), with tolerances in the check file and fixed seeds.
- **Fixture saves** for migrations (§3.2).
- **Playtest notes** in `docs/playtests/` at M13, M18, M22 and M24: who played, how long, where they stalled, what they said, what changed as a result.
- `sim_checks` runtime must stay under 5 minutes; long-run scenarios run behind a `--long` flag before each milestone commit.

## 6. Open decisions

Each is the user's call; the plan proceeds on the leaning until decided.

| Question | Leaning |
| --- | --- |
| World size and region count | 3×3 regions standard, 160×48×160 each (fixed by the M13 spike) |
| Music | Synthesised ambient score (matches the current no-asset audio) with recorded tracks as an option if commissioned |
| Art direction beyond procedural figures | Stay procedural and code-animated; improve the atlas by hand |
| Rival gods and religions | Later (after 1.0); schisms inside the god's own faith (M20) carry that role in 1.0 |
| Malevolent miracles | In 1.0 (concept principle 7); fear worship already exists |
| Distribution | itch.io Windows build; Steam is a separate decision |
| Population caps | 60 detailed in the active region, 200 across the world |
| Coast or lake region with fishing | Only if M18 lands on time; otherwise Later |

## 7. Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Regions refactor destabilises the working sim | M13 spike first; keep the detailed region code path identical to Phase 1; abstract model behind its own checks; statistical consistency check before moving on |
| Abstract and detailed outcomes diverge visibly on return | Consistency rule (§3.1): abstract regions only produce detailed-sim-possible outcomes, sites reserved through `site_finder`, every outcome chronicled |
| GDScript too slow for 60 detailed people | M13 profiling; staggered deliberation and perception; caps on path and site searches per tick; reduce work done by sleepers; abstract everything outside the active region |
| Content sprawl (crops, recipes, miracles) | Closed catalogs tied to implemented effects; every addition needs a system that uses it (concept principle 10) |
| Saves break between updates | Migrations with fixtures from M13 on; newer-version saves refused cleanly |
| Players feel lost in a larger world | World map with report ages, prayer summaries, contextual guide, saga journal as optional direction |
| Malevolent play breaks the world | No game over; fear worship and outlaw faith keep a feared god playable; the world recovers through people |
| Influence-not-obedience erodes under pressure for convenience | Product invariants in `AGENTS.md` apply to every new system: guardians, trade, factions and requests change what NPCs know, want or can do, never what they must do |
