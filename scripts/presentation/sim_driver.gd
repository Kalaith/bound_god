extends Node
## The clock between real time and the simulation: accumulates frame time at
## the chosen speed and runs whole ticks within a frame budget. When the
## budget runs out the remainder carries over and `busy` is raised instead of
## spiralling. Resting runs many days behind an overlay with a larger budget.
signal rest_finished(summary_from_tick: int)
signal region_changed
const Balance = preload("res://scripts/core/balance.gd")
const AbstractWorld = preload("res://scripts/sim/abstract/abstract_world.gd")
const DeliberationCultivation = preload("res://scripts/agents/deliberation_cultivation.gd")

var sim: RefCounted
## The campaign whose frozen regions follow the active one hour by hour (M22).
var campaign: RefCounted = null
## Index into time.speeds: 0 pause, 1 normal, 2 fast, 3 fastest.
var speed_index: int = 1
var accumulator: float = 0.0
## Fraction of the way from the previous tick to the next, for smooth views.
var alpha: float = 0.0
var busy: bool = false
var resting: bool = false
var rest_target_tick: int = 0
var rest_from_tick: int = 0
var ticks_per_second: float = 6.0
## Meditation: the abstract model running behind the overlay, and why it
## stopped early ({} when it ran its span).
var meditation: RefCounted = null
var wake_reason: Dictionary = {}
## Where the meditation was meant to end, kept when something wakes the god
## early so the rest of the span can be sat through.
var meditation_end_tick: int = 0
var _speeds: Array = []


func _ready() -> void:
	ticks_per_second = Balance.number("time.ticks_per_second")
	_speeds = Balance.list("time.speeds")
	process_priority = -10


func speed() -> float:
	return float(_speeds[speed_index])


func set_speed(index: int) -> void:
	speed_index = clampi(index, 0, _speeds.size() - 1)


func rest(days: float) -> void:
	resting = true
	rest_from_tick = sim.calendar.tick
	rest_target_tick = sim.calendar.tick + sim.calendar.ticks_for_days(days)


## Years pass abstractly; the valley materialises at the end or when
## something wakes the god. Meditating on after a wake passes the first
## sitting's start as `from_tick`, so the summary covers the whole span.
func meditate(days: float, from_tick: int = -1) -> void:
	rest(days)
	meditation_end_tick = rest_target_tick
	if from_tick >= 0:
		rest_from_tick = from_tick
	wake_reason = {}
	meditation = AbstractWorld.begin(sim)
	meditation.step = AbstractWorld.step_for(days, float(sim.calendar.days_per_season * 4))
	sim.meditating = true


func meditating() -> bool:
	return resting and meditation != null


## Days of the meditation still unsat when the god woke early (0 if none).
func meditation_days_left() -> float:
	return maxf(float(meditation_end_tick - sim.calendar.tick), 0.0) / float(sim.calendar.ticks_per_day)


func rest_progress() -> float:
	if not resting:
		return 0.0
	return clampf(float(sim.calendar.tick - rest_from_tick) / float(maxi(rest_target_tick - rest_from_tick, 1)), 0.0, 1.0)


func _process(delta: float) -> void:
	# Once the god has left this region its world is frozen: the scene is
	# about to be rebuilt round the new one.
	if sim == null or (campaign != null and campaign.active_sim() != sim):
		return
	var started: int = Time.get_ticks_usec()
	if resting:
		var budget: int = int(Balance.number("time.rest_budget_ms") * 1000.0)
		if meditation != null:
			_meditate_frame(started, budget)
		else:
			while sim.calendar.tick < rest_target_tick and Time.get_ticks_usec() - started < budget:
				sim.step()
				if not _follow():
					return
		if sim.calendar.tick >= rest_target_tick:
			resting = false
			accumulator = 0.0
			rest_finished.emit(rest_from_tick)
		alpha = 1.0
		return
	accumulator += minf(delta, 0.25) * ticks_per_second * speed()
	var budget_usec: int = int(Balance.number("time.frame_budget_ms") * 1000.0)
	busy = false
	while accumulator >= 1.0:
		if Time.get_ticks_usec() - started > budget_usec:
			busy = true
			accumulator = minf(accumulator, 3.0)
			break
		sim.step()
		if not _follow():
			return
		accumulator -= 1.0
	alpha = clampf(accumulator, 0.0, 1.0)


## The frozen regions catch up at each hour the active one passes. False
## when that took the god into another region (the scene must follow).
func _follow() -> bool:
	if campaign != null and sim.calendar.is_new_hour():
		var region: int = campaign.active
		campaign.sync()
		if campaign.active != region:
			region_changed.emit()
			return false
	return true


func _meditate_frame(started: int, budget: int) -> void:
	while sim.calendar.tick < rest_target_tick and Time.get_ticks_usec() - started < budget:
		var reason: Dictionary = meditation.step_hour(sim)
		if not _follow():
			return
		if not reason.is_empty():
			wake_reason = reason
			rest_target_tick = sim.calendar.tick
			break
	if sim.calendar.tick < rest_target_tick:
		return
	meditation.finish(sim)
	meditation = null
	sim.meditating = false
	# A pinned person about to face Heaven does so now, with the god awake.
	if str(wake_reason.get("kind", "")) == "trial":
		var agent: RefCounted = sim.agents[int(wake_reason.agent)]
		sim.tribulations.announce(sim, agent, DeliberationCultivation.trial_site(sim, agent))
