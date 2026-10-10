extends RefCounted
## Seeded creation of people: travellers, ridge miners, migrants and
## children. All randomness comes from the sim's rng.
const Data = preload("res://scripts/core/data.gd")
const Agent = preload("res://scripts/agents/agent.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const Balance = preload("res://scripts/core/balance.gd")


static func _pick(rng: RandomNumberGenerator, list: Array) -> Variant:
	return list[rng.randi_range(0, list.size() - 1)]


static func _traits(rng: RandomNumberGenerator, count: int, required: Array = []) -> Array:
	var chosen: Array = required.duplicate()
	var pool: Array = []
	for entry in Data.traits():
		pool.append(entry.id)
	var attempts: int = 0
	while chosen.size() < count and attempts < 40:
		attempts += 1
		var id: String = _pick(rng, pool)
		if chosen.has(id):
			continue
		var clash: bool = false
		for other in chosen:
			clash = clash or Data.trait_def(other).excludes.has(id) or Data.trait_def(id).excludes.has(other)
		if not clash:
			chosen.append(id)
	return chosen


## An adult. `role_list` is the names key for former roles.
static func adult(rng: RandomNumberGenerator, id: int, role_list: String = "former_roles") -> RefCounted:
	var agent := Agent.new()
	var names: Dictionary = Data.names()
	agent.id = id
	agent.given_name = _pick(rng, names.given)
	agent.family_name = _pick(rng, names.family)
	agent.age_years = float(rng.randi_range(19, 56))
	agent.portrait = rng.randi_range(0, 5)
	agent.hue = rng.randf()
	agent.traits = _traits(rng, rng.randi_range(2, 3))
	agent.personality = Personality.from_traits(agent.traits)
	var role: Dictionary = _pick(rng, names[role_list])
	agent.backstory = {"origin": _pick(rng, names.origins), "former_role": role.name, "memory": _pick(rng, names.memories)}
	agent.skills = Personality.new_skills()
	for skill in range(Personality.SKILLS.size()):
		agent.skills.levels[skill] = rng.randi_range(0, 3)
	var main: int = Personality.SKILLS.find(role.skill)
	agent.skills.levels[main] = rng.randi_range(4, 8)
	agent.skills.passions.append(main)
	if rng.randf() < 0.5:
		var extra: int = rng.randi_range(0, Personality.SKILLS.size() - 1)
		if not agent.skills.passions.has(extra):
			agent.skills.passions.append(extra)
	var ambition: Dictionary = _pick(rng, Data.ambitions())
	agent.ambition = {"id": ambition.id, "progress": 0.0, "fulfilled": false}
	for need in range(5):
		agent.needs[need] = rng.randf_range(62.0, 86.0)
	agent.needs[Personality.Need.SAFETY] = 90.0
	agent.mood = 50.0
	agent.faith = new_faith()
	agent.cultivation = CultivationState.roll(rng)
	return agent


static func child(rng: RandomNumberGenerator, id: int, mother: RefCounted, father: RefCounted) -> RefCounted:
	var agent := adult(rng, id)
	agent.family_name = father.family_name
	agent.age_years = 0.0
	agent.is_child = true
	agent.parents = [mother.id, father.id]
	var inherited: Array = []
	for parent in [mother, father]:
		if not parent.traits.is_empty():
			var id_trait: String = _pick(rng, parent.traits)
			if not inherited.has(id_trait):
				inherited.append(id_trait)
	agent.traits = _traits(rng, maxi(inherited.size(), 2), inherited)
	agent.personality = Personality.from_traits(agent.traits)
	agent.hue = lerpf(mother.hue, father.hue, 0.5)
	# A spiritual root runs in families: half from the parents, half new.
	var parents_talent: float = (float(mother.cultivation.get("talent", 0.0)) + float(father.cultivation.get("talent", 0.0))) * 0.5
	agent.cultivation.talent = clampf(lerpf(float(agent.cultivation.talent), parents_talent, Balance.number("cultivation.inherit_talent")), 0.0, 1.0)
	var parents_drive: float = maxf(float(mother.cultivation.get("drive", 0.0)), float(father.cultivation.get("drive", 0.0)))
	agent.cultivation.drive = clampf(lerpf(float(agent.cultivation.drive), parents_drive, Balance.number("cultivation.inherit_drive")), 0.0, 1.0)
	for skill in range(Personality.SKILLS.size()):
		agent.skills.levels[skill] = 0
	agent.backstory = {"origin": "", "former_role": "", "memory": ""}
	return agent


static func new_faith() -> Dictionary:
	return {
		"knows": false, "devotion": 0.0, "aspects": PackedFloat32Array([0.2, 0.2, 0.2, 0.2, 0.2]),
		"shrine_id": -1, "last_prayer_tick": -1, "last_intent": {}, "stories_heard": 0, "saw_god": false, "witnessed": [], "harmed_tick": -1,
	}
