extends RefCounted
## Debug-only capture of meditation: `meditation_summary` gives Tree Hollow
## a small sect, pins a disciple, meditates five years behind the veil and
## shoots "While you meditated…" when the valley returns.
const Data = preload("res://scripts/core/data.gd")
const Template = preload("res://scripts/building/template.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Generation = preload("res://scripts/agents/generation.gd")
const Population = preload("res://scripts/sim/population.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")

const DESIGNS: Array[String] = ["timber_cottage", "store_shed", "village_hall", "garden_patch", "field_plot", "granary", "cookhouse"]


static func arrange(main: Node3D, shot: Node, scenario: String) -> void:
	var sim: RefCounted = main.sim
	var camp: Vector3i = sim.settlements.entries[1].camp
	for i in range(8):
		Population.arrive(sim, Generation.adult(sim.rng, sim.agents.size()), sim.nav.nearest_walkable(camp + Vector3i(i % 4 - 2, 0, 2 + i / 4), 4), 1, "")
	for i in range(3):
		var cell: Vector3i = sim.nav.surface(camp.x + 3 + i, camp.z - 3)
		if cell.x >= 0 and sim.set_block(cell, Registry.id("storage_chest"), 0, "capture"):
			sim.settlements.chest_add(cell, "berries" if i == 0 else ("grain" if i == 1 else "wood"), 40)
	for id in DESIGNS:
		sim.apply_command({"type": "offer_template", "template": Template.from_starter(Data.starter(id)).to_dict()})
	var hollow: Array = []
	for agent in sim.agents:
		if agent.settlement_id == 1:
			hollow.append(agent)
	var master: RefCounted = hollow[0]
	master.cultivation = CultivationState.fresh(0.6, "wood", 0.5)
	master.cultivation.realm = 1
	master.cultivation.techniques = ["tree_breath"]
	for i in range(1, 4):
		hollow[i].cultivation = CultivationState.fresh(0.6, "none", 0.9)
		hollow[i].cultivation.realm = 1
		hollow[i].cultivation.techniques = ["tree_breath"]
		hollow[i].cultivation.teacher = master.id
		master.cultivation.students.append(hollow[i].id)
	sim.sects.found(sim, master)
	sim.apply_command({"type": "follow", "agent": hollow[1].id})
	sim.apply_command({"type": "protect", "agent": hollow[1].id, "mode": "shield", "limit": 60.0})
	main.driver.rest_finished.connect(func(_from: int) -> void:
		print("MEDITATION woke=%s day=%d people=%d" % [str(main.driver.wake_reason.get("kind", "")), sim.calendar.day(), sim.present_count()])
		shot.shoot_after(20), CONNECT_ONE_SHOT)
	main.meditate(5.0)
