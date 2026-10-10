extends RefCounted
## Worn paths (M19): every step on a column wears it a little; each day the
## wear fades by a share and the day's steps are added. Grass worn past a
## threshold turns to path, which navigation prefers slightly; a path walked
## so little that its wear falls away grasses over again. Only the detailed
## world walks: while abstract, paths keep as they were.
const Balance = preload("res://scripts/core/balance.gd")
const Registry = preload("res://scripts/world/block_registry.gd")

## Vector2i column -> wear (kept while it is above nothing or the ground is path)
var wear: Dictionary = {}
## Vector2i column -> steps taken on it today
var _today: Dictionary = {}


func step_on(cell: Vector3i) -> void:
	var column := Vector2i(cell.x, cell.z)
	_today[column] = int(_today.get(column, 0)) + 1


func daily(sim: RefCounted) -> void:
	var keep: float = Balance.number("paths.wear_keep")
	var worn: float = Balance.number("paths.wear_to_path")
	var faded: float = Balance.number("paths.wear_to_grass")
	var grass: int = Registry.id("grass")
	var path: int = Registry.id("path")
	for column in _today:
		wear[column] = float(wear.get(column, 0.0))
	_today_into_wear(keep)
	var edits: Array = []
	var columns: Array = wear.keys()
	columns.sort()
	for column in columns:
		var top: int = sim.voxels.top_solid_y(column.x, column.y)
		var cell := Vector3i(column.x, top, column.y)
		var block: int = sim.voxels.get_block(cell) if top >= 0 else 0
		var value: float = float(wear[column])
		if block == grass and value >= worn:
			edits.append([cell, path, 0])
		elif block == path and value < faded:
			edits.append([cell, grass, 0])
			wear.erase(column)
		elif block != path and value < faded:
			wear.erase(column)
	if not edits.is_empty():
		sim.set_blocks(edits, "wear")
		for entry in edits:
			sim.nav.set_ground_weight(entry[0])


func _today_into_wear(keep: float) -> void:
	for column in wear:
		wear[column] = float(wear[column]) * keep + float(_today.get(column, 0))
	_today.clear()


func to_dict() -> Dictionary:
	return {"wear": wear.duplicate(), "today": _today.duplicate()}


func from_dict(data: Dictionary) -> void:
	wear = data.get("wear", {})
	_today = data.get("today", {})
