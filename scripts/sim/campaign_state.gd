extends RefCounted
## Saving and restoring a campaign (M22). The home valley keeps its own two
## files (`sim.bin`, `chunks.bin`), so a save from before regions still
## loads; `regions.bin` holds which region the god is in, every other
## region's state and edited chunks, and the abstract record of each frozen
## region (so time already passed abstractly is not surveyed afresh).
## A save without it loads as a campaign of the valley alone, which gains its
## neighbours from the seed.
const SimState = preload("res://scripts/sim/sim_state.gd")
const AbstractWorld = preload("res://scripts/sim/abstract/abstract_world.gd")

const SCHEMA: int = 1


## {"sim": home state, "chunks": home chunks, "regions": Dictionary}.
static func capture(campaign: RefCounted) -> Dictionary:
	var home: Dictionary = SimState.capture(campaign.regions[0].sim)
	var regions: Array = []
	for region in campaign.regions:
		var entry: Dictionary = {"id": int(region.id), "archetype": str(region.archetype), "name": str(region.name), "model": {}}
		if int(region.id) > 0:
			var saved: Dictionary = SimState.capture(region.sim)
			entry["state"] = saved.sim
			entry["chunks"] = saved.chunks
		if campaign.models.has(int(region.id)):
			var model: RefCounted = campaign.models[int(region.id)]
			entry.model = {"from_tick": model.from_tick, "step": model.step, "records": model.records.duplicate(true)}
		regions.append(entry)
	return {"sim": home.sim, "chunks": home.chunks, "regions": {"schema_version": SCHEMA, "active": campaign.active, "seed": campaign.world_seed, "regions": regions,
		"travellers": campaign.travellers.duplicate(true), "relations": campaign.relations.to_dict(), "shared_day": campaign._shared_day,
		"options": campaign.options.duplicate(true), "ages": campaign.ages.duplicate(true), "deeds": campaign.deeds.duplicate(),
		"chronicle_read": campaign.chronicle_read.duplicate(), "kinds_seen": campaign.kinds_seen.duplicate(), "book_closed": campaign.book_closed,
		"realm": campaign.realm}}


## Why a campaign's region file cannot be restored, or "".
static func problem(regions: Variant) -> String:
	if not regions is Dictionary or int(regions.get("schema_version", 0)) > SCHEMA or not regions.get("regions") is Array:
		return "save_version" if regions is Dictionary and int(regions.get("schema_version", 0)) > SCHEMA else "save_damaged"
	for entry in regions.regions:
		if not entry is Dictionary:
			return "save_damaged"
		if int(entry.get("id", 0)) > 0:
			var issue: String = SimState.problem(entry.get("state"), entry.get("chunks"))
			if not issue.is_empty():
				return issue
	return ""


## A campaign from the home valley's state and, if present, the regions file.
static func restore(state: Dictionary, chunks: Dictionary, regions: Variant) -> RefCounted:
	var campaign = load("res://scripts/sim/campaign.gd").new()
	var home: RefCounted = SimState.restore(state, chunks)
	campaign.world_seed = home.world_seed
	campaign.regions.append({"id": 0, "archetype": "", "name": "region_home_valley", "sim": home})
	if not regions is Dictionary:
		# A valley saved before regions: its neighbours come from the seed.
		campaign.add_neighbours()
		load("res://scripts/sim/ages.gd").begin(campaign)
		return campaign
	for entry in regions.regions:
		var id: int = int(entry.id)
		if id > 0:
			campaign.regions.append({"id": id, "archetype": str(entry.archetype), "name": str(entry.name), "sim": SimState.restore(entry.state, entry.chunks)})
	for entry in regions.regions:
		if entry.model.is_empty():
			continue
		var model = AbstractWorld.new()
		model.from_tick = int(entry.model.from_tick)
		model.step = int(entry.model.step)
		model.records = entry.model.records
		campaign.models[int(entry.id)] = model
	campaign.active = int(regions.active)
	campaign.travellers = regions.get("travellers", [])
	campaign.relations.from_dict(regions.get("relations", {}))
	campaign._shared_day = int(regions.get("shared_day", -1))
	# The saga came with M23; older campaigns begin their first age on load.
	campaign.options = regions.get("options", {})
	campaign.ages = regions.get("ages", [])
	campaign.deeds = regions.get("deeds", {})
	campaign.chronicle_read = regions.get("chronicle_read", {})
	campaign.kinds_seen = regions.get("kinds_seen", {})
	campaign.book_closed = bool(regions.get("book_closed", false))
	campaign.realm = int(regions.get("realm", -1))
	load("res://scripts/sim/ages.gd").begin(campaign)
	return campaign
