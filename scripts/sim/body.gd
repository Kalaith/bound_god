extends RefCounted
## Per-tick bodily change: need decay, shelter, health, thoughts and mood.
const Balance = preload("res://scripts/core/balance.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const Mind = preload("res://scripts/agents/mind.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const TreeAbilities = preload("res://scripts/sim/tree_abilities.gd")
const SectHalls = preload("res://scripts/sim/sect_halls.gd")
const Data = preload("res://scripts/core/data.gd")

const Need = Personality.Need

static var _leaves: int = -1
static var _sacred_leaves: int = -1


## How covered a cell is: 1 under a real roof (or inside a sheltering
## structure), 0.5 under foliage, 0 in the open.
static func cover(sim: RefCounted, agent: RefCounted) -> float:
	if agent.inside >= 0:
		return 1.0
	var cell: Vector3i = agent.cell + Vector3i.UP
	if sim.voxels.is_roofed(cell, 6) or (not sim.kindled.is_empty() and sim.is_kindled(agent.cell)):
		return 1.0
	# Once the tree has learned to shelter, its crown is a roof.
	if TreeAbilities.sheltered(sim, agent.cell):
		return 1.0
	if _leaves < 0:
		_leaves = Registry.id("leaves")
		_sacred_leaves = Registry.id("sacred_leaves")
	for dy in range(1, 9):
		var block: int = sim.voxels.get_xyz(cell.x, cell.y + dy, cell.z)
		if block == _leaves or block == _sacred_leaves:
			return 0.5
	return 0.0


## How hard the day itself is on someone outdoors: the weather's exposure,
## and the winter cold. 0 on a fair day outside winter.
static func day_exposure(sim: RefCounted) -> float:
	var exposed: float = sim.weather.exposure() if sim.weather != null else 0.0
	if sim.calendar.is_winter():
		exposed += Balance.number("needs.winter_day_exposure")
	return exposed


## How slowly hunger and cold wear on someone: a cultivator's body needs
## less as their realm rises (the realm's endurance, 1 for a mortal).
static func endurance(agent: RefCounted) -> float:
	return float(Data.realm(int(agent.cultivation.get("realm", 0))).get("endurance", 1.0))


## What starving or freezing costs someone in health, as a share of the full
## damage: their endurance, and the sacred tree's qi where they are, which
## keeps the worst off those who live in its shade.
static func ward(sim: RefCounted, agent: RefCounted) -> float:
	var qi: float = sim.qi.density(sim, agent.cell) if sim.qi != null else 0.0
	return endurance(agent) * (1.0 - Balance.number("health.tree_ward") * qi)


static func _decay(sim: RefCounted, agent: RefCounted) -> void:
	var calendar: RefCounted = sim.calendar
	var rates: Dictionary = Balance.dict("needs.decay_per_day")
	for need in [Need.FOOD, Need.REST, Need.SOCIAL, Need.RECREATION]:
		if need == Need.REST and agent.activity == "sleeping":
			continue
		var rate: float = float(rates[Personality.NEEDS[need]]) * agent.personality.need_decay[need]
		if need == Need.FOOD:
			rate *= endurance(agent)
		agent.change_need(need, -calendar.per_tick(rate))
	agent.change_need(Need.SAFETY, calendar.per_tick(Balance.number("needs.safety_recovery_per_day")))
	_shelter(sim, agent)


static func _shelter(sim: RefCounted, agent: RefCounted) -> void:
	var calendar: RefCounted = sim.calendar
	var covered: float = cover(sim, agent)
	var hardy: float = endurance(agent)
	var gain: float = Balance.number("needs.shelter_gain_per_day")
	var exposed: float = day_exposure(sim)
	if covered >= 1.0:
		agent.change_need(Need.SHELTER, calendar.per_tick(gain))
	elif calendar.is_daylight() and exposed <= 0.0:
		agent.change_need(Need.SHELTER, calendar.per_tick(gain * 0.25 * (1.0 + covered)))
	elif calendar.is_daylight():
		# Rain, storm, snow and the winter cold wear on whoever is out in them.
		var day_loss: float = Balance.number("needs.shelter_loss_per_night_hour") * 24.0 * exposed
		agent.change_need(Need.SHELTER, -calendar.per_tick(day_loss * hardy * agent.personality.need_decay[Need.SHELTER] * (1.0 - covered)))
	else:
		var loss: float = Balance.number("needs.shelter_loss_per_night_hour") * 24.0
		if calendar.is_winter():
			loss *= Balance.number("needs.shelter_winter_factor")
		if sim.weather != null:
			loss *= 1.0 + sim.weather.exposure()
		if agent.activity == "sleeping":
			loss *= 0.8
		agent.change_need(Need.SHELTER, -calendar.per_tick(loss * hardy * agent.personality.need_decay[Need.SHELTER] * (1.0 - covered)))


static func _health(sim: RefCounted, agent: RefCounted) -> void:
	var calendar: RefCounted = sim.calendar
	var change: float = 0.0
	var day: int = calendar.ticks_per_day
	if agent.need(Need.FOOD) <= 0.5:
		change -= Balance.number("health.starvation_damage_per_day")
		if not Mind.has(agent, "went_hungry"):
			Mind.add(agent, "went_hungry", day)
	if agent.need(Need.SHELTER) <= 0.5:
		change -= Balance.number("health.exposure_damage_per_day")
		if not Mind.has(agent, "exposed"):
			Mind.add(agent, "exposed", day)
	if change < 0.0:
		change *= ward(sim, agent)
	if change >= 0.0 and agent.need(Need.FOOD) > 10.0:
		var rate: float = Balance.number("health.regen_per_day")
		if agent.activity == "recovering":
			rate *= Balance.number("halls.infirmary_factor") if SectHalls.in_infirmary(sim, agent) else 2.0
		change += rate
	# Rest in an infirmary slowly mends a foundation a failed trial cracked.
	if agent.activity in ["recovering", "sleeping"] and SectHalls.cracked(agent) and SectHalls.in_infirmary(sim, agent):
		SectHalls.mend(sim, agent, calendar.per_tick(Balance.number("halls.foundation_mend")))
	agent.health.hp = clampf(float(agent.health.hp) + calendar.per_tick(change), 0.0, 100.0)


static func compute_mood(agent: RefCounted) -> float:
	var value: float = Balance.number("mood.baseline") + float(agent.personality.optimism)
	value += agent.mood_pressure(Balance.number("mood.need_weight"))
	value += Mind.total(agent)
	if float(agent.health.hp) < 50.0:
		value -= (50.0 - float(agent.health.hp)) * 0.2
	return clampf(value, 0.0, 100.0)


static func update(sim: RefCounted, agent: RefCounted) -> void:
	_decay(sim, agent)
	_health(sim, agent)
	Mind.tick(agent, 1)
	if (sim.calendar.tick + agent.id) % 10 == 0:
		agent.mood = compute_mood(agent)
	# Lasting misery accumulates; better days slowly wear it away.
	if agent.mood < Balance.number("mood.departure_threshold"):
		agent.low_mood_ticks += 1
	elif agent.low_mood_ticks > 0 and sim.calendar.tick % 4 == 0:
		agent.low_mood_ticks -= 1
