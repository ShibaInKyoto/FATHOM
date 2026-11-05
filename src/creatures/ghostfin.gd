class_name Ghostfin
extends Creature
## Ghostfins: small, near-transparent pack hunters of the Hadal Trench, seen
## mostly as pairs of glowing eyes. Light draws them: a pack circles a lit
## lamp and takes turns darting in to bite, and loses interest a few seconds
## after the lamp goes dark. A burning flare pulls the whole pack off.
## Their flesh is glass: what shows is the eyes, the faint glowing edges of
## the ribbon fins that run their whole length, and the skeleton inside.

enum State { DRIFT, CIRCLE, DART, RETREAT }

## A lit lamp is noticed from this far away (with line of sight).
const SIGHT_RANGE := 24.0
const ORBIT_RADIUS := 6.0
const ORBIT_SPEED := 7.0
const DART_SPEED := 15.0
const DART_TIME := 0.5
## Seconds the pack keeps circling after the lamp goes dark.
const PATIENCE := 3.0
## Model space: x from the tail's tip to the snout. Stations as in
## [method BodyKit.body]: slender and deeper than wide, the head no wider.
const BODY := [[-0.76, 0.004, 0.01, 0.01, 0.0], [-0.6, 0.012, 0.03, 0.028, 0.0], [-0.38, 0.026, 0.062, 0.056, 0.0],
	[-0.1, 0.044, 0.094, 0.088, 0.0], [0.16, 0.058, 0.112, 0.106, 0.0], [0.38, 0.064, 0.112, 0.094, 0.004],
	[0.53, 0.058, 0.094, 0.052, 0.0], [0.63, 0.044, 0.066, 0.032, -0.008], [0.705, 0.016, 0.03, 0.014, -0.016]]
const BODY_LENGTH := 1.47
const JAW_HINGE := Vector3(0.47, -0.04, 0.0)

var state := State.DRIFT
var _home := Vector2.ZERO
var _target := Vector2.ZERO
var _orbit := 0.0
var _timer := 0.0
var _dark := 0.0
var _dart_dir := Vector2.RIGHT
var _jaw: MeshInstance3D
var _jaw_teeth: MeshInstance3D
var _gape := 0.0


func setup() -> void:
	species = &"ghostfin"
	max_hp = 14.0
	radius = 0.5
	mass = 0.5
	contact_damage = 7.0
	salvage_drop = 2
	glow_color = Color(0.6, 0.85, 1.0)
	_turn_speed = 9.0
	super.setup()
	_home = pos
	_target = wander_point(_home, 10.0)
	_orbit = level.rng.randf() * TAU
	_timer = level.rng.randf_range(1.5, 4.0)


func build_model() -> void:
	flex = 1.0
	flex_pivot = 0.2
	body_span = BODY_LENGTH
	var flesh := species_material(func(m: ShaderMaterial) -> void:
		_swim_style(m)
		m.set_shader_parameter(&"back_color", Color(0.42, 0.54, 0.62))
		m.set_shader_parameter(&"belly_color", Color(0.6, 0.67, 0.74))
		m.set_shader_parameter(&"glow_color", Color(0.55, 0.85, 1.0))
		m.set_shader_parameter(&"glow_strength", 1.8)
		m.set_shader_parameter(&"rim_strength", 0.45)
		m.set_shader_parameter(&"roughness", 0.12)
		m.set_shader_parameter(&"metallic", 0.0)
		m.set_shader_parameter(&"glass_alpha", 0.08)
		m.set_shader_parameter(&"glass_rim", 0.55)
		m.set_shader_parameter(&"glass_fin", 0.6), &"flesh", GLASS_SHADER)
	var bone := species_material(func(m: ShaderMaterial) -> void:
		_swim_style(m)
		m.set_shader_parameter(&"back_color", Color(0.74, 0.84, 0.9))
		m.set_shader_parameter(&"belly_color", Color(0.02, 0.015, 0.02))
		m.set_shader_parameter(&"glow_color", Color(0.55, 0.85, 1.0))
		m.set_shader_parameter(&"glow_strength", 1.2)
		m.set_shader_parameter(&"rim_strength", 0.2)
		m.set_shader_parameter(&"roughness", 0.35)
		m.set_shader_parameter(&"metallic", 0.0)
		m.set_shader_parameter(&"tooth_color", Color(0.86, 0.9, 0.92)), &"bone")
	add_visual(_flesh_mesh(), flesh)
	add_visual(_skeleton_mesh(), bone)
	# The lower jaw, flesh and teeth, dropping open as it darts in.
	var hinge := Transform3D(Basis(), JAW_HINGE)
	_jaw = add_visual(BodyKit.body([[0.0, 0.042, 0.012, 0.03, 0.0], [0.1, 0.034, 0.01, 0.024, 0.004],
		[0.19, 0.018, 0.007, 0.012, 0.008], [0.235, 0.004, 0.003, 0.004, 0.01]], 14, 12), flesh, hinge)
	var teeth := []
	for sgn: float in [1.0, -1.0]:
		for t: Array in BodyKit.teeth_row(Vector3(0.03, 0.006, 0.03 * sgn), Vector3(0.21, 0.01, 0.008 * sgn), 7,
				0.03, Vector3(0.0, 1.0, 0.1 * sgn), 5 if sgn > 0.0 else 6):
			teeth.append([BodyKit.enamel(t[0]), t[1], (t[1] as Transform3D).origin.x])
	_jaw_teeth = add_visual(BodyKit.merged(teeth), bone, hinge)
	add_eyes(Vector3(0.575, 0.022, 0.046), 0.04, Color(0.72, 0.95, 1.0), 3.5, Eye.FISH)
	# A soft halo round each eye: from across a dark trench the eyes are all
	# that shows of a pack.
	var halo := StandardMaterial3D.new()
	halo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	halo.albedo_color = Color(0.5, 0.85, 1.0, 0.45)
	# After the flesh, so the far eye's halo stays hidden behind the head.
	halo.render_priority = 1
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.gradient = Gradient.new()
	tex.gradient.set_color(0, Color(1, 1, 1, 1))
	tex.gradient.set_color(1, Color(1, 1, 1, 0))
	tex.gradient.add_point(0.25, Color(1, 1, 1, 0.45))
	halo.albedo_texture = tex
	for r: Array in _riders.slice(-2):
		var glow := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.18, 0.18)
		glow.mesh = quad
		glow.material_override = halo
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glow.position = Vector3(0.0, 0.0, 0.05 * signf((r[1] as Transform3D).origin.z))
		(r[0] as Node3D).add_child(glow)


## The swim both materials share: an eel's, the whole body waving, the head
## too, with more than one wave down it at a time; the ribbon fins ripple
## back along their length.
static func _swim_style(m: ShaderMaterial) -> void:
	m.set_shader_parameter(&"body_length", BODY_LENGTH)
	m.set_shader_parameter(&"swim_amp", 0.09)
	m.set_shader_parameter(&"swim_freq", 10.0)
	m.set_shader_parameter(&"swim_wave", 5.5)
	m.set_shader_parameter(&"swim_vertical", 0.0)
	m.set_shader_parameter(&"swim_head", 0.4)
	m.set_shader_parameter(&"swim_still", 0.05)
	m.set_shader_parameter(&"swim_roll", 0.03)
	m.set_shader_parameter(&"fin_lag", 0.5)
	m.set_shader_parameter(&"bend_pivot", 0.2)
	m.set_shader_parameter(&"anchored", true)
	m.set_shader_parameter(&"flutter_amp", 0.012)
	m.set_shader_parameter(&"flutter_freq", 16.0)
	m.set_shader_parameter(&"flutter_wave", 20.0)


## The see-through flesh: the body, a ribbon fin down the back and another
## under the tail meeting in a pointed tip, and long trailing pectorals, the
## fin edges faintly aglow.
static func _flesh_mesh() -> ArrayMesh:
	var parts := [[BodyKit.body(BODY, 44, 18)]]
	for up: float in [1.0, -1.0]:
		var base := PackedVector2Array()
		var edge := PackedVector2Array()
		var front := 0.28 if up > 0.0 else 0.02
		for i in 34:
			var f := i / 33.0
			var x := lerpf(front, -0.86, f)
			var rim := 0.0
			if x > BODY[0][0]:
				rim = BodyKit.at(BODY, x, 2 if up > 0.0 else 3) - 0.004
			var y := BodyKit.at(BODY, maxf(x, BODY[0][0]), 4) + rim * up
			# Rising from the head, deepest past mid-body, drawing in to the tip.
			var h := 0.075 * smoothstep(0.0, 0.25, f) * lerpf(1.0, 0.45, smoothstep(0.55, 1.0, f))
			h *= 0.85 if up < 0.0 else 1.0
			if x < BODY[0][0]:
				h *= 1.0 - smoothstep(BODY[0][0], -0.86, x)
			base.append(Vector2(x, y))
			edge.append(Vector2(x - 0.025, y + h * up))
		parts.append([BodyKit.membrane(base, edge, 0.01, 16, 0.8, 5)])
	var pec := BodyKit.ray_fin(PackedVector2Array([Vector2(0.43, 0.0), Vector2(0.415, -0.004), Vector2(0.4, -0.008),
		Vector2(0.385, -0.012), Vector2(0.37, -0.016)]), PackedVector2Array([Vector2(0.24, 0.035), Vector2(0.19, 0.0),
		Vector2(0.16, -0.045), Vector2(0.17, -0.09), Vector2(0.21, -0.12)]), 0.18, 0.12, 0.004, 0.006, 0.7)
	for sgn: float in [1.0, -1.0]:
		parts.append([pec, Transform3D(Basis(Vector3.RIGHT, sgn * 1.2), Vector3(0.0, -0.035, 0.05 * sgn))])
	return BodyKit.merged(parts)


## What shows through the flesh: a faintly luminous backbone with its spines
## and ribs, the skull's arches round the eyes and gill cover, the gut a
## black sac (so the glow of what it has eaten never gives it away), needle
## teeth, and two long feelers trailing from the throat.
static func _skeleton_mesh() -> ArrayMesh:
	var bones := []
	var count := 30
	for i in count:
		var f := i / float(count - 1)
		var x := lerpf(-0.73, 0.44, f)
		var y := BodyKit.at(BODY, x, 4)
		var top := BodyKit.at(BODY, x, 2)
		var low := BodyKit.at(BODY, x, 3)
		var r := clampf(top * 0.09, 0.0035, 0.01)
		var vert := MeshKit.ball(r, 0.0, 6, 4)
		bones.append([vert, Transform3D(Basis().scaled(Vector3(1.5, 1.0, 1.0)), Vector3(x, y, 0.0)), x])
		if i % 2 == 0 and x < 0.4:
			bones.append([_bone([Vector3(x, y, 0.0), Vector3(x - top * 0.25, y + top * 0.5, 0.0),
				Vector3(x - top * 0.55, y + top * 0.88, 0.0)], 0.0025), Transform3D.IDENTITY, x])
		if i % 2 == 0 and x < 0.02:
			bones.append([_bone([Vector3(x, y, 0.0), Vector3(x - low * 0.25, y - low * 0.5, 0.0),
				Vector3(x - low * 0.55, y - low * 0.88, 0.0)], 0.0025), Transform3D.IDENTITY, x])
		if x > 0.04 and x < 0.42 and i % 2 == 1:
			var hw := BodyKit.at(BODY, x, 1)
			for sgn: float in [1.0, -1.0]:
				bones.append([_bone([Vector3(x, y, 0.0), Vector3(x - 0.012, y - low * 0.35, hw * 0.78 * sgn),
					Vector3(x - 0.035, y - low * 0.75, hw * 0.6 * sgn), Vector3(x - 0.05, y - low * 0.9, hw * 0.25 * sgn)],
					0.0022), Transform3D.IDENTITY, x])
	# The skull: an arch over the brain to the snout, rings round the eyes,
	# the gill cover's curved edge.
	bones.append([_bone([Vector3(0.44, 0.0, 0.0), Vector3(0.52, 0.05, 0.0), Vector3(0.62, 0.045, 0.0),
		Vector3(0.7, 0.0, 0.0)], 0.004), Transform3D.IDENTITY, 0.56])
	for sgn: float in [1.0, -1.0]:
		var ring := []
		for i in 13:
			var a := TAU * i / 12.0
			ring.append(Vector3(0.575 + cos(a) * 0.046, 0.022 + sin(a) * 0.044, 0.03 * sgn))
		bones.append([_bone(ring, 0.003), Transform3D.IDENTITY, 0.575])
		bones.append([_bone([Vector3(0.49, 0.075, 0.045 * sgn), Vector3(0.455, 0.03, 0.055 * sgn),
			Vector3(0.45, -0.02, 0.055 * sgn), Vector3(0.47, -0.06, 0.045 * sgn)], 0.003), Transform3D.IDENTITY, 0.47])
	var parts := [[MeshKit.painted(BodyKit.merged(bones), func(_v: Vector3) -> Color:
		return Color(0.2, 0.0, 0.0))]]
	# The gut, black, hung under the spine.
	var gut := MeshKit.painted(MeshKit.ball(1.0, 0.0, 10, 6), func(_v: Vector3) -> Color:
		return Color(0.0, 1.0, 0.0))
	parts.append([gut, Transform3D(Basis().scaled(Vector3(0.15, 0.032, 0.028)), Vector3(0.2, -0.045, 0.0))])
	# Needle teeth along the upper jaw, a fang or two among them.
	for sgn: float in [1.0, -1.0]:
		for t: Array in BodyKit.teeth_row(Vector3(0.5, -0.04, 0.034 * sgn), Vector3(0.69, -0.016, 0.01 * sgn), 8,
				0.032, Vector3(0.0, -1.0, 0.1 * sgn), 3 if sgn > 0.0 else 4):
			parts.append([BodyKit.enamel(t[0]), t[1], (t[1] as Transform3D).origin.x])
	# Feelers: two threads from the throat, their tips glowing.
	for sgn: float in [1.0, -1.0]:
		var pts := PackedVector3Array([Vector3(0.49, -0.06, 0.012 * sgn), Vector3(0.42, -0.1, 0.02 * sgn),
			Vector3(0.32, -0.135, 0.026 * sgn), Vector3(0.2, -0.15, 0.03 * sgn), Vector3(0.1, -0.155, 0.032 * sgn)])
		var thread := ArrayMesh.new()
		MeshKit.tube(thread, pts, PackedFloat32Array([0.004, 0.003, 0.0025, 0.002, 0.0016]), 4)
		parts.append([MeshKit.painted(thread, func(v: Vector3) -> Color:
			var f := clampf((0.49 - v.x) / 0.39, 0.0, 1.0)
			return Color(smoothstep(0.7, 1.0, f) * 1.5, 0.0, f)), Transform3D.IDENTITY, 0.49])
	return BodyKit.merged(parts)


static func _bone(points: Array, radius: float) -> ArrayMesh:
	var radii := PackedFloat32Array()
	for i in points.size():
		radii.append(radius * lerpf(1.0, 0.6, i / maxf(points.size() - 1.0, 1.0)))
	var mesh := ArrayMesh.new()
	MeshKit.tube(mesh, PackedVector3Array(points), radii, 4)
	return mesh


func think() -> void:
	var sub := level.player
	var flare := nearest_flare()
	var lit := sub != null and sub.alive and sub.lamp_on and pos.distance_to(sub.pos) < SIGHT_RANGE \
		and level.field.line_of_sight(pos, sub.pos)
	match state:
		State.DRIFT:
			if flare and flare.lure_strength(pos) > 0.05:
				state = State.CIRCLE
			elif lit:
				state = State.CIRCLE
				_timer = level.rng.randf_range(1.5, 3.5)
			elif pos.distance_to(_target) < 2.0:
				_target = wander_point(_home, 10.0)
		State.CIRCLE:
			_dark = 0.0 if lit or flare else _dark + THINK_INTERVAL
			if _dark > PATIENCE:
				state = State.DRIFT
				_home = pos
				_target = wander_point(_home, 10.0)


func behave(delta: float) -> void:
	match state:
		State.DRIFT:
			seek(_target, 2.5, 2.0, delta)
		State.CIRCLE:
			var center := _focus()
			_orbit += delta * ORBIT_SPEED / ORBIT_RADIUS
			seek(center + Vector2.from_angle(_orbit) * ORBIT_RADIUS, ORBIT_SPEED, 3.0, delta)
			_timer -= delta
			# Only a lamp is worth a bite; a flare is just circled.
			var sub := level.player
			if _timer <= 0.0 and sub and sub.alive and sub.lamp_on and nearest_flare() == null:
				state = State.DART
				_timer = DART_TIME
				_dart_dir = (sub.pos - pos).normalized()
				Audio.play_at(&"lancer_dash", pos, -10.0, 0.1, 1.8)
		State.DART:
			_timer -= delta
			vel = _dart_dir * DART_SPEED
			if _timer <= 0.0:
				_retreat()
		State.RETREAT:
			_timer -= delta
			seek(pos - _dart_dir * 4.0, 6.0, 3.0, delta)
			if _timer <= 0.0:
				state = State.CIRCLE
				_timer = level.rng.randf_range(2.0, 4.0)


## What the pack circles: a burning flare if there is one, else the sub.
func _focus() -> Vector2:
	var flare := nearest_flare()
	if flare:
		return flare.pos
	return level.player.pos if level.player else pos


func _retreat() -> void:
	state = State.RETREAT
	_timer = 0.8


func on_touch_player(sub: Submarine) -> void:
	if state == State.DART:
		sub.take_damage(contact_damage, pos, self)
		_retreat()


func on_damaged(_amount: float, _from: Vector2) -> void:
	if alive and state == State.DRIFT:
		state = State.CIRCLE
		_timer = 0.5


func _update_visuals(delta: float) -> void:
	super._update_visuals(delta)
	if _jaw:
		var want := 0.5 if state == State.DART else (0.1 if state == State.CIRCLE else 0.0)
		_gape = lerpf(_gape, want, 1.0 - exp(-12.0 * delta))
		_jaw.rotation.z = -_gape
		_jaw_teeth.rotation.z = -_gape
