extends "res://addons/hatchery/testing/check_runner.gd"
## Headless scenario runner for the simulation (kept out of the exported game),
## on the toolkit's check runner.
## Run: Godot --headless --path . --script res://tools/sim_checks.gd [-- --only=<text>] [--module=<file text>] [--long]
## Every `check_*` method of the modules below returns "" on success or a
## failure message. Prints PASS/FAIL per scenario and exits non-zero on failure.
## Long-run scenarios (`long_check_*`, minutes each) run only with --long.
## Checks are untyped on purpose: a runtime error then returns null, which
## fails, where a typed `-> String` would silently return "" and pass.


func modules() -> Array[String]:
	return [
		"res://tools/checks/checks_data.gd",
		"res://tools/checks/checks_world.gd",
		"res://tools/checks/checks_commands.gd",
		"res://tools/checks/checks_templates.gd",
		"res://tools/checks/checks_agents.gd",
		"res://tools/checks/checks_work.gd",
		"res://tools/checks/checks_social.gd",
		"res://tools/checks/checks_faith.gd",
		"res://tools/checks/checks_expansion.gd",
		"res://tools/checks/checks_threats.gd",
		"res://tools/checks/checks_save.gd",
		"res://tools/checks/checks_stores.gd",
		"res://tools/checks/checks_village.gd",
		"res://tools/checks/checks_food.gd",
		"res://tools/checks/checks_farming.gd",
		"res://tools/checks/checks_woods.gd",
		"res://tools/checks/checks_abstract.gd",
		"res://tools/checks/checks_onboarding.gd",
		"res://tools/checks/checks_cultivation.gd",
		"res://tools/checks/checks_tribulations.gd",
		"res://tools/checks/checks_tree.gd",
		"res://tools/checks/checks_tree_abilities.gd",
		"res://tools/checks/checks_meditation.gd",
		"res://tools/checks/checks_architecture.gd",
		"res://tools/checks/checks_halls.gd",
		"res://tools/checks/checks_seasons.gd",
		"res://tools/checks/checks_alchemy.gd",
		"res://tools/checks/checks_crafts.gd",
		"res://tools/checks/checks_alchemy_herbs.gd",
		"res://tools/checks/checks_elixirs.gd",
		"res://tools/checks/checks_campaign.gd",
		"res://tools/checks/checks_generations.gd",
		"res://tools/checks/checks_designs.gd",
		"res://tools/checks/checks_homes.gd",
		"res://tools/checks/checks_branches.gd",
		"res://tools/checks/checks_regions.gd",
		"res://tools/checks/checks_outsiders.gd",
		"res://tools/checks/checks_saga.gd",
		"res://tools/checks/checks_feel.gd",
		"res://tools/checks/checks_release.gd",
	]
