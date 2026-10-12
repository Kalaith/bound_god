extends Node
## Debug-only performance profile (M25), capture `time_sixty`: the valley's
## first settlement filled to 60 people, then 240 frames at each speed (1×,
## 3×, 10×) after 60 to settle, printing the mean and worst frame. Shoots
## the last frame.
const Population = preload("res://scripts/sim/population.gd")
const Generation = preload("res://scripts/agents/generation.gd")

const SETTLE: int = 60
const MEASURE: int = 240

var main: Node3D
var shot: Node
var _speed: int = 1
var _frame: int = 0
var _times: Array = []
var _last: int = 0


static func fill(sim: RefCounted, people: int) -> void:
	var camp: Vector3i = sim.settlements.entries[sim.settlements.ids()[0]].camp
	var i: int = 0
	while sim.present_count() < people:
		var cell: Vector3i = sim.nav.nearest_walkable(camp + Vector3i(i % 6 - 3, 0, i / 6 - 3), 6)
		Population.arrive(sim, Generation.adult(sim.rng, sim.agents.size()), cell, int(sim.settlements.ids()[0]), "")
		i += 1


func _ready() -> void:
	fill(main.sim, 60)
	main.driver.set_speed(_speed)
	_last = Time.get_ticks_usec()


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	_frame += 1
	if _frame > SETTLE:
		_times.append((now - _last) / 1000.0)
	_last = now
	if _frame < SETTLE + MEASURE:
		return
	var mean: float = _times.reduce(func(a: float, b: float) -> float: return a + b, 0.0) / _times.size()
	print("SIXTY speed %d: %d people, frame mean %.2f ms (%.0f fps), worst %.2f ms" % [
		_speed, main.sim.present_count(), mean, 1000.0 / mean, _times.max()])
	_times.clear()
	_frame = 0
	_speed += 1
	if _speed > 3:
		main.driver.set_speed(0)
		set_process(false)
		shot.shoot_after(5)
		return
	main.driver.set_speed(_speed)
