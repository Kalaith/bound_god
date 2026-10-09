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
