extends RefCounted
## BBCode for the inspector's Cultivation tab: realm and progress, spiritual
## root and affinity, foundation, techniques, teacher and students (linked),
## sect and rank, the qi where they stand and how long they may live.
const Text = preload("res://scripts/core/text.gd")
const Style = preload("res://scripts/presentation/ui/style.gd")
const Data = preload("res://scripts/core/data.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const Sects = preload("res://scripts/sim/sects.gd")


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
	lines.append("")
	lines.append(Text.format("cult_qi_here", {"value": roundi(sim.qi.density(sim, agent.cell) * 100.0)}))
	lines.append(Text.format("cult_lifespan", {"years": roundi(CultivationState.lifespan(c))}))
	return "\n".join(lines)
