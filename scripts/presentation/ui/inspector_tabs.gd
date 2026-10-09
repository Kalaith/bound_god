extends RefCounted
## BBCode for the inspector's text sections: beliefs against reality, bonds,
## life story and faith. Rows that name another person link to them.
const Text = preload("res://scripts/core/text.gd")
const Style = preload("res://scripts/presentation/ui/style.gd")
const AgentText = preload("res://scripts/presentation/ui/agent_text.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const Beliefs = preload("res://scripts/agents/beliefs.gd")
const FaithState = preload("res://scripts/agents/faith_state.gd")
const Data = preload("res://scripts/core/data.gd")


static func _color(color: Color, text: String) -> String:
	return "[color=#%s]%s[/color]" % [color.to_html(false), text]


static func beliefs(sim: RefCounted, agent: RefCounted) -> String:
	var lines: Array[String] = []
	lines.append(_color(Style.GOLD, Text.label("inspect_beliefs")))
	var kinds: Dictionary = {}
	for id in agent.beliefs.sites:
		var kind: String = agent.beliefs.sites[id].kind
		kinds[kind] = int(kinds.get(kind, 0)) + 1
	var parts: Array[String] = []
	for kind in ["tree", "bush", "grass", "rock", "ore"]:
		if kinds.has(kind):
			parts.append("%d %s" % [kinds[kind], Text.label("sites_" + kind)])
	lines.append(Text.format("inspect_knows_sites", {"list": ", ".join(parts) if not parts.is_empty() else Text.label("inspect_nothing")}))
	var actual: Dictionary = sim.settlements.stock_of(agent.settlement_id)
	for resource in ["berries", "wood", "stone", "thatch", "ore"]:
		var believed: int = int(agent.beliefs.stock.get(resource, 0))
		var real: int = int(actual.get(resource, 0))
		if believed == 0 and real == 0:
			continue
		var line: String = Text.format("inspect_believes_stock", {"believed": believed, "resource": Text.label("resource_" + resource).to_lower(), "actual": real})
		var off: bool = absi(believed - real) > int(real * 0.25) + 5
		lines.append(_color(Style.WARN, line) if off else line)
	for threat in agent.beliefs.threats:
		lines.append(_color(Style.BAD, Text.format("inspect_believes_threat", {"kind": Text.label("threat_" + str(threat.kind)), "cell": str(threat.cell)})))
	if not agent.beliefs.known_templates.is_empty():
		var names: Array[String] = []
		for id in agent.beliefs.known_templates:
			names.append(sim.template_name(id))
		lines.append(Text.format("inspect_knows_designs", {"list": ", ".join(names)}))
	return "\n".join(lines)


static func bonds(sim: RefCounted, agent: RefCounted) -> String:
	var rows: Array = []
	for other in agent.beliefs.relations:
		if other < sim.agents.size():
			rows.append([other, agent.beliefs.opinion_of(other)])
	rows.sort_custom(func(a: Array, b: Array) -> bool:
		if a[1] != b[1]:
			return a[1] > b[1]
		return a[0] < b[0])
	if rows.is_empty():
		return Text.label("inspect_no_bonds")
	var lines: Array[String] = []
	for row in rows:
		var other: RefCounted = sim.agents[row[0]]
		var label: String = Text.label("bond_partner") if agent.partner == other.id else AgentText.bond(agent.beliefs.bond_with(other.id))
		var color: Color = Style.GOOD if row[1] >= 30.0 else (Style.BAD if row[1] <= -25.0 else Style.WHITE)
		var state: String = "" if other.is_present() else "  " + Text.label("inspect_" + other.life)
		lines.append("[url=%d]%s[/url]  %s  %s%s" % [other.id, other.full_name(), _color(color, label), _color(Style.MUTED, "%+d" % roundi(row[1])), state])
	return "\n".join(lines)


static func life(sim: RefCounted, agent: RefCounted) -> String:
	var lines: Array[String] = []
	lines.append(_color(Style.GOLD, Text.label("inspect_skills")))
	for skill in range(Personality.SKILLS.size()):
		var passion: String = " " + _color(Style.GOLD, Text.label("inspect_passion")) if agent.skills.passions.has(skill) else ""
		lines.append("%s  %d%s" % [AgentText.skill_name(skill), agent.skills.levels[skill], passion])
	lines.append("")
	var traits: Array[String] = []
	for id in agent.traits:
		traits.append(str(Data.trait_def(id).get("name", id)))
	lines.append(Text.format("inspect_traits", {"list": ", ".join(traits)}))
	var ambition: Dictionary = Data.ambition(agent.ambition.get("id", ""))
	if not ambition.is_empty():
		var state: String = Text.label("inspect_fulfilled") if agent.ambition.fulfilled else "%d%%" % roundi(float(agent.ambition.progress) * 100.0)
		lines.append(Text.format("inspect_ambition", {"name": ambition.name, "state": state}))
	if not str(agent.backstory.get("origin", "")).is_empty():
		lines.append(Text.format("inspect_backstory", agent.backstory))
	lines.append(Text.format("inspect_stats", agent.stats))
	return "\n".join(lines)


static func faith(sim: RefCounted, agent: RefCounted) -> String:
	var state: Dictionary = agent.faith
	var lines: Array[String] = []
	lines.append(_color(Style.FAITH, Text.label("faith_stage_" + FaithState.stage_name(state))))
	if not state.get("knows", false):
		lines.append(Text.label("inspect_faith_unaware"))
		return "\n".join(lines)
	lines.append(Text.format("inspect_devotion", {"value": roundi(float(state.devotion))}))
	var aspects: Array[String] = []
	for i in range(FaithState.ASPECTS.size()):
		aspects.append("%s %d%%" % [Text.label("aspect_" + FaithState.ASPECTS[i]), roundi(state.aspects[i] * 100.0)])
	lines.append(", ".join(aspects))
	var shrine: String = sim.faith.shrine_name(sim, int(state.shrine_id)) if sim.faith != null and int(state.shrine_id) >= 0 else Text.label("inspect_no_shrine")
	lines.append(Text.format("inspect_attends", {"shrine": shrine}))
	if int(state.last_prayer_tick) >= 0:
		var intent: Dictionary = state.last_intent
		lines.append(Text.format("inspect_last_prayer", {"when": AgentText.clock(sim, int(state.last_prayer_tick)), "intent": Text.label("intent_" + str(intent.get("kind", "thanks")))}))
	lines.append(Text.format("inspect_stories", {"count": int(state.stories_heard)}))
	return "\n".join(lines)
