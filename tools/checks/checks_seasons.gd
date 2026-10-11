extends RefCounted
## M20 Seasons and weather: the sky follows its season and its own stream,
## wears on whoever is out in it, waters the fields (a dry spell stalls
## them), makes a trial fiercer in a thunderstorm and is waited out, can be
## calmed by the god, and is saved.
const Sim = preload("res://scripts/sim/sim.gd")
const SimState = preload("res://scripts/sim/sim_state.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Body = preload("res://scripts/sim/body.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const Crops = preload("res://scripts/sim/crops.gd")
const ExecuteFaith = preload("res://scripts/sim/execute_faith.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const DeliberationCultivation = preload("res://scripts/agents/deliberation_cultivation.gd")
const Miracles = preload("res://scripts/sim/miracles.gd")
const Movement = preload("res://scripts/sim/movement.gd")
const WorkPace = preload("res://scripts/sim/work_pace.gd")
const AbstractWorld = preload("res://scripts/sim/abstract/abstract_world.gd")
const AbstractPeople = preload("res://scripts/sim/abstract/abstract_people.gd")

const Need = Personality.Need


static func _flat(seed: int = 21) -> RefCounted:
	return Sim.create(seed, {"world": "flat", "size": Vector3i(64, 16, 64), "ground": 4})


## Sets the calendar to a season's first morning.
static func _season(sim: RefCounted, season: int, hour: float = 10.0) -> void:
	sim.calendar.tick = season * sim.calendar.days_per_season * sim.calendar.ticks_per_day + int(hour * sim.calendar.ticks_per_hour())


func check_the_sky_follows_its_season():
	var sim: RefCounted = _flat()
	for season in range(4):
		_season(sim, season)
		var seen: Dictionary = {}
		for i in range(300):
			sim.weather._roll(sim)
			seen[sim.weather.kind] = int(seen.get(sim.weather.kind, 0)) + 1
		if season == 3 and (not seen.has("snow") or seen.has("rain") or seen.has("thunderstorm")):
			return "winter skies were %s" % seen
		if season != 3 and seen.has("snow"):
			return "snow fell in season %d" % season
		if season != 3 and not seen.has("rain"):
			return "no rain in season %d: %s" % [season, seen]
	# The same world has the same sky, hour by hour.
	var a: RefCounted = _flat(5)
	var b: RefCounted = _flat(5)
	var kinds: Array = []
	for hour in range(24 * 12):
		a.calendar.tick += a.calendar.ticks_per_hour()
		b.calendar.tick += b.calendar.ticks_per_hour()
		a.weather.hourly(a)
		b.weather.hourly(b)
		if a.weather.kind != b.weather.kind:
			return "two worlds from one seed had different skies at hour %d" % hour
		if not kinds.has(a.weather.kind):
			kinds.append(a.weather.kind)
	if kinds.size() < 2:
		return "twelve days passed under one sky (%s)" % kinds
	return ""


## Out on a snowy winter day a person loses shelter; on a fair spring day
## they do not; under a roof the snow does not reach them.
func check_weather_wears_on_the_unsheltered():
	var sim: RefCounted = _flat()
	var agent: RefCounted = sim.agents[0]
	agent.inside = -1
	_season(sim, 0)
	sim.weather.kind = "clear"
	agent.needs[Need.SHELTER] = 60.0
	for i in range(60):
		Body._shelter(sim, agent)
	var fair: float = agent.need(Need.SHELTER)
	if fair < 60.0:
		return "shelter fell on a fair spring day (%.1f)" % fair
	_season(sim, 3)
	sim.weather.kind = "snow"
	agent.needs[Need.SHELTER] = 60.0
	for i in range(60):
		Body._shelter(sim, agent)
	var snowy: float = agent.need(Need.SHELTER)
	if snowy >= 58.0:
		return "a snowy winter day cost the unsheltered only %.1f shelter" % (60.0 - snowy)
	# A roof keeps the snow off.
	var roof: Vector3i = agent.cell + Vector3i(0, 3, 0)
	sim.set_block(roof, Registry.id("planks"), 0, "test")
	agent.needs[Need.SHELTER] = 60.0
	for i in range(60):
		Body._shelter(sim, agent)
	if agent.need(Need.SHELTER) < 60.0:
		return "a roof did not keep the snow off (%.1f)" % agent.need(Need.SHELTER)
	# Work under the open sky slows in the snow, not under the roof.
	if WorkPace.sky(sim, agent) != 1.0:
		return "work under a roof slowed in the snow"
	sim.set_block(roof, 0, 0, "test")
	if WorkPace.sky(sim, agent) >= 1.0:
		return "work in the open did not slow in the snow"
	return ""


## A crop in a dry spell stands still and the chronicle names the drought;
## believers pray for rain; rain sets it growing again.
func check_a_crop_waits_for_rain():
	var sim: RefCounted = _flat()
	var agent: RefCounted = sim.agents[0]
	var cell: Vector3i = agent.cell + Vector3i(4, 0, 0)
	sim.set_block(cell + Vector3i.DOWN, Registry.id("farmland"), 0, "test")
	sim.crops.sow(sim, cell, Crops.staple(), "test")
	var need: int = int(Crops.staple().rain_need)
	sim.weather.kind = "clear"
	sim.weather.last_wet_day = sim.calendar.day() - need - 2
	sim.crops.daily(sim)
	if int(sim.crops.plots[cell].days) != 0:
		return "a crop grew in a dry spell of %d days" % sim.weather.dry_days(sim)
	var noted: bool = false
	for entry in sim.chronicle.entries:
		noted = noted or entry.kind == "drought"
	if not noted:
		return "the drought was not chronicled"
	for i in range(Personality.NEEDS.size()):
		agent.needs[i] = 90.0
	agent.settlement_id = sim.settlements.at_cell(cell)
	if str(ExecuteFaith.intent(sim, agent).get("kind", "")) != "rain":
		return "nobody prayed for rain (%s)" % ExecuteFaith.intent(sim, agent)
	sim.weather.kind = "rain"
	sim.weather.hourly(sim)
	sim.crops.daily(sim)
	if int(sim.crops.plots[cell].days) != 1:
		return "after rain the crop still did not grow"
	return ""


## The same trial is fiercer when Heaven's storm breaks inside a
## thunderstorm, and a cultivator at the peak waits one out unless the wait
## has worn them down.
func check_a_thunderstorm_makes_a_trial_fiercer():
	var sim: RefCounted = Sim.create(11)
	var agent: RefCounted = sim.agents[0]
	agent.cultivation = CultivationState.fresh(0.6, "none", 0.9)
	agent.cultivation.realm = 1
	agent.cultivation.progress = CultivationState.needed(agent.cultivation)
	agent.cultivation.foundation = 0.6
	agent.cultivation.peak_tick = sim.calendar.tick
	agent.position = Movement.center(agent.cell)
	var severities: Array = []
	for sky in ["clear", "thunderstorm"]:
		sim.weather.kind = sky
		var id: int = sim.tribulations.announce(sim, agent, agent.cell)
		var trial: Dictionary = sim.tribulations.entries[id]
		trial.severity = 0.5
		sim.tribulations._begin(sim, trial, agent)
		severities.append(float(trial.severity))
		sim.tribulations.entries.erase(id)
	if not is_equal_approx(severities[1] - severities[0], sim.weather.kind_def("thunderstorm").trial):
		return "a thunderstorm left the trial at %.2f against %.2f" % [severities[1], severities[0]]
	# Waiting it out: fresh at the peak, a storm makes the call less likely.
	var utility: Array = []
	for sky in ["clear", "thunderstorm"]:
		sim.weather.kind = sky
		var out: Array = []
		DeliberationCultivation._breakthrough(sim, agent, out)
		utility.append(float(out[0].utility) if not out.is_empty() else 0.0)
	if utility[1] >= utility[0] * 0.6:
		return "a storm hardly held them back (%.3f against %.3f)" % [utility[1], utility[0]]
	sim.calendar.tick += sim.calendar.ticks_per_day * 10
	agent.cultivation.peak_tick = sim.calendar.tick - sim.calendar.ticks_per_day * 10
	var worn: Array = []
	for sky in ["clear", "thunderstorm"]:
		sim.weather.kind = sky
		var out: Array = []
		DeliberationCultivation._breakthrough(sim, agent, out)
		worn.append(float(out[0].utility))
	if not is_equal_approx(worn[0], worn[1]):
		return "a cultivator worn out by waiting still waited for the storm (%s)" % [worn]
	return ""


## Calm the Sky ends the rain, costs Favour, and cannot be cast at a clear sky.
func check_the_god_can_calm_the_sky():
	var sim: RefCounted = Sim.create(11)
	var shrine: Dictionary = sim.faith.current(sim)
	shrine.favour = 60.0
	var cell: Vector3i = sim.features.sacred_tree + Vector3i(3, 0, 3)
	sim.weather.kind = "rain"
	sim.weather.until_tick = sim.calendar.tick + 100000
	var result: Dictionary = Miracles.cast(sim, "calm_sky", cell, {})
	if not result.ok or sim.weather.kind != "clear":
		return "the sky was not calmed: %s" % result
	if float(shrine.favour) >= 60.0:
		return "calming the sky cost nothing"
	var left: float = float(shrine.favour)
	result = Miracles.cast(sim, "calm_sky", cell, {})
	if result.ok or str(result.reason) != "miracle_sky_clear" or float(shrine.favour) != left:
		return "a clear sky could be calmed again: %s" % result
	# It holds for its hours, then the season rolls again.
	sim.calendar.tick = sim.weather.until_tick - 1
	sim.weather.hourly(sim)
	if sim.weather.kind != "clear":
		return "the calm broke early"
	return ""


## While the valley passes abstractly the sky still changes, the homeless
## feel a snowy day, and herbs sprout and ripen as counts that take root
## when the valley wakes.
func check_the_sky_and_herbs_pass_while_abstract():
	var sim: RefCounted = Sim.create(11)
	sim.tree_growth.maturity = 12.0
	var model: RefCounted = AbstractWorld.begin(sim)
	var kinds: Dictionary = {}
	for hour in range(24 * 4):
		model.run_hours(sim, 1)
		kinds[sim.weather.kind] = true
	if kinds.size() < 2:
		return "four abstract days passed under one sky (%s)" % kinds.keys()
	if sim.herbs.count() > 0 or int(sim.herbs.pool.plants) == 0 or float(sim.herbs.pool.ripe) <= 0.0:
		return "abstract herbs did not grow as counts (placed %d, pool %s)" % [sim.herbs.count(), sim.herbs.pool]
	# A homeless person on a snowy winter day.
	var agent: RefCounted = sim.agents[0]
	agent.home = -1
	agent.needs[Need.SHELTER] = 60.0
	sim.calendar.tick = (3 * sim.calendar.days_per_season + 1) * sim.calendar.ticks_per_day + 11 * sim.calendar.ticks_per_hour()
	sim.weather.kind = "snow"
	sim.weather.until_tick = sim.calendar.tick + 100000
	AbstractPeople._shelter(AbstractPeople.context(sim, 1), agent, false)
	if agent.need(Need.SHELTER) >= 60.0:
		return "an abstract snowy day cost the homeless no shelter"
	var pooled: int = int(sim.herbs.pool.plants)
	model.finish(sim)
	if sim.herbs.count() < mini(pooled, 1) or int(sim.herbs.pool.plants) != 0:
		return "the counted herbs did not take root on waking (%d of %d)" % [sim.herbs.count(), pooled]
	return ""


## The sky, its stream and the dry spell survive a save.
func check_the_sky_is_saved():
	var sim: RefCounted = _flat()
	for hour in range(24 * 3):
		sim.calendar.tick += sim.calendar.ticks_per_hour()
		sim.weather.hourly(sim)
	sim.weather.last_wet_day = 2
	var saved: Dictionary = SimState.capture(sim)
	var restored: RefCounted = SimState.restore(saved.sim, saved.chunks)
	if restored.weather.to_dict() != sim.weather.to_dict():
		return "the sky changed in the save"
	for hour in range(24 * 4):
		for world in [sim, restored]:
			world.calendar.tick += world.calendar.ticks_per_hour()
			world.weather.hourly(world)
		if restored.weather.kind != sim.weather.kind:
			return "the restored sky went its own way at hour %d" % hour
	# A world saved before the sky existed starts under a clear one.
	saved.sim.erase("weather")
	var old: RefCounted = SimState.restore(saved.sim, saved.chunks)
	if old.weather.kind != "clear":
		return "an old world did not start under a clear sky"
	return ""
