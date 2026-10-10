extends Control
## The "why" inspector: what a person is doing and why, how they feel, whom
## they know, their life and their faith. Follow and Close are real buttons
## so everything works without hover. Refreshes a few times a second.
signal closed
signal follow_toggled(on: bool)
signal person_chosen(id: int)
signal whisper(id: int, nudge: String)
signal pin_toggled(id: int)
signal miracle(id: int, miracle: String)
const Style = preload("res://scripts/presentation/ui/style.gd")
const Text = preload("res://scripts/core/text.gd")
const AgentText = preload("res://scripts/presentation/ui/agent_text.gd")
const InspectorTabs = preload("res://scripts/presentation/ui/inspector_tabs.gd")
const InspectorCultivation = preload("res://scripts/presentation/ui/inspector_cultivation.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const Plans = preload("res://scripts/agents/plans.gd")
const Data = preload("res://scripts/core/data.gd")

const TABS: Array[String] = ["mind", "needs", "bonds", "life", "faith", "cultivation"]

var sim: RefCounted
var agent_id: int = -1
var following: bool = false
var _panel: PanelContainer
var _name: Label
var _subtitle: Label
var _tabs: TabBar
var _pages: Array = []
var _goal: Label
var _drive: ProgressBar
var _plan: RichTextLabel
var _log: RichTextLabel
var _beliefs: RichTextLabel
var _need_bars: Array = []
var _need_values: Array = []
var _health: RichTextLabel
var _texts: Dictionary = {}
var _follow: Button
var _pin: Button
## Miracle buttons for cultivators, shown when they apply.
var _bless: Button
var _shield: Button
var _defy: Button
var _refresh_left: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = Style.panel(0.94)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -600
	_panel.offset_right = -18
	_panel.offset_top = 130
	_panel.offset_bottom = -130
	add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	_name = Style.heading("", 30, Style.GOLD)
	titles.add_child(_name)
	_subtitle = Style.label("", 18, Style.MUTED)
	titles.add_child(_subtitle)
	var close: Button = Style.button(Text.label("inspect_close"))
	close.pressed.connect(func() -> void: closed.emit())
	header.add_child(close)
	# The actions sit on their own row, so names and buttons never crowd.
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	column.add_child(actions)
	_follow = Style.button(Text.label("inspect_follow"))
	_follow.toggle_mode = true
	_follow.toggled.connect(func(on: bool) -> void:
		following = on
		follow_toggled.emit(on))
	actions.add_child(_follow)
	_pin = Style.button(Text.label("inspect_pin"))
	_pin.pressed.connect(func() -> void: pin_toggled.emit(agent_id))
	actions.add_child(_pin)
	var urge := MenuButton.new()
	urge.text = Text.label("miracle_whisper")
	urge.add_theme_font_size_override("font_size", 21)
	urge.custom_minimum_size.y = 50
	urge.flat = false
	var nudges: Array = ["rest", "pray", "build", "gather", "talk", "make_peace", "shelter"]
	for i in range(nudges.size()):
		urge.get_popup().add_item(Text.label("nudge_" + nudges[i]), i)
	urge.get_popup().add_theme_font_size_override("font_size", 20)
	urge.get_popup().id_pressed.connect(func(index: int) -> void: whisper.emit(agent_id, nudges[index]))
	actions.add_child(urge)
	_tabs = TabBar.new()
	_tabs.add_theme_font_size_override("font_size", 20)
	for tab in TABS:
		_tabs.add_tab(Text.label("inspect_tab_" + tab))
	_tabs.tab_changed.connect(_show_tab)
	column.add_child(_tabs)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(stack)
	_build_mind(stack)
	_build_needs(stack)
	for tab in ["bonds", "life", "faith", "cultivation"]:
		var page := VBoxContainer.new()
		if tab == "cultivation":
			page.add_child(_cultivation_actions())
		var text: RichTextLabel = _rich(19)
		text.meta_clicked.connect(func(meta: Variant) -> void: person_chosen.emit(int(str(meta))))
		page.add_child(text)
		_texts[tab] = text
		stack.add_child(page)
		_pages.append(page)
	_show_tab(0)
	hide()


func _rich(size: int) -> RichTextLabel:
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", size)
	text.add_theme_color_override("default_color", Style.WHITE)
	return text


func _build_mind(stack: VBoxContainer) -> void:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	_goal = Style.wrapped("", 26)
	page.add_child(_goal)
	_drive = Style.meter(0.0, 1.0, 520.0, Style.GOLD)
	page.add_child(_drive)
	_plan = _rich(19)
	page.add_child(_plan)
	page.add_child(Style.heading(Text.label("inspect_reasoning"), 20, Style.GOLD))
	_log = _rich(18)
	page.add_child(_log)
	_beliefs = _rich(18)
	page.add_child(_beliefs)
	stack.add_child(page)
	_pages.append(page)


func _build_needs(stack: VBoxContainer) -> void:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	page.add_child(grid)
	for need in range(Personality.NEEDS.size()):
		grid.add_child(Style.label(AgentText.need_name(need), 20))
		var bar: ProgressBar = Style.meter(0.0, 100.0, 300.0)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(bar)
		var value := Style.utility("", 20, Style.MUTED)
		grid.add_child(value)
		_need_bars.append(bar)
		_need_values.append(value)
	_health = _rich(19)
	page.add_child(_health)
	stack.add_child(page)
	_pages.append(page)


func _show_tab(index: int) -> void:
	for i in range(_pages.size()):
		_pages[i].visible = i == index
	_refresh_left = 0.0


func inspect(id: int) -> void:
	agent_id = id
	show()
	_refresh_left = 0.0


func _process(delta: float) -> void:
	if not visible or sim == null or agent_id < 0:
		return
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = 0.25
	var agent: RefCounted = sim.agents[agent_id]
	_name.text = agent.full_name()
	var place: String = sim.settlements.get_settlement(agent.settlement_id).get("name", "")
	_subtitle.text = Text.format("inspect_subtitle", {"age": int(agent.age_years), "role": agent.backstory.get("former_role", ""),
		"place": place, "activity": Text.label("activity_" + agent.activity)})
	match TABS[_tabs.current_tab]:
		"mind":
			_refresh_mind(agent)
		"needs":
			_refresh_needs(agent)
		"bonds":
			_texts.bonds.text = InspectorTabs.bonds(sim, agent)
		"life":
			_texts.life.text = InspectorTabs.life(sim, agent)
		"faith":
			_texts.faith.text = InspectorTabs.faith(sim, agent)
		"cultivation":
			_texts.cultivation.text = InspectorCultivation.text(sim, agent)
	_pin.text = Text.label("inspect_pinned" if sim.god.followed.has(agent_id) else "inspect_pin")
	var cultivating: bool = not agent.cultivation.is_empty() and (int(agent.cultivation.realm) >= 1 or float(agent.cultivation.drive) >= 0.05)
	var trial: Dictionary = sim.tribulations.of(agent_id) if sim.tribulations != null else {}
	_bless.visible = cultivating
	_shield.visible = not trial.is_empty()
	_defy.visible = not trial.is_empty()


func _refresh_mind(agent: RefCounted) -> void:
	var goal: Dictionary = agent.current_goal()
	_goal.text = AgentText.goal(sim, goal).capitalize() if not goal.is_empty() else Text.label("goal_none")
	_drive.value = clampf(float(agent.intention.get("utility", 0.0)) / 1.5, 0.0, 1.0)
	var lines: Array[String] = []
	var plan: Dictionary = agent.current_plan()
	if not plan.is_empty():
		lines.append(Text.format("inspect_plan", {"plan": AgentText.plan(plan.id)}))
		for i in range(mini(plan.steps.size(), 6)):
			var marker: String = "[color=#%s]+[/color]" % Style.GOOD.to_html(false) if i < int(plan.cursor) else ("[color=#%s]>[/color]" % Style.GOLD.to_html(false) if i == int(plan.cursor) else "·")
			lines.append("%s %s" % [marker, AgentText.step(sim, plan.steps[i])])
	var tried: Array = agent.intention.get("tried", [])
	if not tried.is_empty():
		var names: Array[String] = []
		for id in tried:
			names.append(AgentText.plan(id))
		lines.append("[color=#%s]%s[/color]" % [Style.WARN.to_html(false), Text.format("inspect_tried", {"list": ", ".join(names)})])
	if not agent.carrying.is_empty():
		lines.append(Text.format("inspect_carrying", {"amount": int(ceil(float(agent.carrying.amount))), "resource": Text.label("resource_" + agent.carrying.resource).to_lower()}))
	_plan.text = "\n".join(lines)
	var log_lines: Array[String] = []
	for entry in agent.decisions:
		var text: String = "[color=#%s]%s[/color]  %s" % [Style.MUTED.to_html(false), AgentText.clock(sim, int(entry.tick)), AgentText.entry(sim, entry)]
		if AgentText.is_setback(entry):
			text = "[color=#%s]%s[/color]" % [Style.WARN.to_html(false), text]
		log_lines.append(text)
	_log.text = "\n".join(log_lines)
	_beliefs.text = InspectorTabs.beliefs(sim, agent)


func _refresh_needs(agent: RefCounted) -> void:
	for need in range(_need_bars.size()):
		var value: float = agent.need(need)
		_need_bars[need].value = value
		(_need_bars[need].get_theme_stylebox("fill") as StyleBoxFlat).bg_color = Style.level_color(value)
		_need_values[need].text = str(roundi(value))
	var lines: Array[String] = []
	lines.append(Text.format("inspect_health", {"hp": roundi(float(agent.health.hp)), "mood": roundi(agent.mood)}))
	lines.append("")
	lines.append(Style.rich_heading(Text.label("inspect_thoughts")))
	for thought in agent.thoughts:
		var mood: float = float(thought.mood)
		var color: Color = Style.GOOD if mood > 0.0 else Style.WARN
		lines.append("%s  [color=#%s]%+d[/color]" % [str(Data.thought(thought.id).get("text", thought.id)), color.to_html(false), roundi(mood)])
	_health.text = "\n".join(lines)


## Bless a cultivator's training; shield or defy a trial they have called.
func _cultivation_actions() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_bless = Style.button(Text.label("inspect_bless"))
	_bless.pressed.connect(func() -> void: miracle.emit(agent_id, "bless_cultivation"))
	_shield = Style.button(Text.label("inspect_shield"))
	_shield.pressed.connect(func() -> void: miracle.emit(agent_id, "shield_trial"))
	_defy = Style.button(Text.label("inspect_defy"))
	_defy.pressed.connect(func() -> void: miracle.emit(agent_id, "defy_heaven"))
	for button in [_bless, _shield, _defy]:
		row.add_child(button)
	return row
