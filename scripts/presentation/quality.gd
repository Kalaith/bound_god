extends RefCounted
## Graphics quality tiers (low, medium, high). A tier sets ceilings: the
## player's own glow, shadow and ink switches still turn their effect off, but
## cannot raise it past what the tier allows. Web builds default to medium,
## since a browser on a laptop's integrated GPU has the least headroom;
## everything else defaults to high, the look the game was drawn with.
const TIERS: Array[String] = ["low", "medium", "high"]

## Per tier: share of the 1080p picture actually rendered (3D only, UI stays
## sharp), MSAA, sun shadow cascades and reach, glow, the cheaper ink and
## paint shaders, weather particle share, lantern lights, and a frame cap.
const PRESETS: Dictionary = {
	"low": {
		"render_scale": 0.67, "msaa": Viewport.MSAA_DISABLED,
		"shadow_mode": DirectionalLight3D.SHADOW_ORTHOGONAL, "shadow_distance": 48.0,
		"glow": false, "cheap_shaders": true, "particles": 0.35, "lanterns": 4, "max_fps": 60,
	},
	"medium": {
		"render_scale": 0.85, "msaa": Viewport.MSAA_DISABLED,
		"shadow_mode": DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, "shadow_distance": 80.0,
		"glow": false, "cheap_shaders": true, "particles": 0.6, "lanterns": 6, "max_fps": 0,
	},
	"high": {
		"render_scale": 1.0, "msaa": Viewport.MSAA_2X,
		"shadow_mode": DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, "shadow_distance": 120.0,
		"glow": true, "cheap_shaders": false, "particles": 1.0, "lanterns": 12, "max_fps": 0,
	},
}

## The tier in force, read by the views that scale their own cost.
static var current: String = "high"


## The tier a fresh install starts on.
static func default_tier() -> String:
	return "medium" if OS.has_feature("web") else "high"


static func preset(tier: String = "") -> Dictionary:
	return PRESETS.get(tier if not tier.is_empty() else current, PRESETS.high)


## Makes `tier` current and applies the parts that belong to the window:
## render scale, MSAA and the frame cap.
static func apply(tier: String, viewport: Viewport) -> void:
	current = tier if PRESETS.has(tier) else default_tier()
	var chosen: Dictionary = preset()
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = float(chosen.render_scale)
	viewport.msaa_3d = chosen.msaa
	Engine.max_fps = int(chosen.max_fps)
