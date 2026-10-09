extends Node
## The clock between real time and the simulation: accumulates frame time at
## the chosen speed and runs whole ticks within a frame budget. When the
## budget runs out the remainder carries over and `busy` is raised instead of
## spiralling. Resting runs many days behind an overlay with a larger budget.
signal rest_finished(summary_from_tick: int)
const Balance = preload("res://scripts/core/balance.gd")

var sim: RefCounted
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


func rest_progress() -> float:
	if not resting:
		return 0.0
	return clampf(float(sim.calendar.tick - rest_from_tick) / float(maxi(rest_target_tick - rest_from_tick, 1)), 0.0, 1.0)


func _process(delta: float) -> void:
	if sim == null:
		return
	var started: int = Time.get_ticks_usec()
	if resting:
		var budget: int = int(Balance.number("time.rest_budget_ms") * 1000.0)
		while sim.calendar.tick < rest_target_tick and Time.get_ticks_usec() - started < budget:
			sim.step()
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
		accumulator -= 1.0
	alpha = clampf(accumulator, 0.0, 1.0)
