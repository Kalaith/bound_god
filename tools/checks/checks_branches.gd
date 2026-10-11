extends RefCounted
## M21 Branches and sacred sites: the spirit cutting as a shrine and a qi
## source, elders founding branches on free grounds and their followers,
## transfer cost and cooldown, worn routes, schools, schisms and relics.
const Sim = preload("res://scripts/sim/sim.gd")
const Balance = preload("res://scripts/core/balance.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Meditation = preload("res://tools/checks/meditation.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const Branches = preload("res://scripts/sim/branches.gd")
const Schools = preload("res://scripts/sim/schools.gd")
const Relics = preload("res://scripts/sim/relics.gd")
const Miracles = preload("res://scripts/sim/miracles.gd")
const EffectsApply = preload("res://scripts/sim/effects_apply.gd")
const Movement = preload("res://scripts/sim/movement.gd")
const Lifecycle = preload("res://scripts/sim/lifecycle.gd")
const FaithPeople = preload("res://scripts/sim/faith_people.gd")
const SimState = preload("res://scripts/sim/sim_state.gd")
const AbstractWorld = preload("res://scripts/sim/abstract/abstract_world.gd")
const Goals = preload("res://scripts/agents/goals.gd")

const NONE := Vector3i(-1, -1, -1)


## Seed 11's valley with a sect grown to `count` members, two of them elders
## of Foundation Establishment, the sect old enough to send out a branch.
static func _sect(count: int) -> Dictionary:
	var valley: Dictionary = Meditation.valley(11)
	var sim: RefCounted = valley.sim
	var sect: Dictionary = sim.sects.in_settlement(1)
	var members: Array = valley.members.duplicate()
	for agent in sim.agents:
		if members.size() >= count:
			break
		if agent.is_present() and agent.settlement_id == 1 and not members.has(agent.id) and not agent.is_child:
			agent.cultivation = CultivationState.fresh(0.5, "none", 0.6)
			agent.cultivation.realm = 1
			agent.cultivation.techniques = ["tree_breath"]
			sim.sects.join(sect, agent, "disciple")
			members.append(agent.id)
	var elders: Array = []
	for id in [members[1], members[2]]:
		var elder: RefCounted = sim.agents[id]
		elder.cultivation.realm = 2
		elder.joined_day = -20
		elders.append(id)
	sect.founded_tick = sim.calendar.tick - sim.calendar.ticks_for_days(50.0)
	sim.sects.daily(sim)
	return {"sim": sim, "sect": sect, "members": members, "elders": elders}


## An elder arrives at a ground carrying a log and settles there as a
## branch's founder.
static func _found(sim: RefCounted, agent: RefCounted, ground: int) -> int:
	agent.carrying = {"resource": "wood", "amount": 1.0}
	var camp: Vector3i = sim.nav.nearest_walkable(sim.features.grounds[ground].center, 4)
	agent.cell = camp
	agent.position = Movement.center(camp)
	EffectsApply._settle(sim, agent, ground, Branches.Cause.CROWDED)
	return sim.settlements.on_ground(ground)


func check_a_cutting_is_a_shrine_and_a_qi_source():
	var sim: RefCounted = Sim.create(11)
	var ground: Vector3i = sim.features.grounds[0].center
	var spot: Vector3i = Branches.cutting_spot(sim, sim.nav.nearest_walkable(ground, 4))
	if spot.x < 0:
		return "no spot for a cutting on the first ground"
	var before: float = sim.qi.density(sim, spot)
	sim.set_block(spot, Registry.id("spirit_cutting"), 0, "npc:0")
	var shrine: Dictionary = sim.faith.get_shrine(int(sim.faith.by_cell.get(spot, -1)))
	if shrine.is_empty() or shrine.kind != "cutting" or shrine.state != "dormant":
		return "the cutting raised no dormant cutting shrine (%s)" % str(shrine)
	var near: float = sim.qi.density(sim, spot + Vector3i(2, 0, 0))
	var far: float = sim.qi.density(sim, spot + Vector3i(25, 0, 0))
	if near < 0.7 or before > 0.2 or far >= near:
		return "qi by the cutting %.2f (before %.2f, 25 away %.2f)" % [near, before, far]
	sim.set_block(spot, 0, 0, "npc:0")
	if shrine.state != "fallen" or sim.qi.density(sim, spot + Vector3i(2, 0, 0)) > 0.2:
		return "a torn-up cutting left the shrine %s and qi %.2f" % [shrine.state, sim.qi.density(sim, spot + Vector3i(2, 0, 0))]
	return ""


func check_an_elder_weighs_founding_a_branch():
	var valley: Dictionary = _sect(10)
	var sim: RefCounted = valley.sim
	var elder: RefCounted = sim.agents[int(valley.elders[0])]
	sim.calendar.tick = (sim.calendar.tick / sim.calendar.ticks_per_day) * sim.calendar.ticks_per_day + sim.calendar.ticks_per_hour() * 10
	var want: Dictionary = Branches.founding(sim, elder)
	if want.is_empty() or int(want.cause) != Branches.Cause.CROWDED:
		return "an elder of a crowded sect does not want a branch (%s)" % str(want)
	if not Branches.founding(sim, sim.agents[int(valley.members[4])]).is_empty():
		return "a disciple wants to found a branch"
	if not Branches.founding(sim, sim.agents[int(valley.sect.master)]).is_empty():
		return "the master wants to found a branch"
	valley.sect.founded_tick = sim.calendar.tick
	if not Branches.founding(sim, elder).is_empty():
		return "an elder of a young sect wants a branch"
	valley.sect.founded_tick = sim.calendar.tick - sim.calendar.ticks_for_days(50.0)
	# Not crowded and not ambitious: no branch.
	for id in valley.members.slice(9):
		valley.sect.members.erase(id)
	elder.personality.leadership = -0.5
	elder.cultivation.drive = 0.2
	if not Branches.founding(sim, elder).is_empty():
		return "a content elder of a small sect wants a branch"
	elder.personality.leadership = 0.9
	elder.cultivation.drive = 0.9
	want = Branches.founding(sim, elder)
	if want.is_empty() or int(want.cause) != Branches.Cause.AMBITION:
		return "an ambitious elder does not want a branch (%s)" % str(want)
	# Every ground taken: nowhere to go.
	for index in range(sim.features.grounds.size()):
		var id: int = sim.settlements.create("x", sim.features.grounds[index].center, sim.features.grounds[index].center, sim.calendar.tick)
		sim.settlements.entries[id]["ground"] = index
		sim.settlements.join(sim.agents[int(valley.members[4 + index])], id)
	if not Branches.founding(sim, elder).is_empty():
		return "an elder wants a branch with no free ground"
	return ""


func check_settling_founds_a_branch_and_followers_join_it():
	var valley: Dictionary = _sect(10)
	var sim: RefCounted = valley.sim
	var founder: RefCounted = sim.agents[int(valley.elders[0])]
	var parent: Dictionary = valley.sect
	var place: int = _found(sim, founder, 0)
	if place < 0:
		return "the founder did not settle the ground"
	var branch: Dictionary = sim.sects.in_settlement(place)
	if branch.is_empty() or int(branch.get("parent", -1)) != int(parent.id) or int(branch.master) != founder.id:
		return "no branch sect with its parent and founder (%s)" % str(branch)
	if parent.members.has(founder.id) or int(founder.cultivation.sect_id) != int(branch.id):
		return "the founder still belongs to the parent sect"
	var cutting: Dictionary = Branches.cutting_of(sim, place)
	if cutting.is_empty() or int(founder.faith.shrine_id) != int(cutting.id) and founder.faith.knows:
		return "no cutting at the branch, or the founder does not pray there"
	if not sim.chronicle.entries.any(func(e: Dictionary) -> bool: return e.kind == "branch_founded" and str(e.cause) == "cause_branch_crowded"):
		return "the founding was not chronicled with its cause"
	if not sim.sects.name_of(branch).contains("Branch"):
		return "the branch is named %s" % sim.sects.name_of(branch)
	var follower: RefCounted = sim.agents[int(valley.members[4])]
	follower.cultivation.teacher = founder.id
	sim.calendar.tick = (sim.calendar.tick / sim.calendar.ticks_per_day) * sim.calendar.ticks_per_day + sim.calendar.ticks_per_hour() * 10
	var want: Dictionary = Branches.following(sim, follower)
	if want.is_empty() or int(want.ground) != 0:
		return "a student does not want to follow their teacher's branch (%s)" % str(want)
	follower.cell = founder.cell
	EffectsApply._settle(sim, follower, 0, Branches.Cause.AMBITION)
	if not branch.members.has(follower.id) or parent.members.has(follower.id):
		return "the follower did not move to the branch"
	return ""


func check_a_transfer_costs_favour_and_waits():
	var sim: RefCounted = Sim.create(11)
	var ridge: int = -1
	for id in sim.faith.ids():
		if sim.faith.shrines[id].kind == "altar":
			ridge = id
	sim.faith.shrines[ridge].state = "active"
	var tree: Dictionary = sim.faith.current(sim)
	tree.favour = 3.0
	if Miracles.transfer_refusal(sim, ridge) != "transfer_favour":
		return "a poor shrine let the god leave (%s)" % Miracles.transfer_refusal(sim, ridge)
	tree.favour = 30.0
	var result: Dictionary = sim.apply_command({"type": "transfer_shrine", "shrine": ridge})
	if not result.ok or absf(float(tree.favour) - (30.0 - Balance.number("shrines.transfer_cost"))) > 0.01:
		return "the transfer did not cost its Favour (%s, favour %.1f)" % [str(result), float(tree.favour)]
	sim.faith.shrines[ridge].favour = 50.0
	result = sim.apply_command({"type": "transfer_shrine", "shrine": int(tree.id)})
	if result.ok or str(result.reason) != "transfer_cooldown":
		return "the god went straight back (%s)" % str(result)
	# The cooldown passes.
	sim.god.last_transfer_tick -= Miracles.transfer_cooldown_ticks(sim)
	result = sim.apply_command({"type": "transfer_shrine", "shrine": int(tree.id)})
	if not result.ok:
		return "after the cooldown the god could not go back (%s)" % str(result)
	return ""


func check_a_route_between_linked_settlements_wears_into_path():
	var valley: Dictionary = _sect(10)
	var sim: RefCounted = valley.sim
	var place: int = _found(sim, sim.agents[int(valley.elders[0])], 0)
	var key: String = "%d:%d" % [mini(1, place), maxi(1, place)]
	if not sim.routes.links(sim).has(key):
		return "the branch and its parent are not linked (%s)" % str(sim.routes.links(sim))
	for day in range(8):
		sim.routes.daily(sim)
		sim.paths.daily(sim)
	var route: Dictionary = sim.routes.routes.get(key, {})
	if route.is_empty() or route.cells.size() < 20:
		return "no route was found (%s)" % str(route.get("cells", []).size())
	var path: int = Registry.id("path")
	var worn: int = 0
	for column in route.cells:
		var top: int = sim.voxels.top_solid_y(column.x, column.y)
		if sim.voxels.get_xyz(column.x, top, column.y) == path:
			worn += 1
	if worn < route.cells.size() / 2:
		return "only %d of %d route columns turned to path" % [worn, route.cells.size()]
	if not sim.chronicle.entries.any(func(e: Dictionary) -> bool: return e.kind == "route_worn"):
		return "the worn route was not chronicled"
	return ""


func check_a_branch_takes_a_school_and_loses_it():
	var valley: Dictionary = _sect(10)
	var sim: RefCounted = valley.sim
	var founder: RefCounted = sim.agents[int(valley.elders[0])]
	var branch: Dictionary = sim.sects.in_settlement(_found(sim, founder, 0))
	branch.doctrine.mercy = 0.9
	for day in range(Balance.integer("branches.school_days")):
		if str(branch.school) != "":
			return "a school came after %d days" % day
		Schools.daily(sim)
	if str(branch.school) != "healing" or Schools.heal_factor(sim, founder) <= 1.0:
		return "a merciful branch is %s (heal factor %.2f)" % [str(branch.school), Schools.heal_factor(sim, founder)]
	if Schools.heal_factor(sim, sim.agents[int(valley.sect.master)]) != 1.0:
		return "the parent sect heals as a healing school"
	branch.doctrine.mercy = 0.5
	Schools.daily(sim)
	if str(branch.school) != "":
		return "the school stayed after its mercy faded"
	if not sim.chronicle.entries.any(func(e: Dictionary) -> bool: return e.kind == "school_lost"):
		return "losing the school was not chronicled"
	return ""


func check_a_far_drifted_branch_breaks_away():
	var valley: Dictionary = _sect(10)
	var sim: RefCounted = valley.sim
	var founder: RefCounted = sim.agents[int(valley.elders[0])]
	var branch: Dictionary = sim.sects.in_settlement(_found(sim, founder, 0))
	branch.doctrine.martial = clampf(float(valley.sect.doctrine.martial) + 0.45, 0.0, 1.0)
	branch.doctrine.mercy = clampf(float(valley.sect.doctrine.mercy) - 0.45, 0.0, 1.0)
	branch.doctrine.secrecy = clampf(float(valley.sect.doctrine.secrecy) + 0.3, 0.0, 1.0)
	founder.beliefs.relation(int(valley.sect.master)).opinion = 10.0
	Schools.daily(sim)
	if int(branch.parent) < 0:
		return "a branch broke away from a master its own thinks well of"
	founder.beliefs.relation(int(valley.sect.master)).opinion = -40.0
	Schools.daily(sim)
	if int(branch.parent) >= 0:
		return "a far-drifted branch with a grudge kept its parent (apart %.2f)" % Schools.distance(branch.doctrine, valley.sect.doctrine)
	if sim.routes.links(sim).has("1:%d" % int(branch.settlement_id)) and float(sim.routes.links(sim)["1:%d" % int(branch.settlement_id)]) >= Balance.number("routes.per_link"):
		return "the broken branch still carries a branch's traffic"
	return ""


func check_a_branch_relic_is_carried_home_when_its_shrine_falls():
	var valley: Dictionary = _sect(10)
	var sim: RefCounted = valley.sim
	var founder: RefCounted = sim.agents[int(valley.elders[0])]
	var place: int = _found(sim, founder, 0)
	var cutting: Dictionary = Branches.cutting_of(sim, place)
	var elder: RefCounted = sim.agents[int(valley.elders[1])]
	elder.cell = founder.cell
	EffectsApply._settle(sim, elder, 0, Branches.Cause.AMBITION)
	Lifecycle.die(sim, elder, "cause_old_age")
	var relics: Array = Relics.at(sim, int(cutting.id))
	if relics.size() != 1:
		return "the elder's relic was not laid at the branch's cutting (%d)" % relics.size()
	if Relics.branch_count(sim, cutting.cell + Vector3i(3, 0, 0)) != 1 or Relics.branch_count(sim, sim.features.sacred_tree) != 0:
		return "the branch relic does not steady trials by its shrine alone"
	sim.set_block(cutting.cell, 0, 0, "raid:1")
	Relics.daily(sim)
	if Relics.ruins(sim) != [int(cutting.id)]:
		return "the fallen cutting's relics are not lying in its ruins"
	var bearer: RefCounted = sim.agents[int(valley.sect.master)]
	bearer.faith.knows = true
	FaithPeople.gain(bearer, 80.0)
	sim.calendar.tick = (sim.calendar.tick / sim.calendar.ticks_per_day) * sim.calendar.ticks_per_day + sim.calendar.ticks_per_hour() * 10
	if not Relics.recovery(sim, bearer).is_empty():
		return "someone who never knew the place wants its relics"
	bearer.beliefs.places["shrine:%d" % int(cutting.id)] = {"kind": "shrine", "id": int(cutting.id), "cell": cutting.cell, "state": "fallen", "seen_tick": 0}
	var want: Dictionary = Relics.recovery(sim, bearer)
	if want.is_empty() or int(want.from) != int(cutting.id):
		return "a believer who knows the ruin does not want its relics (%s)" % str(want)
	Relics.take(sim, bearer, int(want.from))
	Relics.lay(sim, bearer, int(want.to))
	if Relics.at(sim, Relics.tree_shrine(sim)).size() != 1 or not Relics.ruins(sim).is_empty():
		return "the relic did not reach the tree"
	return ""


func check_branches_are_founded_while_abstract():
	var valley: Dictionary = _sect(12)
	var sim: RefCounted = valley.sim
	var model: RefCounted = AbstractWorld.begin(sim)
	sim.meditating = true
	model.run_hours(sim, 24 * 20)
	model.finish(sim)
	sim.meditating = false
	var branches: Array = Branches.living_branches(sim, int(valley.sect.id))
	if branches.is_empty():
		return "no branch in 20 abstract days"
	var branch: Dictionary = sim.sects.entries[branches[0]]
	if Branches.cutting_of(sim, int(branch.settlement_id)).is_empty():
		return "the abstract branch has no cutting"
	return ""


func check_branch_state_is_saved():
	var valley: Dictionary = _sect(10)
	var sim: RefCounted = valley.sim
	var founder: RefCounted = sim.agents[int(valley.elders[0])]
	_found(sim, founder, 0)
	sim.routes.daily(sim)
	sim.god.last_transfer_tick = sim.calendar.tick
	sim.run_ticks(sim.calendar.ticks_per_hour())
	var saved: Dictionary = SimState.capture(sim)
	var restored: RefCounted = SimState.restore(bytes_to_var(var_to_bytes(saved.sim)), bytes_to_var(var_to_bytes(saved.chunks)))
	if restored.sects.to_dict() != sim.sects.to_dict() or restored.routes.to_dict() != sim.routes.to_dict():
		return "branch sects or routes were not restored"
	if restored.god.last_transfer_tick != sim.god.last_transfer_tick:
		return "the last transfer was not restored"
	if restored.state_hash() != sim.state_hash():
		return "the restored world hashes differently"
	return ""


## Exit (plan M21): on seed 11 with a sect of ten that knows the god, within
## 60 days an elder founds a branch on a founding ground with a cutting shrine
## and a branch sect, someone follows, the route between them wears into
## path, the branch shrine wakes, and the god transfers there paying Favour
## and cannot transfer back before the cooldown.
func long_check_an_elder_founds_a_branch_the_god_can_reach():
	var valley: Dictionary = _sect(10)
	var sim: RefCounted = valley.sim
	for id in valley.members:
		sim.agents[id].faith.knows = true
		FaithPeople.gain(sim.agents[id], 75.0)
	var start: int = sim.calendar.tick
	var seen: Dictionary = {}
	for day in range(60):
		sim.run_ticks(sim.calendar.ticks_per_day)
		for entry in sim.chronicle.since(start):
			if entry.kind in ["branch_founded", "branch_joined", "route_worn"] and not seen.has(entry.kind):
				seen[entry.kind] = day
				print("      day %d: %s" % [day, entry.kind])
		var branches: Array = Branches.living_branches(sim, int(valley.sect.id))
		if branches.is_empty():
			continue
		var cutting: Dictionary = Branches.cutting_of(sim, int(sim.sects.entries[branches[0]].settlement_id))
		if day % 10 == 9 and not cutting.is_empty():
			var devotion: Array = []
			for id in sim.sects.entries[branches[0]].members:
				devotion.append(roundi(float(sim.agents[id].faith.devotion)))
			print("      day %d: cutting %s support %.2f, branch devotion %s" % [day, cutting.state, float(cutting.support), str(devotion)])
		if seen.has("branch_joined") and seen.has("route_worn") and not cutting.is_empty() and cutting.state == "active":
			var here: Dictionary = sim.faith.current(sim)
			var before: float = float(here.favour)
			var result: Dictionary = sim.apply_command({"type": "transfer_shrine", "shrine": int(cutting.id)})
			if not result.ok:
				return "the god could not go to the active branch shrine (%s, favour %.1f)" % [str(result), before]
			if float(here.favour) > before - Balance.number("shrines.transfer_cost") + 0.01:
				return "the journey cost nothing"
			if Miracles.transfer_refusal(sim, int(here.id)) != "transfer_cooldown":
				return "the god could go straight back (%s)" % Miracles.transfer_refusal(sim, int(here.id))
			print("      the god stepped through on day %d" % day)
			return ""
	return "after 60 days: %s; branches %s" % [str(seen), str(Branches.living_branches(sim, int(valley.sect.id)))]


## Exit, second half (plan M21): over 50 meditated years at least one branch
## is founded, and every branch holds, takes a school or breaks away, each
## change chronicled with its cause.
func long_check_branches_over_fifty_meditated_years():
	var valley: Dictionary = Meditation.valley(11)
	var sim: RefCounted = valley.sim
	var start: int = sim.calendar.tick
	var result: Dictionary = Meditation.meditate(sim, 50.0 * sim.calendar.days_per_season * 4)
	var counts: Dictionary = {}
	for entry in sim.chronicle.since(start):
		if entry.kind in ["branch_founded", "branch_joined", "school_taken", "school_lost", "schism", "route_worn", "relics_lost", "relics_carried", "relic_left_at"]:
			counts[entry.kind] = int(counts.get(entry.kind, 0)) + 1
			if str(entry.cause).is_empty():
				return "%s was chronicled without a cause" % entry.kind
	var standing: Array = []
	for id in sim.sects.ids():
		var sect: Dictionary = sim.sects.entries[id]
		if Branches.is_branch(sect):
			standing.append("%s:%d members, parent %d, school '%s'" % [sim.sects.name_of(sect), sect.members.size(), int(sect.get("parent", -1)), str(sect.get("school", ""))])
	print("      %s; standing %s; abstract %.1f s" % [str(counts), str(standing), result.abstract_ms / 1000.0])
	if int(counts.get("branch_founded", 0)) == 0:
		return "no branch was founded in 50 years"
	return ""
