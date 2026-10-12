extends SceneTree
## The long soak from the command line (plan M25):
## Godot --headless --path . --script res://tools/soak.gd [-- --years=200 --span=25 --seed=11]
## Prints the report; grep its output for SCRIPT ERROR. Exits 1 on a problem.
const Soak = preload("res://tools/soak_run.gd")


func _init() -> void:
	var years: int = 200
	var span: int = 25
	var seed: int = 11
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--years="):
			years = int(argument.trim_prefix("--years="))
		elif argument.begins_with("--span="):
			span = int(argument.trim_prefix("--span="))
		elif argument.begins_with("--seed="):
			seed = int(argument.trim_prefix("--seed="))
	var result: Dictionary = Soak.run(seed, years, span)
	print("SOAK total %.1f s, reloaded %s" % [float(result.report.get("total_s", 0.0)), str(result.report.get("reloaded", false))])
	print("SOAK %s" % ("PASS" if str(result.problem).is_empty() else "FAIL " + str(result.problem)))
	quit(0 if str(result.problem).is_empty() else 1)
