extends SceneTree
## Headless scenario runner for the simulation (kept out of the exported game).
## Run: Godot --headless --path . --script res://tools/sim_checks.gd [-- --only=<text>]
## Every `check_*` method of the modules below returns "" on success or a
## failure message. Prints PASS/FAIL per scenario and exits non-zero on failure.
## Checks are untyped on purpose: a runtime error then returns null, which
## fails, where a typed `-> String` would silently return "" and pass.

const MODULES: Array[String] = [
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
]


func _init() -> void:
	var only: String = ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--only="):
			only = argument.trim_prefix("--only=")
	var failures: int = 0
	var count: int = 0
	var started: int = Time.get_ticks_msec()
	for path in MODULES:
		var script: Variant = load(path)
		if not script is GDScript or not (script as GDScript).can_instantiate():
			failures += 1
			count += 1
			print("FAIL  %s could not be loaded" % path)
			continue
		var module: RefCounted = script.new()
		for method in module.get_method_list():
			var name: String = method.name
			if not name.begins_with("check_") or (not only.is_empty() and not name.contains(only)):
				continue
			count += 1
			var begin: int = Time.get_ticks_msec()
			var result: Variant = module.call(name)
			var elapsed: float = (Time.get_ticks_msec() - begin) / 1000.0
			if result is String and (result as String).is_empty():
				print("PASS  %s  (%.1fs)" % [name, elapsed])
			else:
				failures += 1
				print("FAIL  %s  (%.1fs): %s" % [name, elapsed, str(result)])
	print("%d scenarios, %d failed, %.1fs" % [count, failures, (Time.get_ticks_msec() - started) / 1000.0])
	quit(1 if failures > 0 or count == 0 else 0)
