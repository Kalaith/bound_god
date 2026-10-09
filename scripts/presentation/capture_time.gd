extends RefCounted
## Debug-only captures of time and history: `time_rest` offers a cottage,
## rests five days and shows "While you rested…"; `time_chronicle` opens the
## chronicle after ten days.
const Data = preload("res://scripts/core/data.gd")
const Template = preload("res://scripts/building/template.gd")


static func arrange(main: Node3D, shot: Node, scenario: String) -> void:
	var sim: RefCounted = main.sim
	if scenario == "time_loaded":
		print("TIME loaded day=%d people=%d hash=%d" % [sim.calendar.day(), sim.present_count(), sim.state_hash()])
		shot.shoot_after(30)
		return
	if scenario == "time_profile":
		sim.run_ticks(sim.calendar.ticks_per_day * 3)
		main.world_view.remesh_now()
		profile(main)
		shot.shoot_after(10)
		return
	sim.run_ticks(12)
	var design: Dictionary = Template.from_starter(Data.starter("miner_hut")).to_dict()
	design.id = "willow_cottage"
	design.name = "Willow Cottage"
	sim.apply_command({"type": "offer_template", "template": design})
	if scenario == "time_save":
		sim.run_ticks(sim.calendar.ticks_per_day * 2)
		main.world_io.slot = "verification_play"
		print("TIME saved=%s day=%d hash=%d" % [main.world_io.save(), sim.calendar.day(), sim.state_hash()])
		shot.shoot_after(5)
		return
	if scenario == "time_loaded":
		print("TIME loaded day=%d people=%d hash=%d" % [sim.calendar.day(), sim.present_count(), sim.state_hash()])
		shot.shoot_after(30)
		return
	if scenario == "time_chronicle":
		sim.run_ticks(sim.calendar.ticks_per_day * 10)
		main.chronicle_screen.open()
		shot.shoot_after(30)
		return
	main.rest_overlay.begin(5.0)
	main.driver.rest_finished.connect(func(_from: int) -> void: shot.shoot_after(20))


## Time each presentation node's per-frame work, called by hand.
static func profile(main: Node3D) -> void:
	var nodes: Dictionary = {"hud": main.hud, "agent_views": main.agent_views, "construction_view": main.construction_view,
		"faith": main.faith, "world_view": main.world_view, "builder": main.builder, "people": main.people, "world_io": main.world_io}
	for name in nodes:
		var node: Node = nodes[name]
		var start: int = Time.get_ticks_usec()
		for i in range(20):
			if name == "hud":
				node.refresh(main._hud_state())
			else:
				node._process(0.016)
		print("PROFILE %s %.2f ms" % [name, (Time.get_ticks_usec() - start) / 20000.0])
	var start2: int = Time.get_ticks_usec()
	for i in range(20):
		main._process(0.016)
	print("PROFILE main %.2f ms" % ((Time.get_ticks_usec() - start2) / 20000.0))
