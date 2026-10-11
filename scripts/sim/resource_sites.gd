extends RefCounted
## Resource sites: a tree, a bush, a grass patch, a boulder, an ore outcrop.
## NPC beliefs remember sites by id, as Final Landing's nodes. The site list
## follows the voxel grid: removing a site's block lowers its amount.
const Registry = preload("res://scripts/world/block_registry.gd")

## A spirit herb is ripe at this stage (Herbs.RIPE).
const HERB_RIPE: int = 2
const RESOURCE_OF: Dictionary = {"tree": "wood", "bush": "berries", "grass": "thatch", "rock": "stone", "ore": "ore", "herb": "herb",
	"ginseng": "ginseng", "thunder_root": "thunder_root", "frost_lotus": "frost_lotus"}
## Herb blocks and the site kind each is (M20b): the kind is the resource.
const HERB_SITES: Dictionary = {"spirit_herb": "herb", "jade_ginseng": "ginseng", "thunder_root": "thunder_root", "frost_lotus": "frost_lotus"}

## id -> {id, kind, cells: Array[Vector3i], amount: int, leaves?: Array}
var sites: Dictionary = {}
## Vector3i -> site id
var by_cell: Dictionary = {}
var next_id: int = 1
## Bumped when a site appears or disappears, for spatial buckets.
var version: int = 0


func load_generated(list: Array) -> void:
	for site in list:
		_add(site)


func _add(site: Dictionary) -> void:
	version += 1
	site.id = next_id
	next_id += 1
	sites[site.id] = site
	for cell in site.cells:
		by_cell[cell] = site.id


func add(kind: String, cells: Array, amount: int) -> int:
	var site: Dictionary = {"id": 0, "kind": kind, "cells": cells, "amount": amount}
	_add(site)
	return site.id


func get_site(id: int) -> Dictionary:
	return sites.get(id, {})


func resource_of(id: int) -> String:
	var site: Dictionary = sites.get(id, {})
	return RESOURCE_OF.get(site.get("kind", ""), "")


static func kind_for_resource(resource: String) -> String:
	for kind in RESOURCE_OF:
		if RESOURCE_OF[kind] == resource:
			return kind
	return ""


## Where a person stands to work the site: its first remaining cell.
func anchor(id: int) -> Vector3i:
	var site: Dictionary = sites.get(id, {})
	if site.is_empty() or site.cells.is_empty():
		return Vector3i(-1, -1, -1)
	return site.cells[0]


## Keep the list true to the grid after any block change at `cell`.
func on_block_changed(cell: Vector3i, old_block: int, new_block: int, world: RefCounted) -> void:
	if by_cell.has(cell):
		var id: int = by_cell[cell]
		var site: Dictionary = sites[id]
		if site.kind == "bush":
			if new_block != Registry.id("berry_bush"):
				_remove(id)
			else:
				site.amount = world.block_meta(cell)
			return
		# A herb is worth gathering only when ripe.
		if site.kind in HERB_SITES.values():
			if HERB_SITES.get(Registry.block_name(new_block), "") != site.kind:
				_remove(id)
			else:
				site.amount = 1 if world.block_meta(cell) >= HERB_RIPE else 0
			return
		if new_block == old_block:
			return
		by_cell.erase(cell)
		site.cells.erase(cell)
		site.amount = maxi(0, int(site.amount) - Registry.yields[old_block])
		if site.cells.is_empty() or site.amount <= 0:
			_remove(id)
	elif new_block == Registry.id("berry_bush"):
		add("bush", [cell], world.block_meta(cell))
	elif HERB_SITES.has(Registry.block_name(new_block)):
		add(HERB_SITES[Registry.block_name(new_block)], [cell], 1 if world.block_meta(cell) >= HERB_RIPE else 0)


func _remove(id: int) -> void:
	version += 1
	var site: Dictionary = sites.get(id, {})
	for cell in site.get("cells", []):
		by_cell.erase(cell)
	sites.erase(id)


func ids_sorted() -> Array:
	var keys: Array = sites.keys()
	keys.sort()
	return keys


func to_dict() -> Dictionary:
	return {"sites": sites.duplicate(true), "next_id": next_id}


func from_dict(data: Dictionary) -> void:
	version += 1
	sites = data.sites
	next_id = int(data.next_id)
	by_cell.clear()
	for id in sites:
		for cell in sites[id].cells:
			by_cell[cell] = id
