extends RefCounted
## The sect's alchemy (M20b): alchemy buildings and their tiers, the benches
## inside them, what a settlement wants refined, and refining itself.
##
## A building's tier is the highest alchemy function it has (herbalist's
## workshop 1, alchemy room 2, alchemy hall 3, pill pavilion 4) and decides
## which recipes may be worked in it; its crafters, how many may work at
## once, come from its components (a bench at each furnace, mortar or
## cauldron). Each crafter works a bench (a seat) of the building, filled a
## load at a time as a kitchen's pot is, so several can work side by side;
## a batch left half done on a bench is finished by whoever sits there next. A batch may
## fail and lose its herbs: less often for a skilled hand and a better
## building. A pill pavilion's great cauldron sometimes yields one more.
const Balance = preload("res://scripts/core/balance.gd")
const Data = preload("res://scripts/core/data.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const SectHalls = preload("res://scripts/sim/sect_halls.gd")
const Herbs = preload("res://scripts/sim/herbs.gd")

const Skill = Personality.Skill
const STATION: String = "alchemy"
## Preparations kept in the stores against need even when nobody needs them.
const KEEP: Dictionary = {"healing_draught": 1}

## Vector2i(structure id, seat) -> {recipe: String, pot: {resource: int}, at: Vector3i}
var benches: Dictionary = {}


static func config() -> Dictionary:
	return Data.alchemy()


static func halls() -> Array:
	return config().halls


## The alchemy functions, lowest tier first.
static func functions() -> Array:
	var result: Array = []
	for hall in halls():
		result.append(str(hall.function))
	return result


static func _hall_of(entry: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	for hall in halls():
		if entry.functions.has(hall.function) and (best.is_empty() or int(hall.tier) > int(best.tier)):
			best = hall
	return best


## The alchemy tier of a structure (0 when it has no alchemy function).
static func tier_of(entry: Dictionary) -> int:
	var hall: Dictionary = _hall_of(entry)
	return 0 if hall.is_empty() else int(hall.tier)


## How many may work in a structure at once.
static func crafters(entry: Dictionary) -> int:
	var hall: Dictionary = _hall_of(entry)
	if hall.is_empty():
		return 0
	var count: int = 0
	for component in hall.crafters:
		count += entry.components.get(component, []).size() * int(hall.crafters[component])
	return clampi(count, 1, int(hall.crafters_most))


## A settlement's alchemy buildings, best tier first, then by id.
static func workshops(sim: RefCounted, id: int) -> Array:
	var found: Array = []
	for entry in sim.structures.built():
		var tier: int = tier_of(entry)
		if tier > 0 and sim.settlements.at_cell(entry.anchor) == id:
			found.append([tier, int(entry.id)])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	var result: Array = []
	for pair in found:
		result.append(pair[1])
	return result


static func best_tier(sim: RefCounted, id: int) -> int:
	var shops: Array = workshops(sim, id)
	return 0 if shops.is_empty() else tier_of(sim.structures.entries[shops[0]])


static func recipes() -> Array:
	var result: Array = []
	for entry in Data.recipes():
		if str(entry.station) == STATION:
			result.append(entry)
	return result


## The preparation a recipe makes (its one output).
static func product(recipe: Dictionary) -> String:
	return str(recipe.outputs.keys()[0])


## How many of each preparation a settlement would like kept, from what its
## people need: {resource: int}. Before anything is subtracted.
static func wants(sim: RefCounted, id: int) -> Dictionary:
	var cultivators: int = 0
	var near_peak: int = 0
	var mortals: int = 0
	var hurt: int = 0
	var poisoned: int = 0
	var old: int = 0
	var care: float = Balance.number("health.care_threshold")
	var cleanse_at: float = float(config().toxicity.cleanse_at)
	var years: float = Balance.number("alchemy.elixir_years")
	for agent in sim.agents:
		if not agent.is_present() or agent.is_child or agent.settlement_id != id:
			continue
		var c: Dictionary = agent.cultivation
		if c.is_empty():
			continue
		var cracked: bool = SectHalls.cracked(agent)
		if float(agent.health.hp) < care or cracked:
			hurt += 1
		if CultivationState.is_cultivator(c):
			cultivators += 1
			if CultivationState.has_next(c) and float(c.progress) >= CultivationState.needed(c) * Balance.number("alchemy.near_peak"):
				near_peak += 1
			if float(c.get("toxicity", 0.0)) >= cleanse_at or cracked:
				poisoned += 1
		elif float(c.drive) >= Balance.number("alchemy.tea_drive"):
			mortals += 1
		if int(c.get("sect_id", -1)) >= 0 and float(c.get("longevity", 0.0)) <= 0.0 \
				and agent.age_years >= CultivationState.lifespan(c) - years:
			old += 1
	var kept: int = Balance.integer("alchemy.pills_kept")
	return {
		"healing_draught": int(KEEP.healing_draught) + hurt,
		"awakening_tea": ceili(mortals / 2.0),
		"pill": maxi(kept, near_peak) if cultivators > 0 else 0,
		"qi_pill": ceili(cultivators / 2.0),
		"warding_pill": maxi(1, near_peak) if cultivators > 0 else 0,
		"cleansing_pill": poisoned,
		"longevity_elixir": old,
	}


## What is worth refining now, most pressing first: [{recipe, short, score}]
## for recipes up to `tier` whose preparation the stores lack.
static func shortfall(sim: RefCounted, id: int, tier: int) -> Array:
	var wanted: Dictionary = wants(sim, id)
	var result: Array = []
	for recipe in recipes():
		if int(recipe.tier) > tier:
			continue
		var made: String = product(recipe)
		var want: int = mini(int(wanted.get(made, 0)), Balance.integer("alchemy.kept_most"))
		var short: int = want - sim.settlements.amount(id, made)
		if short <= 0:
			continue
		var priority: float = float(Data.elixir(made).get("priority", 1.0))
		# Draughts kept against need, with nobody hurt, can wait.
		if want <= int(KEEP.get(made, 0)):
			priority *= 0.5
		result.append({"recipe": str(recipe.id), "short": short, "score": priority * float(short) / float(want)})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score or (a.score == b.score and a.recipe < b.recipe))
	return result


## Herbs the stores should gather for what the settlement's best building
## can refine and lacks: {herb resource: amount}, less what is stored.
static func herbs_wanted(sim: RefCounted, id: int) -> Dictionary:
	var result: Dictionary = {}
	var tier: int = best_tier(sim, id)
	if tier <= 0:
		return result
	var herbs: Array = Herbs.resources()
	for want in shortfall(sim, id, tier):
		var recipe: Dictionary = Data.recipe(want.recipe)
		var batches: int = ceili(float(want.short) / float(recipe.outputs.values()[0]))
		for resource in recipe.inputs:
			if resource in herbs:
				result[resource] = int(result.get(resource, 0)) + int(recipe.inputs[resource]) * batches
	for resource in result.keys():
		result[resource] = maxi(int(result[resource]) - sim.settlements.amount(id, resource), 0)
	return result


## Whether a person may refine a recipe: tier-1 mixtures are anyone's
## craft; pills belong to the sect's cultivators.
static func may_work(agent: RefCounted, recipe: Dictionary) -> bool:
	return int(recipe.tier) <= 1 or int(agent.cultivation.get("sect_id", -1)) >= 0


# --- Benches -----------------------------------------------------------------

func bench(structure: int, seat: int) -> Dictionary:
	return benches.get(Vector2i(structure, seat), {})


## The recipe a bench is half way through, or "".
func recipe_in(structure: int, seat: int) -> String:
	var held: Dictionary = bench(structure, seat)
	return "" if held.is_empty() or held.pot.is_empty() else str(held.recipe)


## What the bench still lacks for `batches` of a recipe: {resource: int}.
func lacking(structure: int, seat: int, recipe_id: String, batches: int) -> Dictionary:
	var result: Dictionary = {}
	var recipe: Dictionary = Data.recipe(recipe_id)
	if recipe.is_empty():
		return result
	var held: Dictionary = bench(structure, seat)
	var pot: Dictionary = held.pot if not held.is_empty() and str(held.recipe) == recipe_id else {}
	var resources: Array = recipe.inputs.keys()
	resources.sort()
	for resource in resources:
		var short: int = int(recipe.inputs[resource]) * batches - int(pot.get(resource, 0))
		if short > 0:
			result[resource] = short
	return result


func batches_ready(structure: int, seat: int) -> int:
	var held: Dictionary = bench(structure, seat)
	if held.is_empty():
		return 0
	var recipe: Dictionary = Data.recipe(str(held.recipe))
	if recipe.is_empty():
		return 0
	var most: int = 1 << 30
	for resource in recipe.inputs:
		most = mini(most, int(held.pot.get(resource, 0)) / int(recipe.inputs[resource]))
	return most


## Puts up to what the recipe still wants of `resource` on the bench; a
## bench half way through another recipe takes nothing. Returns how many.
func add(structure: int, seat: int, recipe_id: String, resource: String, amount: int, batches: int, at: Vector3i) -> int:
	var key := Vector2i(structure, seat)
	var held: Dictionary = benches.get(key, {})
	if not held.is_empty() and not held.pot.is_empty() and str(held.recipe) != recipe_id:
		return 0
	var used: int = mini(int(lacking(structure, seat, recipe_id, batches).get(resource, 0)), amount)
	if used <= 0:
		return 0
	if held.is_empty() or str(held.recipe) != recipe_id:
		held = {"recipe": recipe_id, "pot": {}, "at": at}
	held.pot[resource] = int(held.pot.get(resource, 0)) + used
	benches[key] = held
	return used


## Works every whole batch on the bench: {made: {resource: int}, failed: int}.
func refine(sim: RefCounted, structure: int, seat: int, agent: RefCounted, tier: int) -> Dictionary:
	var key := Vector2i(structure, seat)
	var batches: int = batches_ready(structure, seat)
	if batches <= 0:
		return {"made": {}, "failed": 0}
	var held: Dictionary = benches[key]
	var recipe: Dictionary = Data.recipe(str(held.recipe))
	for resource in recipe.inputs:
		held.pot[resource] = int(held.pot[resource]) - int(recipe.inputs[resource]) * batches
		if int(held.pot[resource]) <= 0:
			held.pot.erase(resource)
	if held.pot.is_empty():
		benches.erase(key)
	var chance: float = fail_chance(Personality.level(agent.skills, Skill.MEDICINE), tier)
	var made: Dictionary = {}
	var failed: int = 0
	for batch in range(batches):
		if sim.rng.randf() < chance:
			failed += 1
			continue
		for resource in recipe.outputs:
			var extra: int = 1 if tier >= 4 and sim.rng.randf() < float(config().refining.cauldron_extra) else 0
			made[resource] = int(made.get(resource, 0)) + int(recipe.outputs[resource]) + extra
	return {"made": made, "failed": failed}


## The chance a batch fails, for a medicine level and a building tier.
static func fail_chance(level: int, tier: int) -> float:
	var r: Dictionary = config().refining
	var bonus: float = float(r.tier_bonus[clampi(tier, 0, r.tier_bonus.size() - 1)])
	return clampf(float(r.fail_base) - float(r.fail_per_level) * level - bonus, float(r.fail_least), 1.0)


## A bench whose building lost its alchemy (or the furnace that gave the
## seat) spills what it held where it stood.
func daily(sim: RefCounted) -> void:
	var keys: Array = benches.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	for key in keys:
		var entry: Dictionary = sim.structures.entries.get(key.x, {})
		if not entry.is_empty() and tier_of(entry) > 0 and key.y < crafters(entry):
			continue
		var held: Dictionary = benches[key]
		var spill: Vector3i = sim.nav.nearest_walkable(held.at, 2) if sim.nav != null else held.at
		var resources: Array = held.pot.keys()
		resources.sort()
		for resource in resources:
			sim.drop_item(spill if spill.x >= 0 else held.at, resource, float(held.pot[resource]))
		benches.erase(key)


func to_dict() -> Dictionary:
	return {"benches": benches.duplicate(true)}


func from_dict(state: Dictionary) -> void:
	benches = state.get("benches", {})
