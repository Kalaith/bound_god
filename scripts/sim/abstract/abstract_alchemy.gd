extends RefCounted
## Alchemy while the valley passes abstractly (M20b): where an alchemy
## building stands, ripe herbs of each kind are gathered from the herb pools
## for what the settlement wants and can refine; its benches work as many
## batches a day as it has crafters, the most wanted preparation first, each
## batch failing as often as the settlement's best hand would; and its
## people take what they would take awake: a sitting pill or a cup of tea, a
## draught when hurt, a cleansing pill when poisoned, an elixir when old.
## (Trial pills are taken by the abstract trial itself.)
const Data = preload("res://scripts/core/data.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const Alchemy = preload("res://scripts/sim/alchemy.gd")
const Elixirs = preload("res://scripts/sim/elixirs.gd")
const Herbs = preload("res://scripts/sim/herbs.gd")
const AbstractPeople = preload("res://scripts/sim/abstract/abstract_people.gd")

## Batches a crafter works in a day.
const BATCHES_PER_DAY: int = 2


static func day(sim: RefCounted, id: int) -> void:
	var shops: Array = Alchemy.workshops(sim, id)
	if not shops.is_empty():
		_gather(sim, id)
		_refine(sim, id, shops)
	_take(sim, id)


static func _gather(sim: RefCounted, id: int) -> void:
	var wanted: Dictionary = Alchemy.herbs_wanted(sim, id)
	var resources: Array = wanted.keys()
	resources.sort()
	for resource in resources:
		var kind: Dictionary = Herbs.by_resource(resource)
		var got: int = sim.herbs.abstract_gather(str(kind.id), int(wanted[resource]))
		if got > 0:
			AbstractPeople.store(sim, id, resource, got)


static func _refine(sim: RefCounted, id: int, shops: Array) -> void:
	var tier: int = Alchemy.tier_of(sim.structures.entries[shops[0]])
	var crafters: int = 0
	for room in shops:
		crafters += Alchemy.crafters(sim.structures.entries[room])
	var level: int = 0
	var anyone: RefCounted = null
	for agent in sim.agents:
		if agent.is_present() and not agent.is_child and agent.settlement_id == id:
			var skill: int = Personality.level(agent.skills, Personality.Skill.MEDICINE)
			if anyone == null or skill > level:
				level = skill
				anyone = agent
	if anyone == null:
		return
	var chance: float = Alchemy.fail_chance(level, tier)
	var left: int = crafters * BATCHES_PER_DAY
	for want in Alchemy.shortfall(sim, id, tier):
		var recipe: Dictionary = Data.recipe(want.recipe)
		var batches: int = mini(ceili(float(want.short) / float(recipe.outputs.values()[0])), left)
		for batch in range(batches):
			if not _has(sim, id, recipe):
				break
			left -= 1
			for resource in recipe.inputs:
				AbstractPeople.take(sim, id, resource, int(recipe.inputs[resource]))
			if sim.rng.randf() < chance:
				continue
			for resource in recipe.outputs:
				var extra: int = 1 if tier >= 4 and sim.rng.randf() < float(Data.alchemy().refining.cauldron_extra) else 0
				AbstractPeople.store(sim, id, resource, int(recipe.outputs[resource]) + extra)
		if left <= 0:
			return


static func _has(sim: RefCounted, id: int, recipe: Dictionary) -> bool:
	for resource in recipe.inputs:
		if sim.settlements.amount(id, resource) < int(recipe.inputs[resource]):
			return false
	return true


## Each person takes what they would take awake, if the stores hold it.
static func _take(sim: RefCounted, id: int) -> void:
	for agent in sim.agents:
		if not agent.is_present() or agent.is_child or agent.settlement_id != id or agent.cultivation.is_empty():
			continue
		var wanted: Array = []
		var sitting: String = Elixirs.for_sitting(sim, agent)
		if not sitting.is_empty():
			wanted.append(sitting)
		for need in Elixirs.needs(sim, agent):
			wanted.append(str(need[0]))
		for elixir in wanted:
			if sim.settlements.amount(id, elixir) > 0 and Elixirs.would_take(sim, agent, elixir) \
					and AbstractPeople.take(sim, id, elixir, 1) > 0:
				Elixirs.consume(sim, agent, elixir)
