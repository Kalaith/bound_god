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


static func hour(sim: RefCounted, agent: RefCounted) -> void:
	var per_hour: float = 1.0 / 24.0
	var rates: Dictionary = Balance.dict("needs.decay_per_day")
	var sleeping: bool = Schedule.is_sleep_time(sim, agent)
	var working: bool = Schedule.is_work_hours(sim, agent)
	agent.change_need(Need.FOOD, -float(rates.food) * agent.personality.need_decay[Need.FOOD] * per_hour)
	if sleeping:
		var rest: String = "needs.bed_rest_per_day" if agent.home >= 0 else "needs.ground_rest_per_day"
		agent.change_need(Need.REST, Balance.number(rest) * per_hour)
		agent.activity = "sleeping"
	else:
		agent.change_need(Need.REST, -float(rates.rest) * agent.personality.need_decay[Need.REST] * per_hour)
		agent.activity = "working" if working else "relaxing"
	for need in [Need.SOCIAL, Need.RECREATION]:
		agent.change_need(need, -float(rates[Personality.NEEDS[need]]) * agent.personality.need_decay[need] * per_hour)
		if not sleeping and not working:
			agent.change_need(need, LEISURE_PER_HOUR)
	agent.change_need(Need.SAFETY, Balance.number("needs.safety_recovery_per_day") * per_hour)
	_shelter(sim, agent, sleeping)
	if agent.need(Need.FOOD) < EAT_BELOW:
		_eat(sim, agent)
	_health(sim, agent)
	Mind.tick(agent, sim.calendar.ticks_per_hour())
	agent.mood = Body.compute_mood(agent)
	if agent.mood < Balance.number("mood.departure_threshold"):
		agent.low_mood_ticks += sim.calendar.ticks_per_hour()
	elif agent.low_mood_ticks > 0:
		agent.low_mood_ticks = maxi(agent.low_mood_ticks - sim.calendar.ticks_per_hour() / 4, 0)
	if float(agent.health.hp) <= 0.0:
		Lifecycle.die(sim, agent, Lifecycle._cause(agent))


## A home is a roof; the homeless lose shelter by night as the detailed body
## does under foliage (half cover), and get it back by day.
static func _shelter(sim: RefCounted, agent: RefCounted, sleeping: bool) -> void:
	var gain: float = Balance.number("needs.shelter_gain_per_day") / 24.0
	if agent.home >= 0:
		agent.change_need(Need.SHELTER, gain)
	elif sim.calendar.is_daylight():
		agent.change_need(Need.SHELTER, gain * 0.25 * 1.5)
	else:
		var loss: float = Balance.number("needs.shelter_loss_per_night_hour")
		if sim.calendar.is_winter():
			loss *= Balance.number("needs.shelter_winter_factor")
		if sleeping:
			loss *= 0.8
		agent.change_need(Need.SHELTER, -loss * agent.personality.need_decay[Need.SHELTER] * 0.5)


## One portion: carried food first, then the best the chests hold.
static func _eat(sim: RefCounted, agent: RefCounted) -> void:
	var food: String = str(agent.carrying.get("resource", ""))
	if Food.is_food(food) and agent.carried(food) >= 1.0:
		agent.carrying.amount = float(agent.carrying.amount) - 1.0
		if float(agent.carrying.amount) < 0.05:
			agent.carrying = {}
		_ate(sim, agent, food)
		return
	if agent.settlement_id < 0:
		return
	var keep_grain: bool = Food.putting_by(sim, agent.settlement_id, Standing.present(sim, agent.settlement_id))
	var order: Array = Food.eat_order().duplicate()
	if keep_grain and order.has("grain"):
		order.erase("grain")
		order.append("grain")
	for resource in order:
		if take(sim, agent.settlement_id, resource, 1) > 0:
			_ate(sim, agent, resource)
			return


static func _ate(sim: RefCounted, agent: RefCounted, food: String) -> void:
	agent.change_need(Need.FOOD, Food.value(food))
	Mind.add(agent, "ate_a_meal" if food == "meal" else "ate_raw", sim.calendar.ticks_per_day)
	Mind.remove(agent, "went_hungry")


static func _health(sim: RefCounted, agent: RefCounted) -> void:
	var change: float = 0.0
	var day: int = sim.calendar.ticks_per_day
	if agent.need(Need.FOOD) <= 0.5:
		change -= Balance.number("health.starvation_damage_per_day")
		if not Mind.has(agent, "went_hungry"):
			Mind.add(agent, "went_hungry", day)
	if agent.need(Need.SHELTER) <= 0.5:
		change -= Balance.number("health.exposure_damage_per_day")
		if not Mind.has(agent, "exposed"):
			Mind.add(agent, "exposed", day)
	if change >= 0.0 and agent.need(Need.FOOD) > 10.0:
		change += Balance.number("health.regen_per_day")
	agent.health.hp = clampf(float(agent.health.hp) + change / 24.0, 0.0, 100.0)


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
