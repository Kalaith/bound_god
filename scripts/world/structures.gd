extends RefCounted
## Stable structure identities anchored to components; edited rooms are probed
## again before the command returns. Events retain the edit's cause. An edit
## re-probes only the anchors within reach of it, and the structures it
## touches, so a large settlement does not re-probe every room per block.
const Registry = preload("res://scripts/world/block_registry.gd")
const RoomProbe = preload("res://scripts/world/room_probe.gd")
const Rules = preload("res://scripts/building/function_rules.gd")
const Data = preload("res://scripts/core/data.gd")
const ANCHORS: Array[String] = RoomProbe.ANCHORS

var entries: Dictionary = {} # int -> structure dictionary
var components: Dictionary = {} # Vector3i -> true
var events: Array = [] # chronicle-ready records with tick and cause
var _next_id: int = 1
## Bumped on every rebuild so caches keyed on structures can tell.
var version: int = 0
var _built: Array = []
## anchor -> [min x, min z, max x, max z, min y]: the box its last probe read
## (open upward). Not saved; an anchor without one is always probed again.
var _reads: Dictionary = {}
## inside cell -> structure id, for every standing structure (rebuilt on load).
var _owner: Dictionary = {}
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
		_reads.erase(cell)
	var limits: Array = Data.template_limits().max_size
	var reach := Vector3i(int(limits[0]), int(limits[1]), int(limits[2]))
	var anchors: Array = []
	for anchor in components:
		if absi(anchor.x - cell.x) <= reach.x and absi(anchor.z - cell.z) <= reach.z and absi(anchor.y - cell.y) <= reach.y 				and _may_read(anchor, cell):
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


## Many edits at once: one re-probe for every anchor any of them could affect.
func on_edits(world: RefCounted, cells: Array, tick: int, source: String) -> void:
	var limits: Array = Data.template_limits().max_size
	var reach := Vector3i(int(limits[0]), int(limits[1]), int(limits[2]))
	var edited: Dictionary = {}
	for cell in cells:
		edited[cell] = true
		if Registry.component(world.get_block(cell)) in ANCHORS:
			components[cell] = true
		else:
			components.erase(cell)
			_reads.erase(cell)
	var chosen: Dictionary = {}
	for anchor in components:
		for cell in cells:
			if absi(anchor.x - cell.x) <= reach.x and absi(anchor.z - cell.z) <= reach.z and absi(anchor.y - cell.y) <= reach.y \
					and _may_read(anchor, cell):
				chosen[anchor] = true
				break
	var touched: Array = []
	for id in entries:
		var entry: Dictionary = entries[id]
		var hit: bool = chosen.has(entry.anchor)
		if not hit:
			for cell in cells:
				if entry.cells.has(cell):
					hit = true
					break
		if hit:
			touched.append(id)
			for part in entry.components.values():
				for anchor in part:
					if components.has(anchor):
						chosen[anchor] = true
	if chosen.is_empty() and touched.is_empty():
		return
	_rebuild(world, chosen.keys(), touched, tick, source)


## Re-probe `anchors`, replacing the structures in `touched`; ids carry over
## when a new room still holds an old structure's anchor.
func _rebuild(world: RefCounted, anchors: Array, touched: Array, tick: int, cause: String) -> void:
	version += 1
	var previous: Dictionary = {}
	for id in touched:
		previous[id] = entries[id]
		_unindex(entries[id])
		entries.erase(id)
	# Rooms found in this rebuild; the standing ones are in _owner.
	var covered: Dictionary = {}
	var used: Dictionary = {}
	anchors.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return world.index_of(a) < world.index_of(b))
	var touched_ids: Array = previous.keys()
	touched_ids.sort()
	for anchor in anchors:
		if covered.has(anchor) or _owner.has(anchor):
			continue
		var room: Dictionary = RoomProbe.probe(world, anchor)
		_reads[anchor] = _padded(room.reads)
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
		_index(entries[id])
		if not previous.has(id) or previous[id].functions != result.functions or previous[id].capacity != result.capacity:
			events.append({"tick": tick, "kind": "structure_changed", "id": id, "cause": cause, "functions": result.functions.duplicate()})
	for id in touched_ids:
		if not entries.has(id):
			events.append({"tick": tick, "kind": "structure_lost", "id": id, "cause": cause, "residents": previous[id].residents.duplicate()})


func _index(entry: Dictionary) -> void:
	for cell in entry.inside:
		_owner[cell] = entry.id


func _unindex(entry: Dictionary) -> void:
	for cell in entry.inside:
		if int(_owner.get(cell, -1)) == int(entry.id):
			_owner.erase(cell)


## Whether an edit at `cell` could change what probing `anchor` finds.
func _may_read(anchor: Vector3i, cell: Vector3i) -> bool:
	if not _reads.has(anchor) or anchor == cell:
		return true
	var box: Array = _reads[anchor]
	return cell.x >= box[0] and cell.z >= box[1] and cell.x <= box[2] and cell.z <= box[3] and cell.y >= box[4]


## A probe's read box widened by how far the rules look round a component
## (an altar's search for open sky).
static func _padded(reads: Array) -> Array:
	var pad: int = 1
	for rule in Data.function_rules():
		pad = maxi(pad, int(rule.get("sky_or_tree_within", 0)) + 1)
	return [reads[0] - pad, reads[1] - pad, reads[2] + pad, reads[3] + pad, reads[4] - pad]


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
	_owner.clear()
	_reads.clear()
	var ids: Array = entries.keys()
	ids.sort()
	for id in ids:
		_index(entries[id])
