extends RefCounted
## BBCode for the inspector's Cultivation tab: realm and progress, spiritual
## root and affinity, foundation, techniques, teacher and students (linked),
## sect and rank, the qi where they stand and how long they may live.
const Text = preload("res://scripts/core/text.gd")
const Style = preload("res://scripts/presentation/ui/style.gd")
const Data = preload("res://scripts/core/data.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const Sects = preload("res://scripts/sim/sects.gd")
const Tribulations = preload("res://scripts/sim/tribulations.gd")
const AgentText = preload("res://scripts/presentation/ui/agent_text.gd")


static func _color(color: Color, text: String) -> String:
	return "[color=#%s]%s[/color]" % [color.to_html(false), text]


static func _person(sim: RefCounted, id: int) -> String:
	return "[url=%d]%s[/url]" % [id, sim.agents[id].full_name()]


static func text(sim: RefCounted, agent: RefCounted) -> String:
	var c: Dictionary = agent.cultivation
	if c.is_empty():
		return ""
	var lines: Array[String] = []
	var realm: String = Text.label("realm_" + str(Data.realm(int(c.realm)).id))
	if CultivationState.at_peak(c) and int(c.realm) >= 1:
		lines.append(Style.rich_heading(Text.format("cult_peak", {"realm": realm})))
	else:
		lines.append(Style.rich_heading(Text.format("cult_realm", {"realm": realm, "progress": floori(float(c.progress)), "needed": int(CultivationState.needed(c))})))
	lines.append(Text.format("cult_talent", {"talent": Text.label(CultivationState.talent_word(float(c.talent))), "affinity": Text.label("affinity_" + str(c.affinity))}))
	lines.append(Text.format("cult_drive", {"value": roundi(float(c.drive) * 100.0)}))
	if int(c.realm) >= 1:
		lines.append(Text.format("cult_foundation", {"value": roundi(float(c.foundation) * 100.0)}))
	if c.techniques.is_empty():
		lines.append(_color(Style.MUTED, Text.label("cult_no_techniques")))
	else:
		var names: Array[String] = []
		for id in c.techniques:
			names.append(Text.label("technique_" + str(id)))
		lines.append(Text.format("cult_techniques", {"list": ", ".join(names)}))
	if int(c.teacher) >= 0:
		lines.append(Text.format("cult_teacher", {"name": _person(sim, int(c.teacher))}))
	if not c.students.is_empty():
		var students: Array[String] = []
		for id in c.students:
			students.append(_person(sim, int(id)))
		lines.append(Text.format("cult_students", {"list": ", ".join(students)}))
	var sect: Dictionary = sim.sects.get_sect(int(c.sect_id)) if sim.sects != null else {}
	if sect.is_empty():
		lines.append(_color(Style.MUTED, Text.label("cult_no_sect")))
	else:
		lines.append(_color(Style.FAITH, Text.format("cult_sect", {"rank": Text.label("rank_" + str(sect.members.get(agent.id, "disciple"))).capitalize(), "sect": Sects.name_of(sect)})))
	_trials(sim, agent, lines)
	_alchemy(sim, agent, lines)
	lines.append("")
	lines.append(Text.format("cult_qi_here", {"value": roundi(sim.qi.density(sim, agent.cell) * 100.0)}))
	lines.append(Text.format("cult_lifespan", {"years": roundi(CultivationState.lifespan(c))}))
	return "\n".join(lines)


## What preparations left (M20b): a pill or tea still working, pills kept
## for a trial, pill toxicity, years an elixir added, and an alchemist's name.
static func _alchemy(sim: RefCounted, agent: RefCounted, lines: Array[String]) -> void:
	var c: Dictionary = agent.cultivation
	if bool(c.get("alchemist", false)):
		lines.append(_color(Style.FAITH, Text.label("cult_alchemist")))
	if int(c.get("elixir_until", -1)) > sim.calendar.tick:
		var hours: int = ceili(float(int(c.elixir_until) - sim.calendar.tick) / sim.calendar.ticks_per_hour())
		lines.append(Text.format("cult_elixir_active", {"factor": snappedf(float(c.get("elixir_factor", 1.0)), 0.1), "hours": hours}))
	var kept: Array[String] = []
	for key in ["pill", "warding"]:
		if bool(c.get(key, false)):
			kept.append(Text.label("cult_kept_" + key))
	if not kept.is_empty():
		lines.append(Text.format("cult_kept", {"list": ", ".join(kept)}))
	var toxicity: float = float(c.get("toxicity", 0.0))
	if toxicity > 0.0:
		var line: String = Text.format("cult_toxicity", {"value": roundi(toxicity * 100.0)})
		lines.append(_color(Style.WARN, line) if toxicity >= float(Data.alchemy().toxicity.cleanse_at) else line)
	if float(c.get("longevity", 0.0)) > 0.0:
		lines.append(Text.format("cult_longevity", {"years": roundi(float(c.longevity))}))


## A trial called or under way, a flawed breakthrough, and past trials.
static func _trials(sim: RefCounted, agent: RefCounted, lines: Array[String]) -> void:
	var c: Dictionary = agent.cultivation
	var trial: Dictionary = sim.tribulations.of(agent.id) if sim.tribulations != null else {}
	if not trial.is_empty():
		var help: String = (Text.label("cult_shielded") if float(trial.shield) > 0.0 else "") + (Text.label("cult_defied") if bool(trial.defy) else "")
		var args: Dictionary = {"severity": roundi(float(trial.severity) * 100.0), "help": help,
			"clock": Tribulations._clock(sim, int(trial.start_tick))}
		var key: String = "cult_trial_storm" if trial.state == "storm" else "cult_trial_pending"
		lines.append(_color(Style.WARN, Text.format(key, args)))
	if bool(c.get("flawed", false)):
		lines.append(_color(Style.WARN, Text.label("cult_flawed")))
	var past: Array[String] = []
	for record in c.get("trials", []):
		past.append("%s (%s)" % [AgentText.clock(sim, int(record.tick)), Text.label("cult_outcome_" + str(record.outcome))])
	if not past.is_empty():
		lines.append(Text.format("cult_trials", {"list": ", ".join(past)}))
