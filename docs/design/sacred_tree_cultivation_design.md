# Sacred Tree Cultivation Sect — Game Design Direction

**Status:** Adopted direction brief (2026-10-10). Its decisions are carried into `GAME_DESIGN.md` v0.3, which is authoritative; the open questions below are resolved there as Tuning or Leaning (see §14).  
**Genre:** Third-person, living-world voxel sandbox / autonomous cultivation-sect simulation  
**Influences:** Dragon Quest Builders (guided creation and functional construction), xianxia cultivation fiction, generational simulation  
**Purpose:** Consolidate the decisions and promising ideas developed when evolving the original bound-god village concept into a cultivation-sect game. This is a design direction, not an implementation contract.

## 1. Core Vision

The player is an ancient **tree spirit / local god**, manifested from the beginning as a physical avatar and bound to an extraordinary sacred tree. The tree produces an unusual spiritual environment, attracting mortal cultivators. Over years, decades, and centuries, these cultivators may found and evolve a sect around it.

The player **nurtures, inspires, advises, and occasionally performs costly miracles**, but does not directly manage every disciple or control the sect's leadership. NPCs pursue their own lives, cultivate, build, form relationships, travel, make decisions, and sometimes act against the guardian's wishes. They continue doing so while the player meditates or attends to another sacred location.

**Design promise:** *Nurture a sect, witness generations rise and fall, and become a more powerful sacred tree through the trials of the people who live beneath it.*

### Core pillars

1. **A world that continues without you.** Ten or a hundred years may pass; the sect can prosper, fracture, decline, relocate, or change beliefs.
2. **Influence instead of orders.** The player proposes plans and inspires mortals to carry them out; acceptance and success depend on NPC priorities and resources.
3. **Individuals matter across generations.** A few disciples may become special to the player, but anyone can become powerful or important independently.
4. **Mutual growth.** The tree aids cultivators, while their breakthroughs and tribulations teach the tree new spiritual principles.
5. **A tangible, editable world.** The voxel environment, NPC-built architecture, sites of breakthroughs, and scars of history make change physically visible.
6. **Divinity has an opportunity cost.** Great miracles can save lives but consume influence that could have aided many others.

## 2. Player Identity and Presence

### Agreed direction

- The player **is the guardian spirit of the sacred tree**, not the mortal sect master or ruler.
- A **physical tree-spirit avatar exists from the very start**. This retains third-person movement and close contact with the environment and disciples.
- The spirit is **bound to sacred land**. It cannot explore the unrestricted world as a conventional adventurer.
- The tree itself **grows and acquires capabilities**, but not by following the exact cultivation realms of mortals.
- NPCs are independent; even the sect master can disagree with the tree's guidance.

### Sacred-site network retained from the god-game concept

- Disciples, pilgrims, and other believers can travel beyond the initial territory and **spread the spirit's name**.
- Recognition alone is insufficient. Local belief and an **established functioning shrine/anchor** are needed for a meaningful foothold.
- The player may eventually **transfer their manifested avatar between sufficiently established sacred sites**, rather than freely roaming beyond sacred territory.
- Shrines and branch sites are vulnerable to neglect, loss of worship, attack, and destruction. Losing them can mean losing access until followers restore belief and an anchor.
- A prosperous branch can be autonomous; expanding the network does not grant perfect information or direct command over its inhabitants.

**Open:** Precise faith thresholds, avatar transfer cost/cooldown, whether remote anchors require tree-root connection, and what happens if every site is lost.

## 3. How a Sect Forms

The tree's unusual spiritual energy makes the location attractive. Wanderers may meditate in its shade, discover faster cultivation, tell others, and settle nearby. Teachers and disciples emerge, then halls and a formal institution. **The player does not have to press “Found Sect.”** Different groups may compete for access to the tree before a stable sect forms.

The sect may become benevolent, isolationist, mercantile, militant, secretive, or dangerous. It should not be locked into a preset morality. The spirit can encourage a philosophy, but successive leaders interpret the sect's traditions differently.

### Autonomous sect life

- NPCs determine training, recruitment, leadership, expeditions, supply needs, building priorities, and defensive policy according to their abilities, motives, and circumstances.
- The sect can form branches, ally with rivals, trade, fight, take refugees, and invite guests.
- Cultivators can leave, return, teach, found competing institutions, fail breakthroughs, die, or outlive many generations.
- The world must be able to make both desirable and undesirable changes without player input, with **traceable causes rather than arbitrary destruction**.

## 4. NPC Cultivators: The Heart of the Simulation

**Chosen direction: living simulation.** All disciples progress independently, but the player can pay close attention to a small number of promising recruits, favourite disciples, sect pillars, or rivals.

### Suggested individual simulation

- Identity, age, lifespan, relationships, commitments, history, and ambitions.
- Talent/spiritual roots or affinity, cultivation stage, technique knowledge, resources, preparation, and risks.
- Duties such as farming, construction, teaching, crafting, guarding, exploring, or administering sect affairs.
- Training under masters, passing techniques to students, rivalries, breakthroughs, injuries, and legacies.

**Simulation scaling:** Ordinary disciples can be simulated economically, notable people in greater depth, and personally followed disciples in the greatest detail. **Being followed does not grant exclusive advancement.** An overlooked recruit can become a legendary elder.

### Generational attachment

A disciple met as a novice might return after ten years as an instructor, after a century as an elder, and eventually leave students, a school of techniques, a relic, or a story remembered by the tree. The player should sometimes face the decision to support the next generation instead of endlessly preserving the old.

### Familiar xianxia structure, flexible outcomes

Use recognizable realms as a scaffold, for example:

1. Mortal
2. Qi Refining
3. Foundation Establishment
4. Golden Core
5. Nascent Soul
6. Further realms to define later

This list is **illustrative**, not a finalized number of stages, duration, power curve, or tribulation schedule. Techniques, affinities, sect identities, and paths should emerge through the simulation and tree guidance rather than being entirely fixed at character creation.

## 5. The Sacred Tree's Distinct Growth

### Confirmed design intent

The sacred tree **does not level like a human cultivator**. It grows as cultivators confront major breakthroughs, particularly **heavenly tribulations**. More powerful and unfamiliar tribulations can deepen the tree's knowledge, unlocking abilities and new opportunities for the sect.

The tree should care about **different experiences**, not just the number of tribulations. Outsiders with unfamiliar cultivation paths may be especially valuable.

### Proposed system: Tribulation Echoes / Insights

Treat spiritual insights as **knowledge or affinities**, not necessarily a second spendable currency. Encountering a new phenomenon provides initial understanding; repeated encounters deepen or refine it, with diminishing value for identical circumstances.

| Phenomenon encountered | Possible tree knowledge and capabilities |
|---|---|
| Lightning tribulation | Resistance, thunder-aligned herbs/materials, protective storm techniques |
| Fire or alchemical tribulation | Spirit flames, rare ingredients, heat-adapted cultivation spaces |
| Heart-demon trial | Dream guidance, emotional insight, spiritual stabilization |
| Elemental breakthroughs | Specialized cultivation environments and affinity-sensitive resources |
| Extraordinary heavenly trial | Expanded sanctuary, new spiritual spaces, rare profound abilities |

These are **illustrative paths**, not required collectible categories. Players need not complete a fixed checklist of elements.

### Abilities should add gameplay

Potential tree growth unlocks:

- **Special spiritual ingredients**, fruits, herbs, and other cultivation materials; their scarcity creates sect politics and trade.
- **Hidden realms / pocket spaces** rooted in the tree, offering training environments, resources, exploration, danger, or rare encounters.
- **Spiritual root networks** and intensified qi areas, including distant or subterranean locations.
- **Protective formations and sanctuary effects** that attract stronger cultivators and outsiders.
- **Dream communication, blessings, and limited environmental miracles** that deepen indirect guidance.

A hidden realm should not be mere player-owned storage: NPCs must be able to explore, exploit, protect, compete for, or become lost in it.

### Possible tree maturity phases (not approved progression)

Awakened Seedling → Spirit Root → Ancient Canopy → Heaven-Touched Tree → World Tree. These are thematic placeholders. Separate **overall maturity** from **specializations learned through tribulations**. The tree can thrive without rushing to maximum maturity.

### World history embodied

Tribulations should leave lasting physical and social traces: lightning-scarred bark, transformed soil, altered vegetation, unusual minerals, shrines, monuments, manuals, and stories. The tree's appearance and abilities become a record of generations.

## 6. Tribulations and the Sanctuary

### Agreed rules

1. **Cultivators may attempt tribulations anywhere.** There is no outright ban on breakthroughs outside the tree's territory.
2. **Both the tree and cultivators prefer a tribulation at the tree** when practical: the tree offers protection; cultivators improve their chances; the tree learns from the event.
3. **Visiting cultivators from other sects may be welcomed.** They receive added protection, while the tree encounters unfamiliar paths and gains new insights.
4. **The tree cannot guarantee success.** Preparation, individual foundations, technique, environmental conditions, and the severity of heavenly trials still matter.
5. **Tribulations carry environmental and political risks.** They can harm buildings, attract hostile attention, change the land, and divide sect leadership over whom to admit.

### A sanctuary that grows with the sect

Initially, breakthroughs occur in a clearing under the branches. Later the sect may independently propose or construct a **tribulation ground** with a platform, protective formations, recovery rooms, observation sites, and safety distances from housing. Architecture and formations have practical requirements; visual grandeur alone does not make protection effective.

Possible visitor arrangements include free access, ally access, offerings or exchanges, or controversial admissions of forbidden cultivators. These should arise from sect needs and leadership decisions, with the spirit influencing rather than merely toggling policies.

### Example scenario

A visiting sword cultivator asks to face a tribulation under the tree. The player wants the unfamiliar sword insight; the sect master fears a rival's spies and the possibility of lightning striking nearby workshops. The tree can express approval and spend influence, but the sect's actual preparation, acceptance, and aftermath remain part of its autonomous simulation.

## 7. Miracles, Influence, and Consequences

### Agreed direction

- Miracles exist and **cost a renewable but limited divine Influence pool**.
- The largest cost is often **opportunity cost**: saving one treasured elder may consume enough influence to nurture ten other disciples.
- The tree should be **powerful but not all-powerful**. Its blessings can improve odds or avert specific failures, not replace mortal progression.
- A rescue from an otherwise fatal tribulation may leave an elder with **imperfect advancement, a damaged or unstable foundation, reduced benefits, and a harder path to the next realm**.
- Do not require permanent tree damage as the standard miracle price.

### Suggested intervention scale

| Miracle | Broad use | Cost expectation |
|---|---|---|
| Whisper / inspire | Suggest a plan, encourage a person, provide an omen | Very low |
| Bless | Modest help with training or a task | Low |
| Nurture | Develop a cultivation area or special resource | Moderate |
| Protect | Improve survival odds at a dangerous moment | High |
| Defy Heaven | Save someone from otherwise fatal tribulation | Extreme |

No numerical costs are final. The earlier illustrative example contrasted **ten small blessings against one large rescue**; use that relationship as a balancing question, not a hard-coded conversion rate.

### Tribulation intervention outcomes

- **No intervention:** Natural odds and consequences play out.
- **Limited protection:** Reduce risk but do not guarantee survival.
- **Major intervention:** Avert imminent death at extreme influence cost; survival can carry a compromised breakthrough and greater future difficulty.
- **Well-prepared assistance:** Timely modest help may preserve a proper breakthrough; intervention should not always inflict a penalty.

Influence regeneration should not encourage mindless century-long skipping. Meditation may replenish the pool, but unattended years allow independent sect events, losses, opportunities, and changes in leadership.

**Open:** Influence sources, capacity, regeneration scaling, whether belief affects generation or primarily local reach, and whether emergency intervention can trigger automatically under optional player-defined rules.

## 8. Building, Blueprints, and NPC Construction

### Revised player-building role

Earlier exploration considered hands-on block placement. The cultivation pivot favours **planning and inspiration**: the player may lay out a structure or place a blueprint, then **inspire a disciple, elder, or the sect to undertake construction**. Mortals gather materials, craft components, and construct the building. The spirit need not personally place each block.

This is a meaningful shift toward indirect god gameplay while retaining a fully editable **voxel** world and **third-person avatar**.

### Shared architectural templates retained

- Players can design, save, import, export, and share building templates.
- Templates are architectural knowledge, not instantaneous buildings.
- NPCs may choose a known template when they need housing, workshops, training halls, shrines, defences, or tribulation facilities.
- Construction requires suitable ground, labour, local resources, crafting knowledge, and enough priority for the NPC decision system.
- NPCs can adapt materials, orientation, foundations, decoration, weathering, repair, and reuse while preserving recognizable designs.
- Cultures and branches can inherit preferred designs. Structures can outlast the original sect or faith.

### Shared build pipeline

1. A need, proposal, or spiritual inspiration arises.
2. NPCs evaluate a structure's utility and priority.
3. A template and site are selected.
4. Materials are sourced and reserved; necessary components are crafted.
5. Workers visibly build nearby or simulate construction in the background.
6. The finished building becomes functional and can later be used, maintained, modified, damaged, or abandoned.

**Open:** Whether direct block placement remains as a limited spirit power, how explicitly the player can target an architect, and how much NPC design invention is supported at launch.

## 9. Broader World, Faith, and Branches

Cultivation progression does not remove the original sacred-site concept. Travelling disciples can spread the tree spirit's name, establish branch shrines or sects, and create distant places where the avatar may eventually manifest. **Belief is local**, so a famous main sect doesn't automatically confer physical presence everywhere.

Different branches can develop competing interpretations of the tree's teachings. A healing school, sword school, alchemical branch, or forbidden-path enclave can all trace their origins to the same guardian yet disagree with one another.

Other sects are not merely enemies. They can be:

- Guests seeking tribulation protection
- Trading partners for spirit herbs and manuals
- Rival claimants to rare resources
- Allies, patrons, teachers, or occasional attackers
- Sources of unfamiliar insights for the tree

A branch shrine can be attacked, abandoned, desecrated, or lose followers. The avatar's physical access can disappear even while memories or architectural traditions survive there.

## 10. Time, Meditation, and Generational Play

The player experiences ordinary moments through the avatar, but their lifespan makes **decades and centuries** meaningful gameplay units.

- **Days/weeks:** Observe cultivation, meet novices, inspire projects, prepare facilities, respond to threats.
- **Years/decades:** Watch training and breakthroughs, recruitment, political shifts, structures, and disciples' personal arcs.
- **Centuries:** Witness succession, the rise and fall of elders, doctrinal changes, legacies, new branches, destroyed sites, and environmental transformation.

### Proposed meditation system

The spirit can enter meditation and accelerate time. The sect does not pause. Important events may interrupt meditation: potentially fatal breakthroughs, shrine destruction, warfare, discovery of an unusual spiritual phenomenon, or the return of a personally favoured disciple.

The player should be able to review a concise **chronicle** of what happened: who advanced, who died, which buildings appeared or fell, which techniques were created, and why the political environment changed.

Player attention is limited: one manifested avatar at one sacred site at a time, with imperfect knowledge of distant events.

## 11. Progression Loop

1. **The tree attracts cultivators** with spiritual energy and the prospect of protection.
2. **NPCs form a sect** and independently recruit, build, train, gather, teach, and explore.
3. **The spirit inspires selected efforts** and spends scarce influence on blessings or miracles.
4. **Cultivators face tribulations**, preferably near the tree, though elsewhere remains possible.
5. **The tree gains insights** from the varied spiritual phenomena and develops new capabilities.
6. **New tree abilities create opportunities:** ingredients, cultivation grounds, hidden realms, branch connections, and prestigious sanctuary services.
7. **The sect attracts new talent, visitors, and conflict**, changing its culture and reputation over generations.
8. **The cycle continues with consequences**, not a fixed victory path.

### What makes this different from Minecraft or a conventional sect manager

- It uses a world the player can reshape but **does not wait for the player to reshape it**.
- Building templates enable **NPC-driven physical construction** rather than just instant blueprint placement.
- Cultivators are not interchangeable resource generators; their experiences **shape the deity's evolution**.
- Tribulations are not only character level checks; they are social, environmental, and spiritual events.
- The player exists **inside the world as an avatar**, but their greatest agency is indirect.
- Long periods of inactivity produce histories, reversals, and new possibilities rather than a frozen base.

## 12. Example Emergent History (Illustrative)

- **Year 1:** A handful of travellers discover cultivation is easier under the ancient tree. The spirit offers subtle guidance.
- **Year 10:** Their students found a sect and build simple dwellings and a practice ground using shared templates.
- **Year 27:** A senior disciple survives a dangerous tribulation within the tree's sanctuary. The tree gains an unfamiliar lightning insight.
- **Year 45:** The tree begins producing a rare ingredient. Alchemists arrive, and a specialised hall is established.
- **Year 76:** A visiting sword cultivator is admitted despite objections from some elders. Their tribulation reveals a new spiritual principle.
- **Year 110:** An elder the player has followed since childhood faces death in a breakthrough. The tree spends influence that could have helped many novices, saving the elder but leaving their foundation unstable.
- **Year 170:** A branch sect forms around a distant shrine. The spirit may manifest there when belief and an active anchor permit.
- **Year 260:** A political dispute isolates one branch and its shrine is destroyed. Its surviving disciples carry architectural designs and fragmentary teachings into exile.
- **Year 400:** The original sect's customs are almost unrecognisable. The sacred tree's scars, fruits, hidden spaces, and remembered cultivators tell the history of how it arrived here.

These are examples of possible simulation outcomes, not scripted milestones or guaranteed pacing.

## 13. Prototype Recommendation

Validate the unique loop before expanding into full xianxia world-building.

### Minimal vertical slice

- One sacred tree and player-controlled third-person spirit avatar with bounded territory.
- One small autonomous group that can emerge into a sect.
- A few named disciples with talents, goals, cultivation stages, and aging.
- A handful of functional building templates; the player inspires construction, NPCs gather and build.
- A simplified cultivation progression with at least one risky breakthrough/tribulation.
- A limited Influence pool with ordinary blessings and a high-cost emergency rescue.
- Tree insight gained from a tribulation, unlocking **one concrete new capability** such as a rare ingredient or cultivation area.
- Time acceleration plus an understandable event chronicle.

### The key test

**Can the player grow attached to a disciple, influence their fate at meaningful cost, meditate through years of autonomous change, and return to a visibly evolved sect whose growth also changed the tree?**

Do not begin with hundreds of techniques, a giant realm ladder, dozens of factions, or a complex hidden-realm generator. Those systems become worthwhile once the core emotional and simulation loop works.

## 14. Decisions and Open Questions

### Decisions from discussion

- Guardian tree spirit (**sect guardian**, not sect founder/leader).
- Physical avatar exists immediately.
- Disciples are autonomous, with close attention possible for a small subset.
- Familiar xianxia progression with emerging, varied paths.
- Sect forms because the tree's spiritual environment is valuable.
- Construction is mainly planned/inspired by the player and executed by NPCs.
- Voxel world and shareable architectural templates remain important.
- Time can advance across decades/centuries while NPC history continues.
- Tree grows through cultivators' major tribulation experiences, not ordinary mortal cultivation.
- Tree can unlock hidden realms and special cultivation ingredients.
- Cultivators prefer tribulations at the tree for its protection, but may do them anywhere.
- Outsiders from other sects may be welcomed for unfamiliar tribulation insights.
- Miracles spend scarce Influence; major rescue is expensive relative to helping many cultivators.
- An elder saved from a fatal tribulation may suffer weaker or unstable advancement and a harder next realm.
- Faith-spreading shrines enable remote manifestation and can be destroyed.

### Still to design / tune

Resolved 2026-10-10: almost all of these are **future balance**, left to tuning passes (GDD §18.1). Where a design answer was needed, the GDD records a leaning.

| # | Question | Where it stands |
|---|---|---|
| 1 | Pace of ordinary time; how much meditation can skip | Tuning. 40-day year kept; meditation to decades runs an abstract model (GDD §13.2) |
| 2 | Which breakthroughs provoke tribulations; their risks | Tuning. The slice uses one lightning tribulation (plan M16) |
| 3 | Insights into maturity and unlocks | Tuning. Slice: lightning insight unlocks spirit fruit (plan M17) |
| 4 | Generating and managing ingredients and hidden realms | Ingredients after the slice; hidden realms Later |
| 5 | Influence sources and limits during meditation | Influence is Favour; regeneration and caps are Tuning |
| 6 | Accepting guests | Leaning: sect doctrine and the master's judgement |
| 7 | Control over recruits, instruction, construction | Whisper, blueprints, offered designs only (GDD §3.3, §5.4) |
| 8 | Template classification and construction | Function from components, as built; sect functions follow (GDD §5.3) |
| 9 | Cost and range of manifestation between sites | Tuning |
| 10 | Presenting histories without overwhelming the UI | Leaning: chronicle, tree screen, followed people |
| 11 | Sect collapse or last shrine lost | Dormancy and recovery through survivors (GDD §10.5) |
| 12 | Good, ruthless, forbidden and mixed traditions | Leaning: doctrine drift, no morality paths (GDD §6.5) |

Also settled: direct block placement remains as the spirit's power inside the presence zone, while the sect's buildings are raised by its people (GDD §5.1).

---

**North star:** *A god rooted in a tree can guide a cultivation sect but never wholly command it. Centuries of mortal struggle transform both the people and their sacred guardian.*
