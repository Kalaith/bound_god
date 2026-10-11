extends RefCounted
## M8 acceptance: prayer feeds Favour, miracles are interpreted, whispers are
## heard and logged, and shrines without support go quiet.
const Sim = preload("res://scripts/sim/sim.gd")
const Balance = preload("res://scripts/core/balance.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const FaithState = preload("res://scripts/agents/faith_state.gd")

const Need = Personality.Need


func _flat() -> RefCounted:
	return Sim.create(21, {"world": "flat", "size": Vector3i(48, 16, 48), "ground": 4})


func _believe(agent: RefCounted, devotion: float) -> void:
	agent.faith.knows = true
	agent.faith.saw_god = true
	agent.faith.devotion = devotion


func check_prayers_raise_favour():
	var sim: RefCounted = _flat()
	var shrine: Dictionary = sim.faith.current(sim)
	var before: float = float(shrine.favour)
	for agent in sim.agents:
		_believe(agent, 60.0)
		agent.needs[Need.FOOD] = 20.0
	sim.run_ticks(sim.calendar.ticks_per_day)
	if shrine.prayers.is_empty():
		return "no one prayed at the tree in a day"
	if float(shrine.favour) <= before:
		return "prayers did not raise Favour (%.1f -> %.1f)" % [before, shrine.favour]
	if str(shrine.prayers[0].intent.get("kind", "")).is_empty():
		return "a prayer carried no intent"
	return ""


func check_bless_growth_before_a_hungry_believer():
	var sim: RefCounted = _flat()
	var agent: RefCounted = sim.agents[0]
	_believe(agent, 45.0)
	agent.needs[Need.FOOD] = 30.0
	var bush: int = Registry.id("berry_bush")
	var cells: Array = []
	for i in range(3):
		var cell: Vector3i = agent.cell + Vector3i(3 + i, 0, 2)
		sim.set_block(cell, bush, 0, "test")
		cells.append(cell)
	sim.god.avatar_cell = agent.cell + Vector3i(1, 0, 1)
	var devotion: float = float(agent.faith.devotion)
	var harvest: float = agent.faith.aspects[FaithState.ASPECTS.find("harvest")]
	var result: Dictionary = sim.apply_command({"type": "cast_miracle", "miracle": "bless_growth", "cell": sim.god.avatar_cell})
	if not result.ok:
		return "Bless Growth was refused: " + str(result.reason)
	if sim.voxels.block_meta(cells[0]) <= 0:
		return "the bushes did not ripen"
	sim.run_ticks(4)
	if float(agent.faith.devotion) <= devotion:
		return "a hungry believer who saw Bless Growth gained no devotion"
	if agent.faith.aspects[FaithState.ASPECTS.find("harvest")] <= harvest:
		return "the harvest aspect did not rise"
	return ""


func check_bless_growth_sprouts_bushes_when_all_are_ripe():
	var sim: RefCounted = Sim.create(1)
	var shrine: Dictionary = sim.faith.current(sim)
	sim.god.avatar_cell = shrine.cell + Vector3i(3, 0, 0)
	var before: int = 0
	for id in sim.sites.ids_sorted():
		before += 1 if sim.sites.get_site(id).kind == "bush" else 0
	var result: Dictionary = sim.apply_command({"type": "cast_miracle", "miracle": "bless_growth", "cell": sim.god.avatar_cell})
	if not result.ok:
		return "Bless Growth among ripe bushes was refused: " + str(result.reason)
	var after: int = 0
	for id in sim.sites.ids_sorted():
		after += 1 if sim.sites.get_site(id).kind == "bush" else 0
	if after <= before:
		return "Bless Growth among ripe bushes sprouted none (%d -> %d)" % [before, after]
	return ""


func check_a_whisper_reaches_the_decision_log():
	var sim: RefCounted = _flat()
	var agent: RefCounted = sim.agents[0]
	_believe(agent, 70.0)
	var result: Dictionary = sim.apply_command({"type": "cast_miracle", "miracle": "whisper", "cell": agent.cell, "agent": agent.id, "nudge": "pray"})
	if not result.ok:
		return "the whisper was refused: " + str(result.reason)
	# A whisper lasts a day; whoever is in the middle of something may finish it first.
	var heard: bool = false
	var urged: bool = false
	for _i in range(24):
		sim.run_ticks(10)
		for entry in agent.decisions:
			heard = heard or (entry.kind == "message" and entry.text == "log_whispered")
			urged = urged or (entry.kind == "adopted" and entry.get("urged", false))
		if heard and urged:
			break
	if not heard:
		return "the whisper never reached the decision log: %s" % str(agent.decisions)
	if not urged:
		return "no adopted goal records the god's urging"
	return ""


func check_an_altar_without_support_sends_the_god_home_to_the_tree():
	var sim: RefCounted = _flat()
	var tree: int = sim.god.active_shrine_id
	var altar_cell: Vector3i = sim.features.sacred_tree + Vector3i(10, 0, 10)
	sim.set_block(altar_cell, Registry.id("altar"), 0, "test")
	var other: int = -1
	for id in sim.faith.ids():
		if id != tree:
			other = id
	if other < 0:
		return "placing an altar did not raise a shrine"
	sim.faith.shrines[other].state = "active"
	sim.god.active_shrine_id = other
	for agent in sim.agents:
		agent.faith.knows = false
		agent.faith.devotion = 0.0
	sim.run_ticks(sim.calendar.ticks_per_day * 4)
	if sim.faith.shrines[other].state != "dormant":
		return "the unsupported altar stayed %s" % sim.faith.shrines[other].state
	if sim.god.active_shrine_id != tree or sim.god.dormant:
		return "the god was not sent home to the tree"
	return ""


func check_the_tree_holds_a_small_circle_that_grows_with_support():
	var sim: RefCounted = _flat()
	var tree: Dictionary = sim.faith.current(sim)
	for agent in sim.agents:
		agent.faith.devotion = 0.0
	sim.run_ticks(sim.calendar.ticks_per_day * 8)
	if tree.state != "active" or sim.god.dormant:
		return "the tree went %s without prayers" % tree.state
	var small: float = sim.zone_radius()
	tree.support = 2.0
	var large: float = sim.zone_radius()
	if small > Balance.number("shrines.tree_min_radius") + 0.5 or large <= small + 4.0:
		return "the tree's reach did not follow its support (%.1f unsupported, %.1f supported)" % [small, large]
	return ""


## Prayers leave the god's feed after a few days, so a plea from long ago is
## not shown as if it were fresh.
func check_old_prayers_expire():
	var sim: RefCounted = _flat()
	var agent: RefCounted = sim.agents[0]
	_believe(agent, 60.0)
	var said: int = sim.calendar.tick
	sim.faith.record_prayer(sim, agent, 1, {"kind": "food", "level": 20.0})
	if sim.faith.feed[1].size() != 1:
		return "the prayer did not reach the feed"
	sim.run_ticks(sim.calendar.ticks_for_days(Balance.number("shrines.prayer_keep_days") - 1.0))
	var kept: bool = false
	for prayer in sim.faith.feed[1]:
		kept = kept or (int(prayer.agent) == agent.id and int(prayer.tick) == said)
	if not kept:
		return "a recent prayer was forgotten too soon"
	sim.run_ticks(sim.calendar.ticks_for_days(2.0))
	for prayer in sim.faith.feed[1] + sim.faith.shrines[1].prayers:
		if sim.calendar.tick - int(prayer.tick) > sim.calendar.ticks_for_days(Balance.number("shrines.prayer_keep_days") + 1.0):
			return "a prayer from day %d is still remembered on day %d" % [int(prayer.tick) / sim.calendar.ticks_per_day + 1, sim.calendar.day()]
	return ""
