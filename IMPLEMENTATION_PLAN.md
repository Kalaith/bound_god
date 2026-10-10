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
| C. The cultivation slice | M15 Qi and cultivators · M16 Breakthroughs and tribulations · M17 The tree learns · M18 Meditation and generations | M15, M16 built; M17 next |
| D. A living sect | M19 Sect architecture and living designs · M20 Seasons, weather and herbs | |
| E. A wider world | M21 Branches and sacred sites · M22 Regions, other sects and outsiders | |
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

### Stage D–F outline (to be detailed after M18)

- **M19 Sect architecture and living designs:** sect functions (meditation hall, training ground, tribulation ground, alchemy room) from components; blueprints placed as proposals; vernacular designs, material substitution, mirroring, renovation, salvage; worn paths; design traditions. (Carries the former M17.)
- **M20 Seasons, weather and herbs:** weather per season with storms that worsen lightning trials; exposure in winter; spirit herbs and an alchemy station making pills for breakthroughs; tools from ore where they speed work. (Carries the former M15 and M16.)
- **M21 Branches and sacred sites:** disciples found branch shrines and sects on founding grounds and beyond; avatar transfer cost and cooldown; branches drifting in doctrine; relics carried from fallen sites. (Carries the former M21 follower and relic work.)
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
