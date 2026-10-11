extends RefCounted
## M15 Qi and cultivators: the tree's qi field, cultivators' state through
## saves, cultivation against hunger, teaching, sects and following.
const Sim = preload("res://scripts/sim/sim.gd")
const SimState = preload("res://scripts/sim/sim_state.gd")
const Qi = preload("res://scripts/sim/qi.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Deliberation = preload("res://scripts/agents/deliberation.gd")
const Generation = preload("res://scripts/agents/generation.gd")
const Population = preload("res://scripts/sim/population.gd")
const Lifecycle = preload("res://scripts/sim/lifecycle.gd")


## Qi is densest at the tree and thins with distance, never below its floor.
func check_qi_falls_off_with_distance():
	var sim: RefCounted = Sim.create(11)
	var tree: Vector3i = sim.features.sacred_tree
	var last: float = INF
	for distance in [0, 4, 10, 20, 35, 60, 80]:
		var here: float = sim.qi.density(sim, tree + Vector3i(distance, 0, 0))
		if here > last:
			return "qi rose from %.2f to %.2f at %d blocks" % [last, here, distance]
		last = here
	var hamlet: float = sim.qi.density(sim, sim.features.hamlet.center)
	if sim.qi.density(sim, tree) < 0.9 or hamlet > 0.15:
		return "qi at the tree %.2f, at the hamlet %.2f" % [sim.qi.density(sim, tree), hamlet]
	return ""


## A save from before cultivation (schema 4) loads with everyone given a
## spiritual root (the same on every load), plays on and saves as schema 5.
func check_the_fields_save_loads_through_migration():
	var file := FileAccess.open_compressed("res://tools/fixtures/save_v4_fields.zst", FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return "the fields fixture save is missing"
	var saved: Variant = bytes_to_var(file.get_buffer(file.get_length()))
	if not saved is Dictionary or int(saved.sim.get("schema_version", -1)) != 4:
		return "the fixture is not a schema 4 save"
	var problem: String = SimState.problem(saved.sim, saved.chunks)
	if not problem.is_empty():
		return "the fields save is refused: " + problem
	var first: RefCounted = SimState.restore(saved.sim.duplicate(true), saved.chunks)
	var second: RefCounted = SimState.restore(saved.sim.duplicate(true), saved.chunks)
	if first.present_count() != 16 or first.calendar.day() != 5:
		return "the fields save restored the wrong world: %d people on day %d" % [first.present_count(), first.calendar.day()]
	for agent in first.agents:
		if agent.cultivation.is_empty() or int(agent.cultivation.realm) != 0:
			return "%s came back without a mortal's cultivation" % agent.full_name()
		if not is_equal_approx(float(agent.cultivation.talent), float(second.agents[agent.id].cultivation.talent)):
			return "two loads gave %s different talent" % agent.full_name()
	first.run_ticks(first.calendar.ticks_per_day)
	if first.present_count() < 12:
		return "the migrated world lost its people within a day"
	var again: Dictionary = SimState.capture(first)
	if int(again.sim.schema_version) != SimState.SCHEMA or not again.sim.sects is Dictionary:
		return "the migrated world does not save in the current schema"
	return ""


static func _cultivator(agent: RefCounted, realm: int, techniques: Array) -> void:
	agent.cultivation = CultivationState.fresh(0.7, "none", 0.9)
	agent.cultivation.realm = realm
	agent.cultivation.techniques = techniques.duplicate()


## A fed cultivator would rather sit in the tree's qi than eat; a hungry
## one would rather eat. Cultivation is one want among the others.
func check_cultivation_competes_with_hunger():
	var sim: RefCounted = Sim.create(11)
	sim.run_ticks(60)
	var agent: RefCounted = sim.agents[0]
	_cultivator(agent, 1, [])
	agent.needs = PackedFloat32Array([85, 85, 85, 85, 85, 100])
	var fed: Dictionary = _utilities(sim, agent)
	agent.needs[Personality.Need.FOOD] = 12.0
	var hungry: Dictionary = _utilities(sim, agent)
	if float(fed.get(Goals.Kind.CULTIVATE, 0.0)) <= float(fed.get(Goals.Kind.EAT, 0.0)):
		return "a fed cultivator would rather eat (%s)" % str(fed)
	if float(hungry.get(Goals.Kind.EAT, 0.0)) <= float(hungry.get(Goals.Kind.CULTIVATE, 0.0)):
		return "a hungry cultivator would rather meditate (%s)" % str(hungry)
	return ""


static func _utilities(sim: RefCounted, agent: RefCounted) -> Dictionary:
	var result: Dictionary = {}
	for entry in Deliberation.candidates(sim, agent):
		var kind: int = int(entry.goal.kind)
		result[kind] = maxf(float(result.get(kind, 0.0)), float(entry.utility))
	return result


## A cultivator who knows the tree's technique teaches a willing student
## who asks: the technique passes, the lineage is kept, the chronicle says so.
func check_teaching_passes_a_technique():
	var sim: RefCounted = Sim.create(11)
	sim.run_ticks(30)
	var teacher: RefCounted = sim.agents[0]
	var student: RefCounted = sim.agents[1]
	_cultivator(teacher, 1, ["tree_breath"])
	student.cultivation.drive = 0.95
	student.beliefs.relation(teacher.id).opinion = 20.0
	teacher.beliefs.relation(student.id).opinion = 20.0
	for _i in range(sim.calendar.ticks_per_day * 2 / 10):
		sim.run_ticks(10)
		if student.cultivation.techniques.has("tree_breath"):
			break
	if not student.cultivation.techniques.has("tree_breath"):
		return "the student never learned: %s" % str(student.decisions.slice(0, 5))
	if int(student.cultivation.teacher) != teacher.id or not teacher.cultivation.students.has(student.id):
		return "the lineage was not kept"
	for entry in sim.chronicle.entries:
		if entry.kind == "taught" and entry.agents.has(student.id):
			return ""
	return "the teaching was not chronicled"


## A teacher with two students founds a sect by their own choice; the
## chronicle names the cause. When the master dies the most respected member
## succeeds, and that is chronicled too.
func check_a_sect_is_founded_and_succeeded():
	var sim: RefCounted = Sim.create(11)
	var camp: Vector3i = sim.settlements.entries[1].camp
	Population.arrive(sim, Generation.adult(sim.rng, sim.agents.size()), sim.nav.nearest_walkable(camp + Vector3i(1, 0, 2), 4), 1, "")
	sim.run_ticks(30)
	var founder: RefCounted = sim.agents[0]
	_cultivator(founder, 1, ["tree_breath"])
	founder.personality.leadership = 0.8
	for i in [1, sim.agents.size() - 1]:
		_cultivator(sim.agents[i], 0, ["tree_breath"])
		sim.agents[i].cultivation.teacher = founder.id
		founder.cultivation.students.append(sim.agents[i].id)
	for _i in range(sim.calendar.ticks_per_day * 2 / 10):
		sim.run_ticks(10)
		if not sim.sects.entries.is_empty():
			break
	if sim.sects.entries.is_empty():
		return "no sect was founded in two days: %s" % str(founder.decisions.slice(0, 5))
	var sect: Dictionary = sim.sects.entries.values()[0]
	if int(sect.master) != founder.id or sect.members.size() != 3:
		return "the sect has master %d and %d members" % [int(sect.master), sect.members.size()]
	var founded: bool = false
	for entry in sim.chronicle.entries:
		founded = founded or (entry.kind == "sect_founded" and str(entry.cause).begins_with("cause_sect_students"))
	if not founded:
		return "the founding was not chronicled with its cause"
	Lifecycle.die(sim, founder, "cause_wounds")
	sim.run_ticks(sim.calendar.ticks_per_day)
	if int(sect.master) == founder.id or not sect.members.has(int(sect.master)):
		return "nobody succeeded the dead master"
	for entry in sim.chronicle.entries:
		if entry.kind == "sect_master" and str(entry.cause) == "cause_master_gone":
			return ""
	return "the succession was not chronicled"


## Pinning a person changes what the god watches and nothing else: the same
## world with and without the pin plays out the same for everyone.
func long_check_following_grants_nothing():
	var plain: RefCounted = Sim.create(11)
	var pinned: RefCounted = Sim.create(11)
	if not pinned.apply_command({"type": "follow", "agent": 0}).ok or not pinned.god.followed.has(0):
		return "the pin was refused"
	for agent in [plain.agents[0], pinned.agents[0]]:
		_cultivator(agent, 0, [])
	plain.run_ticks(plain.calendar.ticks_per_day * 2)
	pinned.run_ticks(pinned.calendar.ticks_per_day * 2)
	if float(pinned.agents[0].cultivation.progress) > float(plain.agents[0].cultivation.progress):
		return "the pinned person advanced faster"
	for i in range(plain.agents.size()):
		if var_to_bytes(plain.agents[i].to_dict()) != var_to_bytes(pinned.agents[i].to_dict()):
			return "%s lived differently under the pin" % plain.agents[i].full_name()
	return ""
