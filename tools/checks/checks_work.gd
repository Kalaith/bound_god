extends RefCounted
## M6 acceptance: an offered dwelling is built by people who chose to, with
## sites, materials and labour that nobody assigned.
const Sim = preload("res://scripts/sim/sim.gd")
const Data = preload("res://scripts/core/data.gd")
const Template = preload("res://scripts/building/template.gd")
const Goals = preload("res://scripts/agents/goals.gd")


static func cottage() -> Dictionary:
	var design: Dictionary = Template.from_starter(Data.starter("miner_hut")).to_dict()
	design.id = "willow_cottage"
	design.name = "Willow Cottage"
	design.author = "local"
	return design


func check_the_cottage_moment():
	var sim: RefCounted = Sim.create(11)
	# The travellers first see the god beside the tree; then it offers the design.
	sim.run_ticks(12)
	var result: Dictionary = sim.apply_command({"type": "offer_template", "template": cottage()})
	if int(result.get("learned", 0)) < 2:
		return "the travellers did not learn the offered design: %s" % str(result)
	if not result.ok:
		return "the offer was refused: " + str(result.reason)
	var started: int = Time.get_ticks_msec()
	var built: int = 0
	for day in range(10):
		sim.run_ticks(sim.calendar.ticks_per_day)
		built = 0
		for entry in sim.structures.built():
			if entry.template_id == "willow_cottage":
				built += 1
		print("      day %d: %d people, %d cottages, %d sites, stock %s" % [sim.calendar.day(), sim.present_count(), built, sim.construction.sites.size(), sim.settlements.stock_of(1)])
	print("      10 days: %.1fs" % ((Time.get_ticks_msec() - started) / 1000.0))
	if built < 2:
		return "only %d cottages after 10 days" % built
	for entry in sim.chronicle.entries:
		if entry.kind == "built" and str(entry.cause).is_empty():
			return "a building was finished without a recorded cause"
	return ""


func check_a_site_without_means_is_not_started() -> String:
	var sim: RefCounted = Sim.create(21, {"world": "flat", "size": Vector3i(64, 16, 64), "ground": 4})
	sim.settlements.entries[1].stock = {"berries": 30}
	sim.run_ticks(12)
	sim.apply_command({"type": "offer_template", "template": cottage()})
	sim.run_ticks(sim.calendar.ticks_per_day)
	if not sim.construction.sites.is_empty():
		return "a site was started with no materials believed anywhere"
	sim.settlements.entries[1].stock = {"berries": 30, "wood": 20}
	sim.settlements.entries[1]["stock"]["stone"] = 20
	sim.settlements.entries[1]["stock"]["thatch"] = 10
	sim.run_ticks(sim.calendar.ticks_per_day)
	if sim.construction.sites.is_empty():
		return "materials in the stores did not lead anyone to found a home"
	for agent in sim.agents:
		if int(agent.current_goal().get("kind", -1)) == Goals.Kind.FOUND_HOME and agent.home >= 0:
			return "someone with a home tried to found another"
	return ""
