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
## The blocks the god keeps at hand, by hotbar slot (0 = empty). Chosen
## and ordered by the player; nothing is added or removed by itself.
var hotbar: Array = []
## Where the avatar stands, so people can see the god.
var avatar_cell := Vector3i(-1, -1, -1)
## Prompt ids the player has dismissed in this world (presentation state,
## set by an unlogged command; never read by the simulation).
var prompts_dismissed: Array = []
## People the player keeps pinned (ids). Following is a lens: it draws the
## god's attention and wakes meditation, and grants nothing.
var followed: Array = []
## Rules the god leaves for pinned people while meditating:
## agent id -> {mode: "shield" | "defy", limit: Favour it may spend}.
var protect: Dictionary = {}
## Blueprints the god has laid (sim/blueprints.gd), oldest first.
var blueprints: Array = []
var next_blueprint: int = 1
## When the god last transferred between shrines (-1: never); the next
## transfer waits out the cooldown (M21).
var last_transfer_tick: int = -1
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
		"avatar_cell": avatar_cell, "hotbar": hotbar.duplicate(), "prompts_dismissed": prompts_dismissed.duplicate(),
		"followed": followed.duplicate(), "protect": protect.duplicate(true),
		"blueprints": blueprints.duplicate(true), "next_blueprint": next_blueprint,
		"last_transfer_tick": last_transfer_tick,
	}


func from_dict(data: Dictionary) -> void:
	divine_stock = data.divine_stock
	active_shrine_id = int(data.active_shrine_id)
	dormant = bool(data.dormant)
	renown = int(data.renown)
	offered = data.offered
	offered_at = data.offered_at
	avatar_cell = data.avatar_cell
	hotbar = data.hotbar
	# Prompts came after schema 4; older worlds have dismissed none.
	prompts_dismissed = data.get("prompts_dismissed", [])
	followed = data.get("followed", [])
	protect = data.get("protect", {})
	# Blueprints came with M19 (schema 5 worlds may lack them).
	blueprints = data.get("blueprints", [])
	next_blueprint = int(data.get("next_blueprint", 1))
	# Transfers were free of a cooldown before M21.
	last_transfer_tick = int(data.get("last_transfer_tick", -1))
