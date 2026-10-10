extends Node3D
## One person drawn from simple shapes: a capsule body tinted by their hue
## and archetype, a head, a mood ring under the feet, a carried cube, and an
## activity glyph. Faded while inside a building.
const Style = preload("res://scripts/presentation/ui/style.gd")

const JACKETS: Array[Color] = [Color("8c5a3c"), Color("4f6d8a"), Color("6b7a3f"), Color("7a4a6b"), Color("9a7b3a"), Color("4d7a72")]
const SKINS: Array[Color] = [Color("f0c9a0"), Color("d9a77c"), Color("b98058"), Color("8d5a3b"), Color("e8bb93"), Color("a8714a")]
const GLYPHS: Dictionary = {
	"sleeping": "z Z", "talking": "...", "fleeing": "!", "fighting": "x", "breaking": "@", "recovering": "+",
	"praying": "^", "building": "#", "eating": "o", "working": "*", "waiting": "?", "sheltering": "~",
	"sowing": ".:.", "reaping": "/", "tending": "%", "cooking": "&", "gardening": "*",
}
const RESOURCE_COLORS: Dictionary = {"wood": Color("9a6b3f"), "stone": Color("9fa6aa"), "thatch": Color("d8c27a"), "berries": Color("b8324a"), "ore": Color("6f7f9a"),
	"grain": Color("e0b84a"), "seed": Color("a88a4a"), "meal": Color("d9793a"),
	"tree_seed": Color("6b8a3a")}
## Activities shown as work at hand: the body sways.
const HANDWORK: Array[String] = ["working", "building", "sowing", "reaping", "tending", "cooking", "gardening"]

static var _body_mesh: CapsuleMesh
static var _head_mesh: SphereMesh
static var _ring_mesh: TorusMesh
static var _cube_mesh: BoxMesh

var agent_id: int = -1
var body := MeshInstance3D.new()
var head := MeshInstance3D.new()
var ring := MeshInstance3D.new()
var cargo := MeshInstance3D.new()
var glyph := Label3D.new()
var name_tag := Label3D.new()
var _body_material := StandardMaterial3D.new()
var _head_material := StandardMaterial3D.new()
var _ring_material := StandardMaterial3D.new()
var _cargo_material := StandardMaterial3D.new()
var _phase: float = 0.0
var _facing: float = 0.0


static func _shared() -> void:
	if _body_mesh != null:
		return
	_body_mesh = CapsuleMesh.new()
	_body_mesh.radius = 0.27
	_body_mesh.height = 1.12
	_head_mesh = SphereMesh.new()
	_head_mesh.radius = 0.21
	_head_mesh.height = 0.42
	_ring_mesh = TorusMesh.new()
	_ring_mesh.inner_radius = 0.36
	_ring_mesh.outer_radius = 0.46
	_cube_mesh = BoxMesh.new()
	_cube_mesh.size = Vector3(0.24, 0.24, 0.24)


func setup(agent: RefCounted) -> void:
	_shared()
	agent_id = agent.id
	var jacket: Color = JACKETS[agent.portrait % JACKETS.size()]
	jacket.h = fposmod(jacket.h + (agent.hue - 0.5) * 0.25, 1.0)
	_body_material.albedo_color = jacket
	_head_material.albedo_color = SKINS[agent.portrait % SKINS.size()]
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cargo_material.albedo_color = Color.WHITE
	for material in [_body_material, _head_material, _ring_material]:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	body.mesh = _body_mesh
	body.material_override = _body_material
	body.position.y = 0.58
	head.mesh = _head_mesh
	head.material_override = _head_material
	head.position.y = 1.36
	ring.mesh = _ring_mesh
	ring.material_override = _ring_material
	ring.scale = Vector3(1, 0.15, 1)
	ring.position.y = 0.04
	cargo.mesh = _cube_mesh
	cargo.material_override = _cargo_material
	cargo.position = Vector3(0.36, 0.72, 0.0)
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
	for child in [body, head, ring, cargo, glyph, name_tag]:
		add_child(child)
	scale = Vector3.ONE * (0.7 if agent.is_child else 1.0)
	_phase = float(agent.id) * 1.7


func refresh(agent: RefCounted, alpha: float, delta: float, selected: bool) -> void:
	var target: Vector3 = agent.previous_position.lerp(agent.position, alpha)
	var motion: Vector3 = target - position
	position = target
	if Vector2(motion.x, motion.z).length() > 0.002:
		_facing = lerp_angle(_facing, atan2(motion.x, motion.z), minf(delta * 10.0, 1.0))
	rotation.y = _facing
	scale = Vector3.ONE * (0.7 if agent.is_child else 1.0)
	_phase += delta
	var bob: float = 0.0
	match agent.activity:
		"walking", "hauling", "fleeing":
			bob = absf(sin(_phase * 9.0)) * 0.08
		"working", "building", "sowing", "reaping", "tending", "cooking", "gardening":
			body.rotation.z = sin(_phase * 5.0) * 0.12
		"sleeping":
			bob = -0.35
	if not agent.activity in HANDWORK:
		body.rotation.z = 0.0
	body.rotation.x = 1.45 if agent.activity == "sleeping" else 0.0
	body.position.y = 0.58 + bob
	head.position = Vector3(0, 1.36 + bob, 0) if agent.activity != "sleeping" else Vector3(0, 0.3, 0.62)
	var faded: float = 0.4 if agent.inside >= 0 else 1.0
	_body_material.albedo_color.a = faded
	_head_material.albedo_color.a = faded
	_ring_material.albedo_color = Style.level_color(agent.mood)
	_ring_material.albedo_color.a = 0.85 * faded
	cargo.visible = not agent.carrying.is_empty()
	if cargo.visible:
		_cargo_material.albedo_color = RESOURCE_COLORS.get(agent.carrying.resource, Color.WHITE)
	var text: String = GLYPHS.get(agent.activity, "")
	if agent.activity == "talking":
		text = ".".repeat(1 + int(_phase * 3.0) % 3)
	glyph.text = text
	glyph.visible = not text.is_empty()
	name_tag.visible = selected
