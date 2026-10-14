extends RefCounted
## M20b The sect's alchemy, its preparations: each one's effect on the same
## person with and without it, the toxicity pills leave (it slows, fades and
## is refused past the limit; cleansing clears it), tiers that gate recipes,
## failure that falls with skill, wants that choose what is needed, Medicate,
## two crafters at work in a hall at once, and the abstract counterparts.
const Sim = preload("res://scripts/sim/sim.gd")
const Data = preload("res://scripts/core/data.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const PlanLibrary = preload("res://scripts/agents/plan_library.gd")
const DeliberationCultivation = preload("res://scripts/agents/deliberation_cultivation.gd")
const SectHalls = preload("res://scripts/sim/sect_halls.gd")
const Elixirs = preload("res://scripts/sim/elixirs.gd")
const Alchemy = preload("res://scripts/sim/alchemy.gd")
const EffectsApply = preload("res://scripts/sim/effects_apply.gd")
const AbstractAlchemy = preload("res://scripts/sim/abstract/abstract_alchemy.gd")
const Stores = preload("res://tools/checks/stores.gd")
const Build = preload("res://tools/checks/build.gd")
const Balance = preload("res://addons/hatchery/core/balance.gd")
const Crafts = preload("res://scripts/sim/crafts.gd")
const SectHallWants = preload("res://scripts/sim/sect_hall_wants.gd")
const Template = preload("res://scripts/building/template.gd")
const Meditation = preload("res://tools/checks/meditation.gd")

const Kind = Goals.Kind


static func _flat() -> RefCounted:
	return Sim.create(21, {"world": "flat", "size": Vector3i(64, 16, 64), "ground": 4})


static func _cultivator(agent: RefCounted, realm: int) -> void:
	agent.cultivation = CultivationState.fresh(0.6, "none", 0.9)
	agent.cultivation.realm = realm
	agent.cultivation.sect_id = 1


static func _with(sim: RefCounted, function: String) -> Dictionary:
	for entry in sim.structures.built():
		if entry.functions.has(function):
			return entry
	return {}


static func _at_stores(sim: RefCounted, agent: RefCounted) -> void:
	agent.cell = sim.settlements.chest_cells(sim, agent.settlement_id)[0] + Vector3i(1, 0, 0)
	agent.carrying = {}


## A healing draught heals at once and mends a crack a little; awakening tea
## and a qi-gathering pill quicken sittings for a while (tea only for a
## mortal, the pill only for a cultivator); a thunder-warding pill softens
## the storm; a cleansing pill clears toxicity and the crack; a longevity
## elixir adds years, once.
func check_each_preparation_does_its_one_thing():
	var sim: RefCounted = _flat()
	sim.weather.kind = "clear"
	var agent: RefCounted = sim.agents[0]
	_cultivator(agent, 1)
	agent.health.hp = 40.0
	agent.cultivation["sound_foundation"] = 0.6
	agent.cultivation.foundation = 0.4
	var draught: Dictionary = Data.elixir("healing_draught")
	Elixirs.consume(sim, agent, "healing_draught")
	if not is_equal_approx(float(agent.health.hp), 40.0 + float(draught.heal)) or not is_equal_approx(float(agent.cultivation.foundation), 0.4 + float(draught.mend)):
		return "a draught left hp %.1f and foundation %.2f" % [agent.health.hp, agent.cultivation.foundation]
	# Sitting: the pill for a cultivator, never the tea; the tea for a mortal.
	if Elixirs.would_take(sim, agent, "awakening_tea") or Elixirs.for_sitting(sim, agent) != "qi_pill":
		return "a cultivator would drink awakening tea"
	var plain: float = Elixirs.sitting_factor(sim, agent)
	Elixirs.consume(sim, agent, "qi_pill")
	var pill: Dictionary = Data.elixir("qi_pill")
	var poison: float = float(Data.alchemy().toxicity.rate) * float(pill.toxicity)
	if not is_equal_approx(Elixirs.sitting_factor(sim, agent), plain * float(pill.factor) * (1.0 - poison)):
		return "a qi pill made sittings %.3f as fast" % Elixirs.sitting_factor(sim, agent)
	if Elixirs.would_take(sim, agent, "qi_pill"):
		return "a second qi pill was taken while the first still worked"
	sim.calendar.tick += int(float(pill.days) * sim.calendar.ticks_per_day) + 1
	if not is_equal_approx(Elixirs.sitting_factor(sim, agent), 1.0 - poison):
		return "the qi pill worked past its days"
	var mortal: RefCounted = sim.agents[1]
	mortal.cultivation = CultivationState.fresh(0.4, "none", 0.6)
	if Elixirs.for_sitting(sim, mortal) != "awakening_tea":
		return "a mortal would not drink awakening tea"
	Elixirs.consume(sim, mortal, "awakening_tea")
	if not is_equal_approx(Elixirs.sitting_factor(sim, mortal), float(Data.elixir("awakening_tea").factor)) or Elixirs.toxicity(mortal) != 0.0:
		return "awakening tea made sittings %.2f as fast" % Elixirs.sitting_factor(sim, mortal)
	# Warding: the same storm, softer.
	agent.cultivation.progress = CultivationState.needed(agent.cultivation)
	Elixirs.consume(sim, agent, "warding_pill")
	var id: int = sim.tribulations.announce(sim, agent, agent.cell)
	var trial: Dictionary = sim.tribulations.entries[id]
	trial.severity = 0.6
	sim.tribulations._begin(sim, trial, agent)
	if not is_equal_approx(float(trial.severity), 0.6 - float(Data.elixir("warding_pill").severity)) or agent.cultivation.has("warding"):
		return "a warding pill left the storm at %.2f" % trial.severity
	sim.tribulations.entries.erase(id)
	# Cleansing: toxicity and the crack gone.
	agent.cultivation.toxicity = 0.5
	agent.cultivation["sound_foundation"] = 0.6
	agent.cultivation.foundation = 0.3
	Elixirs.consume(sim, agent, "cleansing_pill")
	if Elixirs.toxicity(agent) != 0.0 or SectHalls.cracked(agent):
		return "a cleansing pill left toxicity %.2f, cracked %s" % [Elixirs.toxicity(agent), SectHalls.cracked(agent)]
	# Longevity: years more, once.
	var span: float = CultivationState.lifespan(agent.cultivation)
	Elixirs.consume(sim, agent, "longevity_elixir")
	if not is_equal_approx(CultivationState.lifespan(agent.cultivation), span + float(Data.elixir("longevity_elixir").years)):
		return "a longevity elixir did not add its years"
	if Elixirs.would_take(sim, agent, "longevity_elixir"):
		return "a second longevity elixir would be taken"
	var noted: bool = false
	for entry in sim.chronicle.entries:
		noted = noted or entry.kind == "longevity_taken"
	return "" if noted else "the elixir was not chronicled"


## Toxicity slows sittings and weakens a trial's preparation, fades by the
## day, and a pill that would take someone past the limit is refused.
func check_pill_toxicity_slows_fades_and_is_refused():
	var sim: RefCounted = _flat()
	var agent: RefCounted = sim.agents[0]
	_cultivator(agent, 1)
	var config: Dictionary = Data.alchemy().toxicity
	agent.cultivation["toxicity"] = 0.5
	if not is_equal_approx(Elixirs.sitting_factor(sim, agent), 1.0 - float(config.rate) * 0.5):
		return "toxicity 0.5 left sittings %.2f as fast" % Elixirs.sitting_factor(sim, agent)
	if not is_equal_approx(Elixirs.trial_preparation(agent), -float(config.preparation) * 0.5):
		return "toxicity did not weaken the preparation"
	if Elixirs.would_take(sim, agent, "qi_pill"):
		return "a pill past the toxicity limit was taken"
	if not Elixirs.would_take(sim, agent, "healing_draught"):
		return "a draught, which leaves no toxicity, was refused"
	Elixirs.daily(sim)
	if not is_equal_approx(Elixirs.toxicity(agent), 0.5 - float(config.decay)):
		return "toxicity did not fade by a day"
	Stores.fill(sim, agent.settlement_id, {"qi_pill": 2})
	_at_stores(sim, agent)
	EffectsApply._take_stock(sim, agent, {"resource": "qi_pill", "amount": 1, "settlement": agent.settlement_id})
	if int(agent.step_result.took) != 0 or sim.settlements.amount(agent.settlement_id, "qi_pill") != 2:
		return "the stores gave a pill to someone past the limit"
	return ""


## A building's tier gates its recipes; a batch fails less often for a
## skilled hand in a better building; the wants choose what is needed.
func check_tiers_skill_and_wants_choose_what_is_refined():
	var sim: RefCounted = _flat()
	for agent in sim.agents:
		if agent.is_present():
			_cultivator(agent, 1)
	var recipes: Callable = func(tier: int) -> Array:
		var ids: Array = []
		for want in Alchemy.shortfall(sim, 1, tier):
			ids.append(want.recipe)
		return ids
	if recipes.call(2).has("warding_pill") or not recipes.call(3).has("warding_pill"):
		return "tiers do not gate the thunder-warding pill: %s / %s" % [recipes.call(2), recipes.call(3)]
	if recipes.call(1).has("foundation_pill"):
		return "a herbalist's workshop would refine pills"
	if not Alchemy.fail_chance(0, 2) > Alchemy.fail_chance(8, 2) or not Alchemy.fail_chance(4, 2) > Alchemy.fail_chance(4, 4):
		return "failure does not fall with skill and tier"
	# Nobody hurt: pills before draughts; someone hurt: the draught first.
	var first: String = Alchemy.shortfall(sim, 1, 2)[0].recipe
	if first == "healing_draught":
		return "a draught was wanted before pills with nobody hurt"
	sim.agents[0].health.hp = 20.0
	sim.agents[1].health.hp = 30.0
	first = Alchemy.shortfall(sim, 1, 2)[0].recipe
	if first != "healing_draught":
		return "with two hurt the first want was %s" % first
	# The old want an elixir; only the pavilion's tier makes one.
	sim.agents[0].age_years = CultivationState.lifespan(sim.agents[0].cultivation) - 2.0
	if not recipes.call(4).has("longevity_elixir") or recipes.call(3).has("longevity_elixir"):
		return "an elder's elixir was not wanted at the pavilion's tier alone"
	return ""


## Someone hurt who believes the stores hold a draught goes and takes one,
## and it heals them.
func check_the_hurt_go_for_a_draught():
	var sim: RefCounted = _flat()
	var agent: RefCounted = sim.agents[0]
	agent.health.hp = 30.0
	Stores.fill(sim, agent.settlement_id, {"healing_draught": 1, "berries": 20})
	agent.beliefs.stock = sim.settlements.stock_of(agent.settlement_id).duplicate()
	var out: Array = []
	DeliberationCultivation._medicate(sim, agent, out)
	if out.is_empty() or int(out[0].goal.kind) != Kind.MEDICATE or Elixirs.id_at(int(out[0].goal.target)) != "healing_draught":
		return "the hurt did not think to take a draught: %s" % [out]
	var options: Array = PlanLibrary.plans_for(sim, agent, out[0].goal)
	if options.is_empty() or str(options[0].id) != "take_healing_draught":
		return "no plan to take the draught: %s" % [options]
	_at_stores(sim, agent)
	EffectsApply._take_stock(sim, agent, {"resource": "healing_draught", "amount": 1, "settlement": agent.settlement_id})
	if int(agent.step_result.took) != 1 or float(agent.health.hp) <= 30.0 or not agent.carrying.is_empty():
		return "taking the draught left hp %.1f, carrying %s" % [agent.health.hp, agent.carrying]
	return ""


## Two sect members work side by side in an alchemy hall, each at a bench
## of their own, and the hall's pills reach the stores.
func check_two_crafters_work_a_hall_at_once():
	var sim: RefCounted = _flat()
	Build.stamp(sim, 1, "alchemy_hall")
	var hall: Dictionary = _with(sim, "alchemy_hall")
	if hall.is_empty():
		return "the Alchemy Hall design is not an alchemy hall"
	Stores.fill(sim, 1, {"herb": 30, "ginseng": 6, "berries": 60})
	# Members of little drive: their sittings do not outweigh the furnace.
	for agent in sim.agents:
		if agent.is_present():
			_cultivator(agent, 1)
			agent.cultivation.drive = 0.2
			agent.beliefs.stock = sim.settlements.stock_of(1).duplicate()
			agent.beliefs.structures[int(hall.id)] = {"functions": hall.functions.duplicate(), "cell": hall.anchor, "template_id": "", "seen_tick": 0}
	var together: bool = false
	for step in range(2 * sim.calendar.ticks_per_day / 10):
		sim.run_ticks(10)
		var seats: Dictionary = {}
		for agent in sim.agents:
			if agent.is_present() and not agent.intention.is_empty() and int(agent.intention.goal.kind) == Kind.REFINE:
				seats[int(agent.intention.goal.extra)] = agent.id
		together = together or seats.size() >= 2
	if not together:
		return "two crafters never worked the hall at once"
	var made: int = 0
	for resource in ["pill", "qi_pill", "healing_draught"]:
		made += sim.settlements.amount(1, resource)
	return "" if made > 0 else "nothing refined in the hall reached the stores in two days"


## While abstract: herbs of each kind are gathered from their pools, the
## hall refines what is wanted, and people take what they would take awake.
func check_abstract_alchemy_refines_and_is_taken():
	var sim: RefCounted = _flat()
	Build.stamp(sim, 1, "alchemy_hall")
	Stores.fill(sim, 1, {"berries": 20})
	sim.tree_growth.unlocks.append("spirit_herbs")
	sim.herbs.pool = {"spirit_herb": {"plants": 12, "ripe": 12.0}, "jade_ginseng": {"plants": 4, "ripe": 4.0}, "thunder_root": {"plants": 4, "ripe": 4.0}}
	for agent in sim.agents:
		if agent.is_present():
			_cultivator(agent, 1)
			Personality.practise(agent, Personality.Skill.MEDICINE, 20000.0)
	AbstractAlchemy.day(sim, 1)
	var made: Dictionary = {}
	for resource in ["pill", "qi_pill", "warding_pill"]:
		made[resource] = sim.settlements.amount(1, resource)
	if int(made.warding_pill) < 1 or int(made.pill) < 1:
		return "the abstract hall refined %s" % made
	if sim.herbs.abstract_ripe("thunder_root") >= 4:
		return "no thunder root was gathered from its pool"
	var took: int = 0
	for agent in sim.agents:
		took += 1 if int(agent.cultivation.get("elixir_until", -1)) > sim.calendar.tick else 0
	return "" if took > 0 else "nobody took a qi pill while abstract (stores %d)" % sim.settlements.amount(1, "qi_pill")


## A sect wants an alchemy hall once it has a room, enough members and a
## rarer herb growing; a pavilion once it has a hall, more members and an
## elder in Foundation Establishment; a village with herbs and hands wants a
## herbalist's workshop.
func check_who_wants_the_alchemy_halls():
	var sim: RefCounted = _flat()
	var members: Array = []
	for i in range(Balance.integer("alchemy.pavilion_members")):
		var agent: RefCounted = sim.agents[i % sim.agents.size()]
		members.append(agent)
	_cultivator(members[0], 1)
	sim.herbs.plants[Vector3i(1, 5, 1)] = 0
	var wanted: Callable = func(have: Dictionary, count: int) -> Array:
		var result: Array = []
		for want in SectHallWants._alchemy(sim, members.slice(0, count), 1, have):
			result.append(want[0])
		return result
	if not wanted.call({}, 1).has("alchemy_room"):
		return "the sect did not want an alchemy room with herbs growing"
	var hall_members: int = Balance.integer("alchemy.hall_members")
	if wanted.call({"alchemy_room": 1}, hall_members).has("alchemy_hall"):
		return "the sect wanted a hall before any rarer herb grew or anyone was founded"
	sim.herbs.found["jade_ginseng"] = true
	if not wanted.call({"alchemy_room": 1}, hall_members).has("alchemy_hall") or wanted.call({"alchemy_room": 1}, hall_members - 1).has("alchemy_hall"):
		return "the hall was not wanted at %d members with ginseng growing" % hall_members
	var have: Dictionary = {"alchemy_room": 1, "alchemy_hall": 1}
	if wanted.call(have, members.size()).has("pill_pavilion"):
		return "a pavilion was wanted with nobody in Foundation Establishment"
	members[0].cultivation.realm = 2
	if not wanted.call(have, members.size()).has("pill_pavilion"):
		return "a pavilion was not wanted by a grown sect with a founded elder"
	var village: Array = []
	for want in Crafts.village_wants(sim, 1, Balance.integer("alchemy.workshop_people"), {}):
		village.append(want[0])
	if not village.has("herbal_workshop") or not Crafts.village_wants(sim, 1, Balance.integer("alchemy.workshop_people"), {"herbal_workshop": 1}).filter(func(w: Array) -> bool: return w[0] == "herbal_workshop").is_empty():
		return "the village's want of a herbalist's workshop was %s" % [village]
	return ""


## The M20b exit: on seed 11 with a sect, the tree at Spirit Root and the
## alchemy designs offered, the sect raises an alchemy room or herbalist's
## workshop and an alchemy hall by its own proposals within 60 days,
## refines at least four kinds of preparation and its people take them,
## and thunder root grows where Heaven scorched.
func long_check_the_sect_takes_up_alchemy():
	var valley: Dictionary = Meditation.valley(11)
	var sim: RefCounted = valley.sim
	for id in ["herbalist_hut", "alchemy_room", "alchemy_hall", "pill_pavilion", "herb_garden", "ginseng_house"]:
		sim.apply_command({"type": "offer_template", "template": Template.from_starter(Data.starter(id)).to_dict()})
	sim.tree_growth.maturity = 12.0
	var start: int = sim.calendar.tick
	var seen: Dictionary = {}
	var made: Dictionary = {}
	var taken: Dictionary = {}
	for day in range(60):
		sim.run_ticks(sim.calendar.ticks_per_day)
		for entry in sim.chronicle.since(start):
			if entry.kind in ["first_pill", "first_preparation"]:
				made[str(entry.args.get("made", "resource_pill"))] = true
			if entry.kind == "herb_found" and entry.args.get("herb", "") == "resource_thunder_root" and not seen.has("thunder_root"):
				seen["thunder_root"] = sim.calendar.day()
		for agent in sim.agents:
			for record in agent.decisions:
				if str(record.get("text", "")) == "log_took_elixir":
					taken[str(record.args.elixir)] = true
		for function in ["herbal_workshop", "alchemy_room", "alchemy_hall"]:
			if not seen.has(function) and not _with(sim, function).is_empty():
				seen[function] = sim.calendar.day()
		if (seen.has("alchemy_room") or seen.has("herbal_workshop")) and seen.has("alchemy_hall") and made.size() >= 4 and taken.size() >= 4 and seen.has("thunder_root"):
			break
	print("      days: %s made %s taken %s" % [seen, made.keys(), taken.keys()])
	if not (seen.has("alchemy_room") or seen.has("herbal_workshop")) or not seen.has("alchemy_hall"):
		return "the sect raised %s in 60 days" % [seen]
	if made.size() < 4 or taken.size() < 4:
		return "made %s, taken %s" % [made.keys(), taken.keys()]
	return "" if seen.has("thunder_root") else "no thunder root grew on a scar"
