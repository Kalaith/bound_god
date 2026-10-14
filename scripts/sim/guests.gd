extends RefCounted
## Guests seeking sanctuary (M22). A cultivator of a neighbouring region's
## sect, at a realm's peak, may set out to face Heaven beneath the sacred
## tree when their region knows of it and their sect is not hostile to the
## valley's (`sim.sanctuary`, kept by the campaign). In the valley the guest
## stays as a wayfarer does and asks the sect's master, who decides by the
## sect's doctrine, their own nature, the relation between the sects and the
## sect's own trials waiting (goal ADMIT_GUEST; at once while the valley is
## abstract). Admitted, the guest faces Heaven in the sanctuary (the tree
## learns from it), leaves a gift and goes home; refused, they go home. The
## road home and the relation's change are the campaign's (`sim.outbound`).
## A guest's record: backstory.guest = {region, home, sect, relation,
## admitted: -1 undecided | 0 refused | 1 admitted, trials: count on arrival, day}.
const Balance = preload("res://addons/hatchery/core/balance.gd")
const Regions = preload("res://scripts/sim/regions.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const Mind = preload("res://scripts/agents/mind.gd")
const Sects = preload("res://scripts/sim/sects.gd")
const FaithPeople = preload("res://scripts/sim/faith_people.gd")


static func config() -> Dictionary:
	return Regions.config().guests


static func is_guest(agent: RefCounted) -> bool:
	return agent.backstory.has("guest")


## A guest may face Heaven here only once admitted; anyone else may.
static func may_face(agent: RefCounted) -> bool:
	return not is_guest(agent) or int(agent.backstory.guest.admitted) == 1


# --- In the guest's own region -------------------------------------------------

## Whether a cultivator about to face Heaven would rather go to the tree.
## Decided once at each peak (a roll from the world, the person and the
## peak, so asking again changes nothing and draws nothing from the stream).
static func would_seek(sim: RefCounted, agent: RefCounted) -> bool:
	if sim.region_id == 0 or not bool(sim.sanctuary.get("open", false)) or is_guest(agent):
		return false
	var c: Dictionary = agent.cultivation
	if int(c.get("sect_id", -1)) < 0 or int(c.realm) < 1 or not CultivationState.has_next(c) or not CultivationState.at_peak(c):
		return false
	var nerve: float = 0.5 + 0.3 * float(agent.personality.curiosity) + 0.2 * float(c.drive)
	var roll: float = float(absi(hash([sim.world_seed, sim.region_id, agent.id, int(c.peak_tick), "sanctuary"])) % 10000) / 10000.0
	return roll < float(config().seek) * nerve


## The cultivator leaves their region for the valley, meaning to come back.
static func set_out(sim: RefCounted, agent: RefCounted) -> void:
	var sect: Dictionary = sim.sects.get_sect(int(agent.cultivation.sect_id))
	agent.life = "away"
	agent.intention = {}
	agent.path.clear()
	sim.goal_version += 1
	sim.outbound.append({"kind": "guest", "region": 0, "agent": agent.id, "record": agent.to_dict(),
		"sect": {"id": int(sect.id), "name": Sects.name_key(sect), "faction": str(sect.get("faction", ""))}})
	sim.chronicle_event("guest_set_out", agent.settlement_id, {"name": agent.full_name()}, "cause_sought_sanctuary", [agent.id])


## A guest comes home: as they left, with what Heaven gave them, or dead.
static func come_home(sim: RefCounted, trip: Dictionary) -> void:
	var agent: RefCounted = sim.agents[int(trip.home)] if int(trip.home) < sim.agents.size() else null
	if agent == null or agent.life != "away":
		return
	var Lifecycle = load("res://scripts/sim/lifecycle.gd")
	agent.life = "present"
	agent.next_deliberation = sim.calendar.tick
	sim.goal_version += 1
	if bool(trip.get("dead", false)):
		Lifecycle.die(sim, agent, "cause_died_facing_heaven_abroad")
		return
	var c: Dictionary = trip.record.get("cultivation", {})
	for key in ["realm", "progress", "foundation", "trials", "peak_tick", "flawed", "next_factor", "toxicity"]:
		if c.has(key):
			agent.cultivation[key] = c[key]
	agent.health.hp = float(trip.record.get("health", {}).get("hp", agent.health.hp))
	var outcome: String = str(trip.get("outcome", "refused"))
	sim.chronicle_event("guest_came_home", agent.settlement_id, {"name": agent.full_name()}, "cause_guest_%s" % outcome, [agent.id])


# --- In the valley -------------------------------------------------------------

## A guest arrives at the tree's settlement and waits to be received.
static func welcome(sim: RefCounted, agent: RefCounted, trip: Dictionary) -> void:
	agent.backstory["wayfarer"] = true
	agent.backstory["guest"] = {"region": int(trip.from), "home": int(trip.agent), "sect": str(trip.sect.name), "faction": str(trip.sect.faction),
		"sect_id": int(trip.sect.id), "relation": float(trip.get("relation", 0.0)), "admitted": -1, "trials": agent.cultivation.get("trials", []).size(),
		"day": sim.calendar.day()}
	agent.faith["knows"] = true
	FaithPeople.gain(agent, 10.0)
	sim.chronicle_event("guest_arrived", agent.settlement_id, {"name": agent.full_name(), "sect": str(trip.sect.name)}, "cause_sought_sanctuary", [agent.id])


## Guests waiting to be received in a settlement, in id order.
static func waiting(sim: RefCounted, settlement_id: int) -> Array:
	var result: Array = []
	for agent in sim.settlements.present_residents(sim, settlement_id):
		if is_guest(agent) and int(agent.backstory.guest.admitted) < 0:
			result.append(agent)
	return result


## The master's judgement of a guest: [score, cause]. Above nothing, admitted.
static func judge(sim: RefCounted, master: RefCounted, guest: RefCounted) -> Array:
	var sect: Dictionary = sim.sects.get_sect(int(master.cultivation.sect_id))
	var d: Dictionary = sect.get("doctrine", {})
	var w: Dictionary = config().weights
	var terms: Dictionary = {
		"open": float(w.openness) * (float(d.get("openness", 0.5)) - 0.5),
		"mercy": float(w.mercy) * (float(d.get("mercy", 0.5)) - 0.5),
		"secret": -float(w.secrecy) * (float(d.get("secrecy", 0.5)) - 0.5),
		"kind": float(w.kindness) * float(master.personality.kindness),
		"relation": float(w.relation) * float(guest.backstory.guest.relation) / 100.0,
		"crowded": -float(w.waiting) * float(_waiting_trials(sim, sect)),
	}
	var score: float = float(w.base)
	for key in terms:
		score += float(terms[key])
	# The reason given is the weightiest thing on the side the master came down on.
	var leaning: float = 1.0 if score >= 0.0 else -1.0
	var cause: String = "custom"
	var strongest: float = 0.0
	for key in ["open", "mercy", "secret", "kind", "relation", "crowded"]:
		if float(terms[key]) * leaning > strongest:
			strongest = float(terms[key]) * leaning
			cause = key
	return [score, "cause_guest_%s_%s" % ["admit" if leaning > 0.0 else "refuse", cause]]


## The sect's own people near a realm's peak, who would wait behind a guest.
static func _waiting_trials(sim: RefCounted, sect: Dictionary) -> int:
	var count: int = 0
	for id in sect.get("members", {}):
		var member: RefCounted = sim.agents[id]
		if member.is_present() and CultivationState.at_peak(member.cultivation) and CultivationState.has_next(member.cultivation):
			count += 1
	return count


## The master receives a guest: admits or refuses them, and says why.
static func receive(sim: RefCounted, master: RefCounted, guest: RefCounted) -> void:
	if not is_guest(guest) or int(guest.backstory.guest.admitted) >= 0:
		return
	var verdict: Array = judge(sim, master, guest)
	var admitted: bool = float(verdict[0]) >= 0.0
	guest.backstory.guest.admitted = 1 if admitted else 0
	var sect: Dictionary = sim.sects.get_sect(int(master.cultivation.sect_id))
	sim.chronicle_event("guest_admitted" if admitted else "guest_refused", guest.settlement_id,
		{"master": master.full_name(), "name": guest.full_name(), "sect": str(guest.backstory.guest.sect)}, str(verdict[1]), [master.id, guest.id])
	Mind.add(guest, "welcomed" if admitted else "turned_away", sim.calendar.ticks_per_day)
	sim.outbound.append({"kind": "relation", "sect": int(sect.get("id", -1)), "other_region": int(guest.backstory.guest.region),
		"other_sect": int(guest.backstory.guest.sect_id), "amount": float(config().admit_relation) if admitted else -float(config().refuse_relation),
		"cause": str(verdict[1])})


## With no sect to ask, nobody bars the way.
static func unasked(sim: RefCounted, guest: RefCounted) -> void:
	guest.backstory.guest.admitted = 1
	sim.chronicle_event("guest_admitted_unasked", guest.settlement_id, {"name": guest.full_name()}, "cause_no_sect_to_ask", [guest.id])


## Daily (and while abstract, deciding at once): guests are received, and
## those whose trial is done, who were refused or who waited too long go home.
static func daily(sim: RefCounted, abstract: bool = false) -> void:
	if sim.region_id != 0:
		return
	for agent in sim.agents.duplicate():
		if not agent.is_present() or not is_guest(agent):
			continue
		var guest: Dictionary = agent.backstory.guest
		if int(guest.admitted) < 0:
			var sect: Dictionary = sim.sects.in_settlement(agent.settlement_id)
			if sect.is_empty():
				unasked(sim, agent)
			elif abstract or sim.calendar.day() - int(guest.day) >= int(config().wait_days):
				# While abstract (or when the master never came) the master
				# decides from afar, by the same judgement.
				receive(sim, sim.agents[int(sect.master)], agent)
		var faced: bool = agent.cultivation.get("trials", []).size() > int(guest.trials)
		var overstayed: bool = sim.calendar.day() - int(guest.day) >= int(config().stay_days)
		if int(guest.admitted) == 0 or faced or overstayed:
			leave(sim, agent, "refused" if int(guest.admitted) == 0 else ("faced" if faced else "waited"))


## A guest goes home, leaving a gift if they faced Heaven here.
static func leave(sim: RefCounted, agent: RefCounted, outcome: String) -> void:
	var guest: Dictionary = agent.backstory.guest
	if outcome == "faced":
		var gift: Dictionary = config().gift
		for resource in gift:
			sim.settlements.store_any(sim, agent.settlement_id, resource, int(gift[resource]), sim.settlements.get_settlement(agent.settlement_id).get("camp", agent.cell))
		var sect: Dictionary = sim.sects.in_settlement(agent.settlement_id)
		var technique: String = str(Regions.faction(str(guest.faction)).get("technique", ""))
		if not sect.is_empty() and not technique.is_empty() and float(guest.relation) >= float(Regions.config().relations.friendly) and not sect.manuals.has(technique):
			sect.manuals.append(technique)
			sim.chronicle_event("manual_given", agent.settlement_id, {"name": agent.full_name(), "technique": "technique_" + technique, "sect": Sects.name_key(sect)},
				"cause_guest_gift", [agent.id])
	var trials: Array = agent.cultivation.get("trials", [])
	var last: String = str(trials.back().get("outcome", "")) if outcome == "faced" and not trials.is_empty() else outcome
	sim.outbound.append({"kind": "returning", "region": int(guest.region), "home": int(guest.home), "record": agent.to_dict(), "outcome": last})
	var EffectsApply = load("res://scripts/sim/effects_apply.gd")
	EffectsApply._leave(sim, agent, "cause_went_home", false)


## A guest who died facing Heaven here is mourned at home.
static func on_death(sim: RefCounted, agent: RefCounted) -> void:
	if not is_guest(agent):
		return
	var guest: Dictionary = agent.backstory.guest
	sim.outbound.append({"kind": "returning", "region": int(guest.region), "home": int(guest.home), "record": agent.to_dict(), "dead": true, "outcome": "died"})
