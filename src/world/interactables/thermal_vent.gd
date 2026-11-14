class_name ThermalVent
extends Entity
## A vent in the vent fields (see [VentModel]) that erupts every so often. It rumbles and
## glows first, then blasts a column of scalding water that shoves and burns
## anything inside it - and is loud enough to bring every hunter in earshot.
## Creatures caught in the column cook, which a careful pilot can use.

enum State { DORMANT, WARNING, ERUPTING }

const HEIGHT := 15.0
const WIDTH := 2.4
const WARNING_TIME := 1.3
const ERUPT_TIME := 2.6
const PUSH := 34.0
## Damage per scald while inside the column (applied every [constant SCALD_INTERVAL]).
const SUB_SCALD := 6.0
const CREATURE_SCALD := 14.0
const SCALD_INTERVAL := 0.45
const NOISE := 26.0

const SHADER := preload("res://src/fx/shaders/vent.gdshader")
## How far the vent sits out of the rock face (see [method LevelPopulator]).
const LIFT := 0.3
## The first eruption a pilot sees explains itself, once per session.
static var _explained := false

var normal := Vector2.UP
## One of the vents on the Ironclad's lair floor.
var in_lair := false
var state := State.DORMANT
var _timer := 0.0
var _scald_timer := 0.0
var _mat: ShaderMaterial
var _smoke: GPUParticles3D
var _heat := 0.25
var _light: OmniLight3D
var _plume: GPUParticles3D
var _bubbles: GPUParticles3D


func setup() -> void:
	radius = 1.2
	active_radius = 80.0
	_timer = level.rng.randf_range(2.0, 9.0)
	var holder := Node3D.new()
	# Local +Y points out of the floor, along the eruption column.
	holder.rotation.z = normal.angle() - PI * 0.5
	add_child(holder)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter(&"rock_albedo", TerrainRenderer.ROCK_ALBEDO)
	_mat.set_shader_parameter(&"rock_tint", level.biome.rock_tint)
	_mat.set_shader_parameter(&"sediment_tint", level.biome.sediment_tint)
	var model := MeshInstance3D.new()
	model.mesh = VentModel.build(level.rng, LIFT)
	model.material_override = _mat
	holder.add_child(model)
	# The column, its bubbles and its smoke rise from the main throat.
	var throat := VentModel.MAIN_AT + Vector3(0.0, VentModel.mound_height(VentModel.MAIN_AT,
		func(z: float) -> float: return PropScatter.surface_offset(z) - LIFT) + VentModel.MAIN_HEIGHT - 0.2, 0.0)
	_plume = Fx.vent_plume(HEIGHT)
	_plume.position = throat
	holder.add_child(_plume)
	_bubbles = Fx.bubble_emitter()
	_bubbles.emitting = false
	_bubbles.position = throat
	holder.add_child(_bubbles)
	# At rest it smokes: a thin black plume, lit by the throat as it leaves.
	_smoke = _smoker()
	_smoke.position = throat
	holder.add_child(_smoke)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.5, 0.2)
	_light.omni_range = 11.0
	_light.light_volumetric_fog_energy = 1.5
	_light.position = throat + Vector3(0.0, 0.6, 1.0)
	_light.visible = false
	holder.add_child(_light)


## The thin black smoke a resting chimney gives off: glowing as it leaves
## the throat, darkening and spreading as it rises.
static func _smoker() -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 6.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.3
	pm.scale_min = 0.5
	pm.scale_max = 0.9
	var grow := Curve.new()
	grow.max_value = 3.0
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(1.0, 2.6))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	pm.scale_curve = grow_tex
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.turbulence_noise_scale = 2.0
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.08
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1.0, 0.45, 0.15, 0.5), Color(0.16, 0.13, 0.12, 0.45), Color(0.1, 0.1, 0.1, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 0.18, 1.0])
	var ramp := GradientTexture1D.new()
	ramp.gradient = g
	pm.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(0.6, 0.6)
	quad.material = Fx.particle_material(Fx.soft_texture(), false, 1.0)
	var p := GPUParticles3D.new()
	p.amount = 26
	p.lifetime = 3.2
	p.process_material = pm
	p.draw_pass_1 = quad
	p.local_coords = true
	p.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 7, 6))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func tick(delta: float) -> void:
	_timer -= delta
	match state:
		State.DORMANT:
			_heat = move_toward(_heat, 0.22 + 0.06 * sin(level.time * 2.0 + pos.x), delta * 0.5)
			if _timer <= 0.0:
				_set_state(State.WARNING)
		State.WARNING:
			var k := 1.0 - _timer / WARNING_TIME
			_heat = lerpf(0.3, 0.9, k) * (0.85 + 0.15 * sin(level.time * 30.0))
			_light.light_energy = 2.0 * k
			if _timer <= 0.0:
				_set_state(State.ERUPTING)
		State.ERUPTING:
			_heat = 1.0
			_light.light_energy = 5.0 * (0.8 + 0.2 * sin(level.time * 20.0))
			_scald(delta)
			if _timer <= 0.0:
				_set_state(State.DORMANT)
	_mat.set_shader_parameter(&"heat", _heat)


## Starts the warning rumble now (tests and scripted moments).
func erupt_soon() -> void:
	_set_state(State.WARNING)


func _set_state(s: State) -> void:
	state = s
	match s:
		State.DORMANT:
			_timer = level.rng.randf_range(7.0, 13.0)
			_plume.emitting = false
			_bubbles.emitting = false
			_smoke.emitting = true
			_light.visible = false
		State.WARNING:
			_timer = WARNING_TIME
			_bubbles.emitting = true
			_light.visible = true
			Audio.play_at(&"vent_rumble", pos, -2.0)
		State.ERUPTING:
			_timer = ERUPT_TIME
			_scald_timer = 0.0
			_plume.emitting = true
			_smoke.emitting = false
			Audio.play_at(&"vent_erupt", pos, 0.0)
			level.emit_noise(pos + normal * 4.0, NOISE, self)
			_explain()


## How strongly the column grips something at [param p] (0 = outside it).
func column_strength(p: Vector2, r := 0.0) -> float:
	var rel := p - pos
	var along := rel.dot(normal)
	if along < -0.5 or along > HEIGHT:
		return 0.0
	var width := WIDTH * (1.0 + along / HEIGHT * 0.6) + r
	var lateral := absf(rel.dot(normal.orthogonal()))
	if lateral > width:
		return 0.0
	return (1.0 - along / HEIGHT * 0.7) * (1.0 - lateral / width * 0.5)


func _scald(delta: float) -> void:
	_scald_timer -= delta
	var burn := _scald_timer <= 0.0
	if burn:
		_scald_timer = SCALD_INTERVAL
	var sub := level.player
	if sub and sub.alive:
		var k := column_strength(sub.pos, Submarine.RADIUS)
		if k > 0.0:
			sub.vel += normal * PUSH * k * delta
			if burn:
				sub.take_damage(SUB_SCALD, sub.pos - normal, self, false)
	for e in level.targets_in_radius(pos + normal * HEIGHT * 0.5, HEIGHT * 0.6):
		var c := e as Creature
		if c == null:
			continue
		var ck := column_strength(c.pos, c.radius)
		if ck > 0.0:
			c.vel += normal * PUSH * 0.6 * ck * delta / maxf(c.mass, 1.0)
			if burn:
				c.take_damage(CREATURE_SCALD, pos, &"vent")


func _explain() -> void:
	var sub := level.player
	if _explained or sub == null or sub.pos.distance_to(pos) > 35.0:
		return
	_explained = true
	Events.toast.emit("Thermal vent! They rumble and glow before erupting - stay out of the column, " +
		"or lure hunters into it.", UiTheme.WARN)
