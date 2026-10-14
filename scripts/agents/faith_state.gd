extends RefCounted
## A person's faith: whether they know the god, devotion 0-100, what they
## believe the god is (five aspects), the shrine they attend and their last
## prayer. Kept as a plain Dictionary on the agent (see Generation.new_faith).
const Balance = preload("res://addons/hatchery/core/balance.gd")

const STAGES: Array[String] = ["unaware", "aware", "curious", "believer", "devout"]
const ASPECTS: Array[String] = ["harvest", "protection", "travel", "shadow", "wrath"]


static func stage(faith: Dictionary) -> int:
	if not faith.get("knows", false):
		return 0
	var thresholds: Array = Balance.list("faith.stages")
	var devotion: float = float(faith.devotion)
	if devotion >= float(thresholds[2]):
		return 4
	if devotion >= float(thresholds[1]):
		return 3
	if devotion >= float(thresholds[0]):
		return 2
	return 1


static func stage_name(faith: Dictionary) -> String:
	return STAGES[stage(faith)]


static func is_believer(faith: Dictionary) -> bool:
	return stage(faith) >= 3


## Normalise aspects so they sum to one.
static func normalise(aspects: PackedFloat32Array) -> void:
	var sum: float = 0.0
	for value in aspects:
		sum += maxf(value, 0.0)
	if sum <= 0.0:
		for i in range(aspects.size()):
			aspects[i] = 1.0 / aspects.size()
		return
	for i in range(aspects.size()):
		aspects[i] = maxf(aspects[i], 0.0) / sum


static func strongest_aspect(aspects: PackedFloat32Array) -> int:
	var best: int = 0
	for i in range(aspects.size()):
		if aspects[i] > aspects[best]:
			best = i
	return best
