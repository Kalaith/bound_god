extends RefCounted
## Crops in tilled ground. A crop is one block above farmland; its growth
## stage is the block's meta, so the world shows it. Each day in a growing
## season a crop counts toward its next stage; one untended for some days
## gains weeds, which stop its growth and halve what it yields until someone
## tends it. Winter kills whatever still stands. Sowing, tending and reaping
## are people's work, applied through Effects.
const Balance = preload("res://addons/hatchery/core/balance.gd")
const Data = preload("res://scripts/core/data.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const TreeAbilities = preload("res://scripts/sim/tree_abilities.gd")

## crop cell -> {crop: id, days: int (days in this stage), tended: int (day), weedy: bool}
var plots: Dictionary = {}
## settlement id -> crops standing still for want of rain today (not saved:
## rebuilt each day from the sky).
var thirsty: Dictionary = {}


static func definition(id: String) -> Dictionary:
	return Data.crop(id)


## The crop people sow: the first in the catalog (one crop so far).
static func staple() -> Dictionary:
	return Data.crops()[0]


static func is_farmland(sim: RefCounted, cell: Vector3i) -> bool:
	return Registry.component(sim.voxels.get_block(cell)) == "farmland"


func stage(sim: RefCounted, cell: Vector3i) -> int:
	return sim.voxels.block_meta(cell)


func is_ripe(sim: RefCounted, cell: Vector3i) -> bool:
	if not plots.has(cell):
		return false
	return stage(sim, cell) >= int(definition(plots[cell].crop).stages) - 1


## Whether a crop sown today would ripen with a few days to reap it before
## winter.
static func can_sow(sim: RefCounted, crop: Dictionary) -> bool:
	var season: String = sim.calendar.season_name()
	if not crop.sow_seasons.has(season):
		return false
	var to_winter: int = (3 - sim.calendar.season()) * sim.calendar.days_per_season - sim.calendar.day_of_season() + 1
	return to_winter > (int(crop.stages) - 1) * int(crop.days_per_stage) + Balance.integer("farming.reap_margin_days")


## An empty cell above farmland where a seed could go.
static func open_plot(sim: RefCounted, cell: Vector3i) -> bool:
	return sim.voxels.get_block(cell) == 0 and is_farmland(sim, cell + Vector3i.DOWN) \
		and not sim.is_occupied(cell) and not sim.is_reserved_cell(cell)


func sow(sim: RefCounted, cell: Vector3i, crop: Dictionary, source: String) -> void:
	plots[cell] = {"crop": crop.id, "days": 0, "tended": sim.calendar.day(), "weedy": false}
	sim.set_block(cell, Registry.id(crop.block), 0, source)


## Keeps the record in step with the world: a crop broken or reaped is gone.
func on_block(cell: Vector3i, block: int) -> void:
	if plots.has(cell) and Registry.block_name(block) != definition(plots[cell].crop).get("block", ""):
		plots.erase(cell)


func tend(sim: RefCounted, cell: Vector3i) -> bool:
	if not plots.has(cell):
		return false
	var was: bool = bool(plots[cell].weedy) or int(plots[cell].tended) < sim.calendar.day()
	plots[cell].tended = sim.calendar.day()
	plots[cell].weedy = false
	return was


## Whether a crop wants tending: weedy, or untended for some days.
func needs_tending(sim: RefCounted, cell: Vector3i) -> bool:
	if not plots.has(cell) or is_ripe(sim, cell):
		return false
	return bool(plots[cell].weedy) or sim.calendar.day() - int(plots[cell].tended) >= Balance.integer("farming.tend_after_days")


## What reaping a ripe crop gives: {harvest resource: amount, seed: amount}.
func reap_yield(cell: Vector3i) -> Dictionary:
	var crop: Dictionary = definition(plots[cell].crop)
	var amount: int = int(crop.yield)
	if bool(plots[cell].weedy):
		amount = maxi(1, int(floor(amount * Balance.number("farming.weedy_yield"))))
	return {"harvest": crop.harvest, "amount": amount, "seed": crop.seed, "seed_amount": int(crop.seed_return)}


## Daily growth. In winter every crop still standing dies.
func daily(sim: RefCounted) -> void:
	var cells: Array = plots.keys()
	cells.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return sim.voxels.index_of(a) < sim.voxels.index_of(b))
	var season: String = sim.calendar.season_name()
	var today: int = sim.calendar.day()
	## settlement id -> crops lost
	var lost: Dictionary = {}
	thirsty.clear()
	for cell in cells:
		var plot: Dictionary = plots[cell]
		var crop: Dictionary = definition(plot.crop)
		if not is_farmland(sim, cell + Vector3i.DOWN) or not crop.seasons.has(season):
			var place: int = sim.settlements.at_cell(cell)
			lost[place] = int(lost.get(place, 0)) + 1
			sim.set_block(cell, 0, 0, "growth")
			continue
		# A ripe crop waits for the reaper; weeds no longer matter to it.
		var now: int = stage(sim, cell)
		if now >= int(crop.stages) - 1:
			continue
		if today - int(plot.tended) >= Balance.integer("farming.weed_days"):
			plot.weedy = true
		if bool(plot.weedy):
			continue
		# A crop grows only within some days of rain.
		if sim.weather != null and sim.weather.dry_days(sim) > int(crop.get("rain_need", 1 << 20)) and not TreeAbilities.watered(sim, cell):
			var dry: int = sim.settlements.at_cell(cell)
			thirsty[dry] = int(thirsty.get(dry, 0)) + 1
			continue
		plot.days = int(plot.days) + 1
		if int(plot.days) >= int(crop.days_per_stage) and now < int(crop.stages) - 1:
			plot.days = 0
			sim.set_block(cell, Registry.id(crop.block), now + 1, "growth")
	var dry_places: Array = thirsty.keys()
	dry_places.sort()
	if not dry_places.is_empty():
		var total: int = 0
		for place in dry_places:
			total += int(thirsty[place])
		sim.weather.note_drought(sim, int(dry_places[0]), total)
	var places: Array = lost.keys()
	places.sort()
	for place in places:
		if place >= 0:
			sim.chronicle_event("crops_lost", place, {"place": sim.settlements.entries[place].name, "amount": lost[place]},
				"cause_winter_frost" if season == "winter" else "cause_ground_gone")


## Bless Growth: every crop in reach grows a stage at once. Returns how many.
func bless(sim: RefCounted, center: Vector3i, radius: float) -> int:
	var cells: Array = plots.keys()
	cells.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return sim.voxels.index_of(a) < sim.voxels.index_of(b))
	var grown: int = 0
	for cell in cells:
		var crop: Dictionary = definition(plots[cell].crop)
		var now: int = stage(sim, cell)
		if Vector2(cell.x - center.x, cell.z - center.z).length() > radius or now >= int(crop.stages) - 1:
			continue
		plots[cell].days = 0
		plots[cell].weedy = false
		sim.set_block(cell, Registry.id(crop.block), now + 1, "god")
		grown += 1
	return grown


func to_dict() -> Dictionary:
	return {"plots": plots.duplicate(true)}


func from_dict(data: Dictionary) -> void:
	plots = data.plots
