extends RefCounted
## Goal kinds. A goal is a plain Dictionary {kind, target, extra} so agent
## state saves with var_to_bytes; `key` is its identity for backoff,
## commitment and the "others pursuing" count.

enum Kind {
	EAT, SLEEP, TAKE_SHELTER, FLEE, SEEK_CARE,
	RELAX, IDLE,
	GATHER, HAUL, BUILD, REPAIR, DEFEND, SCOUT,
	FOUND_HOME, PROPOSE_PROJECT,
	PRAY, TEND_SHRINE, RESTORE_SHRINE, PREACH, QUEST,
	CHAT, COMFORT, COURT, RECONCILE, HELP,
	BREAK, MIGRATE,
	GARDEN, FARM, COOK,
	PLANT_TREES,
	CULTIVATE, TEACH, LEARN, FOUND_SECT,
	BREAKTHROUGH, SHARE_FRUIT,
}

const NAMES: Array[String] = [
	"eat", "sleep", "take_shelter", "flee", "seek_care",
	"relax", "idle",
	"gather", "haul", "build", "repair", "defend", "scout",
	"found_home", "propose_project",
	"pray", "tend_shrine", "restore_shrine", "preach", "quest",
	"chat", "comfort", "court", "reconcile", "help",
	"break", "migrate",
	"garden", "farm", "cook",
	"plant_trees",
	"cultivate", "teach", "learn", "found_sect",
	"breakthrough", "share_fruit",
]

const SURVIVAL: Array[int] = [Kind.EAT, Kind.SLEEP, Kind.TAKE_SHELTER, Kind.FLEE, Kind.SEEK_CARE]
const SOCIAL: Array[int] = [Kind.CHAT, Kind.COMFORT, Kind.COURT, Kind.RECONCILE]
## Work type per goal kind; settlement culture weights are keyed by these.
const WORK_TYPE: Dictionary = {
	Kind.GATHER: "gather", Kind.HAUL: "haul", Kind.BUILD: "build", Kind.REPAIR: "build",
	Kind.FOUND_HOME: "build", Kind.PROPOSE_PROJECT: "build", Kind.DEFEND: "defend", Kind.SCOUT: "scout",
	Kind.GARDEN: "gather", Kind.FARM: "farm", Kind.COOK: "farm", Kind.PLANT_TREES: "gather",
}
const WORK_TYPES: Array[String] = ["build", "gather", "haul", "defend", "scout", "farm"]
## Goals whose target is another person.
const TARGETS_AGENT: Array[int] = [Kind.CHAT, Kind.COMFORT, Kind.COURT, Kind.RECONCILE, Kind.HELP, Kind.PREACH, Kind.TEACH, Kind.LEARN, Kind.SHARE_FRUIT]

## Help needs carried in a HELP goal's `extra`.
enum HelpNeed { FOOD, CARE, DEFENCE, TEACHING }
const HELP_NAMES: Array[String] = ["food", "care", "defence", "teaching"]

## Mental breaks carried in a BREAK goal's `target`.
enum BreakKind { LASH_OUT, BINGE, SULK, WANDER }
const BREAK_NAMES: Array[String] = ["lash_out", "binge", "sulk", "wander"]


static func make(kind: int, target: int = -1, extra: int = 0) -> Dictionary:
	return {"kind": kind, "target": target, "extra": extra}


static func key(goal: Dictionary) -> int:
	return (int(goal.kind) << 32) | (int(goal.target) & 0xffffffff)


static func key_of(kind: int, target: int = -1) -> int:
	return (kind << 32) | (target & 0xffffffff)


static func is_survival(goal: Dictionary) -> bool:
	return int(goal.kind) in SURVIVAL


static func is_social(goal: Dictionary) -> bool:
	return int(goal.kind) in SOCIAL


static func work_type(goal: Dictionary) -> String:
	return WORK_TYPE.get(int(goal.kind), "")


static func name_of(goal: Dictionary) -> String:
	return NAMES[int(goal.kind)]


static func label_key(goal: Dictionary) -> String:
	return "goal_" + NAMES[int(goal.kind)]
