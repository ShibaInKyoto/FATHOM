class_name DescentMarker
extends Node3D
## The way down: water rushing down into the fissure, sucking at whatever
## comes near (see [method Level.current_at]): a column of moving water the
## cave wavers through, narrowing as it is drawn in, silt streaking down
## through it, and the descent line the Meridian Deep expedition left running
## down into it, marked with lightsticks and line arrows. Placed at the zone
## exit. While a guardian lives the way down is still and its lights red.

## The lightsticks' glow.
const COLOR := Color(0.35, 1.0, 0.75)
## While a guardian lives they glow a warning red and the water is still.
const SEALED_COLOR := Color(1.0, 0.25, 0.2)
## The light thrown on the walls of the fissure.
const WATER_LIGHT := Color(0.7, 0.85, 1.0)

const LINE_TOP := 6.0
const LINE_BOTTOM := -5.0
const DRAFT_SHADER := preload("res://src/fx/shaders/downdraft.gdshader")
const LINE_SHADER := preload("res://src/fx/shaders/equipment.gdshader")

var _light: OmniLight3D
var _ring: MeshInstance3D
var _ring_mat: ShaderMaterial
var _line: MeshInstance3D
var _line_mat: ShaderMaterial
var _sticks: Array[MeshInstance3D] = []
var _inflow: GPUParticles3D
var _stick_mat: StandardMaterial3D
var _stream: GPUParticles3D
var _color := COLOR
var _t := 0.0


func _ready() -> void:
	_light = OmniLight3D.new()
	_light.light_color = WATER_LIGHT
	_light.omni_range = 10.0
	_light.light_energy = 0.6
	_light.position = Vector3(0, 1.0, 1.5)
	add_child(_light)
	# Silt drawn in from round about and sucked down into the fissure: the
	# emitters sit at the fissure, so everything is pulled towards it.
	_stream = _silt(Vector3(4.0, 3.0, 1.5), 7.0, 1.5, -3.5, 110)
	add_child(_stream)
	_inflow = _silt(Vector3(6.0, 1.0, 1.5), 2.2, 0.2, -7.0, 60)
	add_child(_inflow)
	# The water itself, rushing down: the cave wavers through it.
	_ring = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(7.5, 14.0)
	_ring.mesh = q
	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = DRAFT_SHADER
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position = Vector3(0, 2.0, 0.6)
	add_child(_ring)
	# The descent line, its arrows and its lightsticks.
	_line_mat = ShaderMaterial.new()
	_line_mat.shader = LINE_SHADER
	_line_mat.set_shader_parameter(&"detail", 8.0)
	_line = MeshInstance3D.new()
	_line.mesh = _line_mesh()
	_line.material_override = _line_mat
	add_child(_line)
	_stick_mat = StandardMaterial3D.new()
	_stick_mat.albedo_color = Color(0.1, 0.25, 0.15)
	_stick_mat.emission_enabled = true
	_stick_mat.emission = _color
	_stick_mat.emission_energy_multiplier = 4.0
	var stick := CapsuleMesh.new()
	stick.radius = 0.035
	stick.height = 0.32
	stick.radial_segments = 8
	stick.rings = 2
	for k in 4:
		var mi := MeshInstance3D.new()
		mi.mesh = stick
		mi.material_override = _stick_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_sticks.append(mi)


## Silt sucked into the fissure: spawned in a box of [param extents] centred
## [param above] metres over it, falling at [param speed] and pulled in by
## [param pull] (negative: towards the fissure).
static func _silt(extents: Vector3, above: float, speed: float, pull: float, amount: int) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.emission_shape_offset = Vector3(0.0, above, 0.0)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 10.0
	pm.initial_velocity_min = speed * 0.6
	pm.initial_velocity_max = speed * 1.2
	pm.gravity = Vector3(0, -3.5, 0)
	pm.radial_accel_min = pull * 1.2
	pm.radial_accel_max = pull * 0.8
	pm.particle_flag_align_y = true
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(WATER_LIGHT, 0.0), Color(WATER_LIGHT, 0.3), Color(WATER_LIGHT, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	var ramp := GradientTexture1D.new()
	ramp.gradient = g
	pm.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.45)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = Fx.soft_texture()
	quad.material = mat
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 2.2
	p.process_material = pm
	p.draw_pass_1 = quad
	p.position = Vector3(0, -1.5, 0.4)
	p.visibility_aabb = AABB(Vector3(-10, -6, -6), Vector3(20, 20, 12))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Where the descent line runs at height [param y] (it hangs a little
## slack, swinging slowly in the current at [param t]).
static func line_at(y: float, t: float) -> Vector3:
	var f := inverse_lerp(LINE_TOP, LINE_BOTTOM, y)
	var swing := sin(t * 0.5) * 0.25 * sin(f * PI)
	return Vector3(0.35 + swing + 0.4 * f * f, y, -0.4 + 0.2 * f)


## The line itself, with its arrows pointing the way down and a weighted
## float at its top.
static func _line_mesh() -> ArrayMesh:
	var b := ModelBuilder.new()
	var rope := Color(0.85, 0.8, 0.6, 0.0)
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in 21:
		var y := lerpf(LINE_TOP, LINE_BOTTOM, i / 20.0)
		pts.append(line_at(y, 0.0))
		radii.append(0.018)
	b.tube(pts, radii, 5, rope)
	# Line arrows: little triangles clipped on, pointing down.
	for k in 5:
		var y := lerpf(LINE_TOP - 1.5, LINE_BOTTOM + 1.0, k / 4.0)
		var at := line_at(y, 0.0)
		b.plate([at + Vector3(-0.09, 0.08, 0.0), at + Vector3(0.09, 0.08, 0.0), at + Vector3(0.0, -0.12, 0.0),
			at + Vector3(0.0, -0.12, 0.0)], Color(0.95, 0.45, 0.1, 0.0))
	var top := line_at(LINE_TOP, 0.0)
	b.capsule(top + Vector3(0.0, 0.1, 0.0), top + Vector3(0.0, 0.45, 0.0), 0.2, Color(0.95, 0.42, 0.1, 0.0))
	b.cylinder(top + Vector3(0.0, 0.22, 0.0), top + Vector3(0.0, 0.3, 0.0), 0.205, Color(1, 1, 1, 0.8), 16)
	return b.commit()


func set_sealed(sealed: bool) -> void:
	_color = SEALED_COLOR if sealed else COLOR
	if _light:
		_light.light_color = SEALED_COLOR if sealed else WATER_LIGHT
		_light.light_energy = 1.2 if sealed else 0.6
		_ring_mat.set_shader_parameter(&"flow", 0.0 if sealed else 1.0)
		_ring_mat.set_shader_parameter(&"strength", 0.0 if sealed else 1.0)
		_stick_mat.emission = _color
		_stream.emitting = not sealed
		_inflow.emitting = not sealed


func _process(delta: float) -> void:
	_t += delta
	# The lightsticks hang from the line on short cords, swinging with it.
	for k in _sticks.size():
		var y := lerpf(LINE_TOP - 0.8, LINE_BOTTOM + 2.0, k / float(_sticks.size() - 1))
		var at := line_at(y, _t)
		var sway := sin(_t * 1.1 + k * 1.7) * 0.25
		_sticks[k].position = at + Vector3(sin(sway) * 0.2, -0.22, 0.05)
		_sticks[k].rotation = Vector3(0.0, 0.0, sway)
