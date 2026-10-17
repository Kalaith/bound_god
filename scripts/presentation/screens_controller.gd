extends Node
const MouseCapture = preload("res://scripts/presentation/mouse_capture.gd")
## The Saga screen and the epilogue (M23), and gamepad navigation across
## every screen (M24): each screen takes focus on its first button when it
## opens, and the pad's back button closes the topmost one.
const Style = preload("res://scripts/presentation/ui/style.gd")
const Text = preload("res://scripts/core/text.gd")
const SagaText = preload("res://scripts/presentation/ui/saga_text.gd")
const Statistics = preload("res://scripts/sim/statistics.gd")

var main: Node3D


## The Saga: the ages, the deeds and the numbers.
func open_saga() -> void:
	main.pause_menu.hide()
	var campaign: RefCounted = main.campaign
	var lines: Array = []
	lines.append(Style.rich_heading(Text.label("saga_ages")))
	lines.append_array(SagaText.ages(campaign))
	lines.append("")
	lines.append(Style.rich_heading(Text.label("saga_deeds")))
	lines.append_array(SagaText.deeds(campaign))
	lines.append("")
	lines.append(Style.rich_heading(Text.label("saga_numbers")))
	lines.append_array(SagaText.numbers(Statistics.of(campaign)))
	main.page.open(Text.label("saga_title"), lines, [["close", "design_close"]])
	main.builder.enabled = false
	MouseCapture.set_mode(Input.MOUSE_MODE_VISIBLE)


## The epilogue, when the god fades or the player closes the book.
func open_epilogue(faded: bool) -> void:
	main.pause_menu.hide()
	main.campaign.book_closed = true
	main.page.open(Text.label("epilogue_title"), SagaText.epilogue(main.campaign, faded), [["watch", "epilogue_watch"], ["leave", "epilogue_leave"]])
	main.builder.enabled = false
	MouseCapture.set_mode(Input.MOUSE_MODE_VISIBLE)


func page_chosen(id: String) -> void:
	main.page.hide()
	if id == "leave":
		main.world_io.save()
		get_tree().change_scene_to_file(main.TITLE_SCENE)
		return
	main.resume_world_input()


func pad_ready() -> void:
	for screen in screens():
		screen.visibility_changed.connect(func() -> void:
			if screen.visible:
				focus_first.call_deferred(screen))


## The screens a player opens, topmost first.
func screens() -> Array:
	return [main.page, main.settings_screen, main.pause_menu, main.lands_panel, main.chronicle_screen, main.tree_screen, main.settlement_panel,
		main.requests_panel, main.faith.menu, main.library_screen, main.inventory].filter(func(screen: Variant) -> bool: return screen != null)


## Focuses the first button a screen shows (unless it already holds focus).
static func focus_first(screen: Control) -> void:
	var owner: Control = screen.get_viewport().gui_get_focus_owner()
	if owner != null and screen.is_ancestor_of(owner):
		return
	var stack: Array = [screen]
	while not stack.is_empty():
		var node: Node = stack.pop_front()
		if node is BaseButton and node.is_visible_in_tree() and not node.disabled and node.focus_mode != Control.FOCUS_NONE:
			node.grab_focus()
			return
		stack.append_array(node.get_children())


## The topmost open screen, or null.
func topmost() -> Control:
	for screen in screens():
		if screen.visible:
			return screen
	return null


## The pad's back button closes the topmost open screen.
func _input(event: InputEvent) -> void:
	if not (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B):
		return
	var screen: Control = topmost()
	if screen != null and screen != main.settings_screen:
		close(screen)
		get_viewport().set_input_as_handled()


func close(screen: Control) -> void:
	if screen == main.page:
		page_chosen("watch")
	elif screen == main.pause_menu:
		main._close_pause()
	elif screen == main.faith.menu:
		main.faith.close_menu()
	elif screen == main.library_screen:
		main._close_library()
	elif screen.has_signal("closed"):
		screen.emit_signal("closed")
	else:
		screen.hide()
		main.resume_world_input()
