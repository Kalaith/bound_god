extends RefCounted
## Stable structure identities anchored to components; edited rooms are probed
## again before the command returns. Events retain the edit's cause. An edit
## re-probes only the anchors within reach of it, and the structures it
## touches, so a large settlement does not re-probe every room per block.
const Registry = preload("res://scripts/world/block_registry.gd")
const RoomProbe = preload("res://scripts/world/room_probe.gd")
const Rules = preload("res://scripts/building/function_rules.gd")
const Data = preload("res://scripts/core/data.gd")
const ANCHORS: Array[String] = ["bed", "chest", "altar", "hearth", "workbench"]

var entries: Dictionary = {} # int -> structure dictionary
var components: Dictionary = {} # Vector3i -> true
var events: Array = [] # chronicle-ready records with tick and cause
var _next_id: int = 1
## Bumped on every rebuild so caches keyed on structures can tell.
var version: int = 0
var _built: Array = []
var _built_version: int = -1


func initialize(world: RefCounted) -> void:
	for index in range(world.blocks.size()):
		if Registry.component(world.blocks[index]) in ANCHORS:
			components[world.cell_of(index)] = true
	_rebuild(world, components.keys(), entries.keys(), 0, "world_generation")


func on_edit(world: RefCounted, cell: Vector3i, tick: int, source: String) -> void:
	if Registry.component(world.get_block(cell)) in ANCHORS:
		components[cell] = true
	else:
		components.erase(cell)
	var limits: Array = Data.template_limits().max_size
	var reach := Vector3i(int(limits[0]), int(limits[1]), int(limits[2]))
	var anchors: Array = []
	for anchor in components:
		if absi(anchor.x - cell.x) <= reach.x and absi(anchor.z - cell.z) <= reach.z and absi(anchor.y - cell.y) <= reach.y:
			anchors.append(anchor)
	var touched: Array = []
	for id in entries:
		var entry: Dictionary = entries[id]
		if entry.cells.has(cell) or anchors.has(entry.anchor):
			touched.append(id)
			for part in entry.components.values():
				for anchor in part:
					if components.has(anchor) and not anchors.has(anchor):
						anchors.append(anchor)
	if anchors.is_empty() and touched.is_empty():
		return
	_rebuild(world, anchors, touched, tick, source)


## Re-probe `anchors`, replacing the structures in `touched`; ids carry over
## when a new room still holds an old structure's anchor.
func _rebuild(world: RefCounted, anchors: Array, touched: Array, tick: int, cause: String) -> void:
	version += 1
	var previous: Dictionary = {}
	for id in touched:
		previous[id] = entries[id]
		entries.erase(id)
	var covered: Dictionary = {}
	for id in entries:
		covered.merge(entries[id].inside)
	var used: Dictionary = {}
	anchors.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return world.index_of(a) < world.index_of(b))
	var touched_ids: Array = previous.keys()
	touched_ids.sort()
	for anchor in anchors:
		if covered.has(anchor):
			continue
		var room: Dictionary = RoomProbe.probe(world, anchor)
		var result: Dictionary = Rules.evaluate(world, room.cells)
		covered.merge(room.inside)
		if result.functions.is_empty():
			continue
		var id: int = 0
		for old_id in touched_ids:
			if not used.has(old_id) and room.cells.has(previous[old_id].anchor):
				id = old_id
				break
		if id == 0:
			id = _next_id
			_next_id += 1
		used[id] = true
		var residents: Array = previous[id].residents.duplicate() if previous.has(id) else []
		if not result.functions.has("dwelling"):
			residents.clear()
		entries[id] = {"id": id, "anchor": anchor, "cells": room.cells, "inside": room.inside, "closed": room.closed,
			"functions": result.functions, "capacity": result.capacity, "components": result.components,
			"residents": residents, "template_id": previous[id].template_id if previous.has(id) else ""}
		if not previous.has(id) or previous[id].functions != result.functions or previous[id].capacity != result.capacity:
			events.append({"tick": tick, "kind": "structure_changed", "id": id, "cause": cause, "functions": result.functions.duplicate()})
	for id in touched_ids:
		if not entries.has(id):
			events.append({"tick": tick, "kind": "structure_lost", "id": id, "cause": cause, "residents": previous[id].residents.duplicate()})


## Every structure in id order (cached until the next rebuild).
func built() -> Array:
	if _built_version == version:
		return _built
	var ids: Array = entries.keys()
	ids.sort()
	_built = []
	for id in ids:
		_built.append(entries[id])
	_built_version = version
	return _built


func at(cell: Vector3i) -> Dictionary:
	for entry in built():
		if entry.cells.has(cell):
			return entry
	return {}


func to_dict() -> Dictionary:
	return {"entries": entries.duplicate(true), "components": components.duplicate(), "next_id": _next_id, "version": version}


func from_dict(data: Dictionary) -> void:
	entries = data.entries
	components = data.components
	_next_id = int(data.next_id)
	version = int(data.version) + 1
	events = []
