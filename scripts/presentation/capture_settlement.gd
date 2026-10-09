extends RefCounted
## Debug-only captures of a settlement at work: `settlement_<days>` offers a
## cottage, runs the valley that many days, and looks over Tree Hollow with
## the settlement panel open.
const Data = preload("res://scripts/core/data.gd")
const Template = preload("res://scripts/building/template.gd")


static func arrange(main: Node3D, shot: Node, scenario: String) -> void:
	var sim: RefCounted = main.sim
	var days: int = int(scenario.trim_prefix("settlement_"))
	var design: Dictionary = Template.from_starter(Data.starter("miner_hut")).to_dict()
	design.id = "willow_cottage"
	design.name = "Willow Cottage"
	design.author = "local"
	sim.apply_command({"type": "offer_template", "template": design})
	var hours: int = days * 24 - 2
	sim.run_ticks(sim.calendar.ticks_per_hour() * hours)
	main.world_view.remesh_now()
	var camera_rig: Node3D = main.camera_rig
	camera_rig.overlook = true
	camera_rig._overlook_distance = 34.0
	camera_rig._overlook_pitch = -0.7
	camera_rig._overlook_yaw = deg_to_rad(200.0)
	main.settlement_panel.open(1)
	var built: int = 0
	for entry in sim.structures.built():
		if entry.template_id == "willow_cottage":
			built += 1
	print("SETTLEMENT day=%d people=%d cottages=%d sites=%d" % [sim.calendar.day(), sim.present_count(), built, sim.construction.sites.size()])
	shot.shoot_after(90)
