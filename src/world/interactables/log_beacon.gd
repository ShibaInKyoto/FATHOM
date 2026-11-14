class_name LogBeacon
extends Entity
## A data recorder from Meridian Deep in its pinger buoy, broken loose from
## its mooring and drifting: an orange float banded with reflective tape, a
## strobe in a cage on top, the recorder slung beneath and its torn tether
## trailing. Pings faintly on its own, so sonar and sharp ears can find it;
## touch it to recover a signal log.

const SHADER := preload("res://src/fx/shaders/equipment.gdshader")
const ORANGE := Color(0.95, 0.42, 0.1)
const PINGER := Color(0.4, 1.0, 0.6)

var log_id: StringName
var _t := 0.0
var _light: OmniLight3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _model: MeshInstance3D
var _mat: ShaderMaterial
var _collected := false


func setup() -> void:
	radius = 0.8
	active_radius = 90.0
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter(&"lamp_color", PINGER)
	_mat.set_shader_parameter(&"sediment_tint", level.biome.sediment_tint if level else Color(0.4, 0.38, 0.34))
	_mat.set_shader_parameter(&"detail", 9.0)
	_model = MeshInstance3D.new()
	_model.mesh = build()
	_model.material_override = _mat
	_model.rotation = Vector3(0.0, 0.6, 0.18)
	add_child(_model)
	_light = OmniLight3D.new()
	_light.light_color = PINGER
	_light.omni_range = 5.0
	_light.light_energy = 0.0
	_light.position = Vector3(0, 0.8, 1.0)
	add_child(_light)
	_ring = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	_ring.mesh = quad
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_texture = Fx.ring_texture()
	_ring_mat.albedo_color = Color(0.5, 1.5, 0.8, 0.0)
	_ring.material_override = _ring_mat
	_ring.position = Vector3(0, 0.65, 0.5)
	add_child(_ring)


## The buoy, upright, centred on its float. COLOR.a as equipment.gdshader
## reads it.
static func build() -> ArrayMesh:
	var b := ModelBuilder.new()
	var paint := Color(ORANGE, 0.0)
	var dark := Color(0.1, 0.1, 0.1, 0.3)
	var metal := Color(0.75, 0.0, 0.0, 0.2)
	var tape := Color(1, 1, 1, 0.8)
	# The float, banded black at its waist and taped top and bottom.
	b.capsule(Vector3(0.0, -0.08, 0.0), Vector3(0.0, 0.3, 0.0), 0.26, paint)
	b.cylinder(Vector3(0.0, 0.07, 0.0), Vector3(0.0, 0.15, 0.0), 0.268, dark, 24)
	for y: float in [-0.02, 0.24]:
		b.cylinder(Vector3(0.0, y, 0.0), Vector3(0.0, y + 0.035, 0.0), 0.264, tape, 24)
	# The strobe in its cage.
	b.cylinder(Vector3(0.0, 0.5, 0.0), Vector3(0.0, 0.58, 0.0), 0.11, dark, 16)
	b.cylinder(Vector3(0.0, 0.58, 0.0), Vector3(0.0, 0.74, 0.0), 0.075, Color(1, 0, 0, 0.6), 16)
	for k in 4:
		var a := TAU * (k + 0.5) / 4.0
		var d := Vector3(cos(a), 0.0, sin(a)) * 0.1
		b.cylinder(d + Vector3(0.0, 0.56, 0.0), d + Vector3(0.0, 0.79, 0.0), 0.009, metal, 5)
	b.cylinder(Vector3(0.0, 0.78, 0.0), Vector3(0.0, 0.81, 0.0), 0.115, dark, 16)
	# The recorder slung beneath, ribbed, its shackle and the torn tether.
	b.cylinder(Vector3(0.0, -0.5, 0.0), Vector3(0.0, -0.3, 0.0), 0.16, metal, 18)
	for y: float in [-0.46, -0.4, -0.34]:
		b.torus(Vector3(0.0, y, 0.0), Vector3.UP, 0.163, 0.012, metal, 18, 5)
	b.cylinder(Vector3(0.0, -0.3, 0.0), Vector3(0.0, -0.26, 0.0), 0.1, dark, 12)
	b.torus(Vector3(0.0, -0.55, 0.0), Vector3.BACK, 0.04, 0.01, metal, 12, 5)
	var tether := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in 7:
		var t := i / 6.0
		tether.append(Vector3(0.12 * sin(t * 2.5), -0.59 - t * 0.6, 0.06 * t))
		radii.append(0.014 * (1.0 - 0.4 * t))
	b.tube(tether, radii, 5, dark)
	return b.commit()


func tick(delta: float) -> void:
	_t += delta
	var cycle := fmod(_t, 4.0)
	var flash := maxf(1.0 - cycle * 2.0, 0.0)
	_light.light_energy = 2.0 * flash
	_mat.set_shader_parameter(&"lamp", flash)
	# It rides the slow swell of the current, nodding on its tether.
	_model.position.y = sin(_t * 0.8) * 0.05
	_model.rotation.z = 0.18 + sin(_t * 0.6) * 0.08
	_ring.scale = Vector3.ONE * (1.0 + cycle * 3.0)
	_ring_mat.albedo_color.a = maxf(1.0 - cycle / 1.5, 0.0) * 0.8
	if cycle < delta:
		Audio.play_at(&"beacon_ping", pos, -8.0)
	vel = vel.lerp(Vector2.ZERO, 1.0 - exp(-2.0 * delta))
	move_and_collide_field(delta)
	var sub := level.player
	if not _collected and sub and sub.alive and sub.pos.distance_to(pos) < Submarine.RADIUS + radius + 0.5:
		_collect(sub)


func on_sonar(_origin: Vector2, _mark_time: float) -> void:
	_t = 3.5


func _collect(sub: Submarine) -> void:
	_collected = true
	sub.run.logs += 1
	sub.run.research += 5
	sub.show_gain(5, " research", UiTheme.ACCENT)
	if not Game.meta.logs_found.has(String(log_id)):
		Game.meta.logs_found.append(String(log_id))
	Audio.play(&"log_found", -2.0)
	Fx.sparkle(level, pos, Color(0.4, 1.0, 0.6))
	Events.log_found.emit(log_id)
	despawn()
