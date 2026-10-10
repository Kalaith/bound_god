extends Node3D
## One person, drawn as a jointed woodblock figure (see FigureRig) dressed in
## dyes picked from their portrait and hue: jacket, sash, trousers, skin and
## hair, greying with age. A mood ring lies under the feet, carried goods are
## held in both arms, and an activity glyph floats above. Dithered away while
## inside a building.
const Style = preload("res://scripts/presentation/ui/style.gd")
const FigureRig = preload("res://scripts/presentation/figure_rig.gd")

## Woodblock dyes: indigo, vermilion, moss, plum, ochre and teal.
const JACKETS: Array[Color] = [Color("a8523f"), Color("44597a"), Color("6b7a48"), Color("6e4e62"), Color("a8833f"), Color("4b7470")]
const SASHES: Array[Color] = [Color("2f3b52"), Color("c9a24a"), Color("8a3a32"), Color("e4dccb"), Color("3f5a44"), Color("5a3a4a"), Color("b8763a")]
const TROUSERS: Array[Color] = [Color("3d4250"), Color("5a4a3c"), Color("4a5248"), Color("6b6253"), Color("38404a")]
const SKINS: Array[Color] = [Color("f0c9a0"), Color("d9a77c"), Color("b98058"), Color("8d5a3b"), Color("e8bb93"), Color("a8714a")]
const HAIRS: Array[Color] = [Color("2b2420"), Color("3a2a20"), Color("1f1c1c"), Color("5a3a26"), Color("2a2a30")]
const GREY_HAIR := Color("a39e94")
const COLLAR := Color("efe6d2")
const STRAW := Color("c9a86a")
## People of this age and over walk with a stoop and grey hair.
const ELDER_AGE: float = 58.0
const GLYPHS: Dictionary = {
	"sleeping": "z Z", "talking": "...", "fleeing": "!", "fighting": "x", "breaking": "@", "recovering": "+",
	"praying": "^", "building": "#", "eating": "o", "working": "*", "waiting": "?", "sheltering": "~",
	"sowing": ".:.", "reaping": "/", "tending": "%", "cooking": "&", "gardening": "*",
	"cultivating": "( )", "teaching": ">>", "learning": "<<", "proclaiming": "!!",
}
## Jade motes that rise round someone cultivating.
const QI_MOTE := Color(0.62, 0.9, 0.78, 0.85)
const RESOURCE_COLORS: Dictionary = {"wood": Color("9a6b3f"), "stone": Color("9fa6aa"), "thatch": Color("d8c27a"), "berries": Color("b8324a"), "ore": Color("6f7f9a"),
	"grain": Color("e0b84a"), "seed": Color("a88a4a"), "meal": Color("d9793a"),
	"tree_seed": Color("6b8a3a")}

static var _ring_mesh: TorusMesh

var agent_id: int = -1
var figure := FigureRig.new()
var ring := MeshInstance3D.new()
var glyph := Label3D.new()
var name_tag := Label3D.new()
var _ring_material := StandardMaterial3D.new()
var _phase: float = 0.0
var _facing: float = 0.0
var _speed: float = 0.0
var _motes: CPUParticles3D


func setup(agent: RefCounted) -> void:
	if _ring_mesh == null:
		_ring_mesh = TorusMesh.new()
		_ring_mesh.inner_radius = 0.36
		_ring_mesh.outer_radius = 0.46
	agent_id = agent.id
	var look: int = agent.id * 7 + agent.portrait * 3
	var jacket: Color = JACKETS[agent.portrait % JACKETS.size()]
	jacket.h = fposmod(jacket.h + (agent.hue - 0.5) * 0.25, 1.0)
	var elder: bool = agent.age_years >= ELDER_AGE
	var colours: Dictionary = {
		"jacket": jacket,
		"trim": jacket.darkened(0.38),
		"sash": SASHES[look % SASHES.size()],
		"trousers": TROUSERS[(look / 2) % TROUSERS.size()],
		"skin": SKINS[agent.portrait % SKINS.size()],
		"hair": GREY_HAIR if elder else HAIRS[(look / 3) % HAIRS.size()],
		"accent": COLLAR,
		"straw": STRAW,
	}
	figure.build(colours, look / 5, false)
	figure.elder = elder
	if agent.is_child:
		figure.head.scale = Vector3.ONE * 1.22
	add_child(figure)
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.mesh = _ring_mesh
	ring.material_override = _ring_material
	ring.scale = Vector3(1, 0.15, 1)
	ring.position.y = 0.04
	for label in [glyph, name_tag]:
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.outline_size = 10
		label.modulate = Color(1, 1, 1)
		label.outline_modulate = Color(0, 0, 0, 0.75)
	glyph.font_size = 72
	glyph.pixel_size = 0.005
	glyph.position.y = 1.95
	name_tag.font_size = 46
	name_tag.pixel_size = 0.005
	name_tag.position.y = 2.3
	name_tag.text = agent.given_name
	name_tag.modulate = Style.GOLD
	name_tag.hide()
	for child in [ring, glyph, name_tag]:
		add_child(child)
	_motes = _make_motes()
	add_child(_motes)
	scale = Vector3.ONE * (0.7 if agent.is_child else 1.0)
	_phase = float(agent.id) * 1.7


func refresh(agent: RefCounted, alpha: float, delta: float, selected: bool) -> void:
	var target: Vector3 = agent.previous_position.lerp(agent.position, alpha)
	var motion: Vector3 = target - position
	position = target
	var flat: float = Vector2(motion.x, motion.z).length()
	if flat > 0.002:
		_facing = lerp_angle(_facing, atan2(motion.x, motion.z), minf(delta * 10.0, 1.0))
	rotation.y = _facing
	scale = Vector3.ONE * (0.7 if agent.is_child else 1.0)
	_phase += delta
	_speed = lerpf(_speed, flat / maxf(delta, 0.001) / scale.x, minf(delta * 8.0, 1.0))
	var carried: Variant = null
	if not agent.carrying.is_empty():
		carried = RESOURCE_COLORS.get(agent.carrying.resource, Color.WHITE)
	figure.set_cargo(carried)
	figure.pose(agent.activity, _phase, _speed, delta)
	var faded: float = 0.4 if agent.inside >= 0 else 1.0
	figure.set_fade(faded)
	_ring_material.albedo_color = Style.level_color(agent.mood)
	_ring_material.albedo_color.a = 0.85 * faded
	var text: String = GLYPHS.get(agent.activity, "")
	if agent.activity == "talking":
		text = ".".repeat(1 + int(_phase * 3.0) % 3)
	glyph.text = text
	glyph.visible = not text.is_empty()
	_motes.emitting = agent.activity == "cultivating" and _speed < 0.2
	name_tag.visible = selected


## A few soft jade motes drifting up and in round a seated cultivator, as if
## the tree's qi were gathering to them.
static func _make_motes() -> CPUParticles3D:
	var motes := CPUParticles3D.new()
	motes.emitting = false
	motes.amount = 14
	motes.lifetime = 2.6
	motes.local_coords = true
	motes.position.y = 0.5
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	motes.emission_ring_axis = Vector3.UP
	motes.emission_ring_radius = 0.9
	motes.emission_ring_inner_radius = 0.5
	motes.emission_ring_height = 0.2
	motes.direction = Vector3.UP
	motes.spread = 20.0
	motes.gravity = Vector3.ZERO
	motes.initial_velocity_min = 0.15
	motes.initial_velocity_max = 0.35
	motes.radial_accel_min = -0.25
	motes.radial_accel_max = -0.12
	motes.scale_amount_min = 0.5
	motes.scale_amount_max = 1.0
	var fade := Gradient.new()
	fade.set_color(0, Color(QI_MOTE, 0.0))
	fade.add_point(0.3, QI_MOTE)
	fade.set_color(fade.get_point_count() - 1, Color(QI_MOTE, 0.0))
	motes.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.07)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	quad.material = material
	motes.mesh = quad
	return motes
