extends RefCounted
## Personality is summed from traits, never edited directly. Skills hold
## levels (cap 20), experience and passions, as Final Landing.
const Data = preload("res://scripts/core/data.gd")
const Balance = preload("res://addons/hatchery/core/balance.gd")

enum Need { FOOD, REST, SHELTER, SOCIAL, RECREATION, SAFETY }
const NEEDS: Array[String] = ["food", "rest", "shelter", "social", "recreation", "safety"]
enum Skill { CONSTRUCTION, GATHERING, SOCIAL, DEFENCE, MEDICINE, EXPLORATION, DEVOTION, CRAFTING }
const SKILLS: Array[String] = ["construction", "gathering", "social", "defence", "medicine", "exploration", "devotion", "crafting"]
const SCALARS: Array[String] = ["sociability", "bravery", "kindness", "diligence", "curiosity", "romance", "temper", "optimism", "leadership"]
const MAX_LEVEL: int = 20


static func from_traits(traits: Array) -> Dictionary:
	var result: Dictionary = {"night_owl": false}
	for key in SCALARS:
		result[key] = 0.0
	var decay := PackedFloat32Array([1, 1, 1, 1, 1, 1])
	var speed := PackedFloat32Array([1, 1, 1, 1, 1, 1, 1, 1])
	for id in traits:
		var modifiers: Dictionary = Data.trait_def(id).get("modifiers", {})
		for key in modifiers:
			match key:
				"night_owl":
					result.night_owl = result.night_owl or bool(modifiers[key])
				"need_decay":
					for need in modifiers[key]:
						decay[NEEDS.find(need)] += float(modifiers[key][need])
				"skill_speed":
					for skill in modifiers[key]:
						speed[SKILLS.find(skill)] += float(modifiers[key][skill])
				_:
					result[key] += float(modifiers[key])
	for i in range(decay.size()):
		decay[i] = maxf(decay[i], 0.2)
	result["need_decay"] = decay
	result["skill_speed"] = speed
	return result


static func new_skills() -> Dictionary:
	var levels := PackedInt32Array()
	levels.resize(SKILLS.size())
	var xp := PackedFloat32Array()
	xp.resize(SKILLS.size())
	return {"levels": levels, "xp": xp, "passions": []}


static func level(skills: Dictionary, skill: int) -> int:
	return skills.levels[skill]


static func has_passion(skills: Dictionary, skill: int) -> bool:
	return skills.passions.has(skill)


## Work speed multiplier for a skill.
static func speed(agent: RefCounted, skill: int) -> float:
	return (0.6 + agent.skills.levels[skill] * Balance.number("work.skill_speed_per_level")) * agent.personality.skill_speed[skill]


## Practise a skill for one tick; returns true when a level is gained.
static func practise(agent: RefCounted, skill: int, amount: float = 1.0) -> bool:
	var skills: Dictionary = agent.skills
	if skills.levels[skill] >= MAX_LEVEL:
		return false
	var gain: float = Balance.number("work.xp_per_tick") * amount
	if skills.passions.has(skill):
		gain *= Balance.number("work.passion_xp_multiplier")
	skills.xp[skill] += gain
	var needed: float = Balance.number("work.xp_per_level") * (1.0 + skills.levels[skill] * 0.15)
	if skills.xp[skill] >= needed:
		skills.xp[skill] -= needed
		skills.levels[skill] += 1
		return true
	return false
