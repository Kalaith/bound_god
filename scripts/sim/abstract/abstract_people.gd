extends RefCounted
## One abstract hour of a frozen person (plan §3.1): the same needs, food
## values, damage and mood rules as the detailed body, applied in hour-sized
## steps without plans or paths. Sleep comes in the sleep hours, company and
## leisure in the free hours, food from the settlement's chests (the best
## food first, berries before grain while grain is put by).
const Balance = preload("res://scripts/core/balance.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const Mind = preload("res://scripts/agents/mind.gd")
const Schedule = preload("res://scripts/agents/schedule.gd")
const Body = preload("res://scripts/sim/body.gd")
const Food = preload("res://scripts/sim/food.gd")
const Standing = preload("res://scripts/sim/standing.gd")
const Lifecycle = preload("res://scripts/sim/lifecycle.gd")

const Need = Personality.Need
## Below this a person eats in an abstract hour (detailed people eat at
## mealtimes below 70 or when hungry; one portion restores 38 to 70).
const EAT_BELOW: float = 60.0
## Leisure the free hours give back to company and recreation, per hour,
## matching a chat or a sit by the tree in an evening.
const LEISURE_PER_HOUR: float = 9.0


## `forage` is the settlement's economy record: its ripe-berry pool feeds
## people straight from the bush when the chests are empty, as foraging does.
static func hour(sim: RefCounted, agent: RefCounted, forage: Dictionary = {}, step: int = 1) -> void:
	var k: Dictionary = context(sim, step)
	var sleeping: bool = asleep(k, agent)
	var working: bool = at_work(k, agent)
	var decay: PackedFloat32Array = agent.personality.need_decay
	var needs: PackedFloat32Array = agent.needs
	needs[Need.FOOD] = clampf(needs[Need.FOOD] - float(k.food) * decay[Need.FOOD], 0.0, 100.0)
	if sleeping:
		needs[Need.REST] = clampf(needs[Need.REST] + (float(k.bed_rest) if agent.home >= 0 else float(k.ground_rest)), 0.0, 100.0)
		agent.activity = "sleeping"
	else:
		needs[Need.REST] = clampf(needs[Need.REST] - float(k.rest) * decay[Need.REST], 0.0, 100.0)
		agent.activity = "working" if working else "relaxing"
	var leisure: float = LEISURE_PER_HOUR * int(k.step) if not sleeping and not working else 0.0
	needs[Need.SOCIAL] = clampf(needs[Need.SOCIAL] - float(k.social) * decay[Need.SOCIAL] + leisure, 0.0, 100.0)
	needs[Need.RECREATION] = clampf(needs[Need.RECREATION] - float(k.recreation) * decay[Need.RECREATION] + leisure, 0.0, 100.0)
	needs[Need.SAFETY] = clampf(needs[Need.SAFETY] + float(k.safety), 0.0, 100.0)
	agent.needs = needs
	_shelter(k, agent, sleeping)
	if agent.need(Need.FOOD) < EAT_BELOW:
		_eat(sim, agent, forage)
	_health(sim, k, agent)
	var ticks: int = int(k.ticks)
	if not agent.thoughts.is_empty():
		Mind.tick(agent, ticks)
	agent.mood = Body.compute_mood(agent)
	if agent.mood < float(k.departure):
		agent.low_mood_ticks += ticks
	elif agent.low_mood_ticks > 0:
		agent.low_mood_ticks = maxi(agent.low_mood_ticks - ticks / 4, 0)
	if float(agent.health.hp) <= 0.0:
		Lifecycle.die(sim, agent, Lifecycle._cause(agent))


static var _context_tick: int = -1
static var _context: Dictionary = {}


## The hour's shared numbers, worked out once for everyone.
## `step` is how many hours one abstract step covers (1, or 2 in long meditations).
static func context(sim: RefCounted, step: int = 1) -> Dictionary:
	if _context_tick == sim.calendar.tick and not _context.is_empty() and int(_context.step) == step:
		return _context
	_context_tick = sim.calendar.tick
	var per_hour: float = float(step) / 24.0
	var rates: Dictionary = Balance.dict("needs.decay_per_day")
	var loss: float = Balance.number("needs.shelter_loss_per_night_hour")
	if sim.calendar.is_winter():
		loss *= Balance.number("needs.shelter_winter_factor")
	_context = {
		"step": step, "hour": sim.calendar.hour(), "daylight": sim.calendar.is_daylight(), "ticks": sim.calendar.ticks_per_hour() * step,
		"food": float(rates.food) * per_hour, "rest": float(rates.rest) * per_hour, "social": float(rates.social) * per_hour,
		"recreation": float(rates.recreation) * per_hour, "safety": Balance.number("needs.safety_recovery_per_day") * per_hour,
		"bed_rest": Balance.number("needs.bed_rest_per_day") * per_hour, "ground_rest": Balance.number("needs.ground_rest_per_day") * per_hour,
		"shelter_gain": Balance.number("needs.shelter_gain_per_day") * per_hour, "shelter_loss": loss,
		"starve": Balance.number("health.starvation_damage_per_day") * per_hour, "expose": Balance.number("health.exposure_damage_per_day") * per_hour,
		"regen": Balance.number("health.regen_per_day") * per_hour, "departure": Balance.number("mood.departure_threshold"),
		"sleep_hour": Balance.number("time.sleep_hour"), "dawn_hour": Balance.number("time.dawn_hour"),
		"work_start": Balance.number("time.work_start_hour"), "work_end": Balance.number("time.work_end_hour"),
	}
	return _context


## Schedule.is_sleep_time and is_work_hours, from the hour's context.
static func asleep(k: Dictionary, agent: RefCounted) -> bool:
	var hour: float = fposmod(float(k.hour) - (3.0 if agent.personality.night_owl else 0.0), 24.0)
	return hour >= float(k.sleep_hour) or hour < float(k.dawn_hour)


static func at_work(k: Dictionary, agent: RefCounted) -> bool:
	var owl: float = 2.0 if agent.personality.night_owl else 0.0
	return float(k.hour) >= float(k.work_start) + owl and float(k.hour) < float(k.work_end) + owl


## A home is a roof; the homeless lose shelter by night as the detailed body
## does under foliage (half cover), and get it back by day.
static func _shelter(k: Dictionary, agent: RefCounted, sleeping: bool) -> void:
	var gain: float = float(k.shelter_gain)
	if agent.home >= 0:
		agent.change_need(Need.SHELTER, gain)
	elif bool(k.daylight):
		agent.change_need(Need.SHELTER, gain * 0.25 * 1.5)
	else:
		var loss: float = float(k.shelter_loss) * int(k.step)
		if sleeping:
			loss *= 0.8
		agent.change_need(Need.SHELTER, -loss * agent.personality.need_decay[Need.SHELTER] * 0.5)


## One portion: carried food first, then the best the chests hold.
static func _eat(sim: RefCounted, agent: RefCounted, forage: Dictionary) -> void:
	var food: String = str(agent.carrying.get("resource", ""))
	if Food.is_food(food) and agent.carried(food) >= 1.0:
		agent.carrying.amount = float(agent.carrying.amount) - 1.0
		if float(agent.carrying.amount) < 0.05:
			agent.carrying = {}
		_ate(sim, agent, food)
		return
	if agent.settlement_id < 0:
		return
	# While grain is being put by for the winter it is eaten last, after
	# berries from the chests and from the bushes, as the detailed eaters do.
	var keep_grain: bool = Food.putting_by(sim, agent.settlement_id, Standing.present(sim, agent.settlement_id))
	var order: Array = Food.eat_order().duplicate()
	if keep_grain and order.has("grain"):
		order.erase("grain")
	for resource in order:
		if take(sim, agent.settlement_id, resource, 1) > 0:
			_ate(sim, agent, resource)
			return
	if float(forage.get("ripe", 0.0)) >= 1.0:
		forage.ripe = float(forage.ripe) - 1.0
		agent.change_need(Need.FOOD, Balance.number("needs.forage_restore"))
		Mind.add(agent, "ate_foraged", sim.calendar.ticks_per_day)
		Mind.remove(agent, "went_hungry")
		return
	if keep_grain and take(sim, agent.settlement_id, "grain", 1) > 0:
		_ate(sim, agent, "grain")


static func _ate(sim: RefCounted, agent: RefCounted, food: String) -> void:
	agent.change_need(Need.FOOD, Food.value(food))
	Mind.add(agent, "ate_a_meal" if food == "meal" else "ate_raw", sim.calendar.ticks_per_day)
	Mind.remove(agent, "went_hungry")


static func _health(sim: RefCounted, k: Dictionary, agent: RefCounted) -> void:
	var change: float = 0.0
	var day: int = sim.calendar.ticks_per_day
	if agent.need(Need.FOOD) <= 0.5:
		change -= float(k.starve)
		if not Mind.has(agent, "went_hungry"):
			Mind.add(agent, "went_hungry", day)
	if agent.need(Need.SHELTER) <= 0.5:
		change -= float(k.expose)
		if not Mind.has(agent, "exposed"):
			Mind.add(agent, "exposed", day)
	if change >= 0.0 and agent.need(Need.FOOD) > 10.0:
		if float(agent.health.hp) >= 100.0:
			return
		change += float(k.regen)
	agent.health.hp = clampf(float(agent.health.hp) + change, 0.0, 100.0)


## Takes up to `count` of a resource from a settlement's chests, oldest lots
## first, chest by chest in their stable order. Returns how many.
static func take(sim: RefCounted, id: int, resource: String, count: int) -> int:
	var taken: int = 0
	for chest in sim.settlements.chest_cells(sim, id):
		if taken >= count:
			break
		taken += sim.settlements.chest_take(chest, resource, count - taken)
	return taken


## Stores up to `count` in a settlement's chests; returns how many fitted.
static func store(sim: RefCounted, id: int, resource: String, count: int) -> int:
	var stored: int = 0
	for chest in sim.settlements.chest_cells(sim, id):
		if stored >= count:
			break
		stored += sim.settlements.chest_add(chest, resource, count - stored)
	return stored
