extends RefCounted
## Plan steps and their outcomes. A step is a Dictionary {op, ...args}; a
## plan is {id, steps, cursor, step_ticks}; a plan option is {id, steps,
## preference}. Step outcomes are ints: RUNNING, DONE, or a FailReason >= 0.

enum Op {
	GO_TO, TAKE_STOCK, DEPOSIT, DELIVER, PLACE_BLOCK, MARK_SITE, HARVEST, FORAGE, PICK_UP,
	EAT, SLEEP, SHELTER, RELAX, RECOVER, HIDE, WAIT,
	TALK, SEND, WAIT_FOR_HELP, GIVE, ATTACK, SCOUT, BREAK,
	PRAY, TEND, JOIN, REPAIR_BLOCK, LEAVE, TREAT,
	PLANT, SETTLE,
	SOW, REAP, TEND_CROPS, ADD_TO_POT, COOK,
	CULTIVATE, TEACH, WAIT_TO_LEARN, PROCLAIM,
}
const OP_NAMES: Array[String] = [
	"go_to", "take_stock", "deposit", "deliver", "place_block", "mark_site", "harvest", "forage", "pick_up",
	"eat", "sleep", "shelter", "relax", "recover", "hide", "wait",
	"talk", "send", "wait_for_help", "give", "attack", "scout", "break",
	"pray", "tend", "join", "repair_block", "leave", "treat",
	"plant", "settle",
	"sow", "reap", "tend_crops", "add_to_pot", "cook",
	"cultivate", "teach", "wait_to_learn", "proclaim",
]

enum Fail { NO_PATH, TARGET_GONE, STOCK_EMPTY, DEPLETED, OCCUPIED, REFUSED, TIMED_OUT, INTERRUPTED, TOO_DANGEROUS, NO_SITE }
const FAIL_NAMES: Array[String] = [
	"no_path", "target_gone", "stock_empty", "depleted", "occupied", "refused", "timed_out", "interrupted",
	"too_dangerous", "no_site",
]
const RUNNING: int = -2
const DONE: int = -1

## Movement targets.
enum T { CELL, STRUCTURE, SITE, AGENT, STORE, SHRINE, CONSTRUCTION }

## Conversation topics.
enum Topic { SMALL_TALK, INSULT, COMFORT, FLIRT, RECONCILE, STORY }
const TOPIC_NAMES: Array[String] = ["small_talk", "insult", "comfort", "flirt", "reconcile", "story"]


static func target(type: int, id: int = -1, cell: Vector3i = Vector3i(-1, -1, -1)) -> Dictionary:
	return {"type": type, "id": id, "cell": cell}


static func go_to(where: Dictionary) -> Dictionary:
	return {"op": Op.GO_TO, "target": where}


static func go_cell(cell: Vector3i) -> Dictionary:
	return go_to(target(T.CELL, -1, cell))


static func step(op: int, args: Dictionary = {}) -> Dictionary:
	var result: Dictionary = args.duplicate()
	result["op"] = op
	return result


static func option(id: String, preference: float, steps: Array) -> Dictionary:
	return {"id": id, "preference": preference, "steps": steps}


static func plan_from(option_value: Dictionary) -> Dictionary:
	return {"id": option_value.id, "steps": option_value.steps.duplicate(true), "cursor": 0, "step_ticks": 0}


static func current(plan: Dictionary) -> Dictionary:
	if plan.is_empty() or int(plan.cursor) >= plan.steps.size():
		return {}
	return plan.steps[plan.cursor]


## Plan options sorted by preference, ties by id so the order never depends
## on the unstable sort.
static func sort_options(options: Array) -> void:
	options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.preference != b.preference:
			return a.preference > b.preference
		return a.id < b.id)
