extends Control
## The tree screen (T): what the sacred tree has become. Its maturity and
## phase, what it can do now and what it still needs for the rest, the
## fruit on its boughs, the scars on its bark and the spots the god has
## nurtured, then every insight with the latest trials or lessons it came
## from. Read-only.
signal closed
const Relics = preload("res://scripts/sim/relics.gd")
const Style = preload("res://scripts/presentation/ui/style.gd")
const Text = preload("res://scripts/core/text.gd")
const Data = preload("res://scripts/core/data.gd")

var sim: RefCounted
var _body: RichTextLabel
var _refresh_left: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel: PanelContainer = Style.panel(0.95)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -520
	panel.offset_right = 520
	panel.offset_top = -400
	panel.offset_bottom = 400
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title: Label = Style.heading(Text.label("tree_title"), 34, Style.FAITH)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close: Button = Style.button(Text.label("tree_close"))
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
	_body.add_theme_font_size_override("normal_font_size", 21)
	_body.add_theme_color_override("default_color", Style.WHITE)
	scroll.add_child(_body)
	hide()


func open() -> void:
	_refresh_left = 0.0
	show()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("toggle_settings") or event.is_action_pressed("toggle_tree")):
		closed.emit()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible or sim == null or sim.tree_growth == null:
		return
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = 0.5
	_body.text = text(sim)


## Sources shown under each insight; the rest are counted.
const SOURCES_SHOWN: int = 3


static func text(sim: RefCounted) -> String:
	var growth: RefCounted = sim.tree_growth
	var lines: Array[String] = []
	var phases: Array = Data.tree_growth().maturity.phases
	lines.append(Style.rich_heading(Text.format("tree_phase", {"phase": Text.label("phase_" + growth.phase_id()), "maturity": "%.1f" % float(growth.maturity)})))
	if int(growth.phase) + 1 < phases.size():
		var next: Dictionary = phases[int(growth.phase) + 1]
		lines.append(_muted(Text.format("tree_next_phase", {"phase": Text.label("phase_" + str(next.id)), "at": roundi(float(next.at))})))
	lines.append("")
	lines.append(Style.rich_heading(Text.label("tree_unlocks")))
	if growth.unlocks.is_empty():
		lines.append(Text.label("tree_no_unlocks"))
	for id in growth.unlocks:
		lines.append("[color=#%s]%s[/color]" % [Style.FAITH.to_html(false), _sentence(Text.label("unlock_" + str(id)))])
		lines.append("    " + _muted(Text.label("unlock_help_" + str(id))))
	var locked: Array[String] = []
	for unlock in Data.tree_growth().unlocks:
		if not growth.unlocks.has(unlock.id):
			locked.append("    " + _muted(Text.format("tree_locked_line", {"unlock": _sentence(Text.label("unlock_" + str(unlock.id))), "needs": _needs(growth, unlock.requires)})))
	if not locked.is_empty():
		lines.append(Text.label("tree_locked"))
		lines.append_array(locked)
	lines.append("")
	lines.append(Text.format("tree_fruit", {"count": int(growth.fruit)}))
	lines.append(Text.format("tree_scars", {"count": growth.scars.size()}))
	lines.append(Text.format("tree_nurtured", {"count": growth.nurtured.size()}))
	_relic_lines(sim, growth, lines)
	lines.append("")
	lines.append(Style.rich_heading(Text.label("tree_insights")))
	if growth.insights.is_empty():
		lines.append(Text.label("tree_no_insights"))
	var kinds: Array = growth.insights.keys()
	kinds.sort()
	for kind in kinds:
		_insight_lines(growth, str(kind), lines)
	return "\n".join(lines)


## One insight and the latest of what it came from: trials, or lessons.
## Where the relics of great cultivators lie: at the tree, at branch
## shrines, in someone's hands, or in the ruins of a fallen shrine.
static func _relic_lines(sim: RefCounted, growth: RefCounted, lines: Array[String]) -> void:
	if growth.relics.is_empty():
		return
	## where -> count, in first-seen order
	var places: Dictionary = {}
	for relic in growth.relics:
		var shrine: String = str(sim.faith.get_shrine(Relics.shrine_of(sim, relic)).get("name", ""))
		var key: String
		if int(relic.get("carried", -1)) >= 0:
			key = Text.format("tree_relics_carried", {"name": sim.agents[int(relic.carried)].full_name()})
		elif bool(relic.get("lost", false)):
			key = Text.format("tree_relics_ruins", {"shrine": shrine})
		else:
			key = Text.format("tree_relics_at", {"shrine": shrine})
		places[key] = int(places.get(key, 0)) + 1
	var parts: Array[String] = []
	for key in places:
		parts.append("%s %d" % [key, places[key]])
	lines.append(Text.format("tree_relics_where", {"list": ", ".join(parts)}))


static func _insight_lines(growth: RefCounted, kind: String, lines: Array[String]) -> void:
	var sources: Array = []
	for record in growth.history:
		if str(record.kind) == kind:
			sources.append(record)
	var lessons: bool = not sources.is_empty() and str(sources[0].outcome).begins_with("lesson_")
	lines.append(Text.format("tree_lesson_line" if lessons else "tree_insight_line", {"kind": _sentence(Text.label("insight_" + kind)),
		"amount": "%.1f" % float(growth.insights[kind]), "count": int(growth.witnessed.get(kind, 0))}))
	for i in range(maxi(sources.size() - SOURCES_SHOWN, 0), sources.size()):
		var record: Dictionary = sources[i]
		if str(record.outcome).begins_with("lesson_"):
			lines.append("    " + Text.format("tree_lesson_source", {"day": int(record.day), "lesson": Text.format(str(record.outcome), {"name": record.name}), "gain": "%.1f" % float(record.gain)}))
		else:
			lines.append("    " + Text.format("tree_insight_source", {"day": int(record.day), "name": record.name,
				"outcome": Text.label("cult_outcome_" + str(record.outcome)), "gain": "%.1f" % float(record.gain)}))
	var earlier: int = int(growth.witnessed.get(kind, 0)) - mini(sources.size(), SOURCES_SHOWN)
	if earlier > 0:
		lines.append("    " + _muted(Text.format("tree_earlier_sources", {"count": earlier})))


## What a locked unlock still asks for.
static func _needs(growth: RefCounted, needs: Dictionary) -> String:
	var parts: Array[String] = []
	if needs.has("insight"):
		parts.append(Text.format("tree_needs_insight", {"kind": Text.label("insight_" + str(needs.insight)), "have": "%.1f" % float(growth.insights.get(str(needs.insight), 0.0)), "amount": "%.0f" % float(needs.amount)}))
	if needs.has("maturity"):
		for phase in Data.tree_growth().maturity.phases:
			if float(phase.at) >= float(needs.maturity) - 0.001:
				parts.append(Text.format("tree_needs_phase", {"phase": Text.label("phase_" + str(phase.id))}))
				break
	if needs.has("unlock"):
		parts.append(Text.format("tree_needs_unlock", {"unlock": Text.label("unlock_" + str(needs.unlock))}))
	return ", ".join(parts)


static func _muted(line: String) -> String:
	return "[color=#%s]%s[/color]" % [Style.MUTED.to_html(false), line]


## A phrase as the start of a line: its first letter raised, the rest as is.
static func _sentence(phrase: String) -> String:
	return phrase.left(1).to_upper() + phrase.substr(1)
