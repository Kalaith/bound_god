extends Control
## The lands beyond the valley (M22), from the shrine menu: each region's
## settlements, its sect and how it stands with the valley's, its shrines,
## and who is on the road. What the god knows of a region is what people
## there or travellers could tell it: a region where nobody has heard of
## the god is only a name. Read-only.
signal closed
const Style = preload("res://scripts/presentation/ui/style.gd")
const Text = preload("res://scripts/core/text.gd")
const Sects = preload("res://scripts/sim/sects.gd")
const Standing = preload("res://scripts/sim/standing.gd")
const Travel = preload("res://scripts/sim/travel.gd")

var campaign: RefCounted
var _body: RichTextLabel
var _refresh_left: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel: PanelContainer = Style.panel(0.94)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -460
	panel.offset_right = 460
	panel.offset_top = 120
	panel.offset_bottom = -120
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title: Label = Style.heading(Text.label("lands_title"), 30, Style.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close: Button = Style.button(Text.label("inspect_close"))
	close.pressed.connect(func() -> void: closed.emit())
	header.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_font_size_override("normal_font_size", 19)
	scroll.add_child(_body)
	hide()


func open() -> void:
	_refresh_left = 0.0
	show()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("toggle_settings"):
		closed.emit()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible or campaign == null:
		return
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = 0.5
	_body.text = "\n".join(text(campaign))


## The panel's lines, one region after another.
static func text(campaign: RefCounted) -> Array[String]:
	var lines: Array[String] = []
	var valley: int = Travel.valley_sect(campaign)
	for region in campaign.regions:
		var sim: RefCounted = region.sim
		var here: bool = int(region.id) == campaign.active
		lines.append(Style.rich_heading(Text.label(str(region.name)) + (" · " + Text.label("lands_god_here") if here else "")))
		if not here and not _known(sim):
			lines.append("[color=#%s]%s[/color]" % [Style.MUTED.to_html(false), Text.label("lands_unknown")])
			lines.append("")
			continue
		for id in sim.settlements.ids():
			var settlement: Dictionary = sim.settlements.entries[id]
			var people: int = Standing.present(sim, id)
			if people == 0:
				continue
			lines.append(Text.format("lands_settlement", {"name": settlement.name, "people": people, "standing": Text.label("standing_" + str(settlement.get("standing", "camp")))}))
			var sect: Dictionary = sim.sects.in_settlement(id) if sim.sects != null else {}
			if not sect.is_empty():
				var line: String = Text.format("lands_sect", {"sect": Sects.name_of(sect), "members": sect.members.size()})
				if valley >= 0 and not (int(region.id) == 0 and int(sect.id) == valley):
					var score: float = campaign.relations.score(campaign, int(region.id), int(sect.id), 0, valley)
					line += " · " + Text.label("lands_relation_" + campaign.relations.standing_of(score))
				lines.append("    " + line)
		var shrines: Array[String] = []
		for id in sim.faith.ids():
			var shrine: Dictionary = sim.faith.shrines[id]
			shrines.append(Text.format("lands_shrine", {"shrine": shrine.name, "state": Text.label("shrine_state_" + str(shrine.state))}))
		if not shrines.is_empty():
			lines.append(Text.format("lands_shrines", {"list": ", ".join(shrines)}))
		var road: int = 0
		for trip in campaign.travellers:
			if int(trip.region) == int(region.id):
				road += 1
		if road > 0:
			lines.append(Text.format("lands_on_the_road", {"count": road}))
		lines.append("")
	return lines


## Whether anyone there has heard of the god (so word of it can reach the tree).
static func _known(sim: RefCounted) -> bool:
	for agent in sim.agents:
		if agent.is_present() and agent.faith.get("knows", false):
			return true
	return not sim.faith.shrines.is_empty()
