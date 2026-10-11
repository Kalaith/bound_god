extends RefCounted
## What a grown sect would build for its Way (M19b), beyond the meditation
## hall and tribulation ground of M19: each want has its own reason, read
## from what has happened to the sect, and only its master and elders
## propose them (sect_places.gd decides who may). Each entry is
## [function, reason label, weight], most pressing first.
const Balance = preload("res://scripts/core/balance.gd")
const SectHalls = preload("res://scripts/sim/sect_halls.gd")
const SectPlaces = preload("res://scripts/sim/sect_places.gd")

## Everything a sect builds for its Way. Its cultivators raise these beside
## the village's own work: they have `halls.sect_sites` sites of their own
## and do not count against the village's.
const PURPOSES: Array[String] = ["meditation_hall", "tribulation_ground", "library", "meditation_room", "tribulation_chamber", "infirmary",
	"spirit_array", "sect_gate", "ancestral_hall", "precept_stele", "bell_tower", "lecture_hall", "alchemy_room"]


## The village's homes and shelters go up beside its common buildings, not
## instead of them: newcomers arriving without a roof would otherwise hold
## every site and no hall, field or granary would ever be raised. Housing
## has `construction.max_open_sites` sites, common work
## `construction.common_sites`, the sect `halls.sect_sites`.
const HOUSING: Array[String] = ["home", "dwelling", "shelter"]


## Which share of the building a purpose falls in: "sect", "housing" or "common".
static func share(purpose: String) -> String:
	if PURPOSES.has(purpose):
		return "sect"
	return "housing" if HOUSING.has(purpose) else "common"


## Open sites that need materials brought in one share.
static func open_sites(sim: RefCounted, settlement_id: int, kind: String) -> int:
	var count: int = 0
	for id in sim.construction.in_settlement(settlement_id):
		var site: Dictionary = sim.construction.get_site(id)
		if share(str(site.purpose)) != kind:
			continue
		var template: RefCounted = sim.template(site.template_id)
		if template == null or not template.bill.is_empty():
			count += 1
	return count


## Whether there is no room for another site needing materials for `purpose`.
static func busy(sim: RefCounted, settlement_id: int, purpose: String) -> bool:
	var kind: String = share(purpose)
	var most: int = Balance.integer({"sect": "halls.sect_sites", "housing": "construction.max_open_sites",
		"common": "construction.common_sites"}[kind])
	return open_sites(sim, settlement_id, kind) >= most


## Everything a sect would build, M19's places first; `agent` null asks for
## the settlement as a whole, otherwise only a master or elder is answered.
static func all(sim: RefCounted, settlement_id: int, have: Dictionary, agent: RefCounted = null) -> Array:
	var result: Array = SectPlaces.wants(sim, settlement_id, have, agent)
	if sim.sects == null or (agent != null and not SectPlaces.leads(sim, agent)):
		return result
	var sect: Dictionary = sim.sects.in_settlement(settlement_id)
	if not sect.is_empty():
		result.append_array(wants(sim, settlement_id, sect, have))
	return result


static func wants(sim: RefCounted, settlement_id: int, sect: Dictionary, have: Dictionary) -> Array:
	var result: Array = []
	var members: Array = []
	for id in sect.members:
		if sim.agents[int(id)].is_present():
			members.append(sim.agents[int(id)])
	var refined: int = 0
	var hurt_by_heaven: bool = int(sect.get("lost_to_heaven", 0)) > 0
	var cracked: bool = false
	var students: int = 0
	for member in members:
		refined += 1 if int(member.cultivation.realm) >= 1 else 0
		cracked = cracked or SectHalls.cracked(member)
		students += 1 if int(member.cultivation.teacher) >= 0 else 0
		for trial in member.cultivation.get("trials", []):
			hurt_by_heaven = hurt_by_heaven or str(trial.outcome) in ["injured", "defied"]
	var count: int = members.size()
	var lacks: Callable = func(function: String) -> bool: return int(have.get(function, 0)) == 0
	var herbs: bool = sim.herbs != null and sim.herbs.count() + int(sim.herbs.pool.plants) > 0
	if herbs and refined >= 1 and lacks.call("alchemy_room"):
		result.append(["alchemy_room", "reason_no_alchemy_room", 0.6])
	if cracked and lacks.call("infirmary"):
		result.append(["infirmary", "reason_no_infirmary", 0.65])
	if hurt_by_heaven and int(have.get("tribulation_ground", 0)) > 0 and lacks.call("tribulation_chamber"):
		result.append(["tribulation_chamber", "reason_no_chamber", 0.6])
	if refined >= Balance.integer("halls.room_members") and lacks.call("meditation_room"):
		result.append(["meditation_room", "reason_no_meditation_room", 0.55])
	if (not sect.get("manuals", []).is_empty() or count >= Balance.integer("halls.library_members")) and lacks.call("library"):
		result.append(["library", "reason_no_library", 0.55])
	if count >= Balance.integer("halls.lecture_members") and students >= 2 and lacks.call("lecture_hall"):
		result.append(["lecture_hall", "reason_no_lecture_hall", 0.5])
	var relics: bool = sim.tree_growth != null and not sim.tree_growth.relics.is_empty()
	if (relics or int(sect.get("mourned", 0)) > 0) and lacks.call("ancestral_hall"):
		result.append(["ancestral_hall", "reason_no_ancestral_hall", 0.45])
	var settlement: Dictionary = sim.settlements.entries.get(settlement_id, {})
	if int(settlement.get("threatened_tick", -1)) >= 0 and lacks.call("bell_tower"):
		result.append(["bell_tower", "reason_no_bell", 0.45])
	if count >= Balance.integer("halls.gate_members") and float(sect.doctrine.openness) >= Balance.number("halls.gate_openness") and lacks.call("sect_gate"):
		result.append(["sect_gate", "reason_no_gate", 0.4])
	if count >= Balance.integer("halls.array_members") and lacks.call("spirit_array"):
		result.append(["spirit_array", "reason_no_array", 0.4])
	var age: float = float(sim.calendar.tick - int(sect.founded_tick)) / sim.calendar.ticks_per_day
	if age >= Balance.number("halls.stele_days") and lacks.call("precept_stele"):
		result.append(["precept_stele", "reason_no_stele", 0.35])
	return result
