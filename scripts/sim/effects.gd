extends RefCounted
## Everything agents want to change outside themselves this tick. Execution
## pushes here; effects_apply.gd applies it once at the end of the tick, so
## every agent in a tick reads the same world.

## Typed messages {from, to, kind, tick, ...}, delivered to inboxes.
var messages: Array = []
## World changes in push order: {type, agent, ...}.
var actions: Array = []
## Conversations {from, to, topic}, resolved with both people at hand.
var interactions: Array = []


func message(from: int, to: int, kind: String, tick: int, fields: Dictionary = {}) -> void:
	var entry: Dictionary = fields.duplicate()
	entry["from"] = from
	entry["to"] = to
	entry["kind"] = kind
	entry["tick"] = tick
	messages.append(entry)


func action(type: String, agent: int, fields: Dictionary = {}) -> void:
	var entry: Dictionary = fields.duplicate()
	entry["type"] = type
	entry["agent"] = agent
	actions.append(entry)


func interaction(from: int, to: int, topic: int) -> void:
	interactions.append({"from": from, "to": to, "topic": topic})


func clear() -> void:
	messages.clear()
	actions.clear()
	interactions.clear()
