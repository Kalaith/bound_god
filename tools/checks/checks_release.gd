extends RefCounted
## M25 Release: every save that shipped still loads and goes on (the
## schema-5 M20b save as a campaign that gains its neighbours, and the
## current campaign format), and the long soak (`long_check_`, see tools/soak.gd).
const SimState = preload("res://scripts/sim/sim_state.gd")
const CampaignState = preload("res://scripts/sim/campaign_state.gd")
const Soak = preload("res://tools/soak_run.gd")
const Sim = preload("res://scripts/sim/sim.gd")
const Prompts = preload("res://scripts/presentation/ui/prompts.gd")


static func _fixture(name: String) -> Variant:
	var file := FileAccess.open_compressed("res://tools/fixtures/" + name, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return null
	return bytes_to_var(file.get_buffer(file.get_length()))


func check_an_m20b_save_loads_as_a_campaign():
	var saved: Variant = _fixture("save_v5_alchemy.zst")
	if not saved is Dictionary or int(saved.sim.get("schema_version", -1)) != 5:
		return "the schema 5 fixture is missing or not schema 5"
	if not SimState.problem(saved.sim, saved.chunks).is_empty():
		return "the schema 5 save is refused: " + SimState.problem(saved.sim, saved.chunks)
	var campaign: RefCounted = CampaignState.restore(saved.sim.duplicate(true), saved.chunks, null)
	var home: RefCounted = campaign.active_sim()
	if campaign.regions.size() < 2 or home.present_count() != 19 or home.sects.entries.is_empty():
		return "the old save came back as %d regions, %d people, %d sects" % [campaign.regions.size(), home.present_count(), home.sects.entries.size()]
	if campaign.ages.is_empty():
		return "the old save began no age"
	campaign.run_ticks(home.calendar.ticks_per_hour() * 6)
	if home.present_count() < 15:
		return "the migrated valley lost its people within hours"
	var again: Dictionary = CampaignState.capture(campaign)
	if int(again.sim.schema_version) != SimState.SCHEMA or not again.regions is Dictionary:
		return "the migrated campaign does not save in the current format"
	return ""


func check_the_campaign_fixture_loads_and_goes_on():
	var saved: Variant = _fixture("save_c1_campaign.zst")
	if not saved is Dictionary or not saved.get("regions") is Dictionary:
		return "the campaign fixture is missing"
	if not CampaignState.problem(saved.regions).is_empty():
		return "the campaign fixture is refused: " + CampaignState.problem(saved.regions)
	var campaign: RefCounted = CampaignState.restore(saved.sim, saved.chunks, saved.regions)
	if campaign.regions.size() != 3 or campaign.models.size() != 2:
		return "the campaign came back with %d regions, %d frozen" % [campaign.regions.size(), campaign.models.size()]
	campaign.run_ticks(campaign.active_sim().calendar.ticks_per_hour() * 2)
	for region in campaign.regions:
		if region.sim.present_count() == 0:
			return "%s came back empty" % region.name
	return ""


## The later prompts (M25) appear in their moments, read without changing
## the world, and each goes when dismissed.
func check_the_later_prompts_appear_in_their_moments():
	var sim: RefCounted = Sim.create(11)
	sim.run_ticks(30)
	if _ids(sim).has("prompt_lands") or _ids(sim).has("prompt_realm"):
		return "a new valley already prompts about the lands or the realm"
	sim.traders.append({"region": 1, "region_name": "x", "goods": [], "technique": "", "sect": "", "friendly": true})
	sim.sanctuary["realm"] = true
	sim.tree_growth.unlocks.append("warding_formation")
	sim.chronicle.add(sim.calendar.tick, 30, "age_began", "", {"age": "age_first"})
	var ids: Array = _ids(sim)
	for wanted in ["prompt_lands", "prompt_realm", "prompt_ward", "prompt_saga"]:
		if not ids.has(wanted):
			return "%s did not appear: %s" % [wanted, str(ids)]
	for id in ids:
		sim.apply_command({"type": "dismiss_prompt", "prompt": id})
	var shown: Dictionary = Prompts.current(sim, null, false)
	if not shown.is_empty():
		return "a dismissed prompt came back: %s" % str(shown)
	return ""


static func _ids(sim: RefCounted) -> Array:
	var ids: Array = []
	for prompt in Prompts.contextual(sim):
		ids.append(prompt.id)
	return ids


## The soak (plan M25): 200 meditated years with a detailed day every 25
## years and a save and load midway, no script error, the world whole.
func long_check_two_hundred_years():
	var result: Dictionary = Soak.run(11, 200, 25)
	print("      %s" % str(result.report))
	return str(result.problem)
