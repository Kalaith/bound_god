extends Control
## Resting at the shrine: the world goes on behind a veil while time runs as
## fast as it can, then "While you rested…" tells what happened, from the
## chronicle, with its causes.
signal finished
const Style = preload("res://scripts/presentation/ui/style.gd")
const Text = preload("res://scripts/core/text.gd")
const ChronicleText = preload("res://scripts/presentation/ui/chronicle_text.gd")
const MeditationSummary = preload("res://scripts/presentation/ui/meditation_summary.gd")

var sim: RefCounted
var driver: Node
var _title: Label
var _bar: ProgressBar
var _summary: RichTextLabel
var _continue: Button
var _meditating: bool = false
var _before: int = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var veil := ColorRect.new()
	veil.color = Color(0.03, 0.04, 0.05, 0.96)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	var panel: PanelContainer = Style.panel(0.0)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -640
	panel.offset_right = 640
	panel.offset_top = -420
	panel.offset_bottom = 420
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)
	_title = Style.heading("", 36, Style.FAITH)
	column.add_child(_title)
	_bar = Style.meter(0.0, 1.0, 1200.0, Style.FAITH)
	_bar.custom_minimum_size.y = 18
	column.add_child(_bar)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_summary = RichTextLabel.new()
	_summary.bbcode_enabled = true
	_summary.fit_content = true
	_summary.scroll_active = false
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.add_theme_font_size_override("normal_font_size", 21)
	scroll.add_child(_summary)
	_continue = Style.button(Text.label("rest_continue"), true)
	_continue.pressed.connect(func() -> void:
		hide()
		finished.emit())
	column.add_child(_continue)
	driver.rest_finished.connect(_on_finished)
	hide()


func begin_meditation(years: float) -> void:
	_meditating = true
	_before = sim.present_count()
	_title.text = Text.format("med_title", {"years": int(years)})
	_summary.text = ""
	_continue.hide()
	_bar.show()
	show()
	driver.meditate(years * sim.calendar.days_per_season * 4)


func begin(days: float) -> void:
	_meditating = false
	_title.text = Text.format("rest_title", {"days": int(days)})
	_summary.text = ""
	_continue.hide()
	_bar.show()
	show()
	driver.rest(days)


func _process(_delta: float) -> void:
	if visible and driver.resting:
		_bar.value = driver.rest_progress()


func _on_finished(from_tick: int) -> void:
	_bar.hide()
	if _meditating:
		_title.text = Text.label("med_while")
		_summary.text = MeditationSummary.text(sim, from_tick, _before, driver.wake_reason)
		_continue.show()
		_continue.grab_focus()
		return
	_title.text = Text.label("rest_while")
	var lines: Array[String] = []
	for entry in sim.chronicle.since(from_tick):
		lines.append(ChronicleText.line(entry))
	if lines.is_empty():
		lines.append(Text.label("rest_quiet"))
	_summary.text = "\n".join(lines)
	_continue.show()
	_continue.grab_focus()
