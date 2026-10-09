# The Bound God — Game Design Document

> Version 0.2 · 2026-10-10 (Phase 2 scope added in §14) · Godot 4.2.2 (GDScript, Forward+ renderer, Windows)
>
> Source material: `bound_god_game_concept.md` (vision), `NPC System Implementation Guide.md` (the BDI agent system shipped in Final Landing, `RustGames/finallanding`). Implementation is planned in `IMPLEMENTATION_PLAN.md`.
>
> In this document, **Decision** marks a call made for the first playable, **Later** marks a direction kept but deferred, and **Open** marks an unresolved question. Concept-level "agreed direction" is carried over unchanged.

## 1. Pitch

You are a small god bound to a sacred tree. You can walk, dig and build only near your shrines. Everything beyond them happens through people who decide for themselves: they eat, sleep, argue, fall in love, build houses from designs you showed them, pray to you when they are hungry, and carry stories of you to places you cannot go. When believers somewhere else raise a shrine, you can step through it. When a shrine falls, you lose that place.

**Design promise:** Build the foundations of a civilisation, then see what people make of them.

**Genre:** third-person voxel builder + autonomous colony simulation + local god game.
**Platform:** Windows desktop (keyboard/mouse and gamepad). No web build at this stage (see §13).
**Session shape:** 20–60 minute play sessions; a campaign spans several in-game years.

## 2. Design pillars

These are the concept's ten principles, grouped into the five that drive feature decisions. Every feature must serve at least one.

| Pillar | Means in practice | Concept principles |
| --- | --- | --- |
| **Tactile building** | Placing and breaking blocks around the avatar is satisfying on its own; structures have function | 3 |
| **Designs outlive placement** | A saved template becomes architectural knowledge that villagers may choose to reuse | 4 |
| **Influence, not obedience** | The player shapes conditions, offers designs, whispers, performs miracles; NPCs decide | 1, 2, 7 |
| **Reach is earned through belief** | Manifestation and power exist only where people worship; shrines can be lost | 5, 6, 8 |
| **Every outcome has a reason** | Each NPC's "why" is inspectable; the chronicle records causes | 9, 10 |

Non-goals (from the concept): not a Minecraft remake, not a survival-crafting treadmill, not a top-down city builder, not a god game where you command NPCs.

## 3. Player role

### 3.1 The avatar

- Third-person divine avatar (about 1.8 blocks tall, glowing, slightly translucent at the edges). Walks, sprints, jumps 1 block, climbs 1-block steps automatically.
- **Bound:** the avatar can only exist inside the **presence zone** of the shrine it is manifested at. Walking to the edge meets a soft shimmering wall; the avatar cannot pass.
- **Hands-on actions:** break block, place block, pick up and drop loose items, interact (open the shrine menu, inspect an NPC, read a sign-post template).
- The avatar does not eat, sleep or die. It can be **expelled** (see §7.5).
- NPCs can see the avatar. Seeing it is an event in their minds (awe, fear, curiosity), so where and how the player appears matters.

### 3.2 Camera

- **Play camera:** over-the-shoulder spring-arm camera, crosshair-targeted block interaction, reach 5 blocks.
- **Overlook camera:** hold a key (or toggle) to lift the camera to an elevated orbit around the active shrine, still clamped to the presence zone. Used for watching the settlement, selecting NPCs and planning builds. Building is still possible from the overlook at extended reach.

### 3.3 What the player can and cannot do

| Can | Cannot |
| --- | --- |
| Build and terraform inside the presence zone | Leave the presence zone |
| Save structures as templates and offer them at a shrine | Order anyone to build a template |
| Whisper to a believer (a nudge, not an order) | Assign jobs, set work priorities, or move NPCs |
| Perform miracles paid for with local Favour | Perform miracles where nobody worships |
| Post divine requests at a shrine | Force anyone to accept a request |
| Inspect any NPC in view and read their reasoning | Read the minds of people in places they have no shrine |
| Transfer to another active shrine | Manifest at two shrines at once |

**Decision:** unlike Final Landing, there is **no per-work-type priority panel**. Labour is steered only indirectly: the materials the player makes available, the designs offered, whispers and requests. (Final Landing's `priority weight` term becomes a settlement-culture weight that the NPCs themselves shift; see §6.6.)

## 4. The world

### 4.1 Voxel scale and the first valley

- 1 block = 1 metre. Chunks are 16×16×16.
- **Prototype map:** one bounded, procedurally generated valley of 160×48×160 blocks (10×3×10 chunks), generated from a seed. Edges are mountains or sea so the boundary feels natural.
- Contents: river through the valley floor, meadows, woods, a rocky ridge on the far side with stone and ore, berry bushes, a ruined old shrine on the ridge (≈110 blocks from the sacred tree), and a small existing mining hamlet near it.
- **Later:** a larger world split into regions, where only the active region and its neighbours simulate in full and others advance abstractly (§11.3).

### 4.2 Block palette (deliberately small)

Concept principle 10: interacting systems over decorative blocks. The prototype ships about 20 block types in three families:

| Family | Blocks | Notes |
| --- | --- | --- |
| Terrain | grass, dirt, stone, sand, gravel, ore, water (static), bedrock | Generated; breakable except bedrock |
| Material | log, planks, thatch, cut stone, cobble, glass, fence | Placed by the player and NPCs; each maps to a resource |
| Functional | bed, door, storage chest, workbench, hearth, altar, berry bush, sacred tree | Recognised as **components** (§5.3); a structure's purpose comes from these |

Breaking a block yields its resource (log → wood, stone → stone, ore → ore, berry bush → berries without destroying the bush when ripe). Placing a block consumes one unit of its resource from the avatar's divine stock.

### 4.3 Resources

| Resource | Source | Used for |
| --- | --- | --- |
| Wood | Trees (log blocks), dismantling | Planks, beds, doors, fences, fuel |
| Stone | Stone and cobble blocks | Foundations, cut stone, altar |
| Thatch | Tall grass gathering | Roofs |
| Berries | Berry bushes (regrow) | Food (raw) |
| Grain | Farm plots (**Later**) | Food (meals) |
| Ore | Ridge ore blocks | Trade with the ridge hamlet; tools (**Later**) |

Each settlement has a **stockpile** (the sum of its storage chests). Resources in the world are tracked as **resource sites** (a tree, a bush, an outcrop) so NPC beliefs can remember them, exactly as Final Landing's nodes.

### 4.4 Time

- Calendar: 720 ticks per day (as Final Landing), 4 seasons × 10 days = **40-day year**.
- At 1× speed one day lasts 2 real minutes (6 ticks/s). Speeds: Pause, 1×, 3×, 10×.
- **Rest at the shrine:** the god withdraws for a chosen number of days (1, 5, 10, a season). The simulation advances as fast as the machine allows behind a progress overlay, then returns the player to a world that has moved on, with a "While you rested…" summary drawn from the chronicle.
- Seasons affect berry regrowth (none in winter), day length, and the Shelter need (nights are harsher in winter). **Later:** weather and temperature.

## 5. Building and templates (core pillar)

### 5.1 Direct construction

- Crosshair targets a block face; place onto it or break it. Hold to repeat. Rotate orientable blocks (door, bed, stairs later).
- The avatar carries a divine stock of resources gathered by breaking blocks. Players can deposit into or withdraw from a settlement stockpile at a storage chest, which is the main way the god supplies a village with materials.
- **Decision:** no hunger, durability or crafting for the avatar. The friction is materials and reach, not survival.

### 5.2 Capturing a template

1. Open the **Design tool** and mark two corners; a wireframe box (max 16×12×16) shows the captured volume.
2. The game reads every block inside, trims empty margins, records the origin at the box's lowest front-left corner, and detects components.
3. The player names the design. The **detected function** and a **materials bill** (count per resource) are shown; the player cannot override the function.
4. The template is saved to the player's library (`user://templates/<id>.json`).

### 5.3 Function recognition

A structure's function comes from what it contains, not from its name. Rules live in data (`data/templates.json`):

| Function | Requires | Capacity |
| --- | --- | --- |
| Dwelling | ≥1 bed, ≥1 door, every bed covered by a roof block within 4 above | beds |
| Storehouse | ≥2 storage chests, ≥1 door, roofed | chests × 40 units |
| Workshop | workbench, roofed | 1 worker |
| Shrine | altar, and an altar is within 3 blocks of an open sky column or a sacred tree | — |
| Shelter | roofed floor area ≥ 6, ≥1 hearth or bed | sleepers (no bed bonus) |
| Unrecognised | none of the above | — |

A template can satisfy several functions (a house with an altar is also a household shrine). Built instances are re-checked when blocks change, so a ruined house stops counting as a dwelling.

### 5.4 Offering a template

Templates in the player's library are private. To make a design available, the player **offers** it at a shrine. It becomes known to everyone who worships at that shrine.

**Key rule (from the concept):** templates are **knowledge, not commands**. Offering a design makes it possible; it does not make anyone build it.

Designs also spread without the god:

- **Seeing:** an NPC who perceives a completed instance of a known template's structure learns that template (adoption by imitation).
- **Telling:** builders mention designs in small talk (like Final Landing's `InformNode`).
- **Migration:** people moving to a new settlement bring their known templates.
- **Later:** NPCs invent simple vernacular designs (a lean-to, a hut) so the world never depends on the player's library; NPCs vary templates (material substitution, mirroring).

### 5.5 NPC-driven construction

Construction is decided by individual NPCs through the BDI cycle (§6), never by a central planner.

1. **A need exists.** A homeless adult or a couple wanting a home (`FoundHome`); a settlement leader noticing a shortage (`ProposeProject`: storehouse if stores are full, shrine if none, shelter if many sleep rough).
2. **A design is known.** The NPC knows a template whose function fits the need.
3. **A site is feasible.** The NPC searches its believed surroundings for a spot inside the settlement area: footprint on solid ground, height variation ≤ 1 (small gaps are filled with a foundation), no overlap with structures, path access to the door side.
4. **Means are believed available.** Materials are believed in stock or known in the world.
5. **Priorities allow it.** The utility must beat eating, sleeping, safety and current commitments.

Adopting the goal places a **construction site**: ghost blocks visible in the world and on the settlement job board. The founder and anyone else whose work utility favours it then deliver materials and **place blocks one at a time, bottom layer first**, so construction is visible over hours. A site with no progress for 5 days is abandoned and its delivered materials stay as loose items.

**Proof-of-concept moment:** the player builds one cottage, saves it, offers it, and returns days later to find a street of similar cottages.

### 5.6 Template sharing

- Templates are versioned JSON files (format and validation in `scripts/building/template.gd` and `template_validation.gd`). The library screen has **Import** and **Export** (file dialog) on desktop.
- Imported designs are validated (size limits, known block ids) and land in the player's private library; they still have to be offered.
- **Later:** online sharing, moderation, and cultural traditions (settlements weighting designs they have built before).

## 6. The people (BDI agents)

The NPC system is a port of Final Landing's BDI architecture (see `NPC System Implementation Guide.md`). This section records **what changes** for The Bound God; formulas not mentioned here keep their Final Landing form and shipped values.

### 6.1 What is kept unchanged

- One committed intention per NPC; deliberation every ~10 ticks staggered by id; percept interrupts.
- Utility-scored candidate goals with a `reason` label; commitment bonus `c = 0.25` (×3 when leaving a survival goal).
- Plan library with several ranked plans per goal and a cheap last-resort plan for every survival goal.
- Failure learning: a failed step corrects beliefs, the plan id is added to `tried`, the next plan is tried; exhausted goals back off 120 ticks and add `frustrated`.
- Beliefs as a partial, decaying copy of the world; perception within a sight radius; typed messages delivered at the end of the tick.
- Needs, health, mood, thoughts, traits, skills, ambitions, relations, compatibility, gossip, courtship, help requests, mental breaks, departure.
- Deferred `Effects`, deterministic seeded RNG, decision log of 12 entries, and the "why" inspector.

### 6.2 Needs

| Need | Change from Final Landing |
| --- | --- |
| Food, Rest, Social, Recreation, Safety | Unchanged |
| **Shelter** (replaces Warmth) | Decays outdoors at night (×2 in winter and rain); restored by sleeping or staying under a roof. Drives housing demand. |

### 6.3 Goals

| Group | Goals | Notes |
| --- | --- | --- |
| Survival | Eat, Sleep, Flee, SeekCare, TakeShelter | TakeShelter replaces WarmUp |
| Leisure | Relax, Idle | Unchanged |
| Work | Gather(kind), Haul, Build(site), Repair(structure), Defend(threat), Scout | Farm, Cook, Craft, Research: **Later** |
| Settlement | **FoundHome(template)**, **ProposeProject(function)** | New; create construction sites (§5.5) |
| Faith | **Pray**, **TendShrine(shrine)**, **RestoreShrine(site)**, **Preach(person)**, **Quest(request)** | New (§7) |
| Social | Chat, Comfort, Court, Reconcile, Help | Unchanged |
| Crisis | Break(kind) | Unchanged |
| Movement | **Migrate(settlement)** | New: leave a failing settlement for a better known one instead of simply vanishing |

### 6.4 Faith inside the agent

Each NPC holds a **faith state**, separate from faction or settlement membership:

- `knows_god` — has heard the name.
- `devotion` 0–100 — how much they believe and trust the god.
- `aspects` — what they believe the god is: harvest, protection, travel, shadow, wrath (each 0–1, normalised).
- `shrine` — the shrine they attend, if any; `last_prayer_tick`.

Belief stage is derived: **Unaware** (does not know) → **Aware** (< 20) → **Curious** (20–39) → **Believer** (40–69) → **Devout** (70+).

Devotion and aspects change through experience, interpreted through personality:

| Experience | Effect |
| --- | --- |
| Witnessing a miracle | +devotion by miracle size × relevance (Bless Growth while hungry counts more); aspect of that miracle rises |
| Answered prayer | A prayer about need X followed within 1 day by a god act that relieves X: large boost, `prayer_answered` thought |
| Seeing the avatar | First sight: `saw_the_god` (awe for spiritual/curious, fear for cautious); slight devotion |
| Stories (`Story` messages) | Unaware → Aware; Aware/Curious gain devotion weighted by trust in the speaker; aspects shift toward the speaker's |
| Community | Daily drift toward the devotion of friends and partner |
| Harm by the god | Destroyed home or fields: devotion drops for most, but cautious, pessimist or `hot_headed` people may *gain* devotion with a strong wrath aspect (fear worship) |
| Neglect | Slow daily decay without reinforcement; faster after unanswered desperate prayers |

New traits: `pious` (devotion gains ×1.5, Pray utility up), `sceptic` (gains ×0.5, immune to fear worship). Existing `spiritual` keeps its role.

### 6.5 New plans and steps (summary)

- **Pray:** go to attended shrine and kneel (`pray_at_shrine` 1.0) · pray at home altar (0.7) · pray where they stand (0.3). A prayer carries an **intent**: the NPC's most pressing problem (lowest need, a believed threat, a sick partner).
- **TendShrine:** go to the shrine, repair missing blocks from its saved layout, clear debris.
- **Preach:** go to an unaware or curious person and `Talk{topic: Story}`.
- **FoundHome / ProposeProject:** choose template, pick site (`MarkSite` step), then the normal Build plans.
- **Build:** fetch materials (stock or loose items), `Deliver`, then `PlaceBlock` repeatedly (one block per ~20 ticks, faster with Construction skill).
- **Migrate:** gather belongings, travel to the target settlement, join it.

### 6.6 Settlement culture instead of player priorities

Final Landing multiplies work utility by a player-set priority (0–3). Here each settlement holds **culture weights** per work type, starting at 1.0 and drifting slowly toward what the settlement actually needs and what its respected members do (leaders' choices count double). The player influences them only indirectly. This keeps labour spreading without central assignment and gives settlements recognisable characters.

### 6.7 Population and lifecycle

- Start: two travellers arrive at the sacred tree on day 1 (concept's Year 1). The ridge hamlet starts with 5 miners who do not know the god.
- **Migrants** arrive at a settlement's edge when it is attractive (spare beds, food stores, safety, renown of its shrine); one roll per 3 days.
- Births, children, ageing and death as Final Landing. Prototype population cap: 30 total.
- Departure (6 days of very low mood) becomes **Migrate** when a better settlement is known, otherwise leaving the map.

## 7. Faith, shrines and miracles

### 7.1 Two kinds of divinity

- **Renown** (global): how many people across the world know the name. Unlocks miracle tiers and is shown on the shrine menu.
- **Favour** (local, per shrine): spendable power accumulated from prayers at that shrine. Miracles are paid from the Favour of the shrine where the avatar stands.

A famous god can be powerless in a place where nobody prays; a tiny devoted hamlet can give a strong local anchor.

### 7.2 Shrines

A shrine is a recognised Shrine structure (§5.3) with a **congregation**: the NPCs whose `shrine` is it.

| Property | Rule (prototype values, tunable in data) |
| --- | --- |
| Support | Σ devotion of congregation members who prayed there in the last 3 days, ÷ 100 |
| Active (manifestable) | Support ≥ 1.2 (e.g. three believers at 40) |
| Presence radius | 16 + 6 × √support blocks, max 40 |
| Favour gain | Each prayer adds devotion ÷ 25 Favour; cap 100 per shrine |
| Condition | 100 when built; decays 2/day untended; TendShrine restores; < 30 halves Favour gain; altar destroyed → 0 |

The **sacred tree** is the origin shrine: always considered a shrine structure and **always active**, so the god can always tend the small area around its tree. **Decision (2026-10-10):** with no support the tree's presence radius is 10 blocks; it widens toward the normal radius (16 + 6 × √support) as support approaches the active threshold, and shrinks back when prayers fade. There is no grace timer. Altars elsewhere still go dormant without support.

### 7.3 Miracles

Miracles are cast where the avatar stands, cost Favour, and are visible events that NPCs perceive and interpret (§6.4). Prototype set:

| Tier | Miracle | Cost | Effect | Aspect |
| --- | --- | --- | --- | --- |
| Small | **Whisper** | 2 | Talk to one Believer+ in the zone: choose a nudge (rest, build, gather X, pray, make peace with Y, go to Z). Adds a temporary utility bonus to that goal kind of `0.4 × devotion/100` for one day. Aware/Curious only hear "a strange voice" (Safety −5, curiosity +) | — |
| Small | **Bless Growth** | 15 | Berry bushes in a 10-block radius ripen and regrow instantly | harvest |
| Small | **Kindle** | 5 | Lights a hearth; a sheltered area counts as roofed for one night | protection |
| Medium (renown ≥ 15) | **Veil of Fog** | 30 | For one day, threats cannot perceive anything inside a 20-block radius | shadow |
| Medium (renown ≥ 15) | **Mend** | 25 | Restores a structure's missing blocks from its template | protection |

Whispers are the god's voice in the agent system: they enter the inbox as a `Whisper` message and appear in the NPC's decision log as "Felt the god urge me to …", so the inspector stays truthful about why someone acted. They never bypass deliberation.

The **identity** of the god is the devotion-weighted average of believers' aspects. A miracle whose aspect matches the dominant identity costs 25% less; one that contradicts it (e.g. wrath acts by a harvest god) costs 25% more and confuses believers (devotion −). Two communities can worship the same god in contradictory ways.

**Later:** large and exceptional miracles (divert water, storms, guardians, reshape land), destructive miracles (smite, blight) as an explicit malevolent path.

### 7.4 Prayers as information

The god does not have perfect knowledge. What reaches the player:

- **Here (current shrine zone):** everything visible; any NPC can be inspected.
- **Prayer feed:** every prayer at any active shrine is listed with the speaker and intent ("Edda prays for food — Hunger 23"). Prayers at other shrines arrive in a delayed summary when the avatar transfers there or rests.
- **Reports:** followers returning from quests report what they believe (their beliefs, which may be stale or wrong).
- **Chronicle:** major events everywhere (deaths, shrines raised or lost, raids) appear, but only once someone who could know about them has prayed or travelled to an active shrine.

### 7.5 Losing a shrine and dormancy

- A shrine whose support stays below the active threshold for 3 consecutive days goes **dormant**. An altar destroyed or desecrated (by raiders, or by NPCs who turned against the god) makes it **fallen**.
- If the avatar is at a shrine that becomes dormant or fallen, it is **expelled** to the active shrine with the highest support.
- If no shrine is active, the god becomes **dormant**: the avatar is a faint wisp at the last shrine, cannot build, and can only Whisper (free, but heard only by Devout). Recovery happens through people: surviving believers with the `RestoreShrine` goal rebuild the altar, or keep praying until support recovers. **Decision:** no game-over screen; the world keeps running and the chronicle tells what happened. If every believer is gone, the god fades and a "the world remembers" epilogue summarises the run with the option to continue watching.

## 8. Expansion through people

The concept's five steps map directly onto systems:

| Step | System | Prototype content |
| --- | --- | --- |
| 1. Discovery | Scout goal; Quest "explore" | Followers find the ridge ruin and the hamlet; their beliefs now contain it |
| 2. Recognition | `Story` talk topic; travellers and migrants | A follower who meets a miner tells stories; the miner becomes Aware |
| 3. Belief | Faith state (§6.4) | Miners who hear repeated stories, see a Mend or Bless Growth at their edge (if in range later), or get help become Believers |
| 4. Shrine | `RestoreShrine` / `ProposeProject(shrine)` | Believers restore the ruined altar on the ridge or build an offered shrine template |
| 5. Manifestation | Shrine support ≥ threshold | The shrine menu shows the ridge shrine as a transfer destination |

### 8.1 Divine requests

At an active shrine, the player can post a request:

| Request | Goal | Completion |
| --- | --- | --- |
| Carry my name to *place* | Quest(explore + preach) | The follower reaches the place and tells at least 2 stories there |
| Bring *resource* × *n* | Quest(fetch) | Delivered to the shrine's stockpile |
| Raise a shrine at *place* | Quest(found shrine) | A shrine is recognised there and has a congregation of ≥ 1 |
| Restore *shrine* | RestoreShrine | Altar and condition ≥ 50 |
| Protect *settlement* | Defend near target | No raid succeeds there for 5 days |

Requests are broadcast as `DivineRequest` messages to believers at that shrine. Each NPC decides whether to take it from devotion, bravery, curiosity, current needs, believed danger and the promised **boon** (the player attaches a blessing: a Favour-paid bonus on success such as `blessed` thought, +skill, or Bless Growth at their home). A taken quest is an ordinary intention; it can fail, be abandoned, or succeed in an unexpected way, and its outcome is reported when the follower prays next.

Followers also start their own expeditions: devout NPCs with the `curious` trait or the `map_the_wilds` ambition may Preach or Scout unprompted.

### 8.2 Transfer

From the shrine menu, the player transfers to another **active** shrine. The transfer takes a moment of visual effect; the avatar appears at the new altar. Only one manifestation at a time; the old place carries on without the god.

## 9. Threats and change

### 9.1 Wildlife

Wolves roam the woods (creature system from Final Landing): they cause Flee/Defend reactions, Warn messages and Safety loss, and occasionally injure people. Their main role is to make Safety and shelter matter.

### 9.2 Raiders (the prototype threat)

- A **raider band** (3–5 hostile actors) forms off-map. Every 4 days the threat director rolls a raid against the wealthiest or least defended settlement, rising with stockpile wealth and falling with the number of believed defenders. **No raid before day 12.**
- Raiders walk in, take resources from storage, may smash doors, and target the **altar** if the settlement's god is known to them (desecration). They leave when they carry enough or when defenders outnumber them.
- Villagers react through the normal BDI cycle: Warn, Flee to shelter, Defend if brave, Help the injured. **Veil of Fog** and stone walls are the god's main counters; the player is not a fighter (the avatar cannot attack).
- Outcomes are causal: the ridge hamlet, small and far from the god, is more likely to be raided and lose its new shrine, which is exactly the concept's "nothing is permanently secure".

**Later:** raiders who stay and occupy an abandoned settlement, bandit camps adopting the faith (outlaw aspect), rival gods and religions.

### 9.3 Decay and change

- Unmaintained structures lose a block occasionally after 20 days without a resident or repair.
- Abandoned settlements (no residents for 10 days) start to overgrow (grass and saplings spread onto paths).
- Buildings are re-evaluated when their contents change: a dwelling whose bed was taken by raiders becomes a shelter; a house gets adopted by migrants.

## 10. World history: the chronicle

The chronicle stores events with **causes**:

```
Day 14 · Ridge hamlet · The ridge shrine fell — raiders broke the altar (raid by the Ashen band; 2 defenders, 5 raiders).
Day 9  · Tree hollow  · Brannoc and Edda built a cottage from "Willow Cottage" (housing shortage: 5 people, 2 beds).
```

- Entry kinds: arrival, departure, birth, death, bond change, structure built/abandoned/converted, template adopted, shrine raised/dormant/fallen/restored, miracle, request taken/completed/failed, raid, migration.
- Shown in a Chronicle screen filtered by place and person; feeds the "While you rested…" summary and the epilogue.
- Each entry links to the NPCs and structures involved, so "why does this road exist" can be answered by looking.

## 11. Core loops

### 11.1 Immediate (minutes): build and nurture

Manifest → look around (who is hungry, homeless, scared?) → break and place blocks → supply materials to the stockpile → small miracle or whisper → watch people respond.

### 11.2 Medium (days): empower a community

Design a useful building → save and offer it → watch villagers adopt it → solve the problems they cannot (materials out of reach, threats, terrain) → grow devotion → unlock stronger miracles.

### 11.3 Long (seasons and years): spread and defend the faith

Post requests → followers travel and preach → a remote shrine rises → transfer and nurture that place → the first village keeps changing without you → raids, migrations, schisms → recover lost shrines through survivors.

**Later (beyond prototype):** region-based world, low-fidelity simulation of distant regions (population, stock, belief and scheduled projects advanced in daily steps, materialised into voxels on return), rival religions, bandit settlements, endgame options.

## 12. Interface

| Screen / element | Contents |
| --- | --- |
| HUD (small) | Time and speed, current shrine name, Favour, renown, divine stock (top materials), crosshair, prayer toast feed (last 3) |
| Shrine menu (interact with altar) | Shrines list with status and transfer, offer template, post request, miracle list with costs, rest |
| Design tool | Corner marking, capture preview, function, materials bill, name, save |
| Template library | Private and offered designs, adoption counts per settlement, import/export |
| NPC inspector | Final Landing's four tabs (Mind with decision log and beliefs vs reality, Needs, Bonds, Life) + **Faith** tab (stage, devotion, aspects, attended shrine, last prayer and intent, heard stories) |
| Settlement panel | Residents, beds, stock, construction sites, culture weights, known templates, recent events |
| Chronicle | Filterable history with causes |
| Overlays | Presence boundary, construction ghosts, NPC activity glyphs and mood rings, selected NPC's path and strong relations |

Final Landing's rule is kept: **presentation comes before tuning**. The inspector must be usable before balance work starts.

## 13. Technical constraints (summary)

Taken from the `small_following` Godot baseline; details in `IMPLEMENTATION_PLAN.md`.

- Godot **4.2.2**, GDScript, **Forward+** renderer (a deliberate change from `small_following`'s Compatibility renderer, for 3D lighting, fog and ambient occlusion); no plugins or GDExtensions without approval; built-in features first (ArrayMesh, AStar3D, FastNoiseLite, RandomNumberGenerator).
- All tuning in `data/*.json`, loaded once and validated, failing fast on missing keys.
- Simulation is pure data (RefCounted) and runs headless; scenes only present it.
- Deterministic: one seeded RNG; same seed and inputs → same world.
- Saves under `user://` with staged writes and backup recovery.
- Windows only at this stage. Forward+ rules out an HTML5 export; revisiting the web means switching to Compatibility and is not planned.
- Visual style: simple procedural shapes for people and creatures, a small 16 px block texture atlas.

## 14. From first playable to full game

### 14.1 First playable (complete)

The vertical slice (milestones M0–M12) proved that building a design, empowering autonomous residents and leaving them alone works: one 160×48×160 valley, the sacred tree and the ridge, the design tool and offered templates, the BDI people with their social layer and faith, Whisper and four small and medium miracles, three request kinds, wolves and one raider band, rest, chronicle and saves. Its acceptance moment (build a cottage, offer it, rest, find more; carry the name to the ridge; transfer; a later absence changes something with a cause) is built and checked. Record: `PROGRESS.md`.

### 14.2 Full game (Phase 2)

**Goal:** a complete game that a new player can learn unaided and play for years of in-game time across several regions, with a god whose identity is shaped by how it is worshipped. Planned in `IMPLEMENTATION_PLAN.md` (milestones M13–M24, with the definition of "fully playable" in its §1).

These **Later** items from this document are promoted into Phase 2:

| Item | Section | Milestone |
| --- | --- | --- |
| Grain, farm plots, Farm and Cook goals | §4.3, §6.3 | M14 |
| Weather and temperature | §4.4 | M15 |
| Craft goal, tools from ore | §4.3, §6.3 | M16 |
| NPC-devised vernacular designs, material substitution, mirroring, traditions | §5.4, §5.6, §15 | M17 |
| Region-based world with low-fidelity distant regions | §4.1, §11.3 | M18 |
| Raiders as BDI agents, occupation, bandit settlements adopting the faith | §9.2 | M19, M20 |
| Large and exceptional miracles, the malevolent path | §7.3 | M20 |
| Formal endgame (epilogue, ages, optional deeds) | §15 | M22 |

Still **Later** (after 1.0): online template sharing and moderation, rival gods and religions as separate faiths, multiplayer, platforms other than Windows. Research and ore trade with off-map peoples stay out; trade happens between settlements in the world (M19).

**Acceptance for 1.0:** a fresh player reaches the first-playable moment in under two hours unaided; a world plays for at least three in-game years across three regions and five settlements, producing caused change (prosperity, famine, raids, occupation, schism, recovery); nurturing, protective, feared and outlaw gods each develop a distinct identity and reach an epilogue.

## 15. Open questions

Carried from the concept, with current leanings:

| Question | Leaning |
| --- | --- |
| Size of influence zones; overlapping and rival religions | Radius from support (§7.2); schisms within the god's own faith in M20; rival religions Later |
| How many believers enable manifestation | Support ≥ 1.2 for the prototype; tune by playtest |
| Avatar capabilities vs miracles | Avatar builds and carries; anything affecting people or many blocks is a miracle |
| Can NPCs create original templates | Yes, from M17: vernacular designs from a small parametric generator, validated by the function rules |
| Template substitution, renovation, destruction | M17: material substitution groups, mirroring, adoption of empty buildings, salvage of ruins |
| Worship vs faction vs culture | Separate fields: faith state per NPC, settlement membership, settlement culture weights |
| Quest UI without excess | Shrine menu only; outcomes arrive as prayers and chronicle entries |
| World time and fast-forward limits | Speeds up to 10×; rest up to one season; distant regions advance at low fidelity (M18) |
| Remote destruction: consequential not exhausting | Raid cooldowns, warnings via prayers, survivors and dormancy instead of hard loss |
| Formal endgame | Open-ended, with named ages, optional saga deeds and an epilogue on fading or when the player closes the book (M22) |

*Status: v0.2. The first playable is complete; Phase 2 scope is in §14.2. Agreed concept direction is preserved; prototype decisions are marked and expected to change after playtests.*
