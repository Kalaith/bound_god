extends RefCounted
## Social steps: talking, sending messages, giving, waiting for help.
const Plans = preload("res://scripts/agents/plans.gd")


static func run(_sim: RefCounted, _agent: RefCounted, _step: Dictionary, _step_ticks: int) -> int:
	return Plans.Fail.INTERRUPTED
