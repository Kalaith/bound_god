extends RefCounted
## Check helpers that raise a starter design at once where a settlement's
## people would choose to build it, as if they had finished it.
const Data = preload("res://scripts/core/data.gd")
const Template = preload("res://scripts/building/template.gd")
const SiteFinder = preload("res://scripts/building/site_finder.gd")


## Stamps the starter design `id` on the site the settlement would pick.
## Returns the origin, or (-1, -1, -1) when there is no room for it.
static func stamp(sim: RefCounted, settlement_id: int, id: String) -> Vector3i:
	var template: RefCounted = Template.from_starter(Data.starter(id))
	var choice: Dictionary = SiteFinder.find(sim, template, sim.settlements.entries[settlement_id])
	if choice.is_empty():
		return Vector3i(-1, -1, -1)
	for entry in choice.order:
		sim.set_block(entry[0], entry[1], entry[2], "test")
	return choice.origin
