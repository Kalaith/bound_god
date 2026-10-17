extends SceneTree
## Run headless with -- --promo-background. Never requests OS mouse capture.
const MouseCapture = preload("res://scripts/presentation/mouse_capture.gd")


func _init() -> void:
	if not MouseCapture.is_background() or DisplayServer.get_name() != "headless":
		push_error("Run this check headless with --promo-background.")
		quit(1)
		return
	var physical_mode: int = Input.mouse_mode
	for mode in [Input.MOUSE_MODE_CAPTURED, Input.MOUSE_MODE_VISIBLE, Input.MOUSE_MODE_CONFINED]:
		MouseCapture.set_mode(mode)
		if MouseCapture.get_mode() != mode or Input.mouse_mode != physical_mode:
			push_error("Promo pointer state changed the physical mouse or lost gameplay state.")
			quit(1)
			return
	MouseCapture.set_mode(Input.MOUSE_MODE_VISIBLE)
	print("PASS promo pointer changes preserve the physical mouse mode")
	quit(0)
