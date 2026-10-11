# The Bound God — Game Design Document

> Version 0.3 · 2026-10-10 (cultivation-sect direction) · Godot 4.2.2 (GDScript, Forward+ renderer, Windows)
>
> Sources: `docs/design/sacred_tree_cultivation_design.md` (the current direction: a tree spirit guarding a cultivation sect), `docs/design/bound_god_game_concept.md` (the original bound-god vision, still the base for faith, shrines and templates), `docs/reference/npc_system_guide.md` (the Final Landing BDI agent system the people are ported from). Look and type: `docs/design/art_direction.md`, `docs/design/font_direction.md`, concept images in `docs/art/`. Implementation is planned in `IMPLEMENTATION_PLAN.md`; what is built is recorded in `PROGRESS.md`.
>
> Markings: **Decision** is a call made and built on. **Leaning** is the working answer, changeable without rework. **Tuning** is a number or threshold left to balance passes and playtests. **Later** is a direction kept but deferred. **Open** is a design question still unanswered.

## 1. Pitch

You are the spirit of an ancient sacred tree, walking the land beneath it as a robed avatar. The tree breathes an unusual spiritual energy, and mortals who meditate in its shade find that cultivation comes easier. They stay, teach, build, and in time become a sect. You nurture them, whisper to them, show them designs and spend scarce Favour on blessings and the occasional miracle, but you never command them. They choose their own masters, their own buildings and their own quarrels, and they keep living while you meditate through the years.

When a cultivator faces a heavenly tribulation beneath your branches, the tree learns from it. Over generations the sect's struggles shape what the tree becomes, and the tree's growth shapes what the sect can become.

**Design promise:** nurture a sect, witness generations rise and fall, and become a greater sacred tree through the trials of the people who live beneath it.

**Genre:** third-person voxel world + autonomous cultivation-sect simulation + local god game.
**Platform:** Windows desktop (keyboard/mouse and gamepad). No web build (see §16).
**Session shape:** 20–60 minute sessions; a campaign spans generations of in-game years, most of them passed in meditation.

**Decision (2026-10-10):** the cultivation-sect direction replaces "build the foundations of a civilisation" as the game's centre. Everything built in the vertical slice (voxel valley, templates, BDI people, faith, shrines, miracles, food) stays and becomes the ground the sect grows from.

## 2. Design pillars

Every feature must serve at least one.

| Pillar | Means in practice |
| --- | --- |
| **Influence, not obedience** | The god shapes conditions, offers designs, whispers, blesses and performs miracles. NPCs decide, including the sect master, who may disagree. |
| **A world that continues without you** | The sect keeps living while the god is elsewhere or meditating. Years can pass; it can prosper, split, decline or change its beliefs. |
| **Individuals across generations** | People are not interchangeable workers. A novice met today may be an elder in a century; anyone can rise, followed or not. |
| **Mutual growth** | The tree's qi helps cultivators advance; their tribulations teach the tree, which grows new abilities for the sect. |
| **A tangible, editable world** | A voxel world the god and the people reshape. Buildings work by their components, designs outlive their builders, and history leaves marks on the land and the tree. |
| **Reach is earned through belief** | The avatar exists only where people worship. Shrines spread with believers and can be lost. |
| **Divinity has an opportunity cost** | Favour is scarce: one great rescue can cost what would have nurtured ten disciples. |
| **Every outcome has a reason** | Each person's "why" is inspectable; the chronicle records causes. |

Non-goals: not a Minecraft remake, not a survival-crafting treadmill, not a top-down sect manager, not a god game where you command NPCs, not a fixed xianxia storyline.

## 3. Player role

### 3.1 The tree spirit

- **Decision:** the player is the **guardian spirit of the sacred tree**, not the sect's founder, master or ruler. The physical avatar (a robed jade spirit, about 1.8 blocks tall) exists from the first moment.
- **Bound:** the avatar exists only inside the **presence zone** of the shrine it is manifested at, and at one shrine at a time. The zone's edge is a soft shimmering wall. The sacred tree is the origin shrine; other shrines and branch sites come through believers (§11).
- **Hands-on actions:** break and place blocks, pick up and drop loose items, inspect a person, and **use** the block under the crosshair (a chest opens its contents, a bed offers rest, a workbench opens the design library, a hearth is kindled, a door opens or shuts for the avatar, an altar or the tree opens the shrine menu).
- **Hotbar:** nine slots that start empty, filled and ordered by the player on the blocks screen.
- The avatar does not eat, sleep or die. It can be **expelled** (§10.5).
- NPCs see the avatar, and seeing it is an event in their minds (awe, fear, curiosity), so where and how the god appears matters.

### 3.2 Camera

- **Play camera:** over-the-shoulder spring arm, crosshair targeting, reach 5 blocks.
- **Overlook:** an elevated orbit around the active shrine, clamped to the zone, for watching the sect, picking people and planning builds.

### 3.3 What the god can and cannot do

| Can | Cannot |
| --- | --- |
| Build, dig and terraform inside the presence zone | Leave the presence zone |
| Save structures as templates, offer them, and lay out blueprints as proposals | Order anyone to build, or queue construction |
| Whisper to a believer (a nudge) | Assign jobs, set priorities, move people, pick the sect master |
| Bless, protect and, at great cost, defy Heaven for someone | Guarantee a breakthrough or grant a realm |
| Post divine requests at a shrine | Force anyone to accept a request |
| Inspect anyone in view and read their reasoning; follow chosen disciples | Know what happens where no shrine and no report reaches |
| Meditate through seasons and years | Pause the world while away |
| Transfer to another active shrine | Manifest at two shrines at once |

**Decision:** there is no work-priority panel. Labour is steered only indirectly (materials, designs, whispers, requests, blessings); each settlement's culture weights drift by themselves (§6.6).

## 4. The world

### 4.1 Voxel scale and the first valley

- 1 block = 1 metre; chunks 16×16×16.
- **The first valley:** a bounded, seeded valley of 160×48×160 blocks. The sacred tree stands at its centre; a rocky ridge with stone, ore and a ruined altar lies ≈70 blocks away, with a small mining hamlet of five people who do not know the god; three founding grounds lie on open land.
- **Later:** a world of several regions joined by passes, where only the god's region simulates in full and the rest advance abstractly (§13.3).

### 4.2 Blocks

Interacting systems over decorative blocks. Three families:

| Family | Blocks |
| --- | --- |
| Terrain | grass, dirt, stone, sand, gravel, ore, water, bedrock, tall grass |
| Material | log, leaves, planks, thatch, cut stone, cobble, glass, fence, farmland, sapling |
| Functional | bed, door, storage chest, granary bin, workbench, hearth, altar, berry bush, crop, sacred tree, table, bench, planter, lantern |

Breaking a block yields its resource; placing one costs a unit from the god's divine stock. Functional blocks are **components** (§5.3): a structure's purpose comes from them. New blocks enter the catalog only with an implemented effect. Cultivation adds components such as a meditation mat, a formation stone and an alchemy furnace when the systems that use them land (§7, §8).

### 4.3 Resources

| Resource | Source | Use |
| --- | --- | --- |
| Wood | Logs (4 per log) | Planks, furniture, doors, fuel |
| Stone | Stone, cobble | Foundations, hearths, altars, lanterns |
| Thatch | Tall grass | Roofs |
| Soil | Dirt-family blocks | God-only terraforming |
| Berries | Bushes, gardens | Food; spoil in 6 days |
| Grain, seed | Fields | Food that keeps; seed to sow |
| Meals | Kitchens | Best food; spoil in 3 days |
| Tree seed | Falling leaves | Saplings, replanting the woods |
| Ore | The ridge | **Later:** tools and cultivation materials |
| Spirit materials | The tree's growth (§9) | **Later:** pills, formations, techniques |

Each settlement's stock is what lies in the storage chests in its area. Loose goods can be used but are not counted as stock. The god's divine stock is never the settlement's; the god supplies people by filling chests.

### 4.4 Time

- **Decision:** 720 ticks a day; 4 seasons × 10 days = a 40-day year. At 1× a day lasts 2 real minutes. Speeds: pause, 1×, 3×, 10×. People age in years (adult at 18, old age near 88 for mortals; **Tuning**).
- The god's long life makes **decades and centuries** the meaningful units of the campaign. Days are lived through the avatar; years pass through **meditation** (§13).
- Seasons drive berry regrowth, crop growth and frost, night length and Shelter, and the autumn wish to put food by. **Later:** weather and temperature.

## 5. Building and templates

### 5.1 The god's hands

**Decision (2026-10-10):** hands-on block placement stays as the spirit's power inside the presence zone: immediate, tactile, paid from divine stock. It is how the god shapes ground, supplies materials, builds a model to capture as a design and makes small fixes. It is **not** how the sect gets built: the sect's halls and homes are raised by its people.

- Crosshair a block face; place or break; hold to repeat; orientable blocks rotate.
- No hunger, durability or crafting for the avatar. The friction is materials and reach.

### 5.2 Capturing a template

1. Open the **design tool** and mark two corners (box up to 16×12×16).
2. The game reads the blocks, trims empty margins and detects components.
3. The player names the design; the **detected function** and **materials bill** are shown. The player cannot override the function.
4. It is saved to the private library (`user://templates/<id>.json`).

### 5.3 Function recognition

A structure's function comes from what it contains, never from its name. Rules live in `data/templates.json`. Built:

| Function | Requires |
| --- | --- |
| Dwelling | ≥1 bed, ≥1 door, every bed roofed |
| Storehouse | ≥2 chests, ≥1 door, roofed |
| Workshop | workbench, roofed |
| Shrine | altar near open sky or a sacred tree |
| Shelter | roofed floor ≥ 6, a hearth or bed |
| Hall | table, ≥2 benches, roofed floor ≥ 12 (recreation ×2) |
| Garden | ≥4 joined planters under open sky (bushes ×2, bear in winter) |
| Field | ≥6 joined farmland under open sky |
| Kitchen | roofed hearth with a workbench or chest |
| Granary | ≥2 roofed granary bins and a door |

**Leaning (cultivation):** sect functions follow the same rule. A **meditation hall** (roofed, mats, in qi above a threshold), a **training ground** (open, level, a marked area), a **tribulation ground** (an open platform, formation stones, at a distance from housing: protection comes from formations and placement, not grandeur), and an **alchemy room** (furnace, roofed). Exact components: **Tuning** when each lands.

**Leaning (M19b, the sect's halls):** a grown sect also raises a **scripture library** (shelves and a lectern: techniques copied into manuals and studied), a **meditation room** (one mat and incense: closed-door cultivation for one), a **tribulation chamber** (a sealed stone room with an array and a thunder spire: a gentler storm that scorches nothing), an **infirmary** (beds and medicine: healing and a mended foundation), a **spirit-gathering array** (spirit jade on stone: dense qi away from the trunk), a **mountain gate** (pillars and banners: seekers come and join), an **ancestral hall** (tablets and incense: the relics' help at home), a **precept stele** (steady doctrine), a **bell tower** (a warning everyone hears) and a **lecture hall** (a lectern and benches: leisure spent listening to the Way). Existing buildings can be **renovated** into these by adding what they lack. Components and effects: `IMPLEMENTATION_PLAN.md` M19b; numbers **Tuning**.

### 5.4 Offering, blueprints and spread

Templates in the library are private. **Offering** one at a shrine makes it known to the people there who know the god. **Decision (concept):** templates are knowledge, not commands. Offering never queues construction.

**Leaning (cultivation):** the god may also lay a **blueprint**: a template placed as a ghost on a chosen site, inside the zone. A blueprint is a *proposal*. It joins the candidate sites of anyone who needs that function, with a bonus for being where the god wants it; whether anyone builds it, and when, remains the people's decision. A Whisper can urge one person to take it up.

Designs also spread without the god: by seeing a finished building, by talk, and with migrants. **Later:** people devise their own vernacular designs, substitute materials, mirror and renovate (M19 in the plan), and settlements keep traditions.

### 5.5 NPC-driven construction

Built by individuals through the BDI cycle, never by a central planner:

1. **A need** (no home, a shortage the leaders notice, a sect that wants a training ground).
2. **A known design** whose function fits.
3. **A feasible site** in the settlement area (level enough, free, reachable), or a blueprint.
4. **Means believed available** (materials in the chests or known in the world).
5. **Priority** above eating, sleeping, safety and commitments.

The founder places a construction site (ghost blocks); anyone whose work utility favours it delivers materials and places blocks one at a time, bottom up. Builders without stone raise plain walling in planks. A site with no progress for 5 days is abandoned.

### 5.6 Template sharing

Templates are versioned JSON with import and export on the library screen. Imports are untrusted: validated for size, palette and shape, with function and bill recomputed. **Later:** online sharing and moderation.

## 6. The people (BDI agents)

### 6.1 The agent system

A port of Final Landing's BDI architecture: one committed intention per person, deliberation every ~10 ticks, utility-scored candidate goals with a reason, a commitment bonus, ranked plans with a last-resort plan for survival, failure learning and backoff, decaying partial beliefs, typed messages, deferred `Effects`, a seeded RNG and a 12-entry decision log behind the "why" inspector. Needs, mood, thoughts, traits, skills, ambitions, relations, gossip, courtship, help requests, mental breaks and departure are all kept.

### 6.2 Needs

Food, Rest, Social, Recreation, Safety, and **Shelter** (decays outdoors at night, more in winter). **Later:** cultivation may add a need for qi or stillness for cultivators.

### 6.3 Goals

| Group | Goals |
| --- | --- |
| Survival | Eat, Sleep, Flee, SeekCare, TakeShelter |
| Leisure | Relax, Idle |
| Work | Gather, Haul, Build, Repair, Defend, Scout, Garden, Farm, Cook, PlantTrees |
| Settlement | FoundHome, ProposeProject |
| Faith | Pray, TendShrine, RestoreShrine, Preach, Quest |
| Social | Chat, Comfort, Court, Reconcile, Help |
| Crisis | Break |
| Movement | Migrate |
| **Cultivation (planned)** | Cultivate, Teach, Learn, Breakthrough, Spar, Recruit, Guard the tribulation |

### 6.4 Faith inside the agent

Each person has a faith state: `knows_god`, `devotion` 0–100, `aspects` (harvest, protection, travel, shadow, wrath), an attended shrine and last prayer. Stage: Unaware → Aware (< 20) → Curious → Believer (40) → Devout (70). Devotion moves with witnessed miracles, answered prayers, sightings of the avatar, stories, friends, harm and neglect, read through personality (`pious`, `sceptic`, `spiritual`; fear worship for the cautious).

**Leaning (cultivation):** respect for the tree and devotion to its spirit are the same number. A cultivator can use the tree's qi while doubting its spirit, which is a source of politics, not a bug.

### 6.5 Settlement culture

Each settlement holds culture weights per work type that drift toward what it needs and what its respected members do. **Leaning (cultivation):** the sect adds **doctrine** weights in the same style (for example openness to outsiders, martial pride, secrecy, mercy, ambition), drifting with its masters' choices and the tree's influence, so a sect can become benevolent, isolationist, mercantile, militant or ruthless without a hard-coded morality path.

### 6.6 Population and lifecycle

- Start: two wanderers arrive at the tree on day 1; the ridge hamlet has five miners.
- **Migrants** come when a settlement is attractive (beds, food, safety, shrine renown, standing; **Leaning:** and the tree's qi, which draws would-be cultivators). A hungry settlement draws nobody. Migrants bring designs and news of open land.
- Births, childhood, ageing and death as in Final Landing. Migrants stop at 50 people, births at 60, so long-lived cultivators cannot end the generations (**Tuning**). A bed sleeps a couple and partners share a home.
- **Settlement standing** (built): camp, hamlet or village, judged daily from residents, housing, food days, functions and a living shrine; rises and falls are chronicled. **Leaning:** a **sect** is not a fourth standing but an institution that forms inside a settlement (§7.4).
- Long unhappiness leads to Migrate, or to leaving the valley.

## 7. Cultivation

The heart of the new direction. **Decision (brief):** all cultivators progress by their own choices; the player can watch some more closely, but **being followed grants no advancement**.

### 7.1 Qi and the tree

The sacred tree makes a **qi field**: dense under its crown, thinning with distance. Qi speeds cultivation, which is why people come, settle and compete for the best spots. **Leaning:** qi is a function of distance from the tree (and later from nurtured spots, roots and formations); it is not a resource that is spent. Exact curve: **Tuning**.

### 7.2 The cultivator

Added per person (simulated cheaply for most, in depth for notable and followed people):

- **Spiritual root / talent** and an **affinity** (rolled at birth or arrival; most people have little).
- **Realm** and progress within it; **foundation** quality (how sound the last breakthrough was).
- **Techniques** known (learned from a teacher, a manual or the tree), and who taught them.
- Lifespan extended by realm (**Tuning**).

**Decision (brief):** familiar xianxia realms are the scaffold: Mortal → Qi Refining → Foundation Establishment → Golden Core → Nascent Soul → further realms later. Number of realms, durations and power curve are **Tuning**; the slice needs Mortal, Qi Refining and Foundation Establishment. **Built (2026-10-11):** Core Formation (the Golden Core) follows Foundation Establishment, through a fiercer lightning that the tree learns from as a new insight.

### 7.3 Cultivating, teaching, learning

- **Cultivate:** meditate in the best qi a person can reach and is allowed to use; progress by talent × qi × technique × foundation. Competes with work, food and rest in the normal utility contest.
- **Teach / Learn:** a cultivator passes a technique to a student through the social layer; teaching lineages are recorded and become legacies.
- Duties (farming, building, guarding, teaching, exploring) still matter: a sect that only meditates starves.

### 7.4 How a sect forms

**Decision (brief):** the player never presses "Found Sect". **Leaning:** when a settlement has a teacher with several students and a place to cultivate, its cultivators may found a sect by their own choice: they name it, recognise a master (the most respected senior), and record it in the chronicle. A sect has members (disciples, elders, master) and doctrine; non-cultivators can live alongside it. Rival groups can contest the tree before one sect holds it. Thresholds: **Tuning**.

The sect then decides training, recruitment, leadership, expeditions, building priorities and defence through its members' BDI choices. Succession happens when a master dies, steps down or is displaced. Branches, alliances, refugees and guests come later (§11).

### 7.5 Attention and generations

The player can **follow** a few people (pinned in the inspector and highlighted in the chronicle). Followed people are simulated in full detail at all times, and their milestones interrupt meditation. Anyone else can still become legendary. A disciple met as a novice may return as an instructor, an elder, a legacy of students and a relic; the player should sometimes choose to help the next generation instead of preserving the old.

## 8. Tribulations and the sanctuary

### 8.1 Breakthroughs

At the peak of a realm a cultivator may attempt a **breakthrough**. It is their decision, weighing readiness, preparation, foundation, fear and ambition. Some breakthroughs provoke a **heavenly tribulation**: an event of a kind (lightning first; heart-demon, fire and elemental trials later) and a severity. Which breakthroughs, and how severe: **Tuning**.

### 8.2 Rules (Decision, brief)

1. Cultivators may attempt tribulations anywhere.
2. Both they and the tree **prefer the tree**: the sanctuary improves their odds and the tree learns from the event.
3. Visitors from other sects may be welcomed for the same reasons (§11.3).
4. The tree cannot guarantee success. Preparation, foundation, technique, surroundings and severity still decide.
5. Tribulations carry environmental and political risk: lightning scars blocks and buildings, draws attention, changes the land, and divides leaders over whom to admit.

### 8.3 Outcomes

Success (new realm, sound foundation), failure (injury, a cracked foundation, or death), and the god's interventions (§10.3). A tribulation is a public event: people gather, fear, pray and remember. Sites of great tribulations keep their marks.

### 8.4 The sanctuary grows with the sect

At first breakthroughs happen in the clearing under the branches. Later the sect may build a **tribulation ground** (§5.3) by its own decision, with recovery rooms and watchers at a safe distance. Admission of outsiders (free, allies only, for an offering, or forbidden cultivators) is a sect decision the god can only influence.

## 9. The sacred tree's growth

**Decision (brief):** the tree does not level like a cultivator. It grows through what it witnesses, above all tribulations.

- **Insights:** each phenomenon kind (lightning, fire, heart demon, an element, an unfamiliar path) gives the tree knowledge. A new phenomenon gives most; repeats deepen it with diminishing returns. Insights are knowledge, not a currency to spend. Outsiders with unfamiliar paths are especially valuable.
- **Maturity:** overall growth, separate from specialised insights. Placeholder phases: Awakened Seedling → Spirit Root → Ancient Canopy → Heaven-Touched Tree → World Tree. The tree can thrive without rushing them.
- **Unlocks** (each must add play): spirit fruits and herbs (scarce, so they create sect politics and trade), denser qi and nurtured cultivation spots, root networks to distant spots, protective formations and sanctuary effects, dream guidance and blessings, and **Later** hidden realms rooted in the tree that people can explore, exploit, fight over and be lost in.
- **History embodied:** lightning-scarred bark, changed soil and plants, minerals, monuments and stories. The tree's look records its generations.

**Decision (slice):** one tribulation insight unlocks one concrete capability (a spirit fruit or a nurtured cultivation spot). Insight-to-unlock mapping: **Tuning**.

**Built (2026-10-11, user request):** the tree also learns from lessons: winters and droughts its people came through, the Way taught beneath it, deaths in its shade (each with diminishing returns). Unlocks ask for an insight and a growth phase: deep roots (Spirit Root: fields in its qi grow through a dry spell), a sheltering canopy (Ancient Canopy: within ten blocks the crown is a roof), awakening fruit (Ancient Canopy, after spirit fruit: a mortal given a fruit gains talent or drive, never a realm) and a root network (Heaven-Touched Tree: worn paths joined to the tree carry its qi and, at the tree, the god's reach). The god can ripen a fruit for Favour (Ripen Fruit, 30).

## 10. Faith, Favour, shrines and miracles

### 10.1 Two kinds of divinity

- **Renown** (global): how many people know the name. Unlocks miracle tiers.
- **Favour** (local, per shrine): the spendable pool from prayers at that shrine, used for miracles cast there.

**Decision (2026-10-10):** the brief's **Influence** is Favour. The name on screen stays Favour.

### 10.2 Shrines

| Property | Rule (values **Tuning**) |
| --- | --- |
| Support | Σ devotion of congregation members who prayed there in 3 days ÷ 100 |
| Active | Support ≥ 1.2 |
| Presence radius | 16 + 6 × √support, max 40 |
| Favour | Each prayer adds devotion ÷ 25; cap 100 |
| Condition | Decays untended; tending restores; a broken altar makes the shrine fall |

The **sacred tree** is always active: with no support its reach is 10 blocks, widening toward the full radius as support nears the threshold. It starts with 30 Favour. Other shrines go dormant without support.

### 10.3 The intervention scale

**Decision (brief):** the tree is powerful but not all-powerful. Blessings improve odds or avert a specific failure; they never replace mortal progress. Permanent damage to the tree is not the standard price of a miracle.

| Scale | Built miracles | Planned for cultivation |
| --- | --- | --- |
| Whisper / inspire (very low) | **Whisper** (2): a nudge to one believer's goal for a day, logged as "felt the god urge me to…" | An omen; urging someone to take up a blueprint |
| Bless (low) | **Bless Growth** (15), **Kindle** (5) | Bless a cultivator's training or a task |
| Nurture (moderate) | **Ripen Fruit** (30, once the tree bears fruit): a spirit fruit ripens now | Nurture a cultivation spot or spirit herb |
| Protect (high) | **Veil of Fog** (30), **Mend** (25) | Shield a tribulation: lower its risk, no guarantee |
| Defy Heaven (extreme) | — | Avert an otherwise fatal tribulation; the survivor's breakthrough is imperfect: a damaged foundation, reduced benefit and a harder next realm |

- Well-timed modest help may preserve a proper breakthrough; intervention does not always carry a penalty.
- Opportunity cost is the main price: a Defy Heaven should cost what ten blessings would. Costs, the cap and whether Favour regenerates during meditation: **Tuning**.
- Identity: the devotion-weighted aspects of believers. Matching miracles cost 25% less, contradicting ones 25% more and confuse believers.
- **Later:** large and exceptional miracles (divert water, raise land, guardians), destructive miracles (smite, blight). **Leaning:** destructive miracles wait; the sect itself can turn ruthless without the tree becoming malevolent.

### 10.4 Prayers as information

The god's knowledge is imperfect: everything in the current zone is visible and inspectable; prayers at active shrines list the speaker and intent; followers report what they believe; the chronicle shows distant events only once someone who could know has prayed or travelled to an active shrine.

### 10.5 Losing a shrine and dormancy

A shrine under the support threshold for 3 days goes dormant; a broken altar makes it fallen. If the avatar's shrine fails it is expelled to the strongest active shrine. If none is active the god is dormant: a faint wisp that can only whisper to the Devout, until survivors restore an altar. **Decision:** no game-over screen; if every believer is gone the god fades and an epilogue tells the story, with the option to keep watching.

## 11. Sacred sites, branches and the wider world

### 11.1 Expansion through people (built)

Discovery (Scout, quests) → recognition (stories) → belief → a shrine (restored or raised) → manifestation (the shrine becomes a transfer destination). Divine requests at a shrine: Carry my name, Bring resources, Raise a shrine, Restore a shrine, Found a settlement. Each believer decides whether to take one, weighing devotion, nature, needs, danger and the boon.

### 11.2 Branches

**Decision (brief):** travelling disciples spread the spirit's name and may found **branch shrines and sects**. Belief is local: a famous main sect gives no presence elsewhere without an anchor. The avatar can transfer between sufficiently established sites (cost and cooldown **Tuning**). Branches can interpret the teachings differently (a healing school, a sword school, a forbidden-path enclave) and can be attacked, abandoned or desecrated; access is lost with them while memories and architecture survive.

### 11.3 Other sects and outsiders

Other sects are not just enemies: guests seeking tribulation sanctuary, trading partners for herbs and manuals, rival claimants, allies, patrons, teachers, occasional attackers, and sources of unfamiliar insights. Admitting guests is the sect's decision (§8.4). **Later:** rival sects, outlaw and demonic cultivators, factions and trade (plan M22).

### 11.4 Transfer

From the shrine menu, the god transfers to another active shrine. The old place carries on without the god.

## 12. Threats and change

- **Wildlife (built):** wolves roam, frighten, sometimes injure; lantern light keeps them out.
- **Raiders (built):** a scripted band raids the wealthiest or least defended settlement from day 12, every 4 days, may break an altar. **Later:** replaced by outlaws and rival sects as BDI agents; tribulations draw attention.
- **Decay (built):** untended buildings lose blocks; abandoned places overgrow; buildings are re-judged when their contents change; felled trees lose their crowns; saplings grow back.
- **Generational change (planned):** masters die, doctrines drift, branches split, sites are lost and recovered. The world can change without the player, but always for a traceable cause.

## 13. Time, meditation and the chronicle

### 13.1 Scales of play

- **Days and weeks:** observe, meet novices, inspire projects, prepare a tribulation, respond to threats.
- **Years and decades:** training, breakthroughs, recruitment, politics, buildings, personal arcs.
- **Centuries:** succession, the rise and fall of elders, doctrine, legacies, branches, lost sites, a changed land.

### 13.2 Rest and meditation

**Built:** rest at a shrine for 1, 5 or 10 days or a season, with a "While you rested…" summary.

**Decision (brief):** **meditation** extends rest to years. The sect does not pause. Important events interrupt it: a followed person's breakthrough or danger of death, a shrine destroyed, war, an unfamiliar phenomenon, a favoured disciple's return. The player then reads a concise **chronicle** of who advanced, who died, what was built or lost, which techniques arose and why the politics changed. Favour regeneration and other limits on what meditation can skip: **Tuning**, set so that skipping a century is never free.

**Leaning:** spans beyond a season run the **abstract settlement model** (plan §3.1): population, food, buildings, faith, cultivation progress and events advance in hourly steps by the same rules as the detailed sim, so years pass in seconds; the region materialises in full on return.

### 13.3 The chronicle

Events stored with causes ("Day 14 · Ridge Hamlet · The ridge shrine fell — raiders broke the altar"). Kinds: arrivals, departures, births, deaths, bonds, buildings, designs, shrines, miracles, requests, raids, migrations, standing, harvests and frost; planned: breakthroughs, tribulations, insights, sect founding and succession, legacies. Filterable by place and person; feeds the meditation summary and the epilogue.

## 14. Core loops

1. **The tree attracts cultivators** with qi and the promise of protection.
2. **People form a sect** and recruit, build, train, gather, teach and explore by themselves.
3. **The spirit inspires** chosen efforts (designs, blueprints, whispers) and spends scarce Favour on blessings or miracles.
4. **Cultivators face tribulations**, preferably at the tree.
5. **The tree gains insights** and grows new capabilities.
6. **New capabilities create opportunities** (fruits, cultivation spots, sanctuary, branches) and conflict.
7. **The sect changes** over generations: new talent, visitors, reputation, doctrine.
8. **The cycle continues with consequences**, not toward a fixed victory.

The **immediate loop** stays tactile: walk the zone, read who needs what, shape the ground, fill a chest, capture and offer a design, whisper, bless, and watch people respond.

## 15. Interface

| Element | Contents |
| --- | --- |
| HUD | Time, speed, shrine name, Favour, renown, divine stock, crosshair with use prompt, hotbar, prayer feed |
| Blocks screen (I) | Placeable blocks, stock, hotbar slots |
| Chest panel | Contents beside the divine stock, give and take |
| Shrine menu | Shrines and transfer, designs, requests, miracles, rest and meditation |
| Design tool and library | Capture, function and bill, function reference, offer, blueprint, import/export |
| Inspector | Mind (decision log, beliefs vs reality), Needs, Bonds, Life, Faith; planned **Cultivation** tab (realm, foundation, techniques, teacher and students, tribulation history) and a **follow** pin |
| Settlement panel (K) | Residents, standing checklist, beds, food days, stock, sites, culture; planned sect view (master, elders, doctrine) |
| Chronicle (J) | Filterable history with causes |
| Planned | Tree screen (maturity, insights, unlocks, scars); world map with report ages |

Look and type follow `docs/design/art_direction.md` and `docs/design/font_direction.md`: a playable ink-and-pastel painting, woodblock serif headings on warm paper panels (see `docs/art/concept_1.png`). Presentation comes before tuning: the inspector must be usable before balance work.

## 16. Technical constraints (summary)

- Godot **4.2.2**, GDScript, **Forward+**; no plugins or GDExtensions without approval; built-ins first.
- All tuning and catalogs in `data/*.json`, validated at startup, failing fast.
- The simulation is pure `RefCounted` data, runs headless and is deterministic from one seeded RNG.
- Saves under `user://` with staged writes, backups and schema migrations.
- Windows only; Forward+ rules out a web export.

## 17. Scope

### 17.1 Built

The vertical slice (M0–M12) and Phase 2's first milestones: the voxel valley and hands-on building, templates and function recognition, BDI people with a social layer, faith, shrines, miracles and requests, wolves and raiders, rest, chronicle and saves (M0–M12); settlement standing, halls, gardens, lanterns and founding (M13); fields, kitchens, granaries and spoilage (M14); woods and saplings; the painterly look and woodblock type. Record: `PROGRESS.md`.

The slice's acceptance moment (the "first-playable moment" playtests measure, §14 in GDD v0.2) is built and checked: build a cottage, offer it, rest, and find more; carry the name to the ridge and transfer there; return after an absence to a change with a cause.

### 17.2 Next: the cultivation slice

**Decision (brief):** validate the unique loop before expanding into full xianxia world-building. The slice adds, to the existing valley: the tree's qi field; a few named cultivators with talent, realms, ageing and lifespans; a sect that forms by itself; Cultivate, Teach and Breakthrough; one risky tribulation kind (lightning); Favour blessings with Protect and Defy Heaven; one tree insight unlocking one capability; meditation over years with an understandable chronicle.

**The key test:** can the player grow attached to a disciple, influence their fate at a meaningful cost, meditate through years of autonomous change, and return to a visibly evolved sect whose growth also changed the tree?

Do not start with hundreds of techniques, a long realm ladder, many factions or a hidden-realm generator.

### 17.3 After the slice

Sect architecture and living designs, seasons and weather (storms feed tribulations), herbs and alchemy, branches and regions, other sects and outsiders, the tree's wider growth (root networks, formations, hidden realms), campaign shape and epilogue, finish and release. Sequenced in `IMPLEMENTATION_PLAN.md`.

**Later (after 1.0):** online template sharing, multiplayer, rival gods, other platforms.

## 18. Questions

### 18.1 Tuning (left to balance passes)

Settled by play and data, not by design: the qi curve; realm count, durations and lifespans; which breakthroughs provoke tribulations and their severity; insight values and the insight-to-unlock mapping; Favour sources, cap, regeneration and miracle costs (including the ten-blessings-to-one-rescue ratio); meditation spans, interrupts and what they cost; sect founding thresholds; shrine thresholds, avatar transfer cost and cooldown; population caps; migrant pull; raid pacing.

### 18.2 Open (design)

| Question | Leaning |
| --- | --- |
| Does a remote anchor need a root connection to the tree? | No; belief and a working altar are enough |
| Optional player-set rules for automatic emergency intervention during meditation? | Yes, as a per-person "protect if…" with a Favour limit; never a guarantee |
| How explicitly can the god pick an architect? | Through Whisper and blueprints only |
| How much do people invent designs at launch? | Vernacular homes and sect basics (plan M19) |
| How are special ingredients and hidden realms generated, discovered and managed? | Ingredients in the slice's follow-up; hidden realms Later |
| How does the sect choose guests? | Doctrine weights and the master's judgement, influenced by the tree |
| How do legacies and tree memories show without overwhelming the UI? | The chronicle, the tree screen and followed people only |
| What happens when the sect collapses or the last shrine is lost? | Dormancy and recovery through survivors (§10.5); the tree is never destroyed |
| How do good, ruthless, forbidden and mixed traditions emerge? | Doctrine drift from leaders' choices (§6.5); no morality paths |

*Status: v0.3. The vertical slice and village economy are built; the cultivation slice is next. Agreed direction from the brief is marked Decision; everything numeric is Tuning.*
