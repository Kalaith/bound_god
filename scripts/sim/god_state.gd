extends RefCounted
## What the god itself holds: its divine stock, where it is manifested, its
## renown, the designs it has offered and the requests it has posted.

var divine_stock: Dictionary = {}
## The shrine id the avatar is manifested at (-1 = none, dormant).
var active_shrine_id: int = -1
var dormant: bool = false
var renown: int = 0
## template id -> Template dictionary (a copy, so saves stand alone).
var offered: Dictionary = {}
## template id -> shrine id it was offered at
var offered_at: Dictionary = {}
var grace_until_tick: int = 0
## Where the avatar stands, so people can see the god.
var avatar_cell := Vector3i(-1, -1, -1)
## Events for the presentation to react to: expelled, dormant, transfer.
var events: Array = []


func stock(resource: String) -> int:
	return int(divine_stock.get(resource, 0))


func add_stock(resource: String, amount: int) -> void:
	if resource.is_empty() or amount == 0:
		return
	divine_stock[resource] = maxi(0, stock(resource) + amount)


func take_events() -> Array:
	var result: Array = events
	events = []
	return result


func to_dict() -> Dictionary:
	return {
		"divine_stock": divine_stock.duplicate(), "active_shrine_id": active_shrine_id, "dormant": dormant,
		"renown": renown, "offered": offered.duplicate(true), "offered_at": offered_at.duplicate(),
		"grace_until_tick": grace_until_tick, "avatar_cell": avatar_cell,
	}


func from_dict(data: Dictionary) -> void:
	divine_stock = data.divine_stock
	active_shrine_id = int(data.active_shrine_id)
	dormant = bool(data.dormant)
	renown = int(data.renown)
	offered = data.offered
	offered_at = data.offered_at
	grace_until_tick = int(data.grace_until_tick)
	avatar_cell = data.avatar_cell
