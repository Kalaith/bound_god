extends SceneTree
## Focused, silent windowed capture of the real startup screen.
## Run with --audio-driver Dummy --script res://tools/capture_title.gd.
const CapturePaths = preload("res://addons/hatchery/testing/capture_paths.gd")


func _initialize() -> void:
	root.size = Vector2i(1920, 1080)
	_capture.call_deferred()


func _capture() -> void:
	var scene: PackedScene = load(str(ProjectSettings.get_setting("application/run/main_scene")))
	var main: Node = scene.instantiate()
	root.add_child(main)
	current_scene = main
	await create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	CapturePaths.directory()
	var error: Error = root.get_texture().get_image().save_png(CapturePaths.file("title"))
	print("TITLE CAPTURE: ", error_string(error))
	main.queue_free()
	await process_frame
	quit(0 if error == OK else 1)
