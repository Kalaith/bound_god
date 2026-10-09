extends RefCounted
## Resolves conversations with both people at hand: small talk (with gossip,
## sightings and designs passed on), insults and fights, flirting, making
## peace, comfort, and stories of the god. Bond changes reach the chronicle.
const Balance = preload("res://scripts/core/balance.gd")
const Data = preload("res://scripts/core/data.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const Mind = preload("res://scripts/agents/mind.gd")
const Beliefs = preload("res://scripts/agents/beliefs.gd")
const Plans = preload("res://scripts/agents/plans.gd")
const FaithState = preload("res://scripts/agents/faith_state.gd")

const Topic = Plans.Topic
const Need = Personality.Need


## Directional: how a's traits sit with b's.
static func compatibility(a: RefCounted, b: RefCounted) -> float:
	var score: float = 0.0
	for id in a.traits:
		var definition: Dictionary = Data.trait_def(id)
		for other in b.traits:
			if definition.bonds_with.has(other):
				score += Balance.number("social.trait_bond_bonus")
			if definition.clashes_with.has(other):
				score -= Balance.number("social.trait_clash_penalty")
	return score


static func resolve(sim: RefCounted, entry: Dictionary) -> void:
	var a: RefCounted = sim.agents[int(entry.from)]
	var b: RefCounted = sim.agents[int(entry.to)]
	if not a.is_present() or not b.is_present() or a.id == b.id:
		return
	var before_a: String = a.beliefs.bond_with(b.id)
	var before_b: String = b.beliefs.bond_with(a.id)
	match int(entry.topic):
		Topic.SMALL_TALK:
			_small_talk(sim, a, b)
		Topic.INSULT:
			_insult(sim, a, b)
		Topic.FLIRT:
			_flirt(sim, a, b)
		Topic.RECONCILE:
			_reconcile(sim, a, b)
		Topic.COMFORT:
			_comfort(sim, a, b)
		Topic.STORY:
			if sim.faith != null:
				sim.faith.tell_story(sim, a, b)
				if sim.requests != null:
					sim.requests.on_story(sim, a, b)
	_note_bonds(sim, a, b, before_a, before_b)


static func _hostile(bond: String) -> bool:
	return bond == "rival" or bond == "enemy"


static func _note_bonds(sim: RefCounted, a: RefCounted, b: RefCounted, before_a: String, before_b: String) -> void:
	var after_a: String = a.beliefs.bond_with(b.id)
	var after_b: String = b.beliefs.bond_with(a.id)
	var warmth: bool = after_a == after_b and not _hostile(after_a) and (before_a != after_a or before_b != after_b)
	if warmth or (_hostile(after_a) and before_a != after_a):
		_bond_event(sim, before_a, after_a, a, b)
	elif _hostile(after_b) and before_b != after_b:
		_bond_event(sim, before_b, after_b, b, a)


static func _bond_event(sim: RefCounted, before: String, after: String, a: RefCounted, b: RefCounted) -> void:
	var kind: String = ""
	match after:
		"friend":
			kind = "" if before == "close_friend" else "became_friends"
		"close_friend":
			kind = "became_close_friends"
		"rival":
			kind = "" if before == "enemy" else "became_rivals"
		"enemy":
			kind = "became_enemies"
	if not kind.is_empty():
		sim.chronicle_event(kind, a.settlement_id, {"a": a.given_name, "b": b.given_name}, "", [a.id, b.id])


static func _small_talk(sim: RefCounted, a: RefCounted, b: RefCounted) -> void:
	var rng: RandomNumberGenerator = sim.rng
	var mood: float = (a.mood + b.mood - 100.0) / 50.0 * 2.0
	var friction: float = maxf(a.personality.temper + b.personality.temper, 0.0) * 0.25 - minf(compatibility(a, b), 0.0) * 0.02
	if rng.randf() < minf(friction, 0.45):
		_insult(sim, a, b)
		return
	var span: Array = Balance.list("social.chat_opinion_range")
	var delta_a: float = rng.randf_range(float(span[0]), float(span[1])) + compatibility(a, b) * 0.8 + mood
	var delta_b: float = rng.randf_range(float(span[0]), float(span[1])) + compatibility(b, a) * 0.8 + mood
	Beliefs.change_opinion(a.beliefs.relation(b.id), delta_a)
	Beliefs.change_opinion(b.beliefs.relation(a.id), delta_b)
	var familiarity: float = Balance.number("social.familiarity_per_chat")
	for pair in [[a, b.id], [b, a.id]]:
		var relation: Dictionary = pair[0].beliefs.relation(pair[1])
		relation.familiarity = minf(float(relation.familiarity) + familiarity, 100.0)
	b.change_need(Need.SOCIAL, Balance.number("social.chat_social_gain") * 0.8)
	var day: int = sim.calendar.ticks_per_day
	if delta_a > 3.0:
		Mind.add(a, "good_chat", day, b.id)
	if delta_b > 3.0:
		Mind.add(b, "good_chat", day, a.id)
	_gossip(sim, a, b)
	_knowledge(sim, a, b)
	# Believers bring the god into conversation.
	if sim.faith != null and FaithState.stage(a.faith) >= 3 and FaithState.stage(b.faith) < FaithState.stage(a.faith) and sim.rng.randf() < 0.25:
		sim.faith.tell_story(sim, a, b)


static func _gossip(sim: RefCounted, a: RefCounted, b: RefCounted) -> void:
	if sim.rng.randf() >= 0.35:
		return
	var about: int = -1
	var strongest: float = -1.0
	var ids: Array = a.beliefs.relations.keys()
	ids.sort()
	for id in ids:
		var opinion: float = a.beliefs.opinion_of(id)
		if id != b.id and absf(opinion) > strongest:
			about = id
			strongest = absf(opinion)
	if about >= 0:
		sim.effects.message(a.id, b.id, "gossip", sim.calendar.tick, {"about": about, "opinion": a.beliefs.opinion_of(about)})


## Sightings and designs pass from one to the other in conversation.
static func _knowledge(sim: RefCounted, a: RefCounted, b: RefCounted) -> void:
	if sim.rng.randf() < 0.5:
		var unknown: Array = []
		var ids: Array = a.beliefs.sites.keys()
		ids.sort()
		for id in ids:
			if int(a.beliefs.sites[id].amount) > 1 and not b.beliefs.sites.has(id):
				unknown.append(id)
		if not unknown.is_empty():
			var id: int = unknown[sim.rng.randi_range(0, unknown.size() - 1)]
			var belief: Dictionary = a.beliefs.sites[id]
			sim.effects.message(a.id, b.id, "inform_site", sim.calendar.tick,
				{"site": id, "site_kind": belief.kind, "cell": belief.cell, "amount": belief.amount, "seen_tick": belief.seen_tick})
	if sim.rng.randf() < 0.3:
		for id in a.beliefs.known_templates:
			if not b.beliefs.known_templates.has(id):
				sim.effects.message(a.id, b.id, "template_info", sim.calendar.tick, {"template_id": id})
				break
	if sim.rng.randf() < 0.4:
		var keys: Array = a.beliefs.places.keys()
		keys.sort()
		for key in keys:
			if not b.beliefs.places.has(key):
				sim.effects.message(a.id, b.id, "inform_place", sim.calendar.tick, {"key": key, "place": a.beliefs.places[key].duplicate()})
				break


static func _flirt(sim: RefCounted, a: RefCounted, b: RefCounted) -> void:
	var receptive: bool = b.beliefs.opinion_of(a.id) > 15.0 and b.partner < 0 and not b.is_child
	var gain: float = Balance.number("social.romance_gain_per_flirt")
	if receptive:
		var theirs: Dictionary = b.beliefs.relation(a.id)
		theirs.romance = float(theirs.romance) + gain * (1.0 + b.personality.romance * 0.5)
		var mine: Dictionary = a.beliefs.relation(b.id)
		mine.romance = float(mine.romance) + gain
		Beliefs.change_opinion(theirs, 2.0)
		if float(mine.romance) >= Balance.number("social.partner_romance_threshold"):
			sim.effects.message(a.id, b.id, "propose", sim.calendar.tick)
	else:
		Beliefs.change_opinion(b.beliefs.relation(a.id), -2.0)
		Mind.add(a, "frustrated", sim.calendar.ticks_per_day, b.id)


static func _insult(sim: RefCounted, a: RefCounted, b: RefCounted) -> void:
	Beliefs.change_opinion(b.beliefs.relation(a.id), -12.0)
	Beliefs.change_opinion(a.beliefs.relation(b.id), -3.0)
	var day: int = sim.calendar.ticks_per_day
	Mind.add(b, "insulted", day, a.id)
	var fights: bool = (b.personality.temper > 0.25 or a.personality.temper > 0.4) and sim.rng.randf() < 0.5
	if fights:
		for pair in [[a, b], [b, a]]:
			pair[0].health.hp = maxf(float(pair[0].health.hp) - 6.0, 0.0)
			pair[0].health.injuries = int(pair[0].health.injuries) + 1
			Mind.add(pair[0], "fought", day, pair[1].id)
	sim.chronicle_event("fight" if fights else "insult", a.settlement_id, {"a": a.given_name, "b": b.given_name}, "", [a.id, b.id])


static func _reconcile(sim: RefCounted, a: RefCounted, b: RefCounted) -> void:
	var chance: float = 0.4 + b.personality.kindness * 0.3 - b.personality.temper * 0.3 + (b.beliefs.opinion_of(a.id) + 50.0) / 200.0
	if sim.rng.randf() < clampf(chance, 0.05, 0.95):
		Beliefs.change_opinion(a.beliefs.relation(b.id), 12.0)
		Beliefs.change_opinion(b.beliefs.relation(a.id), 12.0)
		sim.chronicle_event("reconciled", a.settlement_id, {"a": a.given_name, "b": b.given_name}, "", [a.id, b.id])
	else:
		Beliefs.change_opinion(a.beliefs.relation(b.id), -3.0)


static func _comfort(sim: RefCounted, a: RefCounted, b: RefCounted) -> void:
	var day: int = sim.calendar.ticks_per_day
	Mind.add(b, "comforted", day, a.id)
	Beliefs.change_opinion(b.beliefs.relation(a.id), 8.0)
	Beliefs.change_opinion(a.beliefs.relation(b.id), 3.0)
	b.change_need(Need.SOCIAL, 15.0)
	Mind.add(a, "helped_friend", day, b.id)
