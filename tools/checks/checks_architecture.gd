extends RefCounted
## M19 Sect architecture: the meditation hall and tribulation ground as
## designs and as places that change cultivation and trials, the sect
## proposing them, blueprints, devised homes and worn paths.
const Sim = preload("res://scripts/sim/sim.gd")
const Data = preload("res://scripts/core/data.gd")
const Balance = preload("res://scripts/core/balance.gd")
const Template = preload("res://scripts/building/template.gd")
const Build = preload("res://tools/checks/build.gd")
const Meditation = preload("res://tools/checks/meditation.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const Movement = preload("res://scripts/sim/movement.gd")
const SectPlaces = preload("res://scripts/sim/sect_places.gd")
const ExecuteCultivation = preload("res://scripts/sim/execute_cultivation.gd")
const DeliberationCultivation = preload("res://scripts/agents/deliberation_cultivation.gd")
const Tribulations = preload("res://scripts/sim/tribulations.gd")
const SiteFinder = preload("res://scripts/building/site_finder.gd")
const AbstractWorld = preload("res://scripts/sim/abstract/abstract_world.gd")
const Vernacular = preload("res://scripts/sim/vernacular.gd")

const NONE := Vector3i(-1, -1, -1)


static func _seat(agent: RefCounted, cell: Vector3i) -> void:
	agent.cell = cell
	agent.position = Movement.center(cell)
	agent.previous_position = agent.position


## Progress one cultivator makes sitting at `cell` for `ticks` ticks.
static func _sit(sim: RefCounted, agent: RefCounted, cell: Vector3i, ticks: int) -> float:
	_seat(agent, cell)
	agent.cultivation.progress = 0.0
	agent.step_result = {}
	for i in range(ticks):
		ExecuteCultivation._cultivate(sim, agent, {"ticks": ticks + 10}, i)
	return float(agent.cultivation.progress)


static func _structure(sim: RefCounted, function: String) -> Dictionary:
	for entry in sim.structures.built():
		if entry.functions.has(function):
			return entry
	return {}


## The starter designs carry their functions on their own.
func check_the_sect_designs_have_their_functions():
	for pair in [["meditation_hall", "meditation_hall"], ["trial_ground", "tribulation_ground"]]:
		var template: RefCounted = Template.from_starter(Data.starter(pair[0]))
		if not template.functions.has(pair[1]):
			return "%s gives %s, not %s" % [pair[0], str(template.functions), pair[1]]
	return ""


## The same person sitting in the same qi progresses faster on a hall's mat
## than outside it; the hall stands only where the tree's qi is dense.
func check_a_hall_speeds_cultivation():
	var sim: RefCounted = Sim.create(11)
	if Build.stamp(sim, 1, "meditation_hall").x < 0:
		return "no site for a meditation hall"
	var hall: Dictionary = _structure(sim, "meditation_hall")
	if hall.is_empty():
		return "the stamped hall is not a meditation hall"
	var mat: Vector3i = hall.components.mat[0]
	if sim.qi.density(sim, mat) < 0.5:
		return "a hall stands in thin qi (%.2f)" % sim.qi.density(sim, mat)
	var agent: RefCounted = sim.agents[0]
	agent.cultivation = CultivationState.fresh(0.6, "none", 0.9)
	agent.cultivation.realm = 1
	var inside: float = _sit(sim, agent, mat, 60) / sim.qi.density(sim, mat)
	var out: Vector3i = sim.nav.nearest_walkable(hall.anchor + Vector3i(0, 0, -6), 3)
	if out.x < 0 or SectPlaces.in_hall(sim, out):
		return "no place outside the hall to compare with"
	var outside: float = _sit(sim, agent, out, 60) / sim.qi.density(sim, out)
	var factor: float = inside / maxf(outside, 0.0001)
	if absf(factor - 1.3) > 0.05:
		return "the hall's help was %.2f, not 1.3" % factor
	# A cultivator of the settlement looks for the hall's mats.
	agent.settlement_id = 1
	_seat(agent, out)
	var spot: Vector3i = DeliberationCultivation.spot(sim, agent)
	if not SectPlaces.in_hall(sim, spot) and DeliberationCultivation.sitting_qi(sim, spot) < DeliberationCultivation.sitting_qi(sim, mat):
		return "the cultivator chose %s over a better mat" % spot
	return ""


## A trial faced on a tribulation ground counts as sanctuary, its lightning
## strikes the formation stones and nothing is scorched.
func check_a_ground_draws_the_lightning():
	var sim: RefCounted = Sim.create(11)
	if Build.stamp(sim, 1, "trial_ground").x < 0:
		return "no site for a trial ground"
	var ground: Dictionary = _structure(sim, "tribulation_ground")
	if ground.is_empty():
		return "the stamped ground is not a tribulation ground"
	var agent: RefCounted = sim.agents[0]
	agent.settlement_id = 1
	agent.cultivation = CultivationState.fresh(0.6, "none", 0.9)
	agent.cultivation.realm = 1
	agent.cultivation.progress = CultivationState.needed(agent.cultivation)
	agent.cultivation.foundation = 0.6
	agent.cultivation.techniques = ["tree_breath"]
	var site: Vector3i = DeliberationCultivation.trial_site(sim, agent)
	if SectPlaces.ground_at(sim, site).is_empty():
		return "the cultivator would not face Heaven on the ground (%s)" % site
	_seat(agent, site)
	if not Tribulations.in_sanctuary(sim, site):
		return "the ground is not counted as sanctuary"
	var before: Dictionary = {}
	for dz in range(-12, 13):
		for dx in range(-12, 13):
			for dy in range(-6, 8):
				before[site + Vector3i(dx, dy, dz)] = sim.voxels.get_block(site + Vector3i(dx, dy, dz))
	var id: int = sim.tribulations.announce(sim, agent, site)
	var trial: Dictionary = sim.tribulations.entries[id]
	trial.start_tick = sim.calendar.tick + 1
	for i in range(trial.strikes.size()):
		trial.strikes[i] = sim.calendar.tick + 2 + i * 3
	trial.end_tick = sim.calendar.tick + 4 + trial.strikes.size() * 3
	for _i in range(trial.strikes.size() * 3 + 6):
		sim.tribulations.step(sim)
		sim.calendar.tick += 1
	if not bool(trial.sanctuary):
		return "the trial was not held in sanctuary"
	if int(trial.scorched) > 0:
		return "lightning scorched %d blocks on the ground" % trial.scorched
	for cell in before:
		if sim.voxels.get_block(cell) != before[cell]:
			return "lightning changed %s" % cell
	if int(trial.get("drawn", 0)) == 0:
		return "no strike went to a formation stone"
	return ""


## A sect of four wants a hall; once one of them has faced Heaven it wants a
## ground; its master proposes them, a disciple or an outsider does not.
func check_the_sect_wants_its_places():
	var valley: Dictionary = Meditation.valley(11)
	var sim: RefCounted = valley.sim
	var wants: Array = SectPlaces.wants(sim, 1, {}).map(func(w: Array) -> String: return str(w[0]))
	if wants != ["meditation_hall"]:
		return "a young sect wants %s" % str(wants)
	sim.agents[int(valley.members[1])].cultivation.trials.append({"tick": 0, "realm": 1, "outcome": "passed"})
	var master: RefCounted = sim.agents[int(valley.master)]
	wants = SectPlaces.wants(sim, 1, {"meditation_hall": 1}, master).map(func(w: Array) -> String: return str(w[0]))
	if wants != ["tribulation_ground"]:
		return "after a trial the master wants %s" % str(wants)
	var sect: Dictionary = sim.sects.in_settlement(1)
	for agent in sim.agents:
		if agent.is_present() and agent.settlement_id == 1 and str(sect.members.get(agent.id, "")) in ["", "disciple"]:
			if not SectPlaces.wants(sim, 1, {}, agent).is_empty():
				return "%s (%s) proposes the sect's places" % [agent.full_name(), str(sect.members.get(agent.id, "outsider"))]
	return ""


## Exit (plan M19): on seed 11 with a sect, offered the two designs, the sect
## raises a meditation hall and a tribulation ground by its own proposals.
func long_check_the_sect_raises_its_hall_and_ground():
	var valley: Dictionary = Meditation.valley(11)
	var sim: RefCounted = valley.sim
	for id in ["meditation_hall", "trial_ground"]:
		sim.apply_command({"type": "offer_template", "template": Template.from_starter(Data.starter(id)).to_dict()})
	var start: int = sim.calendar.tick
	var raised: Array = []
	for day in range(30):
		sim.run_ticks(sim.calendar.ticks_per_day)
		# One of them faces Heaven early on, so the ground is wanted.
		if day == 2:
			sim.agents[int(valley.members[1])].cultivation.trials.append({"tick": sim.calendar.tick, "realm": 1, "outcome": "passed"})
		for entry in sim.chronicle.since(start):
			if entry.kind == "site_marked" and str(entry.cause).begins_with("cause_sect_needs"):
				var line: String = "%s day %d" % [str(entry.cause), day]
				if not raised.any(func(r: String) -> bool: return r.begins_with(str(entry.cause))):
					raised.append(line)
		if not _structure(sim, "meditation_hall").is_empty() and not _structure(sim, "tribulation_ground").is_empty():
			print("      both stand by day %d; marked %s" % [day, str(raised)])
			return ""
	print("      after 30 days: marked %s" % str(raised))
	return "the sect did not raise both (hall %s, ground %s)" % [not _structure(sim, "meditation_hall").is_empty(), not _structure(sim, "tribulation_ground").is_empty()]


## Lays `id` as a blueprint on the first spot, away from the one the
## settlement would choose itself, that the command accepts.
static func _lay_away(sim: RefCounted, id: String) -> Dictionary:
	var template: RefCounted = Template.from_starter(Data.starter(id))
	var settlement: Dictionary = sim.settlements.entries[1]
	var own: Dictionary = SiteFinder.find(sim, template, settlement)
	for ring in range(4, 20, 2):
		for k in range(8):
			var angle: float = k * PI / 4.0
			var corner := Vector3i(settlement.center.x + roundi(cos(angle) * ring), 0, settlement.center.z + roundi(sin(angle) * ring))
			if not own.is_empty() and Vector2(corner.x - own.origin.x, corner.z - own.origin.z).length() < 6.0:
				continue
			var result: Dictionary = sim.apply_command({"type": "lay_blueprint", "template": id, "origin": corner, "rotation": 0})
			if result.ok:
				return sim.god.blueprints.back()
	return {}


## A blueprint laid by the god is taken up by the next founder who wants
## that function and knows the design, on the god's spot.
func check_a_blueprint_is_taken_up():
	var valley: Dictionary = Meditation.valley(11)
	var sim: RefCounted = valley.sim
	var laid: Dictionary = _lay_away(sim, "timber_cottage")
	if laid.is_empty():
		return "no spot took the blueprint"
	var refused: Dictionary = sim.apply_command({"type": "lay_blueprint", "template": "meditation_hall", "origin": laid.origin, "rotation": 0})
	if refused.ok:
		return "a design never offered was laid"
	for _hour in range(sim.calendar.ticks_per_day * 3 / 30):
		sim.run_ticks(30)
		for id in sim.construction.ids():
			var site: Dictionary = sim.construction.get_site(id)
			if site.template_id == "timber_cottage":
				if site.origin != laid.origin:
					return "the first cottage went up at %s, not the god's %s" % [site.origin, laid.origin]
				if not sim.god.blueprints.is_empty():
					return "the blueprint stayed after it was taken"
				for entry in sim.chronicle.entries:
					if entry.kind == "blueprint_taken":
						return ""
				return "taking the blueprint was not chronicled"
	return "no cottage was begun in three days"


## A blueprint nobody needs is never built and fades after a season (two
## days lived in full, the rest of the season through the abstract model,
## which honours blueprints too).
func check_a_blueprint_nobody_needs_fades():
	var sim: RefCounted = Sim.create(11)
	sim.apply_command({"type": "offer_template", "template": Template.from_starter(Data.starter("trial_ground")).to_dict()})
	var laid: Dictionary = _lay_away(sim, "trial_ground")
	if laid.is_empty():
		return "no spot took the blueprint"
	sim.run_ticks(sim.calendar.ticks_per_day * 2)
	var end: int = int(laid.laid_tick) + sim.calendar.ticks_for_days(float(sim.calendar.days_per_season)) + sim.calendar.ticks_per_day
	var model: RefCounted = AbstractWorld.begin(sim)
	while sim.calendar.tick < end - 30:
		model.run_hours(sim, (end - sim.calendar.tick) / 30)
	model.finish(sim)
	for id in sim.construction.ids():
		if sim.construction.get_site(id).template_id == "trial_ground":
			return "a ground nobody needed was begun"
	if not sim.god.blueprints.is_empty():
		return "the blueprint did not fade"
	for entry in sim.chronicle.entries:
		if entry.kind == "blueprint_faded":
			return ""
	return "its fading was not chronicled"


## A settlement with people to house and no dwelling design among them
## devises one from what lies to hand once the god has had time to offer
## one (not on its first day), everyone there learns it, and the next home
## is built to it.
func check_a_settlement_with_no_home_design_devises_one():
	var sim: RefCounted = Sim.create(11)
	var settlement: Dictionary = sim.settlements.entries[1]
	settlement.known_templates.clear()
	for agent in sim.agents:
		agent.beliefs.known_templates.clear()
	sim.run_ticks(sim.calendar.ticks_per_day + 1)
	if not sim.settlements.designs.is_empty():
		return "a home was devised on the first day, before the god could offer one"
	# The settlement has gone without for its while.
	settlement.founded_tick = sim.calendar.tick - sim.calendar.ticks_for_days(Balance.number("construction.vernacular_after_days"))
	var devised: String = ""
	var there: Array = []
	for _hour in range(sim.calendar.ticks_per_day * 2 / 30):
		there = settlement.residents.filter(func(id: int) -> bool: return sim.agents[id].is_present())
		sim.run_ticks(30)
		if not sim.settlements.designs.is_empty():
			devised = sim.settlements.designs.keys()[0]
			break
	if devised.is_empty():
		return "nobody devised a home"
	var template: RefCounted = sim.template(devised)
	if template == null or not template.functions.has("dwelling"):
		return "the devised design is not a dwelling: %s" % (str(template.functions) if template else "missing")
	for agent_id in there:
		if sim.agents[agent_id].is_present() and not sim.agents[agent_id].beliefs.known_templates.has(devised):
			return "%s did not learn the devised home" % sim.agents[agent_id].full_name()
	if not sim.template_name(devised).contains(str(settlement.name)):
		return "the devised home is not named from the place: %s" % sim.template_name(devised)
	for _hour in range(sim.calendar.ticks_per_day * 3 / 30):
		sim.run_ticks(30)
		for id in sim.construction.ids():
			if sim.construction.get_site(id).template_id == devised:
				return ""
	return "no home was begun to the devised design"


## Without stone or grass known, a site's plain stone walls and thatch roof
## are raised in planks, and the chronicle says why.
func check_builders_make_do_without_thatch():
	const Construction = preload("res://scripts/sim/construction.gd")
	var template: RefCounted = Template.from_starter(Data.starter("timber_cottage"))
	var order: Array = template.placement(0).map(func(e: Array) -> Array: return [Vector3i.ZERO + e[0], e[1], e[2]])
	var thatch: int = Data.block_id("thatch")
	var before: int = order.filter(func(e: Array) -> bool: return int(e[1]) == thatch).size()
	if before == 0:
		return "the cottage has no thatch to swap"
	var changed: int = Construction.in_planks(order, 0, "thatch")
	if changed != before or order.any(func(e: Array) -> bool: return int(e[1]) == thatch):
		return "%d of %d thatch blocks went to planks" % [changed, before]
	if order.any(func(e: Array) -> bool: return int(e[1]) == Data.block_id("bed")) == false:
		return "the bed was swapped away"
	return ""


## Grass walked often wears to path, which navigation prefers slightly; a
## path left unwalked grasses over. In a few days of ordinary life the
## valley's busiest ways wear.
func long_check_paths_wear_and_grass_over():
	var sim: RefCounted = Sim.create(11)
	var camp: Vector3i = sim.settlements.entries[1].camp
	var cell: Vector3i = NONE
	for dx in range(3, 15):
		var at: Vector3i = sim.nav.surface(camp.x + dx, camp.z + 5)
		if at.x >= 0 and sim.voxels.get_block(at + Vector3i.DOWN) == Data.block_id("grass"):
			cell = at
			break
	if cell.x < 0:
		return "no grass to walk on"
	for _day in range(3):
		for _step in range(20):
			sim.paths.step_on(cell)
		sim.paths.daily(sim)
	if sim.voxels.get_block(cell + Vector3i.DOWN) != Data.block_id("path"):
		return "twenty steps a day for three days did not wear a path"
	var weight: float = sim.nav.astar.get_point_weight_scale(sim.voxels.index_of(cell))
	if weight >= 1.0:
		return "navigation does not prefer the path (weight %.2f)" % weight
	for _day in range(20):
		sim.paths.daily(sim)
	if sim.voxels.get_block(cell + Vector3i.DOWN) != Data.block_id("grass"):
		return "an unwalked path did not grass over"
	if sim.nav.astar.get_point_weight_scale(sim.voxels.index_of(cell)) != 1.0:
		return "grassed-over ground still counts as path"
	var lived: RefCounted = Sim.create(11)
	lived.run_ticks(lived.calendar.ticks_per_day * 4)
	var worn: int = 0
	for column in lived.paths.wear:
		var top: int = lived.voxels.top_solid_y(column.x, column.y)
		worn += 1 if lived.voxels.get_block(Vector3i(column.x, top, column.y)) == Data.block_id("path") else 0
	print("      %d path cells after four days of ordinary life" % worn)
	if worn == 0:
		return "four days of ordinary life wore no path"
	return ""


## Blueprints, devised designs and the wear of paths are saved and come back.
func check_sect_architecture_is_saved():
	const SimState = preload("res://scripts/sim/sim_state.gd")
	var sim: RefCounted = Sim.create(11)
	sim.apply_command({"type": "offer_template", "template": Template.from_starter(Data.starter("trial_ground")).to_dict()})
	if _lay_away(sim, "trial_ground").is_empty():
		return "no spot took the blueprint"
	var devised: String = Vernacular.devise(sim, 1)
	sim.paths.step_on(sim.settlements.entries[1].camp)
	sim.run_ticks(sim.calendar.ticks_per_day)
	var saved: Dictionary = SimState.capture(sim)
	var restored: RefCounted = SimState.restore(bytes_to_var(var_to_bytes(saved.sim)), bytes_to_var(var_to_bytes(saved.chunks)))
	if restored.god.blueprints != sim.god.blueprints:
		return "blueprints were not restored"
	if devised.is_empty() or restored.template(devised) == null or restored.template_name(devised) != sim.template_name(devised):
		return "the devised design was not restored"
	if restored.paths.wear != sim.paths.wear:
		return "path wear was not restored"
	return ""

