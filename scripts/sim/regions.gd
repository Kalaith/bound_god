extends RefCounted
## The neighbouring regions' catalog (data/regions.json) and the factions of
## their sects (data/factions.json): lookups only.
const Data = preload("res://scripts/core/data.gd")


static func config() -> Dictionary:
	return Data.file("regions")


static func archetypes() -> Array:
	return config().get("archetypes", [])


static func archetype(id: String) -> Dictionary:
	for entry in archetypes():
		if str(entry.id) == id:
			return entry
	# The hidden realm (M23) is a region of its own kind, not a neighbour.
	if str(config().get("realm", {}).get("id", "")) == id:
		return config().realm
	return {}


static func faction(id: String) -> Dictionary:
	for entry in Data.file("factions").get("factions", []):
		if str(entry.id) == id:
			return entry
	return {}


static func number(key: String) -> float:
	return float(config()[key])
