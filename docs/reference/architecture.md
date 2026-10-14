# Architecture notes

How the simulation is shaped where the code alone does not say why. Code comments cite these sections as "architecture §N". `PROGRESS.md` records what is built and the decisions taken while building.

`Sim` owns all state and runs headless; presentation polls it and sends logged commands between ticks; agents write only to `Effects`.

Determinism (binding): simulation code never touches the scene tree, physics, `Time`, `OS` or global `randi()`/`randf()`; all randomness from `sim.rng` or a sub-stream seeded from it; comparators tie-break on stable ids; iterate sorted keys when dictionary order matters; document dictionary key and value types in comments.

## 1. The abstract settlement model

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

## 2. Data catalogs

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

## 3. Performance budget

| Measure | Target |
| --- | --- |
| Detailed region | 60 people at 3× within a 4 ms sim budget per frame |
| Abstract settlement | < 0.2 ms per in-game hour each |
| Meditation | 10 years of the home valley (abstract) < 30 s |
| Materialise | < 3 s behind the transfer or wake effect |
| Frame | 60 fps at 1080p, GPU < 10 ms with weather and particles |

## 4. Verification

`tools/sim_checks.gd` (headless scenarios, PASS/FAIL, non-zero exit), the parse/import check, every run grepped for `SCRIPT ERROR`, off-screen window captures for visuals, plain reporting of what was and was not checked. Additions:

- **Long-run scenarios** behind `--long` (`checks_campaign.gd`): a multi-year meditation with no player commands must not empty the valley, must produce at least one succession, and must keep invariants (no agent stuck in a plan for 2 days, no unreachable site cell, stock never negative).
- **Statistical checks** for abstract vs detailed time, with tolerances and fixed seeds.
- **Fixture saves** for every schema migration.
- **Playtest notes** in `docs/playtests/` at M18, M22, M23 and M25.
- `sim_checks` stays under 5 minutes without `--long`.

