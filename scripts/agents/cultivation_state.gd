extends RefCounted
## A person's cultivation: spiritual root (talent), affinity, drive to
## cultivate, realm and progress within it, foundation, techniques, teacher,
## students and sect. Plain data in `agent.cultivation`:
## {talent, affinity, drive, realm, progress, foundation, techniques: Array[String],
##  teacher: int, students: Array[int], sect_id: int, hours: float,
##  peak_tick: int (when they reached the peak, -1), blessed_until: int (tick),
##  flawed: bool (a breakthrough Heaven meant to end), next_factor: float (harder next realm),
##  trials: Array of {tick, kind, outcome, sanctuary, severity, shield}}
## Most people have little talent; would-be cultivators drawn by the tree's
## qi arrive with more of it and a stronger drive.
const Balance = preload("res://scripts/core/balance.gd")
const Data = preload("res://scripts/core/data.gd")


static func _weighted(rng: RandomNumberGenerator, list: Array) -> Dictionary:
	var total: float = 0.0
	for entry in list:
		total += float(entry.weight)
	var roll: float = rng.randf() * total
	for entry in list:
		roll -= float(entry.weight)
		if roll <= 0.0:
			return entry
	return list.back()


## A new person's cultivation. A seeker is a would-be cultivator.
static func roll(rng: RandomNumberGenerator, seeker: bool = false) -> Dictionary:
	var data: Dictionary = Data.cultivation()
	var band: Dictionary = _weighted(rng, data.seeker_talent if seeker else data.talent)
	var talent: float = rng.randf_range(float(band.range[0]), float(band.range[1]))
	var affinity: String = str(_weighted(rng, data.affinities).id)
	var drive_range: Array = data.drive.seeker if seeker else data.drive.ordinary
	var drive: float = rng.randf_range(float(drive_range[0]), float(drive_range[1]))
	return fresh(talent, affinity, drive)


static func fresh(talent: float, affinity: String, drive: float) -> Dictionary:
	return {"talent": talent, "affinity": affinity, "drive": drive, "realm": 0, "progress": 0.0,
		"foundation": Balance.number("cultivation.start_foundation"), "techniques": [], "teacher": -1, "students": [],
		"sect_id": -1, "hours": 0.0, "peak_tick": -1, "blessed_until": -1, "flawed": false, "next_factor": 1.0, "trials": []}


## For people from saves made before cultivation: a sub-stream seeded from
## the world and the person, so every load of the same save agrees.
static func for_old_save(world_seed: int, id: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, id, "cultivation"])
	return roll(rng, false)


## How long a person may live: mortal old age plus their realm's bonus.
static func lifespan(cultivation: Dictionary) -> float:
	var bonus: float = float(Data.realm(int(cultivation.realm)).get("lifespan_bonus", 0.0))
	if bool(cultivation.flawed):
		bonus *= float(Data.tribulations().outcomes.defied_lifespan)
	return Balance.number("health.old_age_years") + bonus


static func needed(cultivation: Dictionary) -> float:
	return float(Data.realm(int(cultivation.realm)).get("progress_needed", 1.0)) * float(cultivation.next_factor)


## At the top of their realm: only a breakthrough takes them further.
static func at_peak(cultivation: Dictionary) -> bool:
	return float(cultivation.progress) >= needed(cultivation)


static func is_cultivator(cultivation: Dictionary) -> bool:
	return int(cultivation.realm) >= 1


## The label key for how much spiritual root someone has.
static func talent_word(talent: float) -> String:
	if talent < 0.15:
		return "talent_none"
	if talent < 0.4:
		return "talent_weak"
	if talent < 0.7:
		return "talent_fair"
	if talent < 0.9:
		return "talent_strong"
	return "talent_rare"


## How much one hour of meditation in `qi` moves a person on.
static func rate(cultivation: Dictionary, qi: float) -> float:
	var per_hour: float = Balance.number("cultivation.per_hour") * (Balance.number("cultivation.talent_base") + float(cultivation.talent))
	var technique: float = 1.0
	for id in cultivation.techniques:
		technique = maxf(technique, float(Data.technique(id).get("progress", 1.0)))
	var affinity: Dictionary = Data.affinity(str(cultivation.affinity))
	var soundness: float = 1.0
	if int(cultivation.realm) >= 1:
		soundness = Balance.number("cultivation.foundation_base") + Balance.number("cultivation.foundation_weight") * float(cultivation.foundation)
	return per_hour * qi * (1.0 + float(affinity.get("qi_bonus", 0.0))) * technique * soundness


## Whether a breakthrough to the next realm exists for them.
static func has_next(cultivation: Dictionary) -> bool:
	return int(cultivation.realm) + 1 < Data.realms().size()
