extends RefCounted
## What one person believes: a partial, decaying copy of the world. Plans
## read beliefs, never the true world. Every field is plain data so it saves
## with var_to_bytes.
const Balance = preload("res://addons/hatchery/core/balance.gd")

## site id -> {kind, cell, amount, seen_tick}
var sites: Dictionary = {}
## Array of {id, kind, cell, dangerous, seen_tick}
var threats: Array = []
## agent id -> {opinion, familiarity, romance, last_chat_tick}
var relations: Dictionary = {}
## resource -> int, the believed stock of their settlement
var stock: Dictionary = {}
## failed-target key ("site:3", "structure:7", "cell:(1, 2, 3)") -> tick
var failed: Dictionary = {}
## Array of {id, cell}; cleared on each perception pass
var nearby: Array = []
## structure id -> {functions, cell, template_id, seen_tick}
var structures: Dictionary = {}
## "settlement:1" / "shrine:2" -> {kind, id, cell, state, seen_tick}
var places: Dictionary = {}
## Template ids this person knows how to build.
var known_templates: Array = []


func relation(other: int) -> Dictionary:
	if not relations.has(other):
		relations[other] = {"opinion": 0.0, "familiarity": 0.0, "romance": 0.0, "last_chat_tick": -1}
	return relations[other]


func opinion_of(other: int) -> float:
	return float(relations[other].opinion) if relations.has(other) else 0.0


static func change_opinion(entry: Dictionary, amount: float) -> void:
	entry.opinion = clampf(float(entry.opinion) + amount, -100.0, 100.0)


static func bond(entry: Dictionary) -> String:
	var opinion: float = float(entry.opinion)
	if opinion <= Balance.number("social.enemy_threshold"):
		return "enemy"
	if opinion <= Balance.number("social.rival_threshold"):
		return "rival"
	if opinion >= Balance.number("social.close_friend_threshold"):
		return "close_friend"
	if opinion >= Balance.number("social.friend_threshold"):
		return "friend"
	if float(entry.familiarity) >= 10.0:
		return "acquaintance"
	return "stranger"


func bond_with(other: int) -> String:
	return bond(relations[other]) if relations.has(other) else "stranger"


func note_site(id: int, kind: String, cell: Vector3i, amount: int, tick: int) -> void:
	var known: Dictionary = sites.get(id, {})
	if known.is_empty():
		sites[id] = {"kind": kind, "cell": cell, "amount": amount, "seen_tick": tick}
	else:
		known.cell = cell
		known.amount = amount
		known.seen_tick = tick


## Whether any site of a kind with something left is believed (no sorting).
func has_site(kind: String) -> bool:
	for id in sites:
		var belief: Dictionary = sites[id]
		if belief.kind == kind and int(belief.amount) >= 1:
			return true
	return false


func forget_site(id: int) -> void:
	sites.erase(id)


func note_failure(target_key: String, tick: int) -> void:
	failed[target_key] = tick


func recently_failed(target_key: String, now: int, window: int) -> bool:
	return failed.has(target_key) and now - int(failed[target_key]) < window


## Believed sites of a kind with something left, nearest first (ties by id).
func known_sites(kind: String, from: Vector3i) -> Array:
	var found: Array = []
	for id in sites:
		var belief: Dictionary = sites[id]
		if belief.kind == kind and int(belief.amount) >= 1:
			found.append([id, _distance(belief.cell, from)])
	found.sort_custom(func(a: Array, b: Array) -> bool:
		if a[1] != b[1]:
			return a[1] < b[1]
		return a[0] < b[0])
	var result: Array = []
	for entry in found:
		result.append(entry[0])
	return result


func believes_stock(resource: String, amount: int = 1) -> bool:
	return int(stock.get(resource, 0)) >= amount


func note_threat(id: int, kind: String, cell: Vector3i, dangerous: bool, tick: int) -> bool:
	for threat in threats:
		if threat.id == id:
			threat.cell = cell
			threat.seen_tick = tick
			return false
	threats.append({"id": id, "kind": kind, "cell": cell, "dangerous": dangerous, "seen_tick": tick})
	return true


## [threat, distance] of the nearest believed threat, or [] when none.
func nearest_threat(from: Vector3i) -> Array:
	var best: Array = []
	for threat in threats:
		var distance: float = _distance(threat.cell, from)
		if best.is_empty() or distance < best[1]:
			best = [threat, distance]
	return best


func forget_stale(now: int, ticks_per_day: int) -> void:
	var forget_after: int = int(Balance.number("agents.belief_forget_days") * ticks_per_day)
	for id in sites.keys():
		if now - int(sites[id].seen_tick) >= forget_after:
			sites.erase(id)
	var kept: Array = []
	for threat in threats:
		if now - int(threat.seen_tick) < ticks_per_day / 12:
			kept.append(threat)
	threats = kept
	for key in failed.keys():
		if now - int(failed[key]) >= ticks_per_day:
			failed.erase(key)


static func _distance(a: Vector3i, b: Vector3i) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length() + absf(a.y - b.y)


func to_dict() -> Dictionary:
	return {
		"sites": sites.duplicate(true), "threats": threats.duplicate(true), "relations": relations.duplicate(true),
		"stock": stock.duplicate(), "failed": failed.duplicate(), "structures": structures.duplicate(true),
		"places": places.duplicate(true), "known_templates": known_templates.duplicate(),
	}


func from_dict(data: Dictionary) -> void:
	sites = data.sites
	threats = data.threats
	relations = data.relations
	stock = data.stock
	failed = data.failed
	structures = data.structures
	places = data.places
	known_templates = data.known_templates
	nearby = []
