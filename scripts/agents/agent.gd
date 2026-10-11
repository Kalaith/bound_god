extends RefCounted
## One person. Plain fields so the whole agent saves through to_dict and
## var_to_bytes. Reasoning lives in agents/, side effects in sim/.
const Beliefs = preload("res://scripts/agents/beliefs.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Personality = preload("res://scripts/agents/personality.gd")

const LOG_LENGTH: int = 12
const NONE := Vector3i(-1, -1, -1)

# Identity
var id: int = 0
var given_name: String = ""
var family_name: String = ""
var age_years: float = 30.0
var is_child: bool = false
var portrait: int = 0
var hue: float = 0.0
## {origin, former_role, memory}
var backstory: Dictionary = {}
var parents: Array = []
# Character
var traits: Array = []
var personality: Dictionary = {}
var skills: Dictionary = {}
## {id, progress, fulfilled}
var ambition: Dictionary = {}
# Body
var needs := PackedFloat32Array([80, 80, 80, 80, 80, 100])
## {hp, ill, treated, injuries}
var health: Dictionary = {"hp": 100.0, "ill": false, "treated": false, "injuries": 0}
var thoughts: Array = []
var mood: float = 50.0
# BDI core
var beliefs := Beliefs.new()
## {} or {goal, utility, reason, plan: {} or plan dict, tried: Array, started_tick}
var intention: Dictionary = {}
## Newest first: {tick, kind, ...}
var decisions: Array = []
var inbox: Array = []
## goal key -> tick the backoff ends
var backoff: Dictionary = {}
var next_deliberation: int = 0
# World state
var cell := Vector3i.ZERO
var previous_position := Vector3.ZERO
var position := Vector3.ZERO
var path: Array[Vector3i] = []
var move_budget: float = 0.0
var inside: int = -1
## {} or {resource, amount}
var carrying: Dictionary = {}
## Work ticks left in the tools this person carries (0: none; M20).
var tool: float = 0.0
var activity: String = "idle"
var home: int = -1
## present, dead, departed
var life: String = "present"
var life_day: int = 0
var life_cause: String = ""
var settlement_id: int = -1
# Social
var partner: int = -1
## {} or {requester, need}
var help_task: Dictionary = {}
## {} or {kind, until}
var mental_break: Dictionary = {}
var low_mood_ticks: int = 0
# Faith and the god
var faith: Dictionary = {}
var quest_id: int = -1
## Array of {kind, target, bonus, until}
var whispers: Array = []
# Cultivation (agents/cultivation_state.gd)
var cultivation: Dictionary = {}
# Record
var joined_day: int = 1
var stats: Dictionary = {"plans_recovered": 0, "helped_others": 0, "blocks_placed": 0, "prayers": 0, "stories_told": 0}
## Result an effect left for the current step to read next tick.
var step_result: Dictionary = {}
## Why the last perception or message forced a rethink ("" when none).
var interrupted_by: String = ""


func full_name() -> String:
	return given_name + " " + family_name


func is_present() -> bool:
	return life == "present"


func has_trait(trait_id: String) -> bool:
	return traits.has(trait_id)


func need(index: int) -> float:
	return needs[index]


func change_need(index: int, amount: float) -> void:
	needs[index] = clampf(needs[index] + amount, 0.0, 100.0)


func lowest_need() -> int:
	var best: int = 0
	for i in range(needs.size()):
		if needs[i] < needs[best]:
			best = i
	return best


## Mood pressure from needs: each need above or below 60, capped at +5.
func mood_pressure(weight: float) -> float:
	var sum: float = 0.0
	for value in needs:
		sum += minf(value - 60.0, 5.0) * weight / 6.0 * 2.0
	return sum


func needs_care(threshold: float) -> bool:
	return bool(health.ill) or float(health.hp) < threshold


## Work utility and speed scale with health.
func capacity() -> float:
	var result: float = 0.4 + 0.6 * float(health.hp) / 100.0
	return result * 0.7 if bool(health.ill) else result


func carried(resource: String) -> float:
	return float(carrying.amount) if not carrying.is_empty() and carrying.resource == resource else 0.0


func current_goal() -> Dictionary:
	return intention.get("goal", {})


func current_plan() -> Dictionary:
	return intention.get("plan", {})


func is_backed_off(goal_key: int, now: int) -> bool:
	return backoff.has(goal_key) and int(backoff[goal_key]) > now


func back_off(goal_key: int, until: int) -> void:
	backoff[goal_key] = until


func record(tick: int, kind: String, fields: Dictionary = {}) -> void:
	var entry: Dictionary = fields.duplicate()
	entry["tick"] = tick
	entry["kind"] = kind
	decisions.push_front(entry)
	if decisions.size() > LOG_LENGTH:
		decisions.resize(LOG_LENGTH)


func available_to_talk() -> bool:
	# Nobody stops to chat with an outlaw come to rob them (M22).
	return is_present() and not activity in ["sleeping", "fleeing", "fighting", "breaking"] and not backstory.has("outlaw")


const SAVED: Array[String] = [
	"id", "given_name", "family_name", "age_years", "is_child", "portrait", "hue", "backstory", "parents",
	"traits", "skills", "ambition", "needs", "health", "thoughts", "mood", "intention", "decisions", "inbox",
	"backoff", "next_deliberation", "cell", "previous_position", "position", "path", "move_budget", "inside",
	"carrying", "activity", "home", "life", "life_day", "life_cause", "settlement_id", "partner", "help_task",
	"mental_break", "low_mood_ticks", "faith", "quest_id", "whispers", "joined_day", "stats", "step_result",
	"interrupted_by", "cultivation", "tool",
]
## Keys older saves may lack; the agent keeps its default for them.
const OPTIONAL: Array[String] = ["tool"]


func to_dict() -> Dictionary:
	var result: Dictionary = {}
	for key in SAVED:
		var value: Variant = get(key)
		result[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	result["beliefs"] = beliefs.to_dict()
	return result


static func from_dict(data: Dictionary) -> RefCounted:
	var agent = load("res://scripts/agents/agent.gd").new()
	for key in SAVED:
		if not data.has(key) and OPTIONAL.has(key):
			continue
		if not data.has(key):
			push_error("Saved agent is missing " + key)
			assert(false, "Saved agent is missing " + key)
			return null
		if key == "path":
			agent.path.assign(data.path)
		else:
			agent.set(key, data[key])
	agent.personality = Personality.from_traits(agent.traits)
	agent.beliefs.from_dict(data.beliefs)
	return agent
