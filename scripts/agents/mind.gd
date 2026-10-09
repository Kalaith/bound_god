extends RefCounted
## Thoughts: stacking, decaying mood effects. A thought is a Dictionary
## {id, mood, remaining, about}; an agent's `thoughts` is an Array of them.
const Data = preload("res://scripts/core/data.gd")


## Add a thought from society.json. At its stack limit the oldest copy is
## refreshed instead of stacking another.
static func add(agent: RefCounted, id: String, ticks_per_day: int, about: int = -1) -> void:
	var definition: Dictionary = Data.thought(id)
	if definition.is_empty():
		push_error("Unknown thought " + id)
		return
	var duration: int = int(float(definition.days) * ticks_per_day)
	var same: Array = []
	for thought in agent.thoughts:
		if thought.id == id:
			same.append(thought)
	if same.size() >= int(definition.max_stack):
		var oldest: Dictionary = same[0]
		for thought in same:
			if thought.remaining < oldest.remaining:
				oldest = thought
		oldest.remaining = duration
		oldest.about = about
		return
	agent.thoughts.append({"id": id, "mood": float(definition.mood), "remaining": duration, "about": about})


static func has(agent: RefCounted, id: String) -> bool:
	for thought in agent.thoughts:
		if thought.id == id:
			return true
	return false


static func remove(agent: RefCounted, id: String) -> void:
	var kept: Array = []
	for thought in agent.thoughts:
		if thought.id != id:
			kept.append(thought)
	agent.thoughts = kept


static func tick(agent: RefCounted, ticks: int = 1) -> void:
	var expired: bool = false
	for thought in agent.thoughts:
		thought.remaining -= ticks
		expired = expired or thought.remaining <= 0
	if expired:
		var kept: Array = []
		for thought in agent.thoughts:
			if thought.remaining > 0:
				kept.append(thought)
		agent.thoughts = kept


static func total(agent: RefCounted) -> float:
	var sum: float = 0.0
	for thought in agent.thoughts:
		sum += float(thought.mood)
	return sum
