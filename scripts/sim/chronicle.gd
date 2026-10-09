extends RefCounted
## World history with causes. An entry is {tick, day, kind, place, args,
## cause, agents, known}: `args` fill the kind's text template, `cause` says
## why, and `known` is false until someone who could know has told the god.

var entries: Array = []


func add(tick: int, day: int, kind: String, place: String, args: Dictionary, cause: String = "", agents: Array = [], known: bool = true) -> void:
	entries.append({"tick": tick, "day": day, "kind": kind, "place": place, "args": args.duplicate(),
		"cause": cause, "agents": agents.duplicate(), "known": known})


## Entries since a tick, oldest first.
func since(tick: int) -> Array:
	var result: Array = []
	for entry in entries:
		if int(entry.tick) >= tick and entry.known:
			result.append(entry)
	return result


func to_dict() -> Dictionary:
	return {"entries": entries.duplicate(true)}


func from_dict(data: Dictionary) -> void:
	entries = data.entries
