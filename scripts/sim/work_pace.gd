extends RefCounted
## How fast hands work: a person's skill, slowed under an open sky by rain,
## storm or snow, and quickened by tools in hand, which wear with each tick
## of gathering or building (M20). Called once per tick of work.
const Personality = preload("res://scripts/agents/personality.gd")
const Crafts = preload("res://scripts/sim/crafts.gd")


static func speed(sim: RefCounted, agent: RefCounted, skill: int) -> float:
	return Personality.speed(agent, skill) * sky(sim, agent) * Crafts.tool_pace(agent, skill)


## The weather's pace for someone working where it reaches them.
static func sky(sim: RefCounted, agent: RefCounted) -> float:
	if sim.weather == null or sim.weather.work() >= 1.0 or agent.inside >= 0:
		return 1.0
	if sim.voxels.is_roofed(agent.cell + Vector3i.UP, 6):
		return 1.0
	return sim.weather.work()
