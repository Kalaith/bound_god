extends Node
## The god's side of faith in the scene: reports where the avatar stands,
## opens the shrine menu at an altar or the tree, sends miracles and
## whispers, follows the god when it is expelled or transfers, flashes
## miracles where they happen, and words the HUD's shrine line and prayers.
const Text = preload("res://scripts/core/text.gd")
const ShrineMenu = preload("res://scripts/presentation/ui/shrine_menu.gd")
const AgentText = preload("res://scripts/presentation/ui/agent_text.gd")
const Movement = preload("res://scripts/sim/movement.gd")

var sim: RefCounted
var main: Node3D
var menu: Control
var _avatar_cell := Vector3i(-999, -999, -999)
var _last_event: int = -1


func _ready() -> void:
	menu = ShrineMenu.new()
	menu.sim = sim
	main.ui_layer.add_child(menu)
	menu.closed.connect(close_menu)
	menu.command.connect(send)
	menu.open_library.connect(func() -> void:
		close_menu()
		main._open_library())
	menu.open_stores.connect(func(id: int) -> void:
		close_menu()
		main.open_stores_for(id))
	menu.open_requests.connect(func() -> void:
		close_menu()
		main.open_requests())
	menu.rest_requested.connect(func(days: float) -> void:
		close_menu()
		main.rest(days))
	menu.meditate_requested.connect(func(years: float) -> void:
		close_menu()
		main.meditate(years))
	main.inspector.protect_cycled.connect(func(id: int) -> void:
		var rule: Dictionary = sim.god.protect.get(id, {})
		var next: String = {"": "shield", "shield": "defy", "defy": ""}[str(rule.get("mode", ""))]
		send({"type": "protect", "agent": id, "mode": next}))
	main.inspector.whisper.connect(func(id: int, nudge: String) -> void:
		send({"type": "cast_miracle", "miracle": "whisper", "cell": sim.agents[id].cell, "agent": id, "nudge": nudge}))
	main.inspector.miracle.connect(func(id: int, miracle: String) -> void:
		send({"type": "cast_miracle", "miracle": miracle, "cell": sim.agents[id].cell, "agent": id}))


func send(command: Dictionary) -> void:
	var result: Dictionary = sim.apply_command(command)
	if not str(result.reason).is_empty():
		main.hud.flash(Text.label(result.reason), not result.ok)
		if menu.visible:
			menu.notice(Text.label(result.reason), not result.ok)


func close_menu() -> void:
	menu.hide()
	main.builder.enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Interact beside the shrine the god stands at opens its menu.
func try_open_menu() -> bool:
	var shrine: Dictionary = sim.faith.current(sim)
	if shrine.is_empty():
		return false
	var here: Vector3 = main.avatar.global_position
	var at: Vector3 = Vector3(shrine.cell) + (Vector3(1, 0, 1) if shrine.kind == "tree" else Vector3(0.5, 0, 0.5))
	if Vector2(here.x - at.x, here.z - at.z).length() > (6.0 if shrine.kind == "tree" else 4.0):
		return false
	menu.avatar_cell = _avatar_cell
	main.builder.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu.open()
	return true


func _process(_delta: float) -> void:
	if sim == null:
		return
	var cell := Vector3i(main.avatar.global_position.floor())
	if cell != _avatar_cell:
		_avatar_cell = cell
		sim.apply_command({"type": "avatar_moved", "cell": cell})
	for event in sim.god.take_events():
		_on_god_event(event)
	for event in sim.faith.events:
		if int(event.uid) > _last_event:
			_last_event = int(event.uid)
			main.overlays.flash(Vector3(event.cell) + Vector3(0.5, 0.2, 0.5), float(event.radius))


func _on_god_event(event: Dictionary) -> void:
	match str(event.kind):
		"expelled", "transfer", "awakened":
			var shrine: Dictionary = sim.faith.get_shrine(int(event.to))
			var cell: Vector3i = sim.faith.shrine_access(sim, int(event.to), shrine.cell)
			main.avatar.set_dormant(false)
			main.avatar.global_position = Movement.center(cell) + Vector3(0, 0.2, 0)
			main.hud.flash(Text.format("god_event_" + str(event.kind), {"shrine": shrine.name}))
		"dormant":
			main.avatar.set_dormant(true)
			main.hud.flash(Text.label("god_event_dormant"), true)


func shrine_line() -> String:
	var shrine: Dictionary = sim.faith.current(sim)
	if shrine.is_empty():
		return ""
	if sim.god.dormant:
		return Text.format("hud_dormant", {"shrine": shrine.name})
	return Text.format("hud_shrine", {"shrine": shrine.name, "favour": roundi(float(shrine.favour)), "renown": sim.god.renown})


## The last three prayers heard at the shrine the god stands at.
func prayer_lines() -> Array:
	var lines: Array = []
	var feed: Array = sim.faith.feed.get(sim.god.active_shrine_id, [])
	for i in range(feed.size() - 1, maxi(feed.size() - 4, -1), -1):
		var prayer: Dictionary = feed[i]
		var agent: RefCounted = sim.agents[int(prayer.agent)]
		var intent: Dictionary = prayer.intent
		var text: String = Text.format("hud_prayer", {"name": agent.given_name, "intent": Text.label("intent_" + str(intent.get("kind", "thanks")))})
		if float(intent.get("level", 100.0)) < 100.0:
			text += " · %d" % roundi(float(intent.level))
		lines.append(text)
	return lines
