extends RefCounted
## M15 Qi and cultivators: the tree's qi field, cultivators' state through
## saves, cultivation against hunger, teaching, sects and following.
const Sim = preload("res://scripts/sim/sim.gd")
const SimState = preload("res://scripts/sim/sim_state.gd")
const Qi = preload("res://scripts/sim/qi.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")


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
