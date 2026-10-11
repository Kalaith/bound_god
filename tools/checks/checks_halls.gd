extends RefCounted
## M19b The sect's halls: the ten new kinds of building as designs, each
## one's help measured with and without it (same person, same place), and
## what a grown sect wants to build.
const Sim = preload("res://scripts/sim/sim.gd")
const Data = preload("res://scripts/core/data.gd")
const Balance = preload("res://scripts/core/balance.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Template = preload("res://scripts/building/template.gd")
const Build = preload("res://tools/checks/build.gd")
const Meditation = preload("res://tools/checks/meditation.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const Movement = preload("res://scripts/sim/movement.gd")
const SectPlaces = preload("res://scripts/sim/sect_places.gd")
const SectHalls = preload("res://scripts/sim/sect_halls.gd")
const SectHallWants = preload("res://scripts/sim/sect_hall_wants.gd")
const ExecuteCultivation = preload("res://scripts/sim/execute_cultivation.gd")
const ExecuteLife = preload("res://scripts/sim/execute_life.gd")
const DeliberationCultivation = preload("res://scripts/agents/deliberation_cultivation.gd")
const PlansNeeds = preload("res://scripts/agents/plan_library_needs.gd")
const Body = preload("res://scripts/sim/body.gd")
const Tribulations = preload("res://scripts/sim/tribulations.gd")
const Renovations = preload("res://scripts/sim/renovations.gd")

const DESIGNS: Dictionary = {
	"scripture_pavilion": "library", "seclusion_cell": "meditation_room", "thunder_chamber": "tribulation_chamber",
	"house_of_healing": "infirmary", "jade_array": "spirit_array", "mountain_gate": "sect_gate",
	"hall_of_ancestors": "ancestral_hall", "precept_stele": "precept_stele", "bell_pavilion": "bell_tower",
	"lecture_hall": "lecture_hall", "tiled_meditation_hall": "meditation_hall", "disciples_lodge": "dwelling",
}


static func _seat(agent: RefCounted, cell: Vector3i) -> void:
	agent.cell = cell
	agent.position = Movement.center(cell)
	agent.previous_position = agent.position


static func _structure(sim: RefCounted, function: String) -> Dictionary:
	for entry in sim.structures.built():
		if entry.functions.has(function):
			return entry
	return {}


static func _cultivator(agent: RefCounted, realm: int) -> void:
	agent.cultivation = CultivationState.fresh(0.6, "none", 0.9)
	agent.cultivation.realm = realm
	agent.cultivation.techniques = ["tree_breath"]


static func _sit(sim: RefCounted, agent: RefCounted, cell: Vector3i, ticks: int) -> float:
	_seat(agent, cell)
	agent.cultivation.progress = 0.0
	agent.step_result = {}
	for i in range(ticks):
		ExecuteCultivation._cultivate(sim, agent, {"ticks": ticks + 10}, i)
	return float(agent.cultivation.progress) / sim.qi.density(sim, cell)


## Stamps a design with its corner at `origin` (no site rules).
static func _place(sim: RefCounted, id: String, origin: Vector3i) -> void:
	var template: RefCounted = Template.from_starter(Data.starter(id))
	var batch: Array = []
	for entry in template.placement(0):
		batch.append([origin + entry[0], entry[1], entry[2]])
	sim.set_blocks(batch, "test")


static func _outside(sim: RefCounted, entry: Dictionary) -> Vector3i:
	for distance in [7, 9, 11]:
		for offset in [Vector3i(0, 0, -distance), Vector3i(distance, 0, 0), Vector3i(0, 0, distance), Vector3i(-distance, 0, 0)]:
			var cell: Vector3i = sim.nav.nearest_walkable(entry.anchor + offset, 2)
			if cell.x >= 0 and sim.structures.containing(cell).is_empty():
				return cell
	return Vector3i(-1, -1, -1)


## Every new design is recognised as what it was drawn for.
func check_the_hall_designs_have_their_functions():
	for id in DESIGNS:
		var template: RefCounted = Template.from_starter(Data.starter(id))
		if not template.functions.has(DESIGNS[id]):
			return "%s gives %s, not %s" % [id, str(template.functions), DESIGNS[id]]
	return ""


## One of the refined sits faster on a meditation room's mat; a mortal does
## not; a second mat makes the room a hall instead.
func check_a_meditation_room_secludes_the_refined():
	var sim: RefCounted = Sim.create(11)
	if Build.stamp(sim, 1, "seclusion_cell").x < 0:
		return "no site for a seclusion cell"
	var room: Dictionary = _structure(sim, "meditation_room")
	if room.is_empty():
		return "the stamped cell is not a meditation room"
	var mat: Vector3i = room.components.mat[0]
	var out: Vector3i = _outside(sim, room)
	var agent: RefCounted = sim.agents[0]
	agent.settlement_id = 1
	_cultivator(agent, 1)
	var factor: float = _sit(sim, agent, mat, 60) / maxf(_sit(sim, agent, out, 60), 0.0001)
	if absf(factor - Balance.number("halls.seclusion_factor")) > 0.05:
		return "seclusion helped %.2f, not %.2f" % [factor, Balance.number("halls.seclusion_factor")]
	_seat(agent, out)
	if SectHalls.room_mat(sim, agent) != mat:
		return "the refined cultivator does not look to the room's mat"
	_cultivator(agent, 0)
	factor = _sit(sim, agent, mat, 60) / maxf(_sit(sim, agent, out, 60), 0.0001)
	if absf(factor - 1.0) > 0.05:
		return "a mortal was helped %.2f by seclusion" % factor
	for cell in room.inside:
		if cell != mat and sim.nav.is_walkable(cell) and sim.voxels.get_block(cell) == 0:
			sim.set_block(cell, Registry.id("meditation_mat"), 0, "test")
			break
	var changed: Dictionary = sim.structures.containing(mat)
	if changed.functions.has("meditation_room") or not changed.functions.has("meditation_hall"):
		return "two mats gave %s" % str(changed.functions)
	return ""


## A trial in a tribulation chamber is in sanctuary, gentler by the chamber's
## amount, its strikes all go to the spire and nothing is scorched.
func check_a_chamber_gentles_the_storm():
	var sim: RefCounted = Sim.create(11)
	if Build.stamp(sim, 1, "thunder_chamber").x < 0:
		return "no site for a thunder chamber"
	var chamber: Dictionary = _structure(sim, "tribulation_chamber")
	if chamber.is_empty():
		return "the stamped chamber is not a tribulation chamber"
	var agent: RefCounted = sim.agents[0]
	agent.settlement_id = 1
	_cultivator(agent, 1)
	agent.cultivation.progress = CultivationState.needed(agent.cultivation)
	agent.cultivation.foundation = 0.6
	var site: Vector3i = DeliberationCultivation.trial_site(sim, agent)
	if SectHalls.chamber_at(sim, site).is_empty():
		return "the cultivator would not face Heaven in the chamber (%s)" % site
	_seat(agent, site)
	if not Tribulations.in_sanctuary(sim, site):
		return "the chamber is not counted as sanctuary"
	var before: Dictionary = {}
	for dz in range(-12, 13):
		for dx in range(-12, 13):
			for dy in range(-6, 8):
				before[site + Vector3i(dx, dy, dz)] = sim.voxels.get_block(site + Vector3i(dx, dy, dz))
	var id: int = sim.tribulations.announce(sim, agent, site)
	var trial: Dictionary = sim.tribulations.entries[id]
	var announced: float = float(trial.severity)
	trial.start_tick = sim.calendar.tick + 1
	for i in range(trial.strikes.size()):
		trial.strikes[i] = sim.calendar.tick + 2 + i * 3
	trial.end_tick = sim.calendar.tick + 4 + trial.strikes.size() * 3
	for _i in range(trial.strikes.size() * 3 + 6):
		sim.tribulations.step(sim)
		sim.calendar.tick += 1
	var expected: float = maxf(announced - Balance.number("halls.chamber_severity"), 0.05)
	if absf(float(trial.severity) - expected) > 0.001:
		return "severity %.2f, expected %.2f" % [trial.severity, expected]
	if int(trial.scorched) > 0 or int(trial.get("drawn", 0)) != trial.strikes.size():
		return "%d of %d strikes went to the spire, %d scorched" % [int(trial.get("drawn", 0)), trial.strikes.size(), trial.scorched]
	for cell in before:
		if sim.voxels.get_block(cell) != before[cell]:
			return "lightning changed %s" % cell
	return ""


## Resting in an infirmary heals faster and mends a cracked foundation;
## resting elsewhere does neither. The hurt choose it, and a cracked
## cultivator goes there to convalesce.
func check_an_infirmary_mends_a_cracked_foundation():
	var sim: RefCounted = Sim.create(11)
	if Build.stamp(sim, 1, "house_of_healing").x < 0:
		return "no site for a house of healing"
	var infirmary: Dictionary = _structure(sim, "infirmary")
	if infirmary.is_empty():
		return "the stamped house is not an infirmary"
	var agent: RefCounted = sim.agents[0]
	agent.settlement_id = 1
	_cultivator(agent, 1)
	var results: Array = []
	for inside in [true, false]:
		agent.cultivation["sound_foundation"] = 0.6
		agent.cultivation.foundation = 0.35
		agent.health.hp = 40.0
		var cell: Vector3i = infirmary.inside.keys().filter(func(c: Vector3i) -> bool: return sim.nav.is_walkable(c))[0] if inside else _outside(sim, infirmary)
		_seat(agent, cell)
		agent.inside = int(infirmary.id) if inside else -1
		agent.activity = "recovering"
		agent.needs[0] = 100.0
		for _i in range(sim.calendar.ticks_per_day):
			Body._health(sim, agent)
		results.append([float(agent.cultivation.foundation), float(agent.health.hp)])
	if results[0][0] <= 0.35 + Balance.number("halls.foundation_mend") * 0.9 or results[1][0] > 0.35:
		return "foundation after a day: %.3f inside, %.3f outside" % [results[0][0], results[1][0]]
	if results[0][1] - 40.0 < (results[1][1] - 40.0) * 1.4:
		return "healing inside %.1f, outside %.1f" % [results[0][1] - 40.0, results[1][1] - 40.0]
	var plans: Array = PlansNeeds.care(sim, agent)
	if plans.is_empty() or str(plans[0].id) != "infirmary_rest":
		return "the hurt would not rest in the infirmary"
	var out: Array = []
	sim.calendar.tick = sim.calendar.ticks_per_day + sim.calendar.ticks_per_hour() * 11
	DeliberationCultivation._convalesce(sim, agent, out)
	if out.is_empty():
		return "a cracked cultivator does not think of the infirmary"
	return ""


## Qi round a spirit-gathering array far from the tree is as dense as the
## array holds; the settlement's cultivators count it as a place to sit.
func check_an_array_gathers_qi():
	var sim: RefCounted = Sim.create(11)
	var tree: Vector3i = sim.features.sacred_tree
	var far: Vector3i = Vector3i(-1, -1, -1)
	for distance in [40, 36, 32, 28]:
		for offset in [Vector3i(distance, 0, 0), Vector3i(-distance, 0, 0), Vector3i(0, 0, distance), Vector3i(0, 0, -distance)]:
			var cell: Vector3i = sim.nav.nearest_walkable(tree + offset, 4)
			if far.x < 0 and cell.x >= 0 and sim.qi.density(sim, cell) < 0.4:
				far = cell
	if far.x < 0:
		return "no thin-qi ground to test on"
	var before: float = sim.qi.density(sim, far + Vector3i(2, 0, 2))
	_place(sim, "jade_array", far)
	if _structure(sim, "spirit_array").is_empty():
		return "the placed array is not a spirit-gathering array"
	var after: float = sim.qi.density(sim, far + Vector3i(2, 0, 2))
	if absf(after - Balance.number("halls.array_qi")) > 0.001:
		return "qi at the array went from %.2f to %.2f" % [before, after]
	return ""


## A mountain gate draws seekers and joiners; an ancestral hall's tablets keep
## more relics and their help at home; a stele slows doctrine's drift.
func check_gate_ancestors_and_stele():
	var sim: RefCounted = Sim.create(11)
	if SectHalls.seek_factor(sim, 1) != 1.0 or SectHalls.join_factor(sim, 1) != 1.0 or SectHalls.drift_factor(sim, 1) != 1.0:
		return "help before anything is built"
	for id in ["mountain_gate", "hall_of_ancestors", "precept_stele"]:
		if Build.stamp(sim, 1, id).x < 0:
			return "no site for " + id
	if SectHalls.seek_factor(sim, 1) != Balance.number("halls.gate_seekers") or SectHalls.join_factor(sim, 1) != Balance.number("halls.gate_join"):
		return "the gate does not draw seekers"
	if SectHalls.drift_factor(sim, 1) != Balance.number("halls.stele_drift"):
		return "the stele does not steady doctrine"
	if SectHalls.relic_extra(sim, 1) != 2:
		return "the hall's tablets keep %d relics, not 2" % SectHalls.relic_extra(sim, 1)
	var agent: RefCounted = sim.agents[0]
	agent.settlement_id = 1
	var home: Vector3i = sim.settlements.entries[1].center
	if not SectHalls.relics_help(sim, agent, home, false):
		return "the relics do not help at home"
	for i in range(8):
		sim.tree_growth.relics.append({"name": "old %d" % i, "realm": 2, "tick": 0})
	var most: float = Balance.number("cultivation.relics_most") * Balance.number("cultivation.relic_preparation")
	if sim.tree_growth.relic_preparation(SectHalls.relic_extra(sim, 1)) <= most + 0.001:
		return "the tablets keep no more relics' help"
	return ""


## A bell rings when a wolf comes near: everyone living there knows of it.
func check_a_bell_warns_everyone():
	var sim: RefCounted = Sim.create(11)
	var camp: Vector3i = sim.settlements.entries[1].camp
	for i in range(4):
		var cell: Vector3i = sim.nav.nearest_walkable(camp + Vector3i(i * 2 - 3, 0, 3), 4)
		sim.agents[i].settlement_id = 1
		_seat(sim.agents[i], cell)
		if not sim.settlements.entries[1].residents.has(i):
			sim.settlements.entries[1].residents.append(i)
	if Build.stamp(sim, 1, "bell_pavilion").x < 0:
		return "no site for a bell pavilion"
	var bell: Dictionary = _structure(sim, "bell_tower")
	if bell.is_empty():
		return "the stamped pavilion is not a bell tower"
	var at: Vector3i = sim.nav.nearest_walkable(bell.anchor + Vector3i(20, 0, 0), 6)
	var wolf: int = sim.threats.spawn("wolf", at)
	sim.calendar.tick = (sim.calendar.tick / 10 + 1) * 10
	SectHalls.ring(sim)
	for i in range(4):
		var known: bool = sim.agents[i].beliefs.threats.any(func(t: Dictionary) -> bool: return int(t.id) == wolf)
		if not known:
			return "%s did not hear the bell" % sim.agents[i].full_name()
	if not sim.chronicle.since(0).any(func(e: Dictionary) -> bool: return e.kind == "bell_rang"):
		return "the bell is not in the chronicle"
	return ""


## A sect member who spends their leisure in a lecture hall moves on; the
## same leisure outside does not.
func check_a_lecture_hall_teaches_at_leisure():
	var valley: Dictionary = Meditation.valley(11)
	var sim: RefCounted = valley.sim
	if Build.stamp(sim, 1, "lecture_hall").x < 0:
		return "no site for a lecture hall"
	var hall: Dictionary = _structure(sim, "lecture_hall")
	var agent: RefCounted = sim.agents[int(valley.members[1])]
	if PlansNeeds.relax(sim, agent).is_empty() or str(PlansNeeds.relax(sim, agent)[0].id) != "attend_lecture":
		return "a sect member would not attend the lecture"
	var results: Array = []
	for inside in [true, false]:
		agent.cultivation.progress = 0.0
		agent.inside = int(hall.id) if inside else -1
		for i in range(sim.calendar.ticks_per_hour() * 2):
			ExecuteLife._relax(sim, agent, 1000, i)
			agent.inside = int(hall.id) if inside else -1
		results.append(float(agent.cultivation.progress))
	var expected: float = Balance.number("halls.lecture_per_hour") * 2.0
	if absf(results[0] - expected) > 0.1 or results[1] > 0.0:
		return "two hours' leisure: %.2f in the hall, %.2f outside (expected %.2f)" % [results[0], results[1], expected]
	return ""


## With a library the sect copies a living member's technique into its
## manuals, and a member who lacks it learns it from the page.
func check_a_library_keeps_and_teaches():
	var valley: Dictionary = Meditation.valley(11)
	var sim: RefCounted = valley.sim
	var sect: Dictionary = sim.sects.in_settlement(1)
	var learner: RefCounted = sim.agents[int(valley.members[3])]
	learner.cultivation.techniques = []
	sect.manuals = []
	for _i in range(10):
		sim.sects.daily(sim)
	if not sect.manuals.is_empty():
		return "manuals were copied without a library"
	if Build.stamp(sim, 1, "scripture_pavilion").x < 0:
		return "no site for a scripture pavilion"
	for _i in range(40):
		sim.sects.daily(sim)
		if learner.cultivation.techniques.has("tree_breath"):
			return ""
	return "after 40 days the library copied %s and the learner knows %s" % [str(sect.manuals), str(learner.cultivation.techniques)]


## A grown sect wants its halls for its own reasons; a disciple proposes none.
func check_a_grown_sect_wants_its_halls():
	var valley: Dictionary = Meditation.valley(11)
	var sim: RefCounted = valley.sim
	var sect: Dictionary = sim.sects.in_settlement(1)
	var have: Dictionary = {"meditation_hall": 1, "tribulation_ground": 1}
	var names: Callable = func() -> Array: return SectHallWants.all(sim, 1, have).map(func(w: Array) -> String: return str(w[0]))
	var start: Array = names.call()
	if not start.has("meditation_room"):
		return "four refined members want %s, not a meditation room" % str(start)
	sect.manuals = ["tree_breath"]
	var member: RefCounted = sim.agents[int(valley.members[2])]
	member.cultivation["sound_foundation"] = 0.6
	member.cultivation.foundation = 0.3
	member.cultivation.trials.append({"tick": 0, "kind": "lightning", "outcome": "injured"})
	sect["mourned"] = 1
	var later: Array = names.call()
	for wanted in ["library", "infirmary", "tribulation_chamber", "ancestral_hall"]:
		if not later.has(wanted):
			return "the sect wants %s, not %s" % [str(later), wanted]
	var disciple: RefCounted = sim.agents[int(valley.members[1])]
	if str(sect.members.get(disciple.id, "")) == "disciple" and SectHallWants.all(sim, 1, have, disciple).size() > 0:
		return "a disciple proposes the sect's halls"
	return ""


## A village hall takes a lectern and two benches and becomes a lecture hall
## too; a meditation hall takes tablets and incense and becomes an ancestral
## hall; a
## lone bed cannot become an infirmary. The added blocks leave the floor open.
func check_old_buildings_take_new_uses():
	var sim: RefCounted = Sim.create(11)
	for pair in [["village_hall", "lecture_hall", "hall"], ["meditation_hall", "ancestral_hall", "meditation_hall"]]:
		if Build.stamp(sim, 1, pair[0]).x < 0:
			return "no site for " + pair[0]
		var option: Dictionary = Renovations.option(sim, 1, pair[1])
		if option.is_empty():
			return "no renovation would make a %s" % pair[1]
		for entry in option.order:
			sim.set_block(entry[0], entry[1], entry[2], "test")
		var changed: Dictionary = sim.structures.containing(option.order[0][0])
		if not changed.functions.has(pair[1]) or not changed.functions.has(pair[2]):
			return "the %s became %s" % [pair[0], str(changed.functions)]
		var floor: Array = changed.inside.keys().filter(func(c: Vector3i) -> bool: return sim.nav.is_walkable(c))
		for cell in floor:
			if cell != floor[0] and sim.nav.find_path(floor[0], cell).is_empty():
				return "the renovated %s has floor nobody can reach (%s)" % [pair[0], cell]
		if not Renovations.option(sim, 1, pair[1]).is_empty():
			return "a %s is offered again where one stands" % pair[1]
	if Build.stamp(sim, 1, "lean_to").x >= 0 and Build.stamp(sim, 1, "timber_cottage").x >= 0:
		var option: Dictionary = Renovations.option(sim, 1, "infirmary")
		if option.is_empty():
			return "the two-bed cottage would not take a medicine cabinet"
	return ""


## Exit (plan M19b): on seed 11 a sect offered the designs raises at least
## five of the new halls by its own proposals within 40 days, and turns at
## least one older building to a new use.
func long_check_the_sect_raises_its_halls():
	var valley: Dictionary = Meditation.valley(11)
	var sim: RefCounted = valley.sim
	for id in ["meditation_hall", "trial_ground"] + DESIGNS.keys():
		sim.apply_command({"type": "offer_template", "template": Template.from_starter(Data.starter(id)).to_dict()})
	Build.stamp(sim, 1, "village_hall")
	var start: int = sim.calendar.tick
	var halls: Array = ["library", "meditation_room", "tribulation_chamber", "infirmary", "spirit_array", "sect_gate",
		"ancestral_hall", "precept_stele", "bell_tower", "lecture_hall"]
	for day in range(40):
		sim.run_ticks(sim.calendar.ticks_per_day)
		# Heaven throws one of them down early on, so the sect has its reasons.
		if day == 2:
			var hurt: RefCounted = sim.agents[int(valley.members[1])]
			hurt.cultivation.trials.append({"tick": sim.calendar.tick, "kind": "lightning", "outcome": "injured"})
			hurt.cultivation["sound_foundation"] = float(hurt.cultivation.foundation)
			hurt.cultivation.foundation = maxf(float(hurt.cultivation.foundation) - 0.25, 0.05)
		var standing: Array = _standing(sim, halls)
		var renovated: bool = sim.chronicle.since(start).any(func(e: Dictionary) -> bool: return e.kind == "renovated")
		if standing.size() >= 5 and renovated:
			print("      day %d: %s stand, and a renovation" % [day, str(standing)])
			return ""
	var marked: Array = sim.chronicle.since(start).filter(func(e: Dictionary) -> bool: return e.kind in ["site_marked", "built", "renovated"]) \
		.map(func(e: Dictionary) -> String: return "%s %s" % [e.kind, str(e.args.get("design", e.args.get("to", "")))])
	return "after 40 days %s stand; %s" % [str(_standing(sim, halls)), str(marked)]


static func _standing(sim: RefCounted, functions: Array) -> Array:
	var result: Array = []
	for function in functions:
		if not _structure(sim, function).is_empty():
			result.append(function)
	return result
