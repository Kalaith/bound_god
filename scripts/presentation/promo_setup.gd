extends RefCounted
## Promoter capture hook (declared as `promotion/setup_script`). The shared
## driver calls `prepare` before the start scene loads and `action` for a
## plan's `hook` actions. It only uses the player's own routes into the game:
## a new world from a seed or a saved slot, the god's normal transfer to
## another region, time simulated forward, the game's speed, the camera and the
## inspector. It never stamps, grants or edits world state.
const Session = preload("res://scripts/presentation/session.gd")
const Campaign = preload("res://scripts/sim/campaign.gd")
const WorldIO = preload("res://scripts/presentation/world_io.gd")
const SaveStore = preload("res://scripts/core/save_store.gd")
const SettingsStore = preload("res://scripts/core/settings_store.gd")
const Validation = preload("res://scripts/core/validation.gd")

## Longer jumps belong in a saved world: the detailed simulation runs every tick.
const MAX_ADVANCE_HOURS: float = 240.0
## Plan ids of the agents' building options (plan_library_work.gd).
const BUILD_PLANS: Array = ["construct", "deliver_carried", "fetch_from_stores", "fetch_loose"]


## setup: {"seed": int, "options": {...}} for a new world, or {"load": slot};
## optional "region" (region id the god steps into), "advanceHours", and
## "settings" (player preferences such as {"show_guide": false}, saved to the
## run's isolated profile and applied as the title screen would).
static func prepare(setup: Dictionary) -> String:
	var errors: Array[String] = Validation.run()
	if not errors.is_empty():
		return "game data failed validation: %s" % str(errors)
	var preferences := SettingsStore.new()
	preferences.load_settings()
	var settings: Variant = setup.get("settings", {})
	if typeof(settings) != TYPE_DICTIONARY:
		return "setup.settings must be an object"
	for key in settings:
		if not preferences.set_value(str(key), settings[key]):
			return "setting '%s' does not accept %s" % [key, str(settings[key])]
	if not settings.is_empty() and not preferences.save_settings():
		return "the run's settings could not be saved"
	preferences.apply_all(Engine.get_main_loop())
	var campaign: RefCounted = null
	if setup.has("load"):
		Session.slot = str(setup.load)
		campaign = WorldIO.load_slot(Session.slot)
		if campaign == null:
			return "save slot '%s' could not be loaded: %s" % [Session.slot, SaveStore.worlds.last_error]
	else:
		var options: Variant = setup.get("options", {})
		if typeof(options) != TYPE_DICTIONARY:
			return "setup.options must be an object"
		Session.slot = "promo"
		campaign = Campaign.create(maxi(int(setup.get("seed", 1)), 1), options)
	if setup.has("region"):
		var refusal: String = _enter_region(campaign, int(setup.region))
		if not refusal.is_empty():
			return refusal
	var hours: float = float(setup.get("advanceHours", 0.0))
	if hours < 0.0 or hours > MAX_ADVANCE_HOURS:
		return "advanceHours must be from 0 to %d; use a saved world for longer jumps" % MAX_ADVANCE_HOURS
	var sim: RefCounted = campaign.active_sim()
	campaign.run_ticks(roundi(hours * sim.calendar.ticks_per_day / 24.0))
	# The main scene builds itself round a campaign handed over this way, as it
	# does when the god steps into another region.
	Session.campaign = campaign
	Session.mode = "region"
	return ""


## The god's normal transfer to an active shrine in `region`, with its usual costs and refusals.
static func _enter_region(campaign: RefCounted, region: int) -> String:
	if campaign.sim_of(region) == null:
		return "the campaign has no region %d" % region
	if campaign.active == region:
		return ""
	var refusal: String = "transfer_inactive"
	for entry in campaign.shrines():
		if int(entry.region) == region and str(entry.shrine.state) == "active":
			var result: Dictionary = campaign.transfer(region, int(entry.shrine.id))
			if result.ok:
				return ""
			refusal = str(result.reason)
	return "the god cannot step into region %d (%s); use a save where it can" % [region, refusal]


## action: {"type": "hook", "name": ...}
##   "speed" {"value": 0-3}: pause, x1, x3, x10.
##   "look" {"at": "tree" | "construction" | "newest_building" | "settlement" | [x, y, z], "distance", "pitch", "turn"}:
##       hold the overlook camera on a point.
##   "inspect_builder" {"follow": bool}: open the inspector on someone working a building site.
##   "release": hand the camera and inspector back to normal play.
static func action(scene: Node, action: Dictionary) -> String:
	if scene == null or not "sim" in scene or scene.sim == null:
		return "the game world is not running yet"
	var sim: RefCounted = scene.sim
	match str(action.get("name", "")):
		"speed":
			scene.driver.set_speed(int(action.get("value", 1)))
		"look":
			var at: Variant = _point(sim, action.get("at", "tree"))
			if at == null:
				return "nothing to look at for %s" % str(action.get("at", ""))
			_look(scene, at, float(action.get("distance", 30.0)), float(action.get("pitch", -0.7)), float(action.get("turn", 0.0)))
		"inspect_builder":
			var builder: int = _builder(sim)
			if builder < 0:
				return "nobody is working a building site"
			scene.people.select(builder)
			# Following keeps the gaze inside the god's presence, so a builder further out is better shown from a held view.
			scene.inspector._follow.button_pressed = bool(action.get("follow", false))
		"release":
			scene.camera_hold = false
			scene.people.close()
			scene.camera_rig.overlook = false
		_:
			return "unknown Bound God promo action: %s" % str(action.get("name", ""))
	return ""


static func _point(sim: RefCounted, at: Variant) -> Variant:
	if typeof(at) == TYPE_ARRAY and at.size() == 3:
		return Vector3(float(at[0]), float(at[1]), float(at[2]))
	match str(at):
		"tree":
			if sim.features.has("sacred_tree"):
				return Vector3(sim.features.sacred_tree) + Vector3(0.5, 1.0, 0.5)
			return sim.zone_center()
		"settlement":
			var entry: Dictionary = sim.settlements.entries.get(1, {})
			return Vector3(entry.center) + Vector3(0.5, 1.0, 0.5) if not entry.is_empty() else null
		"newest_building":
			var built: Array = sim.structures.built()
			return Vector3(built[-1].anchor) + Vector3(0.5, 1.0, 0.5) if not built.is_empty() else null
		"construction":
			var site_id: int = _busiest_site(sim)
			if site_id < 0:
				return null
			var site: Dictionary = sim.construction.get_site(site_id)
			var middle := Vector3.ZERO
			for entry in site.order:
				middle += Vector3(entry[0])
			return middle / maxf(site.order.size(), 1.0) + Vector3(0.5, 0.5, 0.5)
	return null


## The site with the most blocks still to place.
static func _busiest_site(sim: RefCounted) -> int:
	var best: int = -1
	var most: int = 0
	for id in sim.construction.ids():
		var site: Dictionary = sim.construction.get_site(id)
		var left: int = site.order.size() - int(site.cursor)
		if left > most:
			best = id
			most = left
	return best


static func _builder(sim: RefCounted) -> int:
	for agent in sim.agents:
		if agent.is_present() and BUILD_PLANS.has(str(agent.current_plan().get("id", ""))):
			return int(agent.id)
	return -1


## Hold the overlook on a point, as the game's own verification captures frame a view.
static func _look(scene: Node, at: Vector3, distance: float, pitch: float, turn: float) -> void:
	var camera_rig: Node3D = scene.camera_rig
	var tree: Vector3 = Vector3(scene.sim.features.get("sacred_tree", Vector3i(80, 12, 80)))
	scene.camera_hold = true
	camera_rig.overlook = true
	camera_rig.overlook_center = at
	camera_rig._overlook_distance = distance
	camera_rig._overlook_pitch = pitch
	camera_rig._overlook_yaw = atan2(at.x - tree.x - 1.0, at.z - tree.z - 1.0) + deg_to_rad(turn)
