extends RefCounted
## Cultivation plans: sit in the densest qi to hand (or where one stands),
## ask a teacher and wait to be taught, go and teach a student who asked,
## and gather one's students under the tree to found a sect.
const Balance = preload("res://scripts/core/balance.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Plans = preload("res://scripts/agents/plans.gd")
const H = preload("res://scripts/agents/plan_helpers.gd")
const DeliberationCultivation = preload("res://scripts/agents/deliberation_cultivation.gd")
const Elixirs = preload("res://scripts/sim/elixirs.gd")
const PlansAlchemy = preload("res://scripts/agents/plan_library_alchemy.gd")

const Kind = Goals.Kind
const Op = Plans.Op
const T = Plans.T


static func plans(sim: RefCounted, agent: RefCounted, goal: Dictionary) -> Array:
	var sit: int = Balance.integer("cultivation.sit_ticks")
	match int(goal.kind):
		Kind.CULTIVATE:
			var result: Array = []
			var spot: Vector3i = DeliberationCultivation.spot(sim, agent)
			if spot.x >= 0:
				var sitting: Array = [Plans.go_cell(spot), Plans.step(Op.CULTIVATE, {"ticks": sit})]
				result.append(H.option("meditate_in_qi", 1.0, sitting))
				# A qi-gathering pill (or a mortal's cup of awakening tea) first, when the stores hold one.
				var elixir: String = Elixirs.for_sitting(sim, agent)
				if not elixir.is_empty() and agent.beliefs.believes_stock(elixir):
					result.append(H.option("take_%s_first" % elixir, 1.1, H.free_hands(agent) + PlansAlchemy.take(agent, elixir) + sitting))
			result.append(H.option("meditate_here", 0.2, [Plans.step(Op.CULTIVATE, {"ticks": sit / 2})]))
			return result
		Kind.LEARN:
			var teacher: int = int(goal.target)
			return [H.option("ask_to_learn", 1.0, [
				Plans.go_to(Plans.target(T.AGENT, teacher)),
				Plans.step(Op.SEND, {"to": teacher, "kind": "request_help", "need": Goals.HelpNeed.TEACHING}),
				Plans.step(Op.WAIT_TO_LEARN, {"with": teacher, "ticks": Balance.integer("agents.help_wait_ticks") + Balance.integer("cultivation.teach_ticks") * 2}),
			])]
		Kind.TEACH:
			var student: int = int(goal.target)
			return [H.option("teach_student", 1.0, [
				Plans.go_to(Plans.target(T.AGENT, student)),
				Plans.step(Op.TEACH, {"to": student, "ticks": Balance.integer("cultivation.teach_ticks")}),
			])]
		Kind.BREAKTHROUGH:
			var trial: Dictionary = sim.tribulations.of(agent.id)
			if not trial.is_empty():
				return [H.option("hold_through_the_storm", 1.0, [Plans.step(Op.FACE_HEAVEN, {})])]
			var site: Vector3i = DeliberationCultivation.trial_site(sim, agent)
			var steps: Array = [Plans.go_cell(site)] if site.x >= 0 else []
			steps.append(Plans.step(Op.FACE_HEAVEN, {}))
			var options: Array = [H.option("face_heaven", 1.0, steps)]
			# Pills in the stores are taken first, kept for when Heaven answers:
			# a foundation pill and a thunder-warding pill.
			var pills: Array = []
			for pill in Elixirs.KEPT:
				if Elixirs.would_take(sim, agent, pill) and agent.beliefs.believes_stock(pill):
					pills.append_array(PlansAlchemy.take(agent, pill))
			if not pills.is_empty():
				options.append(H.option("take_a_pill_first", 1.1, pills + steps))
			return options
		Kind.SHARE_FRUIT:
			var recipient: int = int(goal.target)
			var tree: Vector3i = sim.features.get("sacred_tree", Vector3i(-1, -1, -1))
			var below: Vector3i = H.ring_cell(sim, Vector3(tree.x + 1.0, tree.y, tree.z + 1.0), agent.id, 2.0, 3.0)
			var carrying: bool = not agent.carrying.is_empty() and str(agent.carrying.resource) == "spirit_fruit"
			var steps: Array = []
			if not carrying:
				steps = H.free_hands(agent)
				steps.append(Plans.go_cell(below))
				steps.append(Plans.step(Op.PICK_FRUIT, {"with": recipient}))
			elif recipient == agent.id:
				steps.append(Plans.step(Op.HAND_FRUIT, {"to": recipient}))
			if recipient != agent.id:
				steps.append(Plans.go_to(Plans.target(T.AGENT, recipient)))
				steps.append(Plans.step(Op.HAND_FRUIT, {"to": recipient}))
			return [H.option("share_fruit" if recipient != agent.id else "take_fruit", 1.0, steps)]
		Kind.FOUND_SECT:
			var spot: Vector3i = DeliberationCultivation.spot(sim, agent)
			var steps: Array = [Plans.go_cell(spot)] if spot.x >= 0 else []
			steps.append(Plans.step(Op.PROCLAIM, {"ticks": Balance.integer("cultivation.proclaim_ticks")}))
			return [H.option("proclaim_sect", 1.0, steps)]
	return []
