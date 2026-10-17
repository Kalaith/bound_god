extends RefCounted
## Keep gameplay's pointer state without touching the desktop during recording.
## The promo runner uses a private desktop, but ClipCursor can still affect the
## input desktop. Background capture must never call Input.set_mouse_mode.

static var _recording_mode: int = Input.MOUSE_MODE_VISIBLE


static func is_background() -> bool:
	return OS.get_cmdline_user_args().has("--promo-background")


static func get_mode() -> int:
	return _recording_mode if is_background() else Input.mouse_mode


static func set_mode(mode: int) -> void:
	if is_background():
		_recording_mode = mode
	else:
		Input.mouse_mode = mode
