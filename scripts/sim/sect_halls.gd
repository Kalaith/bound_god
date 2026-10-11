extends RefCounted
## The sect's halls (M19b): what each building of a grown sect does for its
## Way. Each is an ordinary structure found from its components (the rules
## in templates.json); this module finds them and gives each one's help
## where the systems ask: sitting in seclusion, a trial in a chamber,
## healing and a mended foundation, an array's qi, a gate's seekers, the
## ancestors' relics, a stele's steady doctrine, a bell's warning and a
## lecture's teaching. What a sect would build is in sect_hall_wants.gd.
const Balance = preload("res://scripts/core/balance.gd")
const SectPlaces = preload("res://scripts/sim/sect_places.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const Mind = preload("res://scripts/agents/mind.gd")

const NONE := Vector3i(-1, -1, -1)

## Lookups by settlement and function, kept while the tick and the
## structures stay the same (the abstract model asks once per person).
static var _key: Array = []
static var _found: Dictionary = {}


## A settlement's standing structures of one function (cached per tick).
static func of(sim: RefCounted, settlement_id: int, function: String) -> Array:
	var key: Array = [sim.get_instance_id(), sim.calendar.tick, sim.structures.version]
	if key != _key:
		_key = key
		_found.clear()
	var name: String = "%d:%s" % [settlement_id, function]
	if not _found.has(name):
		_found[name] = SectPlaces.of(sim, settlement_id, function)
	return _found[name]


static func has(sim: RefCounted, settlement_id: int, function: String) -> bool:
	return not of(sim, settlement_id, function).is_empty()


## How many of a component a settlement's structures of one function hold.
static func parts(sim: RefCounted, settlement_id: int, function: String, component: String) -> int:
	var count: int = 0
	for entry in of(sim, settlement_id, function):
		count += entry.components.get(component, []).size()
	return count


static func at(sim: RefCounted, cell: Vector3i, function: String) -> Dictionary:
	var entry: Dictionary = sim.structures.containing(cell)
	return entry if not entry.is_empty() and entry.functions.has(function) else {}


## A free component cell of a settlement's structures of one function, nearest
## to the person: a mat nobody is sitting on, an array nobody stands on.
static func free_cell(sim: RefCounted, agent: RefCounted, function: String, component: String) -> Vector3i:
	var best: Vector3i = NONE
	var best_distance: float = INF
	for entry in of(sim, agent.settlement_id, function):
		for cell in entry.components.get(component, []):
			var other: int = int(sim.occupied.get(cell, -1))
			if other >= 0 and other != agent.id and sim.agents[other].activity in ["cultivating", "facing_heaven"]:
				continue
			if not sim.nav.is_walkable(cell):
				continue
			var distance: float = Vector3(cell - agent.cell).length()
			if distance < best_distance:
				best = cell
				best_distance = distance
	return best


# Meditation room ---------------------------------------------------------

## Seclusion is for those already on the Way: Qi Refining or beyond.
static func may_seclude(agent: RefCounted) -> bool:
	return not agent.cultivation.is_empty() and int(agent.cultivation.realm) >= 1


static func room_mat(sim: RefCounted, agent: RefCounted) -> Vector3i:
	return free_cell(sim, agent, "meditation_room", "mat") if may_seclude(agent) else NONE


## How much faster a sitting goes at a cell: a hall's mat for anyone, a
## room's mat in seclusion for one who may use it.
static func sitting_factor(sim: RefCounted, agent: RefCounted, cell: Vector3i) -> float:
	if SectPlaces.in_hall(sim, cell):
		return Balance.number("cultivation.hall_factor")
	if may_seclude(agent) and not at(sim, cell, "meditation_room").is_empty():
		return Balance.number("halls.seclusion_factor")
	return 1.0


## The same help while the valley passes abstractly: a hall for everyone,
## and a room's seclusion shared among those who may use it.
static func abstract_factor(sim: RefCounted, agent: RefCounted) -> float:
	var factor: float = Balance.number("cultivation.hall_factor") if has(sim, agent.settlement_id, "meditation_hall") else 1.0
	if not may_seclude(agent):
		return factor
	var rooms: int = of(sim, agent.settlement_id, "meditation_room").size()
	if rooms == 0:
		return factor
	var users: int = 0
	for id in sim.settlements.entries.get(agent.settlement_id, {}).get("residents", []):
		users += 1 if sim.agents[id].is_present() and may_seclude(sim.agents[id]) else 0
	var share: float = minf(1.0, float(rooms) / maxf(float(users), 1.0))
	return maxf(factor, lerpf(factor, Balance.number("halls.seclusion_factor"), share))


# Tribulation chamber -----------------------------------------------------

static func chamber_at(sim: RefCounted, cell: Vector3i) -> Dictionary:
	return at(sim, cell, "tribulation_chamber")


## Where a person of this settlement would sit for their trial in a chamber.
static func chamber_cell(sim: RefCounted, agent: RefCounted) -> Vector3i:
	return free_cell(sim, agent, "tribulation_chamber", "array")


## The chamber's spire, which takes the lightning.
static func spire(entry: Dictionary) -> Vector3i:
	var spires: Array = entry.get("components", {}).get("spire", [])
	return spires[0] if not spires.is_empty() else NONE


# Infirmary ---------------------------------------------------------------

static func in_infirmary(sim: RefCounted, agent: RefCounted) -> bool:
	var entry: Dictionary = sim.structures.entries.get(agent.inside, {})
	if entry.is_empty():
		entry = sim.structures.containing(agent.cell)
	return not entry.is_empty() and entry.functions.has("infirmary")


## A foundation cracked by a failed trial, not yet mended. (A foundation
## Heaven damaged when the god defied it is not a wound and does not mend.)
static func cracked(agent: RefCounted) -> bool:
	var c: Dictionary = agent.cultivation
	return not c.is_empty() and c.has("sound_foundation") and float(c.foundation) < float(c.sound_foundation) - 0.001


## Mends a cracked foundation by `amount`, towards what it was before.
static func mend(sim: RefCounted, agent: RefCounted, amount: float) -> void:
	if not cracked(agent):
		return
	var c: Dictionary = agent.cultivation
	c.foundation = minf(float(c.foundation) + amount, float(c.sound_foundation))
	if float(c.foundation) >= float(c.sound_foundation) - 0.001:
		c.erase("sound_foundation")
		Mind.add(agent, "foundation_mended", sim.calendar.ticks_per_day)
		sim.chronicle_event("foundation_mended", agent.settlement_id, {"name": agent.full_name()}, "cause_infirmary", [agent.id])


## The infirmary nearest a person in their settlement, or -1.
static func infirmary(sim: RefCounted, agent: RefCounted) -> int:
	var best: int = -1
	var best_distance: float = INF
	for entry in of(sim, agent.settlement_id, "infirmary"):
		var distance: float = Vector3(entry.anchor - agent.cell).length()
		if distance < best_distance:
			best = int(entry.id)
			best_distance = distance
	return best


# Spirit-gathering array --------------------------------------------------

static var _arrays_key: Array = []
static var _arrays: Array = []


## The middle of every standing array, in the xz plane.
static func arrays(sim: RefCounted) -> Array:
	var key: Array = [sim.get_instance_id(), sim.structures.version]
	if key == _arrays_key:
		return _arrays
	_arrays_key = key
	_arrays = []
	for entry in sim.structures.built():
		if not entry.functions.has("spirit_array"):
			continue
		var sum := Vector2.ZERO
		var jades: Array = entry.components.get("jade", [])
		for cell in jades:
			sum += Vector2(cell.x + 0.5, cell.z + 0.5)
		_arrays.append(sum / maxf(float(jades.size()), 1.0))
	return _arrays


## The qi an array holds at a cell (0 beyond every array's reach).
static func array_qi(sim: RefCounted, cell: Vector3i) -> float:
	var radius: float = Balance.number("halls.array_radius")
	for middle in arrays(sim):
		if Vector2(cell.x + 0.5, cell.z + 0.5).distance_to(middle) <= radius:
			return Balance.number("halls.array_qi")
	return 0.0


# Mountain gate, ancestral hall, precept stele ----------------------------

static func seek_factor(sim: RefCounted, settlement_id: int) -> float:
	return Balance.number("halls.gate_seekers") if has(sim, settlement_id, "sect_gate") else 1.0


static func join_factor(sim: RefCounted, settlement_id: int) -> float:
	return Balance.number("halls.gate_join") if has(sim, settlement_id, "sect_gate") else 1.0


## Relics beyond the usual number whose help the ancestors' tablets keep.
static func relic_extra(sim: RefCounted, settlement_id: int) -> int:
	return parts(sim, settlement_id, "ancestral_hall", "tablet")


## Whether the relics steady a trial faced here: in the sanctuary, or at
## home in a settlement whose ancestral hall keeps their memory.
static func relics_help(sim: RefCounted, agent: RefCounted, site: Vector3i, sanctuary: bool) -> bool:
	if sanctuary:
		return true
	if not has(sim, agent.settlement_id, "ancestral_hall"):
		return false
	return sim.settlements.at_cell(site) == agent.settlement_id


static func drift_factor(sim: RefCounted, settlement_id: int) -> float:
	return Balance.number("halls.stele_drift") if has(sim, settlement_id, "precept_stele") else 1.0


# Bell tower ---------------------------------------------------------------

## Every few ticks: a threat within reach of a bell rings it, and everyone
## living in its settlement knows of the threat at once. Each threat rings a
## settlement's bell once in the chronicle. A settlement a threat has come
## near remembers it (a reason to want a bell).
static func ring(sim: RefCounted) -> void:
	if sim.calendar.tick % 10 != 0:
		return
	var threats: Array = sim.threats_list()
	if threats.is_empty():
		return
	var reach: float = Balance.number("halls.bell_reach")
	for id in sim.settlements.ids():
		var settlement: Dictionary = sim.settlements.entries[id]
		var bells: Array = of(sim, id, "bell_tower")
		for threat in threats:
			if not bool(threat.aggressive):
				continue
			var near: bool = Vector2(threat.cell.x - settlement.center.x, threat.cell.z - settlement.center.z).length() <= float(settlement.radius)
			if near and int(settlement.get("threatened_tick", -1)) < 0:
				settlement["threatened_tick"] = sim.calendar.tick
			var heard: bool = false
			for entry in bells:
				heard = heard or Vector2(threat.cell.x - entry.anchor.x, threat.cell.z - entry.anchor.z).length() <= reach
			if not heard:
				continue
			for agent_id in settlement.residents:
				var agent: RefCounted = sim.agents[agent_id]
				if agent.is_present() and agent.beliefs.note_threat(int(threat.id), str(threat.kind), threat.cell, true, sim.calendar.tick):
					agent.interrupted_by = "interrupt_bell"
					agent.next_deliberation = sim.calendar.tick
			var rung: Dictionary = settlement.get("bell_rung", {})
			if not rung.has(int(threat.id)):
				rung[int(threat.id)] = sim.calendar.tick
				settlement["bell_rung"] = rung
				sim.chronicle_event("bell_rang", id, {"threat": "threat_" + str(threat.kind)}, "cause_threat_near", [])
		# Old alarms are forgotten after a few days.
		var rung_now: Dictionary = settlement.get("bell_rung", {})
		for threat_id in rung_now.keys():
			if sim.calendar.tick - int(rung_now[threat_id]) > sim.calendar.ticks_per_day * 3:
				rung_now.erase(threat_id)


# Lecture hall --------------------------------------------------------------

## The lecture hall a sect member would gather in, or -1.
static func lecture_hall(sim: RefCounted, agent: RefCounted) -> int:
	if agent.cultivation.is_empty() or int(agent.cultivation.sect_id) < 0:
		return -1
	var best: int = -1
	var best_distance: float = INF
	for entry in of(sim, agent.settlement_id, "lecture_hall"):
		var distance: float = Vector3(entry.anchor - agent.cell).length()
		if distance < best_distance and distance < 40.0:
			best = int(entry.id)
			best_distance = distance
	return best


## Hearing the Way expounded moves a sect member's cultivation on.
static func listen(sim: RefCounted, agent: RefCounted, hours: float) -> void:
	var c: Dictionary = agent.cultivation
	if c.is_empty() or int(c.sect_id) < 0:
		return
	var needed: float = CultivationState.needed(c)
	c.progress = minf(float(c.progress) + Balance.number("halls.lecture_per_hour") * hours, needed)
	if int(c.realm) >= 1 and float(c.progress) >= needed and int(c.peak_tick) < 0 and CultivationState.has_next(c):
		c.peak_tick = sim.calendar.tick


static func in_lecture(sim: RefCounted, agent: RefCounted) -> bool:
	return sim.structures.entries.get(agent.inside, {}).get("functions", []).has("lecture_hall")


# The abstract day ----------------------------------------------------------

## While the valley passes abstractly: the cracked mend in an infirmary and
## sect members spend some leisure in a lecture hall.
static func abstract_day(sim: RefCounted) -> void:
	for agent in sim.agents:
		if not agent.is_present() or agent.is_child or agent.cultivation.is_empty():
			continue
		if cracked(agent) and has(sim, agent.settlement_id, "infirmary"):
			mend(sim, agent, Balance.number("halls.foundation_mend") * 0.5)
		if int(agent.cultivation.sect_id) >= 0 and has(sim, agent.settlement_id, "lecture_hall"):
			listen(sim, agent, Balance.number("halls.lecture_hours"))
