extends RefCounted
## The sky over the valley (M20): one spell of weather at a time. When a
## spell ends the next is rolled on the hour from the season's weights
## (`data/weather.json`): snow only in winter, rain never in it. Each kind
## carries what it does: exposure (shelter lost outdoors by day as well as
## by night), the pace of outdoor work, whether it waters the fields, and
## the severity it adds to a trial whose storm breaks under it. The sky has
## its own random stream, seeded from the world's, so it never shifts the
## people's rolls; its state is saved with it.
const Data = preload("res://scripts/core/data.gd")

## The kind of the spell now over the valley.
var kind: String = "clear"
## The tick the spell ends at; the next is rolled on the first hour after.
var until_tick: int = 0
## The last day rain fell (the fields count their dry spell from it).
var last_wet_day: int = 1
## The year whose first snow has been chronicled.
var snow_noted_year: int = 0
## Whether the current dry spell has been chronicled as a drought.
var drought_noted: bool = false
var rng := RandomNumberGenerator.new()


func setup(sim: RefCounted) -> void:
	rng.seed = hash([sim.world_seed, "weather"])
	kind = "clear"
	until_tick = sim.calendar.tick + sim.calendar.ticks_per_hour() * 10
	last_wet_day = sim.calendar.day()


static func data() -> Dictionary:
	return Data.file("weather")


static func kind_def(id: String) -> Dictionary:
	for entry in data().get("kinds", []):
		if str(entry.id) == id:
			return entry
	return {}


func current() -> Dictionary:
	return kind_def(kind)


## Shelter lost outdoors, as a share of the night's loss, by day too.
func exposure() -> float:
	return float(current().get("exposure", 0.0))


## How fast work goes under an open sky.
func work() -> float:
	return float(current().get("work", 1.0))


## Severity a trial takes when its storm breaks under this sky.
func trial() -> float:
	return float(current().get("trial", 0.0))


func is_wet() -> bool:
	return bool(current().get("wet", false))


func is_storm() -> bool:
	return kind == "thunderstorm"


## Days since rain last fell.
func dry_days(sim: RefCounted) -> int:
	return sim.calendar.day() - last_wet_day


## On the hour (or each abstract step): rain waters the day, and a spell
## that has run its course gives way to the next.
func hourly(sim: RefCounted) -> void:
	if is_wet():
		_watered(sim)
	if sim.calendar.tick >= until_tick:
		_roll(sim)


func _watered(sim: RefCounted) -> void:
	last_wet_day = sim.calendar.day()
	drought_noted = false


func _roll(sim: RefCounted) -> void:
	var spells: Array = data().seasons[sim.calendar.season_name()]
	var total: float = 0.0
	for spell in spells:
		total += float(spell.weight)
	var pick: float = rng.randf() * total
	var chosen: Dictionary = spells[spells.size() - 1]
	for spell in spells:
		pick -= float(spell.weight)
		if pick < 0.0:
			chosen = spell
			break
	var was: String = kind
	kind = str(chosen.kind)
	var hours: int = rng.randi_range(int(chosen.hours[0]), int(chosen.hours[1]))
	until_tick = sim.calendar.tick + hours * sim.calendar.ticks_per_hour()
	if is_wet():
		_watered(sim)
	if kind == "snow" and snow_noted_year != sim.calendar.year():
		snow_noted_year = sim.calendar.year()
		sim.chronicle_event("first_snow", _place(sim), {}, "cause_winter")
	elif kind == "thunderstorm" and was != kind:
		sim.chronicle_event("thunderstorm", _place(sim), {}, "cause_summer_heat" if sim.calendar.season_name() == "summer" else "")


## The god stills the sky: whatever falls stops, clear for some hours.
func calm(sim: RefCounted) -> bool:
	if not is_wet() and kind != "snow":
		return false
	kind = "clear"
	until_tick = sim.calendar.tick + int(data().calm_hours) * sim.calendar.ticks_per_hour()
	return true


## A dry spell long enough to stall the crops, chronicled once per spell.
func note_drought(sim: RefCounted, settlement_id: int, crops: int) -> void:
	if drought_noted:
		return
	drought_noted = true
	sim.chronicle_event("drought", settlement_id, {"days": dry_days(sim), "count": crops}, "cause_no_rain")


static func _place(sim: RefCounted) -> int:
	return sim.settlements.at_cell(sim.features.get("sacred_tree", Vector3i.ZERO))


func to_dict() -> Dictionary:
	return {"kind": kind, "until_tick": until_tick, "last_wet_day": last_wet_day, "snow_noted_year": snow_noted_year,
		"drought_noted": drought_noted, "rng_state": rng.state, "rng_seed": rng.seed}


func from_dict(sim: RefCounted, state: Dictionary) -> void:
	if state.is_empty():
		setup(sim)
		return
	kind = str(state.kind)
	until_tick = int(state.until_tick)
	last_wet_day = int(state.last_wet_day)
	snow_noted_year = int(state.snow_noted_year)
	drought_noted = bool(state.drought_noted)
	rng.seed = int(state.rng_seed)
	rng.state = int(state.rng_state)
