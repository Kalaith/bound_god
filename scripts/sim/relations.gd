extends RefCounted
## Relations between sects (M22): one score per pair of sects, wherever they
## stand (−100..100). A neighbouring region's sect starts at its faction's
## relation towards everyone else; a branch abroad and the sect it came from
## start close. Scores move with what passes between them (a guest admitted
## or refused, a manual traded, a schism) and the crossing of the friendly
## or hostile line is chronicled in both sects' regions, with its cause.
## Kept by the campaign; sects are named by (region id, sect id).
const Regions = preload("res://scripts/sim/regions.gd")
const Sects = preload("res://scripts/sim/sects.gd")

## "region:sect|region:sect" (the lower first) -> score
var scores: Dictionary = {}


static func key(a_region: int, a_sect: int, b_region: int, b_sect: int) -> String:
	var a: String = "%d:%d" % [a_region, a_sect]
	var b: String = "%d:%d" % [b_region, b_sect]
	return a + "|" + b if a < b else b + "|" + a


## Where a pair stands: what passed between them, else where they began.
func score(campaign: RefCounted, a_region: int, a_sect: int, b_region: int, b_sect: int) -> float:
	var k: String = key(a_region, a_sect, b_region, b_sect)
	if scores.has(k):
		return float(scores[k])
	return start(campaign, a_region, a_sect, b_region, b_sect)


## How a pair begins: kin (a branch abroad and its parent) close, a faction's
## sect at its faction's relation, strangers at nothing.
static func start(campaign: RefCounted, a_region: int, a_sect: int, b_region: int, b_sect: int) -> float:
	var a: Dictionary = campaign.sim_of(a_region).sects.get_sect(a_sect) if campaign.sim_of(a_region) != null else {}
	var b: Dictionary = campaign.sim_of(b_region).sects.get_sect(b_sect) if campaign.sim_of(b_region) != null else {}
	if _kin(a, b_region, b_sect) or _kin(b, a_region, a_sect):
		return float(Regions.config().relations.kin)
	var total: float = 0.0
	for sect in [a, b]:
		if not str(sect.get("faction", "")).is_empty():
			total += float(Regions.faction(str(sect.faction)).get("relation", 0.0))
	return total


static func _kin(sect: Dictionary, region: int, id: int) -> bool:
	var parent: Dictionary = sect.get("parent_abroad", {})
	return not parent.is_empty() and int(parent.region) == region and int(parent.sect) == id


## Moves a pair by `amount`, chronicling a crossing of the friendly or the
## hostile line in both sects' regions.
func change(campaign: RefCounted, a_region: int, a_sect: int, b_region: int, b_sect: int, amount: float, cause: String) -> void:
	var before: float = score(campaign, a_region, a_sect, b_region, b_sect)
	var after: float = clampf(before + amount, -100.0, 100.0)
	scores[key(a_region, a_sect, b_region, b_sect)] = after
	var was: String = standing_of(before)
	var now: String = standing_of(after)
	if was == now:
		return
	var a: Dictionary = campaign.sim_of(a_region).sects.get_sect(a_sect)
	var b: Dictionary = campaign.sim_of(b_region).sects.get_sect(b_sect)
	if a.is_empty() or b.is_empty():
		return
	for side in [[a_region, a, b], [b_region, b, a]]:
		var sim: RefCounted = campaign.sim_of(int(side[0]))
		sim.chronicle_event("relation_%s" % now, int(side[1].settlement_id), {"sect": Sects.name_key(side[1]), "other": Sects.name_key(side[2])}, cause)


## "friendly", "hostile" or "wary" (between the lines).
static func standing_of(value: float) -> String:
	var config: Dictionary = Regions.config().relations
	if value >= float(config.friendly):
		return "friendly"
	if value <= float(config.hostile):
		return "hostile"
	return "wary"


func to_dict() -> Dictionary:
	return {"scores": scores.duplicate()}


func from_dict(data: Dictionary) -> void:
	scores = data.get("scores", {})
