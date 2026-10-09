extends SceneTree
## Headless scenario runner for the simulation (kept out of the exported game).
## Run: Godot --headless --path . --script res://tools/sim_checks.gd [-- --only=<text>]
## Every `check_*` method of the modules below returns "" on success or a
## failure message. Prints PASS/FAIL per scenario and exits non-zero on failure.

const MODULES: Array[String] = [
	"res://tools/checks/checks_data.gd",
	"res://tools/checks/checks_world.gd",
	"res://tools/checks/checks_commands.gd",
	"res://tools/checks/checks_templates.gd",
	"res://tools/checks/checks_agents.gd",
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
		var module: RefCounted = load(path).new()
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
