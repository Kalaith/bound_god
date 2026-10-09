extends RefCounted
## Building steps: delivering materials, marking sites and placing blocks.
const Plans = preload("res://scripts/agents/plans.gd")


static func run(_sim: RefCounted, _agent: RefCounted, _step: Dictionary, _step_ticks: int) -> int:
	return Plans.Fail.INTERRUPTED
