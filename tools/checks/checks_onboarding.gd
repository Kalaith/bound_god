extends RefCounted
## Contextual prompts read the world and never change it; a dismissed
## prompt stays away in that world and is not replayed as a decision.
const Sim = preload("res://scripts/sim/sim.gd")
const Prompts = preload("res://scripts/presentation/ui/prompts.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const TemplateLibrary = preload("res://scripts/building/template_library.gd")


func check_a_hungry_traveller_prompts_the_god_and_can_be_dismissed():
	var sim: RefCounted = Sim.create(11)
	sim.run_ticks(30)
	var traveller: RefCounted = sim.agents[0]
	traveller.needs[Personality.Need.FOOD] = 10.0
	traveller.carrying = {}
	var before: int = sim.state_hash()
	var library: RefCounted = TemplateLibrary.new()
	var shown: Dictionary = Prompts.current(sim, library, true)
	if sim.state_hash() != before:
		return "reading the prompts changed the world"
	if str(shown.get("id", "")) != "prompt_hungry" or not str(shown.text).contains(traveller.given_name):
		return "expected the hungry prompt, got %s" % str(shown)
	var logged: int = sim.command_log.size()
	if not sim.apply_command({"type": "dismiss_prompt", "prompt": shown.id}).ok:
		return "the prompt could not be dismissed"
	if sim.command_log.size() != logged:
		return "dismissing a prompt was logged as a decision"
	var next: Dictionary = Prompts.current(sim, library, true)
	if str(next.get("id", "")) == "prompt_hungry":
		return "a dismissed prompt came back"
	if next.is_empty() or not str(next.id).begins_with("guide_"):
		return "the first-steps guide did not follow: %s" % str(next)
	if not Prompts.current(sim, library, false).is_empty():
		return "the guide showed with the setting off"
	return ""
