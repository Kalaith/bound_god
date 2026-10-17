extends RefCounted
const MouseCapture = preload("res://scripts/presentation/mouse_capture.gd")
## Debug-only input test: `input_settlement_panel` presses the settlement key
## and Esc through the input system and prints where the mouse is at each
## step (free while the panel is open, captured again once it closes); the
## shot is taken with the panel open.


static func arrange(main: Node3D, shot: Node, _scenario: String) -> void:
	MouseCapture.set_mode(Input.MOUSE_MODE_CAPTURED)
	var tree: SceneTree = main.get_tree()
	var press := func(action: String) -> void:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = true
		Input.parse_input_event(event)
	var mode := func() -> String:
		return "captured" if MouseCapture.get_mode() == Input.MOUSE_MODE_CAPTURED else "free"
	tree.create_timer(0.5).timeout.connect(func() -> void:
		press.call("toggle_settlement")
		tree.create_timer(0.3).timeout.connect(func() -> void:
			print("INPUT after K: panel %s, mouse %s" % [main.settlement_panel.visible, mode.call()])
			press.call("toggle_settlement")
			tree.create_timer(0.3).timeout.connect(func() -> void:
				print("INPUT after K again: panel %s, mouse %s" % [main.settlement_panel.visible, mode.call()])
				press.call("toggle_settlement")
				tree.create_timer(0.3).timeout.connect(func() -> void:
					print("INPUT after K a third time: panel %s, mouse %s" % [main.settlement_panel.visible, mode.call()])
					press.call("toggle_settings")
					tree.create_timer(0.3).timeout.connect(func() -> void:
						print("INPUT after Esc: panel %s, mouse %s, pause menu %s" % [main.settlement_panel.visible, mode.call(), main.pause_menu.visible])
						press.call("toggle_settlement")
						tree.create_timer(0.3).timeout.connect(func() -> void:
							print("INPUT reopened: panel %s, mouse %s" % [main.settlement_panel.visible, mode.call()])
							shot.shoot_after(30)))))))
