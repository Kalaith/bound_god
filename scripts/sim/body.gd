extends RefCounted
## Per-tick bodily change: need decay, shelter, health, thoughts and mood.
const Balance = preload("res://scripts/core/balance.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const Mind = preload("res://scripts/agents/mind.gd")
const Registry = preload("res://scripts/world/block_registry.gd")

const Need = Personality.Need


## How covered a cell is: 1 under a real roof (or inside a sheltering
## structure), 0.5 under foliage, 0 in the open.
static func cover(sim: RefCounted, agent: RefCounted) -> float:
	if agent.inside >= 0:
		return 1.0
	var cell: Vector3i = agent.cell + Vector3i.UP
	if sim.voxels.is_roofed(cell, 6) or sim.is_kindled(agent.cell):
		return 1.0
	for dy in range(1, 9):
		var block: int = sim.voxels.get_block(cell + Vector3i(0, dy, 0))
		if block == Registry.id("leaves") or block == Registry.id("sacred_leaves"):
			return 0.5
	return 0.0


static func _decay(sim: RefCounted, agent: RefCounted) -> void:
	var calendar: RefCounted = sim.calendar
	var rates: Dictionary = Balance.dict("needs.decay_per_day")
	for need in [Need.FOOD, Need.REST, Need.SOCIAL, Need.RECREATION]:
		if need == Need.REST and agent.activity == "sleeping":
			continue
		var rate: float = float(rates[Personality.NEEDS[need]]) * agent.personality.need_decay[need]
		agent.change_need(need, -calendar.per_tick(rate))
	agent.change_need(Need.SAFETY, calendar.per_tick(Balance.number("needs.safety_recovery_per_day")))
	_shelter(sim, agent)


static func _shelter(sim: RefCounted, agent: RefCounted) -> void:
	var calendar: RefCounted = sim.calendar
	var covered: float = cover(sim, agent)
	var gain: float = Balance.number("needs.shelter_gain_per_day")
	if covered >= 1.0:
		agent.change_need(Need.SHELTER, calendar.per_tick(gain))
	elif calendar.is_daylight():
		agent.change_need(Need.SHELTER, calendar.per_tick(gain * 0.25 * (1.0 + covered)))
	else:
		var loss: float = Balance.number("needs.shelter_loss_per_night_hour") * 24.0
		if calendar.is_winter():
			loss *= Balance.number("needs.shelter_winter_factor")
		if agent.activity == "sleeping":
			loss *= 0.8
		agent.change_need(Need.SHELTER, -calendar.per_tick(loss * agent.personality.need_decay[Need.SHELTER] * (1.0 - covered)))


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
	if change >= 0.0 and agent.need(Need.FOOD) > 10.0:
		var rate: float = Balance.number("health.regen_per_day")
		if agent.activity == "recovering":
			rate *= 2.0
		change += rate
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
