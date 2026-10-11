# The Bound God — Implementation Plan, Phase 2: from vertical slice to full game

> Version 0.3 · 2026-10-10 (cultivation-sect direction) · companion to `GAME_DESIGN.md`
>
> Phase 1 (M0–M12, the vertical slice), M13's village track and M14 (fields and meals) are built. **The code and `PROGRESS.md` are the reference for everything already built**; their specifications are no longer kept here. This plan covers what turns the slice into a complete game under the cultivation-sect direction (GDD v0.3): the cultivation slice first (M15–M18), then the systems that widen it (M19–M25).
>
> The people remain a port of Final Landing's BDI agents (`docs/reference/npc_system_guide.md`, **the NPC guide**). Its formulas and values apply unless this plan or `PROGRESS.md` says otherwise.

## 1. What "fully playable" means

Version 1.0 is done when all of these hold:

1. **A new player needs no outside help.** From the title screen, a player who has never seen the game sees a sect form around the tree and witnesses a first tribulation within the first two hours, guided only by the game.
2. **The key test holds** (GDD §17.2): a player grows attached to a disciple, influences their fate at a meaningful cost, meditates through years and returns to a visibly evolved sect whose growth also changed the tree.
3. **A campaign spans generations.** A world plays for at least **200 in-game years**, mostly in meditation, through at least three sect masters, and keeps producing caused, readable change: prosperity, famine, schism, branches founded and lost, recovery.
4. **The tree has a shape.** Different tribulation histories leave trees with different insights, unlocks and scars, and different nurturing styles give sects different doctrines.
5. **People feed and equip themselves.** Food, seasons and weather matter; herbs and crafts feed cultivation.
6. **The world is bigger than one valley.** Branch sites in other regions, with only the god's region simulated in full detail and the rest advancing at lower fidelity in a consistent way.
7. **It holds together.** 60 fps at 1080p on the dev PC with the active region populated; saves survive updates; no known crash or soft-lock; a long headless soak (200 years, mostly abstract) finishes without script errors.
8. **It looks and sounds finished.** Coherent art (the ink-and-pastel direction), animation, effects, music and UI, with accessibility and full gamepad navigation.

Out of scope for 1.0 (**Later**): online template sharing, multiplayer, rival gods, mod support beyond templates, a web build, platforms other than Windows, hidden-realm generation beyond one hand-built realm.

## 2. Baseline and conventions

| Topic | Rule |
| --- | --- |
| Engine | Godot **4.2.2**, GDScript only, **Forward+**. No upgrade, plugin or GDExtension without approval. |
| Platform | **Windows only.** One Windows Desktop export preset. |
| Built-ins first | `ArrayMesh`/`SurfaceTool`, `ConcavePolygonShape3D`, `AStar3D`, `FastNoiseLite`, `RandomNumberGenerator`, `WorkerThreadPool`, `GPUParticles3D`, `AudioStreamGenerator`, `FileAccess`/`DirAccess`. |
| Scripts | `extends RefCounted` for pure logic, `Node`/`Node3D` only for presentation. `const X = preload("res://…")`, no `class_name` sprawl. Static typing. Tabs, LF, UTF-8. |
| Data | All tuning in `data/*.json` with `schema_version`, validated at startup. Missing or mistyped keys fail fast; no silent defaults. |
| File size | **Hard limit 800 lines per file** (scripts, scenes, data, docs); aim ≤ 600 in scripts. Split by responsibility; never compact formatting. |
| Resolution | Authored at **1920×1080** (`canvas_items`, `expand`), readable at 1280×720. |
| Saves | `user://`, staged writes, `.bak` recovery, `.corrupt` quarantine, schema migrations with fixtures (`core/save_migrations.gd`, `tools/fixtures/`). Newer-version saves are refused cleanly. |
| Commits | Commit after every complete, working step; each commit boots and passes checks. Publishing needs separate authorisation. |

Determinism (binding): simulation code never touches the scene tree, physics, `Time`, `OS` or global `randi()`/`randf()`; all randomness from `sim.rng` or a sub-stream seeded from it; comparators tie-break on stable ids; iterate sorted keys when dictionary order matters; document dictionary key and value types in comments.

## 3. Architecture changes

The architecture stays: `Sim` owns all state and runs headless; presentation polls it and sends logged commands between ticks; agents write only to `Effects`.

### 3.1 The abstract settlement model (M18, reused by regions in M22)

Generational play needs years to pass in seconds. A settlement can be advanced in two fidelities:

- **Detailed:** the full BDI simulation (today's sim).
- **Abstract:** `sim/abstract/*.gd` advances a settlement record once per in-game hour: food produced and eaten from population, culture and fields; construction progress from labour-hours on sites reserved by `site_finder`; births, ageing, deaths, migrants and departures from detailed-sim rates; cultivation progress from talent, qi and technique; breakthroughs and tribulations rolled from the same rules; faith drift and prayers (Favour and support still accrue); raids and decay.

**Abstracting** freezes agents into records (needs, beliefs summary, faith, bonds, cultivation, current goal kind) and sites into `{template, origin, rotation, cursor}`; edited chunks are kept. **Materialising** stamps completed projects at their reserved sites, advances partial sites, applies decay, overgrowth and tribulation scars, rebuilds navigation and thaws people at plausible places.

**Consistency rule:** abstract time may only produce outcomes the detailed sim could produce, from the same balance numbers, and every outcome writes a chronicle entry with a cause. Detailed and abstract runs will not hash-match; the check is statistical.

**Determinism:** each settlement (later each region) draws from a sub-stream seeded from `(world_seed, id)`; abstract steps run in id order.

Meditation (M18) uses this for spans beyond a season in the god's own valley. Regions (M22) use it for every region the god is not in.

**Shape after the M13 spike** (`scripts/sim/abstract/`, checks in `checks_abstract.gd`):

- **Records are the agents themselves, frozen.** `AbstractWorld.begin` clears only what a person was doing this moment (intention, path, inbox, step result, a break, a help task) and keeps everything else, so freezing and thawing need no conversion (45 people in 3.5 ms) and a region's records (M22) are the same `Agent.to_dict()` the saves already use. Newcomers and children born during abstraction arrive frozen.
- **An hour** (`step_hour`): the calendar jumps to the next hour boundary; at a day boundary the daily turn runs first; each present person in id order takes `AbstractPeople.hour` (needs at the detailed rates, rest restored in the sleep hours, company and leisure in the free hours, one portion from the chests when Food falls below 60, best food first and berries before grain while grain is put by, shelter from a home, starvation and exposure damage, thoughts and mood, departure after the detailed misery threshold); believers pray at dawn and dusk through `faith.record_prayer`, so Favour and support accrue as in the detailed world; each settlement takes `AbstractEconomy.hour` (labour from adults in work hours, berries picked from a ripe pool while food is short, cooking); `faith.hourly`.
- **A day**: spoilage, `AbstractEconomy.day` (bushes ripen into the pool at the detailed regrowth rates, the field cycle sows when a crop can still ripen, grows a stage every `days_per_stage`, is reaped for the yield or lost to frost), `Lifecycle.daily` (births, ageing, ambitions), standing, faith, requests and migrants, exactly the detailed functions.
- **Nothing edits blocks while abstract.** Bush berries, crop stages, saplings, leaf fall, decay and overgrowth are held in the record and applied when the valley materialises; threats and raids pause (M18: raids rolled from the director's odds; M22: outsiders).
- **Materialise** (`finish`): bushes get the pool's berries, fields get crops at the cycle's stage, people stand at home by night or round the camp by day and deliberate afresh. With no blocks changed there is no navigation rebuild (M18's stamped buildings will need one, about 0.9 s).
- **Cost:** a year of Tree Hollow (12 people with a field) and the hamlet takes 0.65 s, 0.34 ms per settlement-hour (target 0.2; 50 years ≈ 33 s, inside the key test's minute); materialising takes 26 ms.
- **What the spike showed:** the food the valley already grows does not carry a settlement through winter (everyone starved by day 38). Detailed people respond to a lean year by proposing fields, gardens and granaries; the abstract model must do the same, so **M18 adds abstract construction**: proposals from the same `deliberation_work` / `deliberation_food` wants, sites found by `site_finder` and reserved through `construction.create`, labour-hours advancing each site's cursor and spending its materials, gathering of wood and stone by the same culture weights, and finished projects stamped on materialise. M18 also adds cultivation progress, breakthroughs rolled from M16's rules, and the 20-day statistical comparison with the detailed sim.
- **Determinism:** the spike draws from `sim.rng` in settlement id order. Per-settlement sub-streams seeded from `(world_seed, id)` wait for M22, when settlements in other regions step independently.

### 3.2 New data catalogs

| File | Contents | Milestone |
| --- | --- | --- |
| `cultivation.json` | Realms `{id, order, progress_needed, lifespan_bonus}`, talent and affinity distributions, qi curve, technique list (small, closed) | M15 |
| `tribulations.json` | Kinds `{id, severity range, damage, insight}`, breakthrough rules, outcome tables | M16 |
| `tree.json` | Insights, maturity phases, unlocks `{id, requires, effect}` | M17 |
| `weather.json` | Weather kinds per season with weights, durations and modifiers | M20 |
| `regions.json` | Region archetypes | M22 |
| `factions.json` | Sect and faction kinds with doctrine biases and relations | M22 |
| `saga.json` | Optional deeds and age-naming rules | M23 |

Every catalog gets validation and label coverage (every id has player-facing text in a text catalog). Catalogs stay closed: an entry exists only with an implemented effect.

### 3.3 Performance budget

| Measure | Target |
| --- | --- |
| Detailed region | 60 people at 3× within a 4 ms sim budget per frame |
| Abstract settlement | < 0.2 ms per in-game hour each |
| Meditation | 10 years of the home valley (abstract) < 30 s |
| Materialise | < 3 s behind the transfer or wake effect |
| Frame | 60 fps at 1080p, GPU < 10 ms with weather and particles |

## 4. Milestones

Each milestone ends with a runnable game, new `sim_checks` scenarios for its simulation features, captures in `docs/verification/` for anything visual, and commits throughout.

| Stage | Milestones | State |
| --- | --- | --- |
| A. Hold up | M13 Playtest, balance and foundations | Built except the fresh-player playtests (need people) |
| B. A living economy | M14 Fields and meals | Built (`PROGRESS.md`) |
| C. The cultivation slice | M15 Qi and cultivators · M16 Breakthroughs and tribulations · M17 The tree learns · M18 Meditation and generations | Built headlessly; the key test's fresh-player sessions are open |
| D. A living sect | M19 Sect architecture and living designs · M19b The sect's halls · M20 Seasons, weather and herbs · M20b The sect's alchemy | M19 built headlessly (not played; seekers do not yet bring the sect designs); M19b built headlessly (not played); M20 built headlessly (not played); M20b built headlessly (not played) |
| E. A wider world | M21 Branches and sacred sites · M22 Regions, other sects and outsiders | M21 built headlessly (not played) |
| F. A whole game | M23 Campaign shape · M24 Look, sound and feel · M25 Release | |

Stage C is detailed below; stages D–F are outlined and will be detailed after M18's key test, since what players feel there should shape them.

---

### M13 — Playtest, balance and foundations (open items)

Built: save migrations and version stamp, the village track (standing, halls, gardens, lanterns, timber make-do, migrant designs, founding a second settlement). Still open:

- **Timed fresh-player playtests** (`docs/playtests/`), updated for the cultivation slice once M16 lands.
- **Contextual onboarding:** world-state prompts that replace the first-steps line, dismissible, never acting for the player.
- **Profiling at 60 detailed people** at 1×, 3×, 10× and fixing the top costs (sim cost is about 5 s per in-game day headless at 30 people).
- **Abstract-model spike** (replaces the region spike): freeze and thaw 40 agent records, and measure a year of one abstract settlement. Fixes the shape of §3.1 before M18.

---

### M15 — Qi and cultivators

**Goal:** people cultivate under the tree by their own choice, teach each other, and a sect forms without the player founding it.

- **Qi field** (`sim/qi.gd`): density from distance to the sacred tree (curve in `cultivation.json`), queried per cell; cached per column. Shown on an overlay and in the inspector.
- **Cultivator state** per agent: talent, affinity, realm (Mortal, Qi Refining, Foundation Establishment for the slice), progress, foundation, techniques, teacher, students. Saved; save schema bump with a fixture.
- **Arrivals:** wanderers drawn by qi. Migrant attractiveness gains a qi term; some migrants arrive as would-be cultivators with talent. Lifespan grows by realm.
- **Goals and plans:** `Cultivate` (seek the densest reachable spot not taken, sit, progress per hour; utility from ambition, talent and qi, competing with work and needs), `Teach` / `Learn` (a social pairing: a teacher with a technique and a willing student, progress bonus, a lineage record), and duties left as they are so a sect that only meditates goes hungry. Meditation spots use the existing ring cells round the tree.
- **Sect formation** (`sim/sects.gd`, daily): when a settlement has a teacher with enough students and a cultivation place, its cultivators may found a sect: a name generated from the place and the founder's nature, a master by respect, members and ranks (disciple, elder, master). Chronicled with the cause. Succession on the master's death or absence.
- **Doctrine:** sect weights (openness, martial pride, secrecy, mercy, ambition) that drift with the master's and elders' choices, beside the settlement's culture weights.
- **Presentation:** a Cultivation tab in the inspector, a follow pin, a sect section in the settlement panel, a meditation pose and qi motes round cultivators.

**Exit:** on seed 11, with the usual cottage and chest help and no other prompting, at least three people reach Qi Refining and a sect forms with a master within 30 days headless; a followed person advances no faster than the same person unfollowed. Checks: qi falls off with distance, cultivation competes with hunger, teaching passes a technique, sect founding chronicled with cause, follow grants nothing.

---

### M16 — Breakthroughs and tribulations

**Goal:** advancement is a risky, public event the god can influence only at a cost.

- **Breakthrough decision:** at a realm's peak a person may attempt a breakthrough, weighing readiness, foundation, preparation (rest, food, a teacher's help), fear and ambition. Where: they prefer the tree's sanctuary when they can reach it, but may go anywhere.
- **Tribulation** (`sim/tribulations.gd`) for the Foundation Establishment breakthrough: lightning, with severity rolled from the realm and the person. It runs over a short span of ticks: strikes at the person and the surroundings, damage to exposed blocks (scorched and split, chronicled), people gathering, praying and fleeing, warnings beforehand through prayers ("Wen will face Heaven at dawn").
- **Outcome:** success (new realm, foundation from preparation), injury and a cracked foundation, or death. Odds from foundation, preparation, technique, sanctuary bonus and severity (`tribulations.json`).
- **Miracles** (closed catalog additions): **Bless Cultivation** (low: a day of faster progress for one person), **Shield the Trial** (high: lowers severity, no guarantee), **Defy Heaven** (extreme: turns a death into survival with a damaged foundation, lower benefit and a harder next realm). Favour cap and costs revisited so Defy Heaven costs roughly ten blessings (**Tuning**). An unhelped success and a well-timed modest help both leave a sound foundation.
- **Presentation:** storm clouds over the person, lightning, scorch marks, a tribulation toast that pauses at 1× if a followed person is involved.

**Exit:** a headless run shows breakthroughs at the tree and elsewhere, with sanctuary attempts succeeding more often; Defy Heaven saves a doomed cultivator and leaves the foundation damaged; a tribulation scorches the surroundings and the chronicle names it. Checks: sanctuary bonus, outcome table, Defy Heaven penalty, no miracle grants a realm, tribulation damage within its radius.

---

### M17 — The tree learns

**Goal:** the sect's trials change the tree, and the tree's growth changes what the sect can do.

- **Insights** (`sim/tree_growth.gd`, `tree.json`): a tribulation witnessed in the sanctuary adds insight of its kind; first encounters give most, repeats diminish. Insights are knowledge, not a currency. **Maturity** grows separately from total experience.
- **First unlock (one concrete capability):** lightning insight lets the tree bear **spirit fruit** (a new resource on the sacred leaves, a few per season) that aids a breakthrough's preparation. Scarcity is the point: who gets the fruit is a sect decision, chronicled.
- **Nurture miracle** (moderate): deepen qi on a chosen spot inside the zone for a season, making a new cultivation place.
- **Embodied history:** lightning scars on the bark and scorched ground near the tree persist; maturity slowly widens the crown (procedural, in the existing sacred aura and world edits).
- **Tree screen:** maturity, insights with where each came from, unlocks, scars.

**Exit:** after a lightning tribulation at the tree, spirit fruit appears within a season and is eaten by a cultivator before a breakthrough, with the chronicle recording who got it and why. Checks: diminishing insight, unlock gating, fruit distribution decision, scars saved.

---

### M18 — Meditation and generations

**Goal:** years pass, and the player returns to a sect that has changed for reasons they can read. This milestone carries the key test.

- **Abstract settlement model** (§3.1) for the home valley, behind the existing rest overlay.
- **Meditation:** rest extended to 1, 5, 10 and 50 years. Interrupts: a followed person's breakthrough, mortal danger or return; a shrine falling; a new phenomenon; a sect succession. Favour regeneration during meditation and its limit (**Tuning**). Optional per-person "protect if…" rules with a Favour limit (Leaning, GDD §18.2).
- **Generations:** ageing to death for mortals and cultivators by lifespan, children growing into disciples, succession, legacies (a teacher's lineage, a manual, a relic left at the tree).
- **"While you meditated…":** a concise summary from the chronicle: advanced, died, built, lost, founded, and why the politics changed; followed people first.

**Exit (key test):** a scripted run follows one novice, spends Favour on them at one tribulation, meditates 50 years in under a minute, and returns to a materialised valley where the sect has new buildings, a new master and older or departed members, the followed person's fate is in the summary with its cause, and the tree shows the insight and scars of the period. Then: fresh players play the slice (`docs/playtests/`) and say whether they cared what happened to their disciple. Checks: abstract vs detailed statistical consistency over 20 days, materialised sites valid, succession, meditation interrupts.

---

### M19 — Sect architecture and living designs

**Goal:** the sect builds places for its Way by its own judgement, the god proposes where without commanding, and people make designs of their own.

Detailed after M18 ahead of its fresh-player sessions (the key test's human half is still open), so its order follows what the slice most lacks: places that change how cultivation and trials go, then the god's proposals, then designs people devise.

- **Meditation hall** (function, `templates.json`): roofed, at least two meditation mats (a new mat block and component), in qi of at least 0.5 at its anchor. Effect: meditating on a mat inside it progresses faster (`cultivation.hall_factor`) and shelters. The Cultivate plan prefers a free mat in a known hall over the ring round the trunk when its qi is near; abstract cultivation uses the factor for sect members while a hall stands. A starter design, offered or brought by seekers; a sect's leaders propose one once the sect has four members and none stands.
- **Tribulation ground** (function): an open platform of cut stone (6+ cells, sky above) with at least two formation stones (a new block and component), its anchor at least 10 blocks from any dwelling. Effect: a trial faced on it counts as sanctuary when it lies within the tree's sanctuary reach, and lightning that would strike the surroundings strikes a formation stone instead (no scorching); cultivators choose it over their spot when they know one. Starter design; proposed by a sect's leaders once a member has faced Heaven.
- **Blueprints** (GDD §5.4 leaning): from the design library the god lays a design it has offered as a ghost on a chosen spot in the zone (`lay_blueprint` command: template, origin, rotation, checked like a site). A blueprint is a proposal: a founder who wants that function and knows the design takes the blueprint's spot when it is still free (a preference, chronicled with "where the god proposed"), otherwise finds their own; a blueprint nobody takes for a season fades. Whispering "build" to a person still only raises Build. Ghosts in the presentation, a "Lay blueprint" mode in the library.
- **Vernacular homes:** a settlement whose people know no dwelling design devises one from what lies to hand (`sim/vernacular.gd`: a small roofed room with a bed and a door in the walling and roofing its people can get: timber or stone, thatch or planks), named from the place, chronicled ("devised by"), learned by its people; designs it devises spread like any other.
- **Material substitution** generalises the timber make-do: stone walling in planks when stone is not known, thatch roofs in planks when grass is not.
- **Worn paths:** cells walked often wear from grass to a path (a new path block, daily), and navigation prefers them slightly; unwalked paths grass over.
- Later in stage D, as play shows the need: mirrored and renovated designs, salvage from fallen buildings, design traditions (a settlement preferring designs it has built).
- Moved: the alchemy room comes with herbs and pills (M20); the training ground with sparring, when outsiders give fighting a purpose (M22). Neither has an effect to give it before then.

**Exit:** on seed 11 with a sect, offered the meditation hall and tribulation ground designs, the sect raises both by its own proposals; cultivators in the hall progress faster than on the ring (same person, same qi); a trial on the ground scorches nothing and counts as sanctuary; a blueprint laid by the god is taken up by the next founder who wants that function, and one that conflicts with nobody's needs is not built. Checks: hall factor, ground draws lightning, blueprint preference and fading, a settlement with no dwelling design devises one, paths wear and grass over. Captures: hall, ground, blueprint ghost, paths.

### M19b — The sect's halls

**Goal:** a sect grows into a compound of its own: ten more kinds of building, each doing one real thing for its Way, raised by its people's judgement, and older buildings turned to new uses by adding what they lack. The god can raise or alter any of them by hand inside the zone; a function still comes only from components.

- **Blocks** (atlas grows to 8 × 9, new tiles painted at the end so old ones keep their look): scripture shelf, lectern, incense burner, medicine cabinet, memorial tablet, bronze bell, tribulation array (a carved disc one sits on), thunder spire (set into a roof), spirit jade, precept stele, sect banner, and three for the look of a sect: roof tiles, lacquered pillar, paper screen. Each furniture block is a component and an anchor; spirit jade, stele and banner stand on a cut-stone platform as formation stones do.
- **Functions** (appended to `FunctionRules.FUNCTIONS`; one new rule key `at_most`):

| Function | Components | Effect |
| --- | --- | --- |
| Scripture library | 2+ roofed scripture shelves, a lectern, a door | the sect copies its living members' techniques into its manuals now and then, and members study the manuals `library_study_factor` times as often |
| Meditation room | exactly one roofed mat, an incense burner, a door, tree qi 0.5+ | one cultivator of Qi Refining or beyond sitting alone progresses `seclusion_factor` faster; preferred over a hall's mat by those who may use it |
| Tribulation chamber | a roofed tribulation array, a thunder spire under the open sky, a door, 12+ cut stone, 10 blocks from dwellings | a trial inside counts as sanctuary within the tree's reach, Heaven's severity is lowered by `chamber_severity`, the spire takes every strike that would scorch; preferred over a ground |
| Infirmary | 2+ roofed beds and a medicine cabinet, a door | recovering inside heals `infirmary_factor` faster and mends a cracked foundation by `foundation_mend` a day up to its start; a cultivator with a cracked foundation goes there to convalesce |
| Spirit-gathering array | 4+ spirit jade under the open sky on 5+ cut stone | qi within `array_radius` of it is at least `array_qi`: a new cultivation place |
| Mountain gate | 2+ banners and 2+ lacquered pillars on a stone threshold | seekers among migrants `gate_seekers` times as likely; cultivators living there join `gate_join` times as readily |
| Ancestral hall | 2+ roofed memorial tablets and an incense burner | the relics at the tree steady the sect's trials wherever its people face Heaven at home, and each tablet keeps one more relic's help |
| Precept stele | a stele on 4+ cut stone, under the open sky | the sect's doctrine drifts at `stele_drift` of its rate |
| Bell tower | a roofed bronze bell | a threat within `bell_reach` of it rings the bell: every resident learns of it at once (chronicled) |
| Lecture hall | a roofed lectern, 4+ benches, 12+ roofed floor | sect members who gather there listen to the Way expounded and progress by `lecture_per_hour`; they prefer it to the common hall |

- **Designs:** at least one starter for each (Scripture Pavilion, Seclusion Cell, Thunder Chamber, House of Healing, Jade Array, Mountain Gate, Hall of Ancestors, Precept Stele, Bell Tower, Lecture Hall) plus sect-style variants (a tiled meditation hall, a stone disciples' lodge), authored by "wandering cultivators" and offered like the M19 designs.
- **Wants:** a sect's master and elders propose each when the sect has need of it (a library once it keeps a manual or has five members; a meditation room once two members reach Qi Refining; a chamber once a trial has injured or killed one of them; an infirmary once a member's foundation is cracked; an array once eight members share the ring; a gate once six members and open doctrine; an ancestral hall once a relic or a member's death; a stele once a succession or after 20 days; a bell tower once a threat has come within reach; a lecture hall once six members), chronicled with their own causes. The abstract builder uses the same wants.
- **Renovations** (`templates.json` `renovations`, `sim/renovations.gd`): a building that has one function becomes another by adding components to free floor inside it (a storehouse takes shelves and a lectern and becomes a library too; a village hall takes a lectern and two benches; a home of two beds takes a medicine cabinet; a meditation hall takes tablets and incense). Known to anyone who knows a design with the function; preferred to a new building when a fitting building stands; raised as an ordinary site whose order is only the added blocks, chosen so every floor cell stays reachable; chronicled as a renovation. Nothing is removed.
- **Abstract:** every effect has its counterpart in the abstract model (study, seclusion, chamber trials, mending, array qi, gate, relics, stele, lecture).

**Exit:** the ten designs carry their functions; each effect holds in a check (same person, same place, with and without the building); on seed 11 a sect offered the designs raises at least five of the new buildings by its own proposals within 40 days headless, and at least one renovation; 50 years of meditation leave a sect compound with several of them. Captures: each building, a renovation before and after, the library function reference.

### M20 — Seasons, weather and herbs

**Goal:** the sky presses on the valley and the sect's road to Heaven runs through its gardens and furnaces as well as its halls: weather changes how people work, shelter and choose their hour to face Heaven; spirit herbs grow where the tree's qi lies deep once the tree has grown; alchemists refine them into pills that steady a breakthrough; ore becomes tools that speed work.

- **Weather** (`data/weather.json`, `sim/weather.gd`): one sky over the valley, a spell at a time. Kinds (closed): clear, overcast, rain, thunderstorm, snow. Each season weighs each kind and gives its spell length in hours; when a spell ends the next is rolled from `sim.rng` on the hour (snow only in winter, rain never in winter). Each kind carries modifiers: `exposure` (shelter lost outdoors by day as well as by night), `work` (speed of outdoor work: gathering, building, farming), `wet` (waters the fields) and `trial` (severity added to a trial whose storm breaks under it). The first snow of a winter, a thunderstorm and a drought are chronicled. Saved under an optional key (no schema bump).
- **Exposure:** outdoors and uncovered, shelter falls by day in weather with `exposure` (rain, thunderstorm, snow) and in winter (`needs.winter_day_exposure`), so the homeless suffer a snowy day as well as the night. Roofs and kindled cells protect as before. People respond through the existing Shelter goal.
- **Rain and fields:** `crops.json` gains `rain_need`: a crop grows only on a day within `rain_need` days of rain; a crop in a longer dry spell stalls (a drought, chronicled once per spell, and the fear of a failing harvest enters prayers, which Bless Growth answers). The weather table keeps droughts uncommon.
- **Storms and trials:** a trial whose storm breaks in a thunderstorm takes `trial` more severity (rain a little). Cultivators weighing a breakthrough under a thunderstorm mostly wait it out (utility × `weather.trial_wait` unless impatience is full). Miracle **Calm the Sky** (closed catalog, medium): ends the current rain, thunderstorm or snow and holds the sky clear for `weather.calm_hours`.
- **Spirit herbs** (`sim/herbs.gd`): a tree unlock `spirit_herbs` (`tree.json`, requires the Spirit Root phase: unlock rules gain `maturity`). Once unlocked a new `spirit_herb` block (a cross plant whose ripeness is its meta, three atlas stages) sprouts on open grass where qi is at least `herbs.qi`, a few a day outside winter, up to `herbs.most` in the valley; a Nurtured spot counts (GDD "nurture a spirit herb"). A ripe herb is gathered for the new resource `herb` and grows again (a resource site like a bush). Herbs are gathered only where an alchemy room stands, for its furnace.
- **Alchemy:** block `alchemy_furnace` (component `furnace`), function **alchemy room** (a roofed furnace and a medicine cabinet, a door), recipe `foundation_pill` (3 herb → 1 pill, station `alchemy`) in `recipes.json`; kitchens generalise to stations so a furnace is a pot like a kitchen's. Goal **Refine** (weighed beside cultivation, since the pills are for the sect's own trials): a sect member fills the furnace from the stores and refines; pills (`pill` resource) go into the chests. A cultivator at a realm's peak who believes the stores hold a pill takes one before facing Heaven (`cultivation.pill`), eats it when the storm breaks (`alchemy.pill_preparation` added to preparation) and the chronicle says so. Want: the sect's master and elders propose an alchemy room once herbs grow in reach and a member is in Qi Refining. Starter design **Alchemy Room** by wandering cultivators.
- **Tools:** block `anvil` (component `anvil`, ore), function **smithy** (a roofed anvil and a hearth, a door), recipe `tools` (1 ore + 1 wood → 1 tools, station `smithy`). Goal **Smith** (weighed as building work, culture weight `build`): fill the anvil's stock and forge. A person setting out to gather, build or farm takes tools from the stores when they have none (`agent.tool`, worn out after `tools.wear_hours` of work); work with tools runs at `tools.speed`. Want: leaders propose a smithy once ore is known, the stores hold `tools.smithy_ore` ore and the settlement has `tools.smithy_people` people. Starter design **Smithy**; migrants may bring it.
- **Abstract:** weather rolls in the abstract hour (exposure for the homeless, fields watered, trial severity); herbs sprout and ripen into a pool gathered when an alchemy room stands; furnaces and anvils turn stock into pills and tools from labour-hours; an abstract trial takes a pill from the stores; labour is multiplied by the share of workers the settlement's tools can equip.
- **Presentation:** rain and snow particles round the camera, a dimmer sky and thicker mist under overcast and storm, distant flashes in a thunderstorm, snow lying on upward faces through a snowy winter (a shader uniform), the weather in the clock line, herb stages, furnace and anvil tiles (atlas grows to 8 × 10, new tiles painted after every older one), a weather prompt before a trial in a storm, the Calm the Sky button in the shrine menu.

**Exit:** on seed 11 with a sect, offered the alchemy room design and the tree at Spirit Root, herbs sprout in the tree's qi, the sect raises an alchemy room by its own proposal, gathers herbs, refines a pill and a cultivator eats it before facing Heaven within 40 days headless, chronicled; a settled village with ore, offered the smithy design, raises one and carries its tools to work within 30 days. Checks: weather follows its season (snow only in winter, same seed same sky); a homeless person loses shelter on a snowy day and not indoors; a crop stalls in a dry spell and grows after rain; the same trial is fiercer in a thunderstorm and a cultivator waits one out; Calm the Sky clears it; herbs sprout only after the unlock and only in dense qi, ripen and regrow; a pill raises preparation; tools speed the same person's gathering and wear out; the new state saves; abstract weather, herbs, pills and tools. Captures: rain, snow, thunderstorm, herbs under the tree, alchemy room, smithy, the clock line.

### M20b — The sect's alchemy

**Goal:** alchemy becomes a craft of its own, added at the user's request (2026-10-11): several spirit herbs that each grow where something particular happened to the valley, mixtures and pills that each do one real thing to a person's cultivation, the cost of taking too many, alchemists who grow skilled, and a ladder of alchemy buildings from a herbalist's workshop to a pill pavilion, the larger holding more crafters at once. Everything stays influence, not obedience: what to refine, gather and take is each person's own deliberation.

- **Herbs** (`data/alchemy.json` `herbs`, `sim/herbs.gd` generalised to kinds; closed): each a cross plant with three stages, gathered from the root and growing again, all behind the `spirit_herbs` unlock.

| Herb (resource) | Grows | Notes |
| --- | --- | --- |
| Spirit herb (`herb`) | open grass where the tree's qi is deep (as M20) | the common herb |
| Jade ginseng (`ginseng`) | grass or dirt in shade (no sky above), qi 0.35+ | slow to ripen |
| Thunder root (`thunder_root`) | scorched earth Heaven's lightning left | every trial scar is a seed bed: the sect's trials feed its furnaces |
| Frost lotus (`frost_lotus`) | grass beside water, only in winter | withers when spring comes; the rarest |

- **Herb garden** (function): 4+ herb beds (new block and component, spirit soil) where the tree's qi is 0.3+. Empty beds sprout herbs of their own (a spirit herb under the open sky, jade ginseng in shade, so a roofed garden grows ginseng), outside the valley's wild limit, and ripen `alchemy.garden_ripen` times as fast.
- **Preparations** (`recipes.json` station `alchemy` with a `tier`; effects in `alchemy.json` `elixirs`; closed): taken from the stores, never carried in the hands; each applies at once or is kept for its moment.

| Preparation | Recipe | Tier | Effect |
| --- | --- | --- | --- |
| Healing draught (mixture) | 1 herb + 2 berries → 2 | 1 | heals `heal` at once and mends a cracked foundation by `mend` |
| Awakening tea (mixture) | 1 herb + 1 grain → 2 | 1 | a mortal's sittings progress `factor` times as fast for `days` |
| Foundation pill | 3 herb → 1 | 2 | preparation for a trial (M20) |
| Qi-gathering pill | 2 herb + 1 ginseng → 2 | 2 | a cultivator's sittings progress `factor` times as fast for `days` |
| Thunder-warding pill | 2 thunder root + 1 herb → 1 | 3 | kept for a trial: Heaven's severity lowered by `severity` |
| Marrow-cleansing pill | 1 frost lotus + 1 ginseng → 1 | 3 | clears pill toxicity and mends a cracked foundation fully |
| Longevity elixir | 2 frost lotus + 2 ginseng + 1 thunder root → 1 | 4 | `years` more life, once in a life, chronicled |

- **Toxicity** (`cultivation.toxicity`, 0–1): every pill (not the mixtures) leaves some; it fades `toxicity_decay` a day, slows sittings by `toxicity_rate` × toxicity and weakens a trial's preparation by `toxicity_preparation` × toxicity. A person declines a pill that would take them past `toxicity_limit`. The marrow-cleansing pill clears it.
- **Refining:** a batch is worked as a kitchen's is, at a bench of the person's own inside the building (so several can work at once). A batch can fail and lose its herbs: `fail_base` less `fail_per_level` per medicine level and the building's tier bonus. Refining practises medicine; someone who reaches `alchemist_level` becomes an alchemist (chronicled once) and is drawn to the furnace more. A pill pavilion's great cauldron sometimes yields one more.
- **What to refine** (`sim/alchemy.gd`): each preparation has a want from the sect's own state (cultivators near a peak, cultivators at all, awakening mortals, the hurt and cracked, the poisoned, elders near the end of their span), less what the stores hold. A refiner works the most wanted preparation their building's tier allows and whose herbs they believe are to hand; gatherers gather each herb kind for the wants their settlement can refine.
- **Taking them** (`sim/elixirs.gd`): before facing Heaven, a foundation pill and a thunder-warding pill are taken from the stores if believed there; before sitting, a cultivator takes a qi-gathering pill, a mortal a cup of awakening tea; goal **Medicate** (healing draught when hurt or cracked, marrow-cleansing when poisoned or cracked, longevity elixir when old): go to the stores and take it. Every taking is in the decision log; a longevity elixir and a first of each kind are chronicled.
- **Buildings** (functions appended to `FunctionRules.FUNCTIONS`; a structure's tier is the highest alchemy function it has, and its crafters the benches its components give):

| Function | Components | Tier | Crafters |
| --- | --- | --- | --- |
| Herbalist's workshop | a roofed mortar and drying rack, a door | 1 | 1 |
| Alchemy room (M20) | a roofed furnace and medicine cabinet, a door | 2 | 1 |
| Alchemy hall | 2+ roofed furnaces, a medicine cabinet, a drying rack, a door | 3 | one per furnace, up to 4 |
| Pill pavilion | a roofed great cauldron, 3+ furnaces, 2+ cabinets, a mortar, a door, 30+ roofed floor, tree qi 0.4+ | 4 | furnaces + 2, up to 8 |

- **Blocks** (atlas grows to 8 × 12, new tiles painted after every older one): jade ginseng, thunder root and frost lotus (three stages each), mortar, drying rack, great cauldron, herb bed.
- **Designs:** Herbalist's Hut (valley folk and wandering cultivators; migrants may bring it), Alchemy Hall, Pill Pavilion, Herb Garden and a roofed Ginseng House, by wandering cultivators. Renovations: a furnace and cabinet turn a herbalist's workshop into an alchemy room too; a furnace and drying rack turn an alchemy room into an alchemy hall.
- **Wants:** a herbalist's workshop once herbs grow in reach and the settlement has `workshop_people`; an alchemy hall once the sect has an alchemy room, `hall_members` and a rarer herb grows or a member reached Foundation Establishment; a pill pavilion once it has an alchemy hall, `pavilion_members` and a member in Foundation Establishment or beyond; a herb garden once it refines and the wild herbs are fewer than `garden_wild`.
- **Abstract:** herb pools per kind (gardens add to them), benches by crafters and tier with the same wants, failure from the best medicine skill, and the same takings: trial pills, sitting pills and tea scaling abstract cultivation, draughts for the hurt, cleansing for the poisoned, elixirs for the old; toxicity fades by the day.
- **Presentation:** the new tiles, preparations and herbs named in the stores, toxicity, an active pill and extra years on the Cultivation tab, captures.
- **Saves:** new state under optional keys; an M20 save's alchemy-room pots spill into the room as loose goods.

**Exit:** on seed 11 with a sect, the tree at Spirit Root and the designs offered, the sect raises an alchemy room or workshop and an alchemy hall by its own proposals within 60 days headless, refines at least four kinds of preparation and its people take them, two crafters work in the hall at once, and thunder root grows on a trial's scar. Checks: each herb grows only in its own conditions; beds sprout spirit herb in sun and ginseng in shade; each preparation's effect (same person, with and without); toxicity slows, fades and is refused past the limit, and cleansing clears it; tiers gate recipes; a pavilion holds more crafters than a room; failure falls with skill; the want chooses what is needed; Medicate; the new state saves; abstract herbs, refining and takings. Captures: each building, the three new herbs, a garden.

### M21 — Branches and sacred sites

**Goal:** the sect outgrows the tree's shade: elders carry a cutting of the tree to open land and found branches with shrines and sects of their own, the god follows its people there at a price, branches go their own way in doctrine, and what a fallen branch kept is carried home. Everything stays the people's own choice; the god can only make a place worth going to.

- **Spirit cutting** (block `spirit_cutting`, component `cutting`, a sapling-like cross plant; atlas tile after every older one): a living cutting of the sacred tree. It is a **shrine anchor** like an altar (`faith.gd`: shrine kind `cutting`; broken → fallen, planted again → dormant, the ordinary support rules) and a **qi source**: qi round it follows `branches.cutting_curve` (dense at the trunk, gone by 20 blocks), so a branch can cultivate far from the tree. Cultivators look for a spot on a ring round their settlement's living cutting as they do round the tree. Only people plant cuttings (the god cannot place one; breaking one by hand fells its shrine like any altar), and raiders tear one up as they break altars.
- **Branch founding** (`sim/branches.gd`, goal `FOUND_BRANCH`, target a founding ground): an elder (not the master) of a sect, settled `branches.settled_days`, may set out to found a branch when the sect is crowded (`branches.crowded` members or more, or more sitters than the ring holds) or the elder's ambition outruns their place (leadership and drive), the sect is `branches.after_days` old, has fewer than `branches.most` living branches, and a founding ground is free. Weighed beside cultivation and work; chronicled with its cause (crowding or ambition). The plan packs wood for the chest as a founder does, walks to the ground, settles (`Op.SETTLE` with the branch flag): the settlement is created as today, and the founder plants a cutting by the camp and becomes master of a **branch sect** (`sects.found_branch`: `parent` = the old sect, its name `"<parent>, <place> Branch"`, doctrine copied from the parent), chronicled.
- **Followers:** the founder's students in the parent sect, and disciples who think well of the founder, weigh following (`FOUND_BRANCH` at a settled ground: opinion, crowding, ambition; at most `branches.followers`). Settling there moves them from the parent sect to the branch.
- **Transfer cost and cooldown:** a transfer costs `shrines.transfer_cost` Favour from the shrine the god leaves and is refused within `shrines.transfer_cooldown_days` of the last one (expulsion is free and resets nothing). The shrine menu shows the cost, the cooldown and why a shrine cannot be reached.
- **Routes** (`sim/routes.gd`, daily in both fidelities): linked settlements (a branch and its parent; a settlement and the one whose shrine its people pray at) carry traffic, pilgrims, messengers and traders between them, that wears the route between their camps (a navigation path, cached and refound every `routes.refind_days`) by `routes.per_link` + `routes.per_pilgrim` steps a day on each column. Worn routes turn to path through the ordinary wear rules (while abstract, wear is added and the paths are laid when the valley materialises), so the tree's root network can reach a branch along its road. A route first worn through is chronicled.
- **Schools:** a branch whose doctrine has one weight at or beyond `branches.school_at` for `branches.school_days` days takes a school: mercy → **healing school** (residents heal `schools.heal_factor` faster), martial → **sword school** (its people defend `schools.defend_factor` as readily and strike `schools.strike_factor` as hard), secrecy → **hidden school** (raiders weigh its wealth at `schools.hidden_wealth`). A school is lost when the weight falls back below `branches.school_lose`. Chronicled with the doctrine that made it.
- **Schism:** a branch whose doctrine lies `branches.schism_distance` from its parent's (summed) while its master thinks ill of the parent's master (`branches.schism_opinion`) breaks away: no parent, no traffic, its route grasses over. Chronicled with both causes.
- **Relics:** a great cultivator who dies in a branch leaves their relic at the branch's living shrine (`{name, realm, tick, shrine}`); relics steady trials faced within `branches.relic_reach` of the shrine they lie at (the tree's as before). When a shrine falls or its settlement empties, its relics lie in the ruins; a believer who knows the place and whose own shrine lives weighs carrying them home (goal `RECOVER_RELIC`: walk to the ruin, take them, walk to their shrine), chronicled with where they came from.
- **Abstract:** branch founding by the same want, rolled each day for elders in id order (the founder and followers move to the ground and the camp, chest and cutting are set at once); routes wear; schools and schism by the same daily rules; relics recovered by a believer of a living linked shrine with `branches.abstract_recover` a day.
- **Presentation:** the cutting tile; the settlement panel's sect section shows its parent or branches and its school; the shrine menu's transfer rows show cost, cooldown and reason; branch shrines in the shrine list; the tree screen lists relics by where they lie.
- **Saves:** new state under optional keys (sects' `parent`/`school`, relics' `shrine`, the god's last transfer, routes); no schema bump.

**Exit:** on seed 11 with a sect of ten, within 60 days headless an elder founds a branch on a founding ground with a cutting shrine and a branch sect, at least one disciple follows, the route between them wears into path, the branch shrine becomes active and the god transfers there paying Favour and cannot transfer back before the cooldown. Over 50 meditated years at least one branch is founded, and every branch either holds, takes a school or breaks away, each chronicled with its cause. Checks: cutting qi and shrine; the branch want (crowded, ambitious, too young, no free ground); settle makes a branch sect with its parent; followers move sects; transfer cost and cooldown; route wear to path; school from doctrine, lost again; schism; relic left at a branch shrine and recovered after it falls; abstract founding; the new state saves. Captures: a branch with its cutting, the shrine menu's transfer rows, the settlement panel's branch section.

### Stage E–F outline (to be detailed after M21)

- **M22 Regions, other sects and outsiders:** regions with the abstract model; visiting cultivators seeking sanctuary and the sect's admission decision; rival sects and outlaw cultivators as BDI agents replacing the scripted raid director; trade in herbs and manuals; schisms. (Carries the former M18 and M19.)
- **M23 Campaign shape:** new-world options, named ages, optional deeds, the epilogue on fading or "Close the book", chronicle export, statistics; the tree's later unlocks (root networks, formations, one hidden realm).
- **M24 Look, sound and feel:** the ink-and-pastel direction carried to every screen, tribulation and miracle effects, figure poses, music, accessibility, full gamepad navigation, localisation readiness.
- **M25 Release:** soak, saves from every schema, performance on a lower-spec machine, onboarding final, credits and licences, closed beta, 1.0 build.

## 5. Verification

`tools/sim_checks.gd` (headless scenarios, PASS/FAIL, non-zero exit), the parse/import check, every run grepped for `SCRIPT ERROR`, off-screen window captures for visuals, plain reporting of what was and was not checked. Additions:

- **Long-run scenarios** behind `--long` (`checks_campaign.gd`): a multi-year meditation with no player commands must not empty the valley, must produce at least one succession, and must keep invariants (no agent stuck in a plan for 2 days, no unreachable site cell, stock never negative).
- **Statistical checks** for abstract vs detailed time, with tolerances and fixed seeds.
- **Fixture saves** for every schema migration.
- **Playtest notes** in `docs/playtests/` at M18, M22, M23 and M25.
- `sim_checks` stays under 5 minutes without `--long`.

## 6. Open decisions

Each is the user's call; work proceeds on the leaning.

| Question | Leaning |
| --- | --- |
| Year length for generational play | Keep the 40-day year; meditation, not a shorter day, carries the centuries |
| Hands-on building in the cultivation game | Kept as the spirit's power inside the zone (GDD §5.1) |
| Destructive miracles | Later; the sect can turn ruthless without the tree being malevolent |
| Music | Synthesised ambient score; recorded tracks if commissioned |
| Art beyond procedural figures | Stay procedural; the painted atlas and shaders carry the look |
| Distribution | itch.io Windows build; Steam is a separate decision |
| Population caps | 60 detailed in the active region, 200 across the world (**Tuning**) |

## 7. Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Generational time is too slow in the detailed sim | The abstract model (§3.1) is built in M18 and spiked in M13; meditation never runs the detailed sim beyond a season |
| Abstract and detailed outcomes diverge visibly on return | The consistency rule; reserved sites; every outcome chronicled; statistical checks |
| Cultivation turns people into resource generators | Duties still matter; cultivators have needs, bonds and ambitions; attention is a lens, not a buff |
| The player cannot see why a tribulation failed | Outcome causes in the decision log and chronicle; the Cultivation tab shows foundation and preparation |
| Favour makes death trivial | Defy Heaven's cost and its damaged-foundation consequence; scarce Favour during meditation |
| Content sprawl (realms, techniques, insights) | Closed catalogs tied to implemented effects; the slice uses three realms and one tribulation kind |
| GDScript too slow for 60 detailed people | M13 profiling; staggered deliberation; abstract everything outside the active region |
| Influence-not-obedience erodes for convenience | The product invariants in `AGENTS.md` bind every system: blueprints, blessings and sect politics change what people know, want or can do, never what they must do |
