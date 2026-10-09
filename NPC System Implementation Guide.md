# NPC System Implementation Guide

Oct 9, 2026 · @Kalaith

## Overview

Final Landing's survivors are BDI agents (Belief, Desire, Intention) built with the Prometheus methodology: nobody is commanded, each NPC reasons from its own partial view of the world. The player shapes the world (buildings, priorities, policies) and the NPCs decide for themselves. This guide describes the system as implemented in `src/agents/` and `src/sim/` (about 4,500 lines of Rust), detailed enough to rebuild it in another macroquad game.

The seven properties the design delivers, and the mechanism behind each:

| Property | What the player sees | Mechanism |
| --- | --- | --- |
| Situated | NPCs only react to what they can see | Perception within a sight radius writes `Beliefs`; plans read beliefs, never the true world |
| Autonomous | NPCs pick their own jobs and leisure | Goal generation scores \~25 goal kinds from needs, personality, skills, priorities, ambition |
| Reactive | A creature appears and people flee or fight | Percept interrupts force immediate re-deliberation |
| Proactive | People finish what they start | Commitment: the current intention gets a bonus; a rival must beat it by a margin |
| Flexible | Hungry NPCs take a meal, or raw food, or forage | Each goal has several plans in a plan library, ranked by preference |
| Robust | "The berries were gone, so she went to the stockpile" | A failed step corrects beliefs, the plan is excluded, the next plan is tried; exhausted goals back off or become help requests |
| Social | Warnings, gossip, help, courtship | Typed messages delivered to inboxes, handled before deliberation |

The result is legible emergent behaviour: every change of course is written to a 12-entry decision log, and the inspector shows goal, reason, plan steps and beliefs side by side with reality. That legibility ("why is this survivor doing that?") is the part most worth reproducing.

## Architecture

The system splits into a pure agent model (`agents/`, no world mutation) and a simulation driver (`sim/`) that owns all side effects. Agents read the world through immutable views and write to it only through an `Effects` buffer that is applied once per tick, so every agent in a tick sees the same world and iteration order cannot bias outcomes.

| Module | Lines | Owns |
| --- | --- | --- |
| `agents.rs` | 200 | `Agent` struct, `LifeState`, `Activity`, helpers (`back_off`, `has_trait`) |
| `agents/personality.rs` | 128 | `Personality` (summed trait modifiers), `Skills` (levels, xp, passions) |
| `agents/body.rs` | \~180 | `Needs` (0–100), `Health`, `Mind` (stacking, decaying thoughts) |
| `agents/beliefs.rs` | 183 | `Beliefs`: remembered nodes, threats, relations, stock, failed targets |
| `agents/goals.rs` | 219 | `Goal` enum, `GoalKey`, `WorkType`, `HelpNeed`, `BreakKind` |
| `agents/deliberation.rs` | 568 | `AgentSnapshot`, `View`, candidate goal generation and utility scoring |
| `agents/plans.rs` | \~200 | `Step`, `Plan`, `PlanOption`, `FailReason`, `StepOutcome` |
| `agents/plan_library*.rs` | 227 + 349 + 302 | `plans_for(goal)`: several ranked plans per goal |
| `agents/intention.rs` | \~100 | `Intention` (goal + plan + tried list), `DecisionLog` |
| `agents/messages.rs` | \~60 | `Message`, `MessageKind` (the social protocol) |
| `agents/generation.rs` | 221 | Seeded creation of adults and children |
| `sim/perception.rs` | \~170 | Sight radius, belief updates, threat alarms, warnings |
| `sim/inbox.rs` | \~210 | Receiving side of each message protocol |
| `sim/cognition.rs` | \~190 | Deliberation timing, commitment, plan choice, give-up |
| `sim/execute*.rs` | 201 + 528 + 355 + social | Step execution, failure learning, achievement |
| `sim/body.rs` | \~190 | Need decay, warmth, health, mood |
| `sim/social.rs` | 373 | Applies `Effects`: conversations, gifts, treatments, attacks |
| `ui/inspector_agent.rs` | 532 | The "why" inspector: goal, reason, plan, log, beliefs vs reality |

### Per-tick order

`Sim::step` advances the calendar, runs daily/hourly hooks, refreshes the colony job board every 10 ticks, moves creatures, then calls `update_agents`:

1. Snapshot every agent into `Vec<AgentSnapshot>` (what others can see: tile, mood, activity, goal, partner).
2. For each present agent, build a `Ctx` (mutable world and colony, the snapshots, calendar, RNG, shared `Effects`).
3. `body::update` — decay needs, update warmth and health, tick thoughts, recompute mood every 10 ticks.
4. `perception::perceive` — every `perception_interval` ticks (staggered by id); returns `true` on a new threat.
5. `inbox::process` — handle messages; returns `true` on an urgent warning.
6. `cognition::think` — deliberate if due or interrupted, then ensure a plan exists.
7. `execute::run_step` — run one tick of the current step; handle done or failed.
8. `movement::advance` — follow the path with a fractional move budget.
9. After the loop: `social::apply_effects` (deliver messages to inboxes, resolve conversations, gifts, treatments, attacks), then `lifecycle::resolve_deaths`.

Messages pushed in tick N land in inboxes at the end of tick N and are read in tick N+1. Deliberation is staggered by `agent.id % 3` and perception by `(tick + id) % interval`, which spreads CPU cost and avoids lockstep behaviour.

## Data model

Every NPC is one serializable `Agent` struct; all tuning lives in JSON loaded once through `macroquad_toolkit::include_json!` into a `OnceLock<GameData>` and validated at startup. Derive `Clone, Debug, Serialize, Deserialize` on everything so saves are a plain serde round-trip.

### The Agent struct (grouped)

| Group | Fields | Notes |
| --- | --- | --- |
| Identity | `id: u32`, `given_name`, `family_name`, `age_years`, `is_child`, `portrait: u8`, `hue: f32`, `backstory {origin, former_role, memory}`, `parents` | Generated from name lists |
| Character | `traits: Vec<String>`, `personality: Personality`, `skills: Skills`, `ambition: AmbitionState {id, progress, fulfilled}` | Personality is derived from traits, never edited directly |
| Body | `needs: Needs`, `health: Health`, `mind: Mind`, `mood: f32` | Mood 0–100, recomputed every 10 ticks |
| BDI core | `beliefs: Beliefs`, `intention: Option<Intention>`, `decisions: DecisionLog`, `inbox: Vec<Message>`, `backoff: Vec<(GoalKey, u64)>`, `next_deliberation: u64` | The reasoning state |
| World state | `tile`, `position: Point`, `path: VecDeque<Tile>`, `move_budget`, `inside: Option<StructureId>`, `carrying: Option<(Resource, f32)>`, `activity: Activity`, `home`, `life: LifeState` | `Activity` is the visible verb used by rendering |
| Social | `partner`, `help_task: Option<(AgentId, HelpNeed)>`, `volunteered` |  |
| Mood crises | `mental_break: Option<(BreakKind, u64)>`, `low_mood_ticks` |  |
| Record | `joined_day`, `stats: AgentStats` | Counters for plans recovered, help given, etc. |

`LifeState` = `Present | Away { expedition } | Dead { day, cause } | Departed { day }`. Only `Present` agents run the cycle.

### Body types

- **Needs**: `[f32; 6]` indexed by `Need` (Food, Rest, Warmth, Social, Recreation, Safety), clamped 0–100, default 80. `lowest()` and `mood_pressure()` = Σ `min(value − 60, 5) × need_weight / 6 × 2`.
- **Health**: `hp` 0–100, `ill`, `treated`, `injuries`. `needs_care()` when ill or `hp < care_threshold` (70). `capacity()` = `0.4 + 0.6 × hp/100`, ×0.7 when ill; multiplies work utility and speed.
- **Mind**: a list of `Thought {id, mood, remaining_ticks, about}`. `add(id)` looks up a `ThoughtDef`, respects `max_stack` (refreshes the oldest instead of stacking), and lasts `days × ticks_per_day`. `total()` sums mood effects.

### Personality and skills

`Personality::from_traits` starts from zero (decay and speed multipliers at 1.0) and adds each trait's modifiers: `sociability, bravery, kindness, diligence, curiosity, romance, temper, optimism, leadership` (f32), `night_owl` (bool), plus per-need `need_decay` and per-skill `skill_speed` offsets. Need decay is floored at 0.2.

`Skills` holds `levels: [u8; 8]` (cap 20), `xp: [f32; 8]`, `passions: Vec<Skill>`. Work speed = `(0.6 + level × skill_speed_per_level) × personality.skill_speed[skill]`. XP needed per level = `xp_per_level × (1 + level × 0.15)`; passions multiply XP gain.

### Beliefs

| Field | Type | Updated by | Forgotten |
| --- | --- | --- | --- |
| `nodes` | `BTreeMap<NodeId, NodeBelief {kind, tile, amount, seen_tick}>` | Perception, `InformNode` messages | After `belief_forget_days` (20), or when seen to be gone |
| `threats` | `Vec<ThreatBelief {creature, tile, dangerous, seen_tick}>` | Perception, `Warn` messages | After 1/12 day, or when the creature is seen gone |
| `relations` | `BTreeMap<AgentId, Relation {opinion, familiarity, romance, last_chat_tick}>` | Conversations, proximity, shared work, gossip | Opinion decays daily |
| `stock` | `ResourceBag` | Daily broadcast, standing at a store, failed `TakeStock` | Never; overwritten |
| `failed` | `Vec<(FailedTarget, u64)>` | Step failure | After 1 day |
| `nearby` | `Vec<(AgentId, Tile)>` | Each perception pass | Cleared each pass |

`Relation::bond()` maps opinion to `Enemy (≤ −55) / Rival (≤ −25) / CloseFriend (≥ 60) / Friend (≥ 30) / Acquaintance (familiarity ≥ 10) / Stranger`. Use `BTreeMap` and `Vec` rather than `HashMap` so iteration order, and therefore the simulation, is deterministic.

### Goals, plans, intentions, messages

- **Goal** (25 variants, `Copy`): survival `Eat, Sleep, WarmUp, Flee, SeekCare`; leisure `Relax, Idle`; work `Build(id), Repair(id), Haul, Farm(id), Gather(NodeKind), Cook, Craft(id), Research, Treat(agent), Defend(creature), Scout`; social `Chat, Comfort, Court, Reconcile (agent)`; `Help {requester, need}`, `Volunteer`, `Break(BreakKind)`.
- **GoalKey** `{kind: u8, target: u32}`: a hashable identity used for backoff, the "others pursuing" count and commitment comparisons.
- **Step** (\~30 primitives): `GoTo(Target)`, `TakeStock`, `TakeMeal`, `Deposit`, `Deliver`, `Construct`, `Repair`, `Harvest`, `Forage`, `PickUp`, `Eat(FoodSource)`, `Sleep(Option<id>)`, `Warm{ticks}`, `Relax`, `Tend`, `Cook`, `Craft`, `Research`, `StudyRelic`, `Treat`, `Recover`, `Talk{with, topic}`, `Send{to, kind}`, `WaitForHelp{ticks}`, `Give`, `Attack`, `Hide`, `Scout(tile)`, `JoinExpedition`, `Break`, `Wait`. `Target` = `Tile | Structure | Node | Agent`.
- **Plan** `{id: String, steps, cursor, step_ticks}`; **PlanOption** `{id: &'static str, steps, preference}`.
- **FailReason**: `NoPath, TargetGone, StockEmpty, Depleted, Occupied, Refused, TimedOut, Interrupted, TooDangerous`.
- **Intention** `{goal, plan: Option<Plan>, tried: Vec<String>, utility, started_tick}`.
- **DecisionLog**: a `VecDeque<Decision {tick, kind}>` capped at 12, newest first. Kinds: `Adopted{goal, utility, reason}`, `ChosePlan`, `PlanFailed{plan, reason}`, `GaveUp`, `Achieved`, `Interrupted{by}`, `Message{text}`.
- **Message** `{from, to, kind, tick}` with `MessageKind`: `InformNode`, `Warn`, `RequestHelp{need, place}`, `AcceptHelp`, `DeclineHelp`, `Delivered`, `Gossip{about, opinion}`, `Propose`, `AcceptProposal`, `RejectProposal`.

### JSON data files

`people.json` holds 22 traits, 7 ambitions and name lists. A trait states only what it changes:

```json
{"id": "loner", "name": "Loner", "description": "Needs quiet; crowds wear them down.",
 "modifiers": {"sociability": -0.5, "need_decay": {"social": -0.5}},
 "excludes": ["social"], "clashes_with": ["social"], "bonds_with": []}
```

The shipped trait set: social, loner, brave, cautious, kind, abrasive, optimist, pessimist, diligent, lazy, curious, romantic, stubborn, gourmand, green\_thumb, tinkerer, spiritual, leader, hot\_headed, night\_owl, homesick, resilient. Ambitions: `master_skill` (target 14), `raise_family` (1), `befriend_colony` (5), `map_the_wilds` (3), `decode_spire` (4), `build_home` (0.8), `lead_council` (40). Names: `given`, `family`, `origins`, `former_roles [{name, skill}]`, `memories`.

`society.json` holds 39 thoughts, e.g. `{"id": "good_chat", "text": "Had a good conversation", "mood": 3, "days": 1.0, "max_stack": 1}`. Range: `partner_died` −30 for 20 days to `ambition_fulfilled` +20 for 30 days.

`balance.json` sections the NPC system reads (shipped values):

```json
"time":   {"ticks_per_day": 720, "dawn_hour": 6, "dusk_hour": 20, "work_start_hour": 7, "work_end_hour": 18, "sleep_hour": 22},
"needs":  {"decay_per_day": {"food": 95, "rest": 80, "warmth": 0, "social": 40, "recreation": 30, "safety": 0},
           "comfortable_temperature": 14, "cold_loss_per_degree": 5, "shelter_warmth_gain_per_day": 70,
           "heat_warmth_gain_per_day": 160, "meal_restore": 55, "raw_food_restore": 38, "forage_restore": 30,
           "bed_rest_per_day": 220, "ground_rest_per_day": 140, "recreation_gain_per_day": 180,
           "safety_recovery_per_day": 60, "safety_loss_on_threat": 35, "urgent_threshold": 25},
"agents": {"tiles_per_tick": 1.0, "sight_radius": 9, "night_sight_factor": 0.6, "storm_sight_factor": 0.5,
           "perception_interval": 3, "deliberation_interval": 10, "commitment_bonus": 0.25,
           "max_plan_attempts": 4, "goal_backoff_ticks": 120, "carry_capacity": 12,
           "belief_forget_days": 20, "help_wait_ticks": 90, "child_growth_days": 120, "adult_age_years": 18},
"social": {"chat_ticks": 12, "chat_social_gain": 26, "chat_opinion_range": [-6, 8], "familiarity_per_chat": 4,
           "proximity_familiarity_per_day": 2, "shared_work_opinion_per_day": 2.5, "friend_threshold": 30,
           "close_friend_threshold": 60, "rival_threshold": -25, "enemy_threshold": -55,
           "romance_gain_per_flirt": 9, "partner_romance_threshold": 60, "gossip_weight": 0.2,
           "trait_clash_penalty": 7, "trait_bond_bonus": 6, "child_chance_per_day": 0.025, "opinion_decay_per_day": 0.4},
"mood":   {"baseline": 50, "need_weight": 0.3, "break_threshold": 22, "extreme_threshold": 10,
           "break_chance_per_day": 0.6, "break_ticks": 90, "departure_threshold": 12, "departure_days": 6, "expectation_per_act": 4},
"health": {"regen_per_day": 4, "care_regen_per_day": 20, "illness_damage_per_day": 6,
           "illness_recovery_chance_per_day": 0.12, "treated_recovery_bonus": 0.3,
           "starvation_damage_per_day": 14, "hypothermia_damage_per_day": 12, "care_threshold": 70, "old_age_years": 88}
```

Rates are authored per day and converted with `Calendar::per_tick(x) = x / ticks_per_day`, so changing tick rate does not retune the game.

### Validation (`data/validation.rs`)

The project owns semantic validation; failure panics at startup because embedded data is a build defect. Checks that matter for NPCs: unique trait, ambition and thought ids; every `excludes`, `clashes_with` and `bonds_with` names a real trait; at least one ambition; and a `REQUIRED_THOUGHTS` list (`ate_meal`, `went_hungry`, `slept_bed`, `freezing`, `good_chat`, `insulted`, `comforted`, `new_partner`, `frustrated`, `friend_died`, and others) because code records those ids by name.

## Behaviour logic

An NPC does exactly one thing per tick: run one tick of the current step of the current plan of its one committed intention. Everything else in this section decides which intention and which plan that is, and what happens when the step fails.

&#91;embedded content: per-agent tick · 7 stages, 3 step outcomes\]

A running step simply resumes next tick; only a failure walks back up to plan choice, and only an empty plan list ends in a backoff.

### 1. Perception (`sim/perception.rs`)

Runs when `(tick + id) % perception_interval == 0` (every 3 ticks). Sight radius = `sight_radius + tech bonus`, ×0.6 at night, ×0.5 in storms.

- **Nodes** in radius are written to `beliefs.nodes` with the current amount. Remembered nodes inside the radius that no longer exist are forgotten (the NPC sees they are used up).
- **People** in radius go into `beliefs.nearby`; familiarity rises by `proximity_familiarity_per_day` per tick-share; if both are pursuing the same work goal key, opinion rises by `shared_work_opinion_per_day`.
- **Stock**: standing within 1.5 tiles of a store or kitchen copies the real stockpile into `beliefs.stock`.
- **Creatures**: each sighting becomes a `ThreatBelief`. A creature not already believed in drops Safety by 35, sends `Warn` to everyone within 14 tiles (earshot), and returns `interrupted = true`.

### 2. Inbox (`sim/inbox.rs`)

The inbox is drained with `std::mem::take`. A `Warn` about an unknown dangerous creature also sets `urgent = true`. The receiving side of each protocol is described under Interaction & UI.

### 3. Deliberation: candidate goals and utility (`agents/deliberation.rs`)

Runs when there is no intention, when `tick >= next_deliberation`, or when perception/inbox interrupted. Then `next_deliberation = tick + 10 + id % 3`. `candidates(agent, view)` returns `Vec<Candidate {goal, utility, reason}>`, where `reason` is a short label such as "Hunger 31" shown in the inspector.

Helper: `deficit(v) = clamp((100 − v) / 100, 0, 1)`.

| Goal | Utility (shipped formula) | Gate |
| --- | --- | --- |
| Eat | `1.5 × deficit(food)²` + 0.7 if food < 25 + 0.18 at mealtimes (7:30, 12:30, 18:30 ± 1 h) if food < 70 | always |
| Sleep | in sleep hours and rest < 92: `0.62 + 0.6 × deficit(rest)`; otherwise `1.3 × deficit(rest)²` + 0.8 if rest < 15. +0.2 under curfew. ×0.25 if a threat is believed within 7 tiles and rest > 5 | always |
| WarmUp | `1.6 × deficit(warmth)²` + 0.6 if warmth < 20 | warmth < 60 |
| Flee | `1.4 × (1 − 0.6 × clamp(bravery, −0.5, 0.8)) × max(1 − d/10, 0.3)` | threat within 7 and (dangerous, or bravery < −0.2, or child) |
| SeekCare | `1.3 × (1 − hp/100)` + 0.45 if ill | needs care |
| Relax | `0.9 × deficit(recreation)² × (0.6 work hours / 1.4 off)` | recreation < 65 |
| Chat(best partner) | `0.85 × deficit(social)^1.5 × (1 + 0.6 × sociability) × (0.7 / 1.4)` + `0.05 × partner score` | social < 75, someone awake within 30 tiles |
| Court(crush) | `0.3 × (1 + romance) × (0.7 / 1.4) + 0.004 × relation.romance` | adult, single, and romantic trait, family ambition, or opinion > 55 of anyone |
| Comfort(friend) | `0.55 × (0.5 + kindness)` | kindness > 0, friend (opinion > 20) with mood < 30 within 20 tiles |
| Reconcile(rival) | 0.2 | kindness or leadership > 0, a rival is awake |
| Help (accepted request) | 1.0 for food/care; `0.9 × (0.5 + bravery)` for defence | `help_task` set and requester present |
| Volunteer | `0.55 + 0.3 × willingness` | expedition call open, adult, hp > 60, mood > 30, willingness > 0.4 |
| Work goals | `base × priority weight × aptitude × factor × company` (below) | not a child |
| Defend(creature) | `0.8 × (0.4 + bravery) × hp/100` | bravery > 0.1 or leader trait, threat within 16 |
| Idle | 0.04 | always (the floor) |

Chat partner score = `0.02 × opinion + 0.005 × familiarity + (1 − distance/30) + 0.2 × sociability`. Volunteer willingness = `0.2 + 0.3 × bravery + 0.2 × curiosity + 0.025 × exploration level` (+0.3 for the map-the-wilds ambition, + up to 0.35 for unanswered calls, × a policy bias).

**Work utility.** Work comes from a colony-owned `JobBoard` refreshed every 10 ticks (build sites with missing materials, repairs, farms, loose items, cook demand, crafting stations, labs, patients, threats, gather demand per node kind). Nothing is assigned; NPCs read the board.

- `base` = `0.42 + 0.1 × diligence` in work hours, else `max(0.08 + 0.12 × diligence, 0.02)`; ×0.5 if rest < 25; ×0.8 if mood < 30; × health capacity.
- Priority weight from the player's per-`WorkType` setting 0–3: `[0, 0.55, 1.0, 1.5]`. This is the only way the player steers labour.
- `aptitude(skill)` = `0.6 + 0.04 × level` + 0.3 if a passion + 0.3 if it is the master-skill ambition's skill.
- `company` = product over others already on this goal: ×0.55 per rival/enemy, ×1.15 per friend, ×0.8 per stranger.
- Builds only count when actionable (ready, or a missing material is believed in stock or lying on the map); at most 4 builds, 2 repairs, 3 farms, 3 crafts, 2 patients are offered.
- Gather goals require a known node of that kind; Scout appears when demand > 0.3 exists for an unknown kind or curiosity > 0.3.

**Post-processing.** Goals under backoff are removed. Every work goal is divided by `1 + 0.35 × (others pursuing the same GoalKey)`, which spreads labour without central assignment.

**Mental break override.** If `mental_break` is active, the only candidate is `Break(kind)` at utility 10 (a LashOut break becomes `Chat` with the least-liked person, which the plan library turns into an insult).

### 4. Commitment (`sim/cognition.rs`)

The best candidate replaces the current intention only if:

```latex
U_{best} > \max(U_{current}, 0.01) \times \theta, \quad \theta = \begin{cases} 1 + 3c & \text{current is survival and best is not} \\ 1 + c & \text{otherwise} \end{cases}
```

with `c = commitment_bonus = 0.25`. `U_current` is the current goal's freshly scored utility this tick (0 if it is no longer a candidate). Same `GoalKey` never switches; `Break` always switches. On adoption: log `Interrupted{by}` if a percept caused it, drop carried materials (food is kept for Eat, Help and Cook), log `Adopted{goal, utility, reason}`, clear the path, leave any building, and create a fresh `Intention`.

### 5. Plan selection (`agents/plan_library*.rs`)

`plans_for(goal, agent, view)` returns every applicable `PlanOption`, sorted by `preference` descending. Applicability (the BDI context condition) is checked against beliefs, not truth. `ensure_plan` picks the first option whose id is not in `intention.tried`; if none remain or `tried.len() >= max_plan_attempts (4)`, the NPC gives up.

Shared helpers: `nearest(predicate)` finds the closest built, operational structure the NPC has not failed to use in the last 240 ticks; `known_nodes(kind)` returns up to 3 believed nodes with no recent failure; `friend_nearby(min_opinion)` finds the closest awake adult above an opinion.

| Goal | Plans in preference order (pref) |
| --- | --- |
| Eat | `eat_carried` (1.3) · `mess_meal` (1.0, +0.3 gourmand) · `raw_stores` (0.7) · `forage` (0.45) · `ask_friend_for_food` (0.2: Send RequestHelp, WaitForHelp 90, Eat) |
| Sleep | `family_home` (1.6) · `partner_bed` (1.5) · `own_bed` (1.0 + comfort) · `free_bed` (0.8) · `sleep_by_fire` (0.4) · `sleep_rough` (0.15) |
| WarmUp | `heated_room` (1.0) · `fireside` (0.9) · `shelter` (0.6) · `huddle` with a friend (0.3) · `keep_moving` (0.1) |
| Flee | `shelter_indoors` away from the threat (1.0) · `run_away` 8 tiles opposite (0.6) · `freeze` (0.1) |
| SeekCare | `infirmary` (1.0) · `bed_rest` (0.6) · `ask_for_care` (0.4) · `rest_here` (0.1) |
| Relax | `recreation` building (0.6 + quality) · `stroll` (0.3) |
| Social | one plan: GoTo(agent), Talk{topic}: `chat`/SmallTalk, `pick_a_fight`/Insult (during LashOut), `comfort`, `court`/Flirt, `make_peace`/Reconcile |
| Help: food | `hand_over_food` (1.2) · `fetch_food` (1.0) · `forage_for_friend` (0.6) |
| Build | construct when ready; otherwise fetch a loose item or take stock, then Deliver |
| Gather | GoTo node, Harvest, GoTo store, Deposit (one plan per known node) |
| Others | Repair, Farm (Tend + Deposit), Haul, Cook, Craft, Research/StudyRelic, Treat (with or without medicine), Scout frontier tile, Defend/Attack, Volunteer (GoTo gate, JoinExpedition), Break (binge, wander\_off, sulk), Idle (loiter: GoTo wander tile, Wait 20) |

Every goal has a cheap last-resort plan that always applies (sleep rough, keep moving, freeze, rest here), so survival goals rarely give up entirely.

### 6. Execution and failure recovery (`sim/execute*.rs`)

`run_step` dispatches the current `Step` and gets `Running`, `Done` or `Failed(reason)`. `plan.step_ticks` counts ticks in the step; most steps finish on a duration or a need threshold (sleep until rest ≥ 99 outside sleep hours, warm until warmth ≥ 85, relax until recreation ≥ 96).

- `GoTo` resolves the target to a walkable tile each tick (agents move, so `Target::Agent` re-paths every 8 ticks), fails `TargetGone`, `NoPath`, or `TimedOut` after 500 ticks.
- **Done** advances the cursor; a completed plan means **achieve**: log `Achieved`, count `plans_recovered` if `tried` was non-empty, clear `help_task`, and set `next_deliberation = now` so the NPC picks a new goal immediately.
- **Failed** calls `learn_from_failure`, which corrects beliefs so the next plan does not repeat the mistake: a failed harvest or node GoTo forgets that node and records `FailedTarget::Node`; `StockEmpty` overwrites the believed stock with the real stockpile; a failed structure GoTo or Sleep records `FailedTarget::Structure`. Then the plan id is pushed to `tried`, `PlanFailed{plan, reason}` is logged, and the next tick's `ensure_plan` picks the next option.
- **Give up** when attempts are exhausted: log `GaveUp`, back off the `GoalKey` for 120 ticks, add the `frustrated` thought for survival or social goals, clear `help_task`, and re-deliberate next tick.

This loop produces the signature behaviour: the NPC walks to remembered berries, finds them gone, forgets them, goes to the stockpile instead, finds it empty, learns the real stock, and finally asks a friend for food.

### 7. Body, mood and crises (`sim/body.rs`, `sim/daily.rs`)

- Needs decay per tick: `decay_per_day[need] × personality.decay(need) × tech modifier × difficulty / ticks_per_day`. Rest does not decay while sleeping. Safety recovers 60 per day. Warmth gains from heat sources and shelter and loses `(14 − temperature) × 5` per day outdoors in the cold.
- Health: starvation (food ≤ 0.5) −14 hp/day, hypothermia −12, illness −6 (×0.4 if treated) with a daily recovery chance; regeneration 4/day, ×2 while recovering, 20 in an infirmary.
- Mood every 10 ticks: `baseline 50 + optimism − 4 × (act − 1) + need pressure + Σ thoughts + tech + policies − 0.2 × (50 − hp if hp < 50)`, clamped 0–100.
- Daily: the colony broadcasts the stockpile into every belief set, stale beliefs are forgotten, and opinions decay 0.4 toward zero. Mood < 22 rolls a 60% (×1.5 below 10) chance of a mental break chosen by personality: temper > 0.3 → LashOut, gourmand or lazy → Binge, sociability < 0 → Sulk, else Wander. Break lasts 180 ticks. Six cumulative days below mood 12 makes a single NPC leave the colony. Ambition progress is recomputed and fulfilment adds a +20 thought.

### 8. Determinism

All randomness flows through one `SeededRng` (from `macroquad_toolkit::rng`) owned by `Sim` and passed in `Ctx`. Plan helpers that need variety use hashes of id and tick instead of RNG (`wander_tile` uses `id × 31 + tick / 60`). Maps are `BTreeMap`. Floats are compared with `total_cmp`. With the same seed the run is bit-identical, which is what makes the save round-trip and regression tests possible.

## Interaction & UI

NPCs interact with each other through two channels: asynchronous typed messages (delivered next tick) and synchronous conversations (a `Talk` step that resolves for both parties after the tick). The player interacts with NPCs only by inspecting them; legibility comes from showing their reasoning, not dialogue trees.

### Message protocols (receiver side in `sim/inbox.rs`)

| Message | Sent when | Receiver does |
| --- | --- | --- |
| `Warn(threat)` | Perception spots a new creature; to all within 14 tiles | Adds the threat belief; urgent re-think if dangerous and new |
| `InformNode` | 50% chance after small talk, about a node the listener does not know | Accepts if opinion of sender > −15 and the sighting is newer |
| `Gossip{about, opinion}` | 35% chance after small talk: the speaker's strongest feeling about a third person | `opinion += (theirs − mine) × 0.2 × trust`, trust = `clamp((opinion of sender + 50)/150, 0, 1)` |
| `RequestHelp{need, place}` | `ask_friend_for_food` / `ask_for_care` plans | Accepts if not busy, not a child, not hungry (< 30) or hurt, and `opinion + 40 × kindness + skill bonus > 5` (care: medicine × 2, defence: bravery × 30). Accepting sets `help_task`, forces deliberation, and replies `AcceptHelp`; else `DeclineHelp` |
| `AcceptHelp` / `DeclineHelp` | Reply to a request | Logs "{name} is coming to help" / "{name} would not help" (decline: opinion −2) |
| `Propose` | Flirt pushes the proposer's romance ≥ 60 | Accepts if single, adult, opinion > 40, romance > 42; sets partner, +14 thought, chronicle entry. Rejection: romance ×0.7 |
| `AcceptProposal` / `RejectProposal` | Reply | Accept sets partner; reject adds `frustrated`, romance ×0.5 |
| `Delivered` | `Give` step | No-op marker |

The requester's `WaitForHelp{90}` step succeeds as soon as it carries food or is treated, and fails `TimedOut` with a `refused_help` thought otherwise, which sends it on to the next plan.

### Conversations (`sim/execute_social.rs`, `sim/social.rs`)

`Talk` approaches to within 2 tiles (re-path every 8 ticks, fail after 160), fails `Refused` if the partner is sleeping, fleeing, fighting or breaking, then holds for `chat_ticks` (12). On completion the speaker gains Social +26 and Recreation +6, practises the Social skill, and pushes an `Interaction{from, to, topic}` that `apply_effects` resolves with mutable access to both agents (`split_at_mut` via `pair_mut`).

- **Compatibility(a, b)** = Σ over a's traits × b's traits of `+6` for each `bonds_with` match and `−7` for each `clashes_with` match. It is directional.
- **SmallTalk**: friction = `0.25 × max(temper_a + temper_b, 0) − 0.02 × min(compat, 0)`, capped at 0.45; a friction roll turns the chat into an Insult. Otherwise each side's opinion changes by `rand(−6, 8) + 0.8 × compat + mood term`, familiarity +4, listener Social +20.8, a `good_chat` thought if the change > 3, then gossip and knowledge sharing.
- **Insult**: target opinion −12, speaker −3, `insulted` thought; 50% fight if either has a temper (6 damage each, `fought` thought).
- **Flirt**: if the target likes the speaker (> 15) and is single, romance rises on both sides; if not, opinion −2 and `frustrated`.
- **Reconcile**: success chance `0.4 + 0.3 kindness − 0.3 temper + (opinion + 50)/200` gives +12 both ways.
- **Comfort**: target gets `comforted` (+6), opinion +8, Social +15; the comforter gets `helped_friend`.
- Bond changes (Friend, Close friend, Rival, Enemy) are written to the chronicle: friendship when mutual, hostility when either side turns.

Daily births (`lifecycle::consider_births`) roll `child_chance_per_day` for partnered couples; `create_child` inherits one trait from each parent, the family name, and blends hue. Children grow up over 120 days and skip work goals.

### Rendering NPCs (`ui/world_view/actors.rs`)

NPCs are procedural, no sprite sheet required:

- A shadow ellipse, a mood ring under the feet coloured by `level_color(mood)`, a body circle in a jacket colour (6 portrait archetypes, hue-shifted by `agent.hue`), a highlight, and a head circle with portrait-based skin shade. Children draw at 0.7 scale.
- A carried-resource square beside the body.
- `bob()` adds a walk bounce for Walking/Hauling/Fleeing and a slower sway for Working.
- An activity glyph bubble above the head: Zs for sleeping, animated dots for talking, "!" for fleeing, × for fighting, a dot for eating, a ring for a break, + for recovering.
- NPCs inside a building render at the footprint centre with an id-based offset and 75% alpha.
- `movement::advance` uses a fractional `move_budget` and lerps `position` between tiles for smooth motion at any tick rate.
- The selected NPC gets a pulsing ring, its path drawn as a line, and lines to everyone it feels strongly about (|opinion| ≥ 25), coloured by opinion and thickened by strength.

### The inspector (`ui/inspector_agent.rs`)

This panel is the main payoff of the system. Four tabs:

1. **Mind**: the current goal in large type, a "drive" meter (`utility / 1.5`), the plan name, up to 6 steps with done/current/pending markers, "Already tried: …" in warning colour, carried item, then the reasoning log (time + one line per decision, setbacks in warning colour). At the bottom, **beliefs vs reality**: known node counts, "Believes {believed} food in stores ({actual})" highlighted when off by more than 25% + 5, and believed threats.
2. **Needs**: six meters, health, illnesses and injuries, and the active thoughts with their mood effects.
3. **Bonds**: every relation with bond label (or Partner), opinion; rows are tappable to jump to that person.
4. **Life**: skills with passions, ambition and progress, backstory, life stats.

Decision log templates (from `text.json`): `log_adopted` "Decided to {goal}" + `(reason)`, `log_plan` "Plan: {plan}", `log_failed` "{plan} failed — {reason}", `log_gave_up` "Gave up on {goal} for now", `log_achieved` "Done: {goal}", `log_interrupted` "Interrupted: {by}". Every goal, plan id, fail reason and activity has a label key (`goal_eat`, `plan_mess_meal` "a meal at the mess hall", `fail_stock_empty` "the stores were empty", `activity_eating`), so all player-facing text lives in data.

### Input and touch

`ui/input.rs::pick` tests the tapped world point against present, outdoor NPCs first, with a zoom-aware reach of `18 / zoom + 6` pixels, then creatures (×1.3 reach), then structures, then nodes. A tap emits `UiAction::Select(Selection::Agent(id))`; tapping empty ground deselects. The inspector has visible Follow (camera tracks the NPC) and Close buttons, so the whole flow works by touch without hover or keyboard.

## Integration steps

Port the system in eight stages, each buildable and testable on its own; the agent core (stages 1–5) depends only on a small world contract, so most of the work is mapping that contract onto the new game.

### The world contract

The agent code calls these, and nothing else, from the host game. Implement them first (names as in Final Landing):

| Need | Final Landing API | Minimum for a new game |
| --- | --- | --- |
| Grid positions | `Tile {x, y}`, `distance`, `steps`, `offset`; `Point {x, y}`, `of_tile`, `lerp` | Any integer grid |
| Pathfinding | `World::find_path(from, to) -> Option<VecDeque<Tile>>`, `map.is_walkable`, `map.nearest_walkable(tile, r)`, `map.move_cost` | A\* on the grid (the toolkit or a local helper) |
| Places | `world.built()` iterator of `Structure {id, footprint, residents}` + `def()` flags: `storage, kitchen, beds, family_only, comfort, heat, indoor, recreation, beauty, care_beds, expedition`; `access_tile(id, from)`; `is_operational`, `free_beds` | Whatever buildings or rooms the game has; the flags are what plans query |
| Resources in the world | `world.nodes` (`id, kind, tile, amount`), `node_access_tile`, `world.items` (loose drops), `drop_item` | Optional: drop Gather/Haul if there is no economy |
| Danger | `world.creatures` (`id, kind, tile`) with an `aggressive` flag in balance | Any hostile entity list |
| Shared economy | `Colony.stock: ResourceBag`, `colony.jobs: JobBoard`, `colony.priority(WorkType)` | A store and a job board, or remove work goals |
| Time | `Calendar {tick}` with `hour()`, `day()`, `is_daylight()`, `ticks_per_day()`, `per_tick(x)` | Required: schedules come from hours |
| Environment | `weather.temperature`, `is_storm()`, `world.heat_at(tile)` | Optional: drop Warmth if there is no climate |
| Text | `game_data().label(key)`, `fill_template` | Required for the reason strings and log |

### Build order

1. **Data and loading.** Add `people.json` (traits, ambitions, names), thoughts, and the `agents`, `needs`, `social`, `mood`, `time` sections of `balance.json`. Load with `macroquad_toolkit::include_json!` into a validated `OnceLock`; port the trait, ambition and required-thought checks.
2. **Agent model.** Copy `agents.rs`, `personality.rs`, `body.rs`, `beliefs.rs`, `goals.rs`, `plans.rs`, `intention.rs`, `messages.rs`, `generation.rs`. Trim the `Goal`, `Step` and `Resource`/`NodeKind` enums to what the game has. Add a `SeededRng` to the sim and spawn a few NPCs.
3. **Body tick.** Port `sim/body.rs`: need decay, health, `Mind::tick`, mood. Verify needs fall and mood moves with a headless run.
4. **Deliberation and plans.** Port `deliberation.rs` and the plan library for survival goals first (Eat, Sleep, Flee, Idle), then `sim/cognition.rs` and `sim/execute.rs` with `GoTo`, `Eat`, `Sleep`, `Hide`, `Wait`. Each goal must have a last-resort plan.
5. **Perception and messages.** Port `perception.rs`, `inbox.rs`, the `Effects` buffer and `apply_effects` message delivery. At this point NPCs are situated, reactive and robust.
6. **Social layer.** Add `Talk`, `Give`, `Send`, `WaitForHelp`, `Interaction` resolution, compatibility, gossip, knowledge sharing, courtship, help requests, and daily opinion decay.
7. **Work layer.** Build the host game's `JobBoard` (refresh every 10 ticks) and port the work candidates and work plans that make sense. Expose per-`WorkType` priority to the player as the only labour control.
8. **Presentation.** NPC drawing with activity glyphs, the selection overlay, tap picking, and the inspector Mind tab with the decision log and beliefs vs reality. Do this before tuning: you cannot tune what you cannot read.

### Scaling it down

- A game without an economy can keep needs + social + survival plans and drop the job board; Idle and Relax fill the day.
- A game with few NPCs can deliberate every tick; keep the `id`-based staggering only if CPU matters.
- A game that needs scripted beats can inject them as messages or high-utility candidates (the mental-break override is the pattern: one candidate at utility 10) without bypassing the cycle, which keeps the decision log truthful.
- Keep `Effects` deferred application even for small games; it is what keeps the result independent of NPC update order.

### Workspace checklist

- [ ] Every `.rs` file under 800 lines: the plan library is already split into `plan_library.rs`, `plan_library/needs.rs`, `plan_library/work.rs`, and execution into `execute_life`, `execute_work`, `execute_social`.
- [ ] Named module files, no new `mod.rs`.
- [ ] Macroquad pinned to `=0.4.16`; RNG from `macroquad_toolkit::rng::SeededRng`.
- [ ] All player-facing strings (goals, plans, reasons, fail reasons, activities, log templates) as label keys in data.
- [ ] Tests in the crate's `tests/` directory (next section).
- [ ] Inspector reachable and readable by touch at the minimum supported size, with visible Follow and Close; visual review captures in `docs/verification/`.

## Testing

Reproduction is proven by tests that check the agent properties, not exact numbers: Final Landing's `tests/agents.rs` has one test per BDI property and `tests/simulation.rs` covers determinism and saves. Port these first; they are the acceptance criteria for the new game.

| Test | Setup | Asserts | Property |
| --- | --- | --- | --- |
| `survivors_only_know_what_they_have_perceived` | New colony, run 6 ticks | Every believed node is within sight + 1 of some NPC; NPC 0 knows fewer nodes than exist | Situated |
| `a_sighted_predator_interrupts_and_warns_others` | Spawn an aggressive creature 3 tiles from an awake NPC, run 6 ticks | Watcher's goal is Flee, Defend or Help; at least one other NPC now believes in a threat | Reactive, social |
| `a_failed_plan_corrects_beliefs_and_tries_another_way` | Food 5, believed stock 0, a fake forage node 2 tiles away, a friend at opinion 60; run 20 ticks | Log contains `PlanFailed{"forage"}` followed by `ChosePlan` of a different plan; the fake node is forgotten | Robust, flexible |
| `committed_goals_resist_small_temptations_but_yield_to_breaks` | Pure calls to `should_switch` | Build 0.5 vs Relax 0.55 keeps; vs 0.9 switches; vs 0.8 switches from work but not from Eat; Break 0.1 always switches | Proactive |
| `survivors_share_knowledge_and_answer_requests_for_help` | A knows an ore vein, B does not; 12 forced SmallTalk interactions; then a RequestHelp to a kind, fed B | B's inbox holds `InformNode` for that vein; after one step B's `help_task == (A, Food)` | Social |
| `the_same_seed_plays_out_identically` | Two sims, seed 21, 2 days each | serde\_json fingerprints are equal | Determinism |
| `a_saved_colony_restores_exactly` | Run 1 day, serialize, deserialize | Restored fingerprint equals the saved one | Save round-trip |
| `a_scripted_colony_survives_and_grows_through_its_first_weeks` | Autoplay plans every 120 ticks for 20 days | Population ≥ 8, ≥ 8 buildings, ≥ 3 techs, ≥ 19 daily reports | Integration |

Suggested additions for a new game, to reach roughly five cases per feature:

- [ ] Exhausted plans back off: force all Eat plans to fail and assert `GaveUp`, a backoff entry for the Eat key, and the `frustrated` thought.
- [ ] Labour spreads: with two identical build jobs and four NPCs, assert no job has more than three pursuers after deliberation.
- [ ] Priority 0 disables a work type: no NPC adopts a goal of that `WorkType`.
- [ ] Trait clashes cost opinion: forced SmallTalk between `abrasive` and `kind` trends negative over many rolls with a fixed seed.
- [ ] Mental break overrides: set `mental_break` and assert the only candidate is `Break` at utility 10.
- [ ] Text coverage: every `Goal`, plan id, `FailReason` and `Activity` label key resolves in `text.json`.

Test with a fixed seed and headless `Sim::run_ticks`; tests reach into `sim.agents[i]` to set needs and beliefs directly, so keep agent fields `pub` and keep `should_switch`, `apply_effects` and `Effects` public for test access.
