extends RefCounted
## Abstract cultivation and company (plan §3.1). Each hour a person with a
## drive to cultivate spends a share of it in meditation, in the qi of their
## spot by the tree (or their settlement's), by the detailed rate; a mortal
## who crosses the threshold enters Qi Refining; one at a realm's peak waits
## as long as their courage and preparation let them, then faces Heaven, and
## the trial is decided by the same odds and outcome table. Each day the
## willing are taught, teachers with students found sects, a sect's master
## hands out the tree's fruit, and neighbours grow fond and pair off.
## A pinned person's trial stops meditation instead (unless a protect rule
## says what to do), so the god can watch it happen.
const Balance = preload("res://scripts/core/balance.gd")
const SectPlaces = preload("res://scripts/sim/sect_places.gd")
const Data = preload("res://scripts/core/data.gd")
const Mind = preload("res://scripts/agents/mind.gd")
const Beliefs = preload("res://scripts/agents/beliefs.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const Schedule = preload("res://scripts/agents/schedule.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const DeliberationCultivation = preload("res://scripts/agents/deliberation_cultivation.gd")
const FruitChoice = preload("res://scripts/agents/fruit_choice.gd")
const EffectsCultivation = preload("res://scripts/sim/effects_cultivation.gd")
const Social = preload("res://scripts/sim/social.gd")
const AbstractPeople = preload("res://scripts/sim/abstract/abstract_people.gd")

## Share of each waking hour spent meditating: a base for anyone who walks
## the Way and more per point of drive (detailed cultivators of modest drive
## sat about six hours a day in the M15 runs; these give about 4 to 7).
const SIT_BASE: float = 0.15
const SIT_SHARE: float = 0.35
const SIT_MOST: float = 0.6
## Meditation is taken in three sittings a day (morning, midday, evening),
## each covering a third of the waking hours.
const SITTINGS: Array = [7.0, 13.0, 19.0]
const SITTING_HOURS: int = 5


## `hours` waking hours of meditation. Returns the id of a pinned person who
## has just decided to face Heaven (meditation must stop), or -1.
static func hour(sim: RefCounted, agent: RefCounted, hours: int = 1) -> int:
	var c: Dictionary = agent.cultivation
	if agent.is_child or c.is_empty() or (float(c.drive) < 0.05 and int(c.realm) == 0):
		return -1
	var share: float = minf((SIT_BASE + SIT_SHARE * float(c.drive)) * (1.0 + Balance.number("cultivation.realm_bonus") * int(c.realm)), SIT_MOST)
	if agent.need(Personality.Need.FOOD) < 40.0:
		share *= 0.5
	share *= hours
	var qi: float = _spot_qi(sim, agent)
	var needed: float = CultivationState.needed(c)
	var rate: float = CultivationState.rate(c, qi)
	if int(c.blessed_until) > sim.calendar.tick:
		rate *= Balance.number("cultivation.bless_factor")
	if not SectPlaces.of(sim, agent.settlement_id, "meditation_hall").is_empty():
		rate *= Balance.number("cultivation.hall_factor")
	c.progress = minf(float(c.progress) + rate * share, needed)
	c.hours = float(c.hours) + share
	if float(c.progress) < needed:
		return -1
	if int(c.realm) == 0:
		EffectsCultivation._advance(sim, agent, qi)
		return -1
	if not CultivationState.has_next(c):
		return -1
	if int(c.peak_tick) < 0:
		c.peak_tick = sim.calendar.tick
		return -1
	return _maybe_trial(sim, agent)


static var _qi_tick: int = -1
static var _qi: Dictionary = {}


static func _spot_qi(sim: RefCounted, agent: RefCounted) -> float:
	var now: int = sim.calendar.tick * 1000003 + sim.get_instance_id()
	if _qi_tick != now:
		_qi_tick = now
		_qi.clear()
	if not _qi.has(agent.settlement_id):
		_qi[agent.settlement_id] = _settlement_qi(sim, agent)
	return float(_qi[agent.settlement_id])


static func _settlement_qi(sim: RefCounted, agent: RefCounted) -> float:
	var tree: Vector3i = sim.features.get("sacred_tree", Vector3i(-1, -1, -1))
	var settlement: Dictionary = sim.settlements.get_settlement(agent.settlement_id)
	var home: Vector3i = settlement.get("center", agent.cell)
	if tree.x >= 0 and Vector2(home.x - tree.x, home.z - tree.z).length() <= Balance.number("cultivation.sanctuary_reach"):
		return sim.qi.density(sim, tree + Vector3i(3, 0, 3))
	return sim.qi.density(sim, home)


## After waiting at the peak as long as their nature allows, they go.
static func _maybe_trial(sim: RefCounted, agent: RefCounted) -> int:
	var c: Dictionary = agent.cultivation
	var courage: float = clampf(0.5 + 0.3 * float(agent.personality.bravery) + 0.3 * float(c.drive), 0.2, 1.2)
	var wait: float = Balance.number("cultivation.peak_days") * (1.6 - courage) * sim.calendar.ticks_per_day
	if float(sim.calendar.tick - int(c.peak_tick)) < wait:
		return -1
	if sim.god.followed.has(agent.id) and not sim.god.protect.has(agent.id):
		return agent.id
	var site: Vector3i = DeliberationCultivation.trial_site(sim, agent)
	sim.tribulations.abstract_trial(sim, agent, site if site.x >= 0 else agent.cell)
	return -1


## Daily: teaching, sects, fruit and courtship.
static func day(sim: RefCounted) -> void:
	_teach(sim)
	_found(sim)
	_fruit(sim)
	_court(sim)


static func _teach(sim: RefCounted) -> void:
	for agent in sim.agents:
		if not agent.is_present() or agent.is_child or agent.cultivation.is_empty():
			continue
		if float(agent.cultivation.drive) < 0.3 and int(agent.cultivation.realm) < 1:
			continue
		var teacher: int = DeliberationCultivation.teacher_for(sim, agent)
		if teacher < 0 or sim.rng.randf() >= 0.3:
			continue
		var lacking: Array = DeliberationCultivation.lacking(agent, sim.agents[teacher])
		if lacking.is_empty():
			continue
		var asker_opinion: float = sim.agents[teacher].beliefs.opinion_of(agent.id)
		if asker_opinion + 20.0 + float(sim.agents[teacher].personality.kindness) * 20.0 <= 0.0:
			continue
		EffectsCultivation._teach(sim, sim.agents[teacher], agent.id, str(lacking[0]))


static func _found(sim: RefCounted) -> void:
	for agent in sim.agents:
		if not agent.is_present() or agent.cultivation.is_empty() or int(agent.cultivation.sect_id) >= 0:
			continue
		if not CultivationState.is_cultivator(agent.cultivation):
			continue
		if DeliberationCultivation.students_here(sim, agent).size() < Balance.integer("cultivation.sect_students"):
			continue
		if not sim.sects.can_found_in(sim, agent.settlement_id):
			continue
		var chance: float = Balance.number("cultivation.found_sect_base") + 0.3 * maxf(float(agent.personality.leadership), 0.0)
		if sim.rng.randf() < chance:
			sim.sects.found(sim, agent)


## The master gives the tree's fruit as they would in person.
static func _fruit(sim: RefCounted) -> void:
	if sim.tree_growth == null:
		return
	for id in sim.sects.ids():
		var sect: Dictionary = sim.sects.entries[id]
		if int(sim.tree_growth.fruit) <= 0 or not sect.members.has(int(sect.master)):
			continue
		var master: RefCounted = sim.agents[int(sect.master)]
		var choice: Array = FruitChoice.choose(sim, sect, master)
		if int(choice[0]) < 0:
			continue
		sim.tree_growth.pick(sim)
		var recipient: RefCounted = sim.agents[int(choice[0])]
		recipient.cultivation.fruit = true
		var kind: String = "fruit_kept" if recipient.id == master.id else "fruit_given"
		var args: Dictionary = {"name": recipient.full_name()}
		if kind == "fruit_given":
			args["giver"] = master.full_name()
			Mind.add(recipient, "given_fruit", sim.calendar.ticks_per_day, master.id)
		sim.chronicle_event(kind, int(sect.settlement_id), args, "%s|%s" % [str(choice[1]), master.given_name], [master.id, recipient.id])


## Neighbours who live side by side grow familiar and, by their natures,
## fond or cold; the fond and romantic among the unpartnered pair off.
static func _court(sim: RefCounted) -> void:
	for id in sim.settlements.ids():
		var people: Array = []
		for agent_id in sim.settlements.entries[id].residents:
			var agent: RefCounted = sim.agents[agent_id]
			if agent.is_present() and not agent.is_child:
				people.append(agent)
		if people.size() < 2:
			continue
		for i in range(people.size()):
			var a: RefCounted = people[i]
			# Each person spends the day with a few others, not everyone.
			for k in range(1, mini(4, people.size())):
				var b: RefCounted = people[(i + k * 7 + sim.calendar.day()) % people.size()]
				if b.id == a.id:
					continue
				var relation: Dictionary = a.beliefs.relation(b.id)
				relation.familiarity = minf(float(relation.familiarity) + 4.0, 100.0)
				Beliefs.change_opinion(relation, 1.0 + Social.compatibility(a, b) * 0.3)
				if a.partner < 0 and b.partner < 0 and a.id < b.id and absf(a.age_years - b.age_years) < 15.0:
					relation.romance = float(relation.romance) + maxf(float(a.personality.romance), 0.0) * 4.0 + 1.0
					var back: Dictionary = b.beliefs.relation(a.id)
					if float(relation.opinion) > 40.0 and float(back.opinion) > 40.0 and float(relation.romance) > Balance.number("social.partner_romance_threshold") \
							and sim.rng.randf() < 0.1:
						a.partner = b.id
						b.partner = a.id
						Mind.add(a, "new_partner", sim.calendar.ticks_per_day, b.id)
						Mind.add(b, "new_partner", sim.calendar.ticks_per_day, a.id)
						sim.chronicle_event("partnership", id, {"a": a.given_name, "b": b.given_name}, "", [a.id, b.id])
