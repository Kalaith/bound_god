extends RefCounted
## Sects: institutions cultivators found by their own choice inside a
## settlement. A sect has a name, a master, members with ranks and doctrine
## weights that drift with its leaders. Founding comes from a person's
## FoundSect goal; succession and ranks are settled each day.
## id -> {id, name, settlement_id, founded_tick, founder, master, members: {agent id: rank},
##        doctrine: {openness, martial, secrecy, mercy, ambition}}
var entries: Dictionary = {}
var next_id: int = 1


func ids() -> Array:
	var keys: Array = entries.keys()
	keys.sort()
	return keys


func get_sect(id: int) -> Dictionary:
	return entries.get(id, {})


func to_dict() -> Dictionary:
	return {"entries": entries.duplicate(true), "next_id": next_id}


func from_dict(data: Dictionary) -> void:
	entries = data.entries
	next_id = int(data.next_id)
