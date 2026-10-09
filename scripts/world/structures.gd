extends RefCounted
## Stable structure identities anchored to components; edited rooms are probed
## again before the command returns. Events retain the edit's cause.
const Registry = preload("res://scripts/world/block_registry.gd")
const RoomProbe = preload("res://scripts/world/room_probe.gd")
const Rules = preload("res://scripts/building/function_rules.gd")
const Data = preload("res://scripts/core/data.gd")
const ANCHORS: Array[String] = ["bed", "chest", "altar", "hearth", "workbench"]

var entries: Dictionary = {} # int -> structure dictionary
var components: Dictionary = {} # Vector3i -> true
var events: Array = [] # chronicle-ready records with tick and cause
var _next_id: int = 1


func initialize(world: RefCounted) -> void:
	for index in range(world.blocks.size()):
		if Registry.component(world.blocks[index]) in ANCHORS:
			components[world.cell_of(index)] = true
	_rebuild(world, 0, "world_generation")


func on_edit(world: RefCounted, cell: Vector3i, tick: int, source: String) -> void:
	var relevant: bool = components.has(cell)
	if Registry.component(world.get_block(cell)) in ANCHORS:
		components[cell] = true
		relevant = true
	else:
		components.erase(cell)
	var reach: int = int(Data.template_limits().max_size[0])
	for anchor in components:
		if absi(anchor.x - cell.x) <= reach and absi(anchor.z - cell.z) <= reach:
			relevant = true
			break
	if relevant:
		_rebuild(world, tick, source)


func _rebuild(world: RefCounted, tick: int, cause: String) -> void:
	var previous: Dictionary = entries
	entries = {}
	var used: Dictionary = {}
	var covered: Dictionary = {}
	var anchors: Array = components.keys()
	anchors.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return world.index_of(a) < world.index_of(b))
	for anchor in anchors:
		if covered.has(anchor):
			continue
		var room: Dictionary = RoomProbe.probe(world, anchor)
		var result: Dictionary = Rules.evaluate(world, room.cells)
		covered.merge(room.inside)
		if result.functions.is_empty():
			continue
		var id: int = 0
		for old_id in previous:
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
		entries[id] = {"id": id, "anchor": anchor, "cells": room.cells, "closed": room.closed,
			"functions": result.functions, "capacity": result.capacity, "components": result.components,
			"residents": residents, "template_id": previous[id].template_id if previous.has(id) else ""}
		if not previous.has(id) or previous[id].functions != result.functions or previous[id].capacity != result.capacity:
			events.append({"tick": tick, "kind": "structure_changed", "id": id, "cause": cause, "functions": result.functions.duplicate()})
	for id in previous:
		if not entries.has(id):
			events.append({"tick": tick, "kind": "structure_lost", "id": id, "cause": cause, "residents": previous[id].residents.duplicate()})


func built() -> Array:
	return entries.values()


func at(cell: Vector3i) -> Dictionary:
	for entry in entries.values():
		if entry.cells.has(cell):
			return entry
	return {}
