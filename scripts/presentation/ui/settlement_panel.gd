extends Control
## The settlement the god stands in: residents and homes, stock, building
## sites, culture weights, known designs and recent events. Read-only: the
## panel explains the place, it gives no orders.
signal closed
const Style = preload("res://scripts/presentation/ui/style.gd")
const Text = preload("res://scripts/core/text.gd")
const ChronicleText = preload("res://scripts/presentation/ui/chronicle_text.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Standing = preload("res://scripts/sim/standing.gd")
const StandingText = preload("res://scripts/presentation/ui/standing_text.gd")
## Goods listed on the panel, food last.
const STOCK: Array[String] = ["wood", "stone", "thatch", "ore", "seed", "berries", "grain", "meal"]

var sim: RefCounted
var settlement_id: int = -1
var _title: Label
var _body: RichTextLabel
var _refresh_left: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel: PanelContainer = Style.panel(0.94)
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 18
	panel.offset_right = 620
	panel.offset_top = 130
	panel.offset_bottom = -130
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	_title = Style.label("", 30, Style.GOLD)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
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


func open(id: int) -> void:
	settlement_id = id
	_refresh_left = 0.0
	show()


func _gold(text: String) -> String:
	return "[color=#%s]%s[/color]" % [Style.GOLD.to_html(false), text]


func _process(delta: float) -> void:
	if not visible or sim == null:
		return
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = 0.5
	var settlement: Dictionary = sim.settlements.get_settlement(settlement_id)
	if settlement.is_empty():
		_title.text = Text.label("settlement_none")
		_body.text = ""
		return
	_title.text = settlement.name
	var lines: Array[String] = []
	var present: int = 0
	var homeless: int = 0
	for id in settlement.residents:
		if sim.agents[id].is_present():
			present += 1
			if sim.agents[id].home < 0:
				homeless += 1
	var beds: int = 0
	for entry in sim.structures.built():
		if Vector2(entry.anchor.x - settlement.center.x, entry.anchor.z - settlement.center.z).length() <= float(settlement.radius):
			beds += int(entry.capacity.get("beds", 0))
	lines.append(Text.format("settlement_people", {"count": present, "homeless": homeless, "beds": beds}))
	var stock: Array[String] = []
	for resource in STOCK:
		stock.append("%s %d" % [Text.label("resource_" + resource), sim.settlements.amount(settlement_id, resource)])
	lines.append(Text.format("settlement_stock", {"list": ", ".join(stock), "total": sim.settlements.total(settlement_id), "capacity": sim.settlements.capacity(sim, settlement_id)}))
	lines.append(Text.format("settlement_food", {"days": "%.1f" % Standing.food_days(sim, settlement_id), "meals": sim.settlements.amount(settlement_id, "meal"),
		"grain": sim.settlements.amount(settlement_id, "grain"), "berries": sim.settlements.amount(settlement_id, "berries")}))
	if Standing.fear_of_winter(sim, settlement_id):
		lines.append("[color=#%s]%s[/color]" % [Style.WARN.to_html(false), Text.label("settlement_winter_fear")])
	lines.append("")
	lines.append(_gold(StandingText.title(settlement)))
	var checklist: Array = StandingText.checklist(sim, settlement_id)
	if checklist.is_empty():
		lines.append(Text.label("settlement_top"))
	else:
		lines.append(Text.format("settlement_toward", {"next": Text.label("standing_" + Standing.next_level(str(settlement.get("standing", "camp"))))}))
	for item in checklist:
		var colour: Color = Style.LEAF if item.met else Style.MUTED
		lines.append("[color=#%s]%s %s[/color]" % [colour.to_html(false), "+" if item.met else "-", item.text])
	lines.append("")
	lines.append(_gold(Text.label("settlement_sites")))
	var sites: Array = sim.construction.in_settlement(settlement_id)
	if sites.is_empty():
		lines.append(Text.label("settlement_no_sites"))
	for id in sites:
		var site: Dictionary = sim.construction.get_site(id)
		var founder: String = sim.agents[int(site.founder)].given_name if int(site.founder) >= 0 else ""
		lines.append(Text.format("settlement_site", {"design": sim.template_name(site.template_id), "done": site.cursor, "total": site.order.size(), "name": founder}))
	lines.append("")
	lines.append(_gold(Text.label("settlement_culture")))
	var weights: Array[String] = []
	for work in Goals.WORK_TYPES:
		weights.append("%s %.2f" % [Text.label("work_" + work), float(settlement.culture[work])])
	lines.append(", ".join(weights))
	lines.append("")
	lines.append(_gold(Text.label("settlement_designs")))
	var names: Array[String] = []
	for id in settlement.known_templates:
		names.append(sim.template_name(id))
	lines.append(", ".join(names) if not names.is_empty() else Text.label("inspect_nothing"))
	lines.append("")
	lines.append(_gold(Text.label("settlement_events")))
	var shown: int = 0
	for i in range(sim.chronicle.entries.size() - 1, -1, -1):
		var entry: Dictionary = sim.chronicle.entries[i]
		if entry.place != settlement.name or not entry.known:
			continue
		lines.append(ChronicleText.line(entry))
		shown += 1
		if shown >= 8:
			break
	_body.text = "\n".join(lines)
