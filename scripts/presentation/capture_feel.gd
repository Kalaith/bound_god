extends RefCounted
## Debug-only captures of the look, sound and feel (M24):
## `feel_miracle_<id>` (that miracle's sign at the tree), `feel_music` (the
## score's mood at night, in a storm and in meditation, printed), `feel_settings`
## (the settings screen's rows), `feel_pseudo` (the pseudo-language on the
## shrine menu), `feel_scale` (150 % interface on the settlement panel) and
## `feel_pad_tour` (each screen opened, its focus and the pad's back button
## checked, printed).
const Text = preload("res://scripts/core/text.gd")
const Style = preload("res://scripts/presentation/ui/style.gd")


static func arrange(main: Node3D, shot: Node, scenario: String) -> void:
	var sim: RefCounted = main.sim
	var tree: Vector3i = sim.features.sacred_tree
	if scenario.begins_with("feel_miracle_"):
		var id: String = scenario.trim_prefix("feel_miracle_")
		main.avatar.global_position = Vector3(tree) + Vector3(1.5, 0.2, 9.5)
		main.camera_rig.yaw = 0.0
		var definition: Dictionary = load("res://scripts/core/data.gd").miracle(id)
		var cell: Vector3i = sim.nav.nearest_walkable(tree + Vector3i(1, 0, 6), 4)
		sim.faith.events.append({"uid": 999999, "id": id, "cell": cell, "radius": float(definition.get("radius", 4)), "aspect": "", "tick": sim.calendar.tick})
		print("FEEL miracle %s" % id)
		shot.shoot_after(int(18 if id != "veil_of_fog" else 40))
		return
	match scenario:
		"feel_music":
			await _music(main)
		"feel_settings":
			main._open_settings()
		"feel_pseudo":
			Text.pseudo = true
			main.avatar.global_position = Vector3(tree) + Vector3(1.5, 0.2, 5.5)
			main.faith._process(0.0)
			main.faith.try_open_menu()
		"feel_scale":
			main.get_tree().root.content_scale_factor = 1.5
			main.settlement_panel.open(1)
		"feel_pad_tour":
			await _pad_tour(main)
	shot.shoot_after(60)


static func _music(main: Node3D) -> void:
	var sim: RefCounted = main.sim
	var music: Node = main.music
	main.driver.set_speed(0)
	sim.calendar.tick = sim.calendar.ticks_per_day * 2 + sim.calendar.ticks_per_hour() * 23
	for i in range(240):
		await main.get_tree().process_frame
	print("FEEL music night mood=%s notes=%d" % [music.mood, music.notes_played])
	sim.weather.kind = "thunderstorm"
	sim.weather.until_tick = sim.calendar.tick + 100000
	for i in range(30):
		await main.get_tree().process_frame
	print("FEEL music storm mood=%s" % music.mood)
	sim.weather.kind = "clear"
	main.driver.meditate(400.0)
	for i in range(10):
		await main.get_tree().process_frame
	print("FEEL music meditation mood=%s notes=%d" % [music.mood, music.notes_played])


static func _pad_tour(main: Node3D) -> void:
	var tours: Array = [["pause", func() -> void: main.pause_menu.open()], ["chronicle", func() -> void: main.chronicle_screen.open()],
		["tree", func() -> void: main.tree_screen.open()], ["settlement", func() -> void: main.settlement_panel.open(1)],
		["lands", func() -> void: main.lands_panel.open()], ["requests", func() -> void: main.open_requests()],
		["saga", func() -> void: main.open_saga()], ["library", func() -> void: main.open_library()]]
	for tour in tours:
		tour[1].call()
		for i in range(3):
			await main.get_tree().process_frame
		var screen: Control = main.screens.topmost()
		var owner: Control = main.get_viewport().gui_get_focus_owner()
		var focused: bool = screen != null and owner != null and screen.is_ancestor_of(owner)
		var back := InputEventJoypadButton.new()
		back.button_index = JOY_BUTTON_B
		back.pressed = true
		Input.parse_input_event(back)
		for i in range(3):
			await main.get_tree().process_frame
		var closed: bool = screen != null and not screen.visible
		print("PAD %s focus=%s back_closes=%s" % [tour[0], focused, closed])
