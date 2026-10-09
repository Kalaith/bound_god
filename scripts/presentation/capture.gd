extends Node
## Debug-only verification captures: `-- --capture=<scenario> --out=<png>`.
## The owning scene sets up the scenario, then this node waits a few frames,
## saves the viewport image and quits. Release builds ignore the arguments.

signal ready_to_shoot

var scenario: String = ""
var out_path: String = ""
var frames_left: int = -1
var settle_frames: int = 12


static func request() -> Dictionary:
	if not OS.is_debug_build():
		return {}
	var result: Dictionary = {}
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			result["scenario"] = argument.trim_prefix("--capture=")
		elif argument.begins_with("--out="):
			result["out"] = argument.trim_prefix("--out=")
		elif argument.begins_with("--frames="):
			result["frames"] = int(argument.trim_prefix("--frames="))
		elif argument.begins_with("--seed="):
			result["seed"] = int(argument.trim_prefix("--seed="))
	return result if result.has("scenario") else {}


func configure(request_args: Dictionary) -> void:
	scenario = str(request_args.get("scenario", ""))
	out_path = str(request_args.get("out", "docs/verification/" + scenario + ".png"))
	settle_frames = int(request_args.get("frames", 12))


## Start counting once the scene has finished arranging the shot.
func shoot_after(frames: int = -1) -> void:
	frames_left = settle_frames if frames < 0 else frames


func _process(_delta: float) -> void:
	if frames_left < 0:
		return
	frames_left -= 1
	if frames_left > 0:
		return
	frames_left = -1
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = out_path
	if not path.begins_with("res://") and not path.begins_with("user://") and not path.is_absolute_path():
		path = ProjectSettings.globalize_path("res://" + path)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error: int = image.save_png(path)
	print("CAPTURE ", scenario, " -> ", path, " (", image.get_width(), "x", image.get_height(), ") ", "ok" if error == OK else "failed")
	get_tree().quit(0 if error == OK else 1)
