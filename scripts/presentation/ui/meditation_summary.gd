extends RefCounted
## "While you meditated…": what the chronicle kept of a long absence, short
## enough to read. Why the god woke (if early), the pinned people first with
## their fate and its cause, then the sect, the people, the tree, and the
## few events worth naming. Reads the chronicle and the sim; words from the
## text catalogs.
const Text = preload("res://scripts/core/text.gd")
const Style = preload("res://scripts/presentation/ui/style.gd")
const Data = preload("res://scripts/core/data.gd")
const ChronicleText = preload("res://scripts/presentation/ui/chronicle_text.gd")
const Sects = preload("res://scripts/sim/sects.gd")

## Events worth naming one by one, in this order of interest.
const NOTABLE: Array[String] = ["sect_founded", "sect_master", "tree_unlock", "tree_grew", "relic_left", "trial_defied",
	"trial_died", "manual_kept", "shrine_fell", "settlement_abandoned", "standing_rose", "standing_fell"]
const MOST_NOTABLE: int = 10


static func _muted(text: String) -> String:
	return "[color=#%s]%s[/color]" % [Style.MUTED.to_html(false), text]


## `before` is how many people were present when the god sat down.
static func text(sim: RefCounted, from_tick: int, before: int, wake: Dictionary) -> String:
	var entries: Array = sim.chronicle.since(from_tick)
	var lines: Array[String] = []
	var days: int = (sim.calendar.tick - from_tick) / sim.calendar.ticks_per_day
	var years: float = float(days) / float(sim.calendar.days_per_season * 4)
	lines.append(Text.format("med_span", {"years": "%.1f" % years, "days": days}))
	if not wake.is_empty():
		var who: String = sim.agents[int(wake.agent)].full_name() if int(wake.get("agent", -1)) >= 0 else ""
		lines.append("[color=#%s]%s[/color]" % [Style.WARN.to_html(false), Text.format("med_woke_" + str(wake.kind), {"name": who})])
	lines.append("")
	_pinned(sim, entries, lines)
	_sect(sim, entries, lines)
	_people(sim, entries, before, lines)
	_tree(sim, entries, lines)
	var notable: Array[String] = []
	for kind in NOTABLE:
		for entry in entries:
			if str(entry.kind) == kind and notable.size() < MOST_NOTABLE:
				notable.append(ChronicleText.line(entry))
	if not notable.is_empty():
		lines.append(Style.rich_heading(Text.label("med_notable")))
		lines.append_array(notable)
	return "\n".join(lines)


## Each pinned person: where they stand now, then their part of the story.
static func _pinned(sim: RefCounted, entries: Array, lines: Array[String]) -> void:
	if sim.god.followed.is_empty():
		return
	lines.append(Style.rich_heading(Text.label("med_pinned")))
	for id in sim.god.followed:
		var agent: RefCounted = sim.agents[int(id)]
		var realm: String = Text.label("realm_" + str(Data.realm(int(agent.cultivation.get("realm", 0))).id))
		if agent.is_present():
			lines.append(Text.format("med_pinned_alive", {"name": agent.full_name(), "age": int(agent.age_years), "realm": realm}))
		else:
			lines.append(Text.format("med_pinned_gone", {"name": agent.full_name(), "realm": realm, "day": agent.life_day,
				"cause": ChronicleText.cause(agent.life_cause), "life": Text.label("inspect_" + agent.life)}))
		var shown: int = 0
		for entry in entries:
			if entry.agents.has(int(id)) and shown < 6 and not str(entry.kind) in ["miracle"]:
				lines.append("    " + ChronicleText.line(entry))
				shown += 1
	lines.append("")


static func _sect(sim: RefCounted, entries: Array, lines: Array[String]) -> void:
	if sim.sects == null or sim.sects.entries.is_empty():
		return
	lines.append(Style.rich_heading(Text.label("med_sect")))
	for id in sim.sects.ids():
		var sect: Dictionary = sim.sects.entries[id]
		if sect.members.is_empty():
			continue
		lines.append(Text.format("med_sect_line", {"sect": Sects.name_of(sect), "master": sim.agents[int(sect.master)].full_name(), "members": sect.members.size()}))
	var masters: int = 0
	for entry in entries:
		masters += 1 if str(entry.kind) == "sect_master" else 0
	if masters > 0:
		lines.append(Text.format("med_successions", {"count": masters}))
	lines.append("")


static func _count(entries: Array, kind: String) -> int:
	var count: int = 0
	for entry in entries:
		count += 1 if str(entry.kind) == kind else 0
	return count


static func _people(sim: RefCounted, entries: Array, before: int, lines: Array[String]) -> void:
	lines.append(Style.rich_heading(Text.label("med_people")))
	var causes: Dictionary = {}
	for entry in entries:
		if str(entry.kind) == "death":
			causes[str(entry.cause)] = int(causes.get(str(entry.cause), 0)) + 1
	var died: Array[String] = []
	var keys: Array = causes.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return causes[a] > causes[b] or (causes[a] == causes[b] and a < b))
	for key in keys:
		died.append("%d %s" % [causes[key], ChronicleText.cause(key)])
	lines.append(Text.format("med_people_line", {"before": before, "now": sim.present_count(), "births": _count(entries, "birth"),
		"arrivals": _count(entries, "arrival_migrants"), "departures": _count(entries, "departed")}))
	if not died.is_empty():
		lines.append(Text.format("med_deaths", {"list": ", ".join(died)}))
	lines.append(Text.format("med_cultivation", {"realms": _count(entries, "realm_reached") + _count(entries, "trial_passed") + _count(entries, "trial_defied"),
		"passed": _count(entries, "trial_passed"), "injured": _count(entries, "trial_injured"), "died": _count(entries, "trial_died")}))
	lines.append(Text.format("med_built", {"count": _count(entries, "built"), "taught": _count(entries, "taught")}))
	lines.append("")


static func _tree(sim: RefCounted, entries: Array, lines: Array[String]) -> void:
	if sim.tree_growth == null:
		return
	lines.append(Style.rich_heading(Text.label("med_tree")))
	lines.append(Text.format("med_tree_line", {"phase": Text.label("phase_" + sim.tree_growth.phase_id()), "insights": _count(entries, "tree_insight"),
		"scars": sim.tree_growth.scars.size(), "fruit": _count(entries, "fruit_given") + _count(entries, "fruit_kept") + _count(entries, "fruit_taken"),
		"relics": sim.tree_growth.relics.size()}))
	lines.append("")
