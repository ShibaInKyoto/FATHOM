class_name Jelly
extends Creature
## Drifter jelly: pulses slowly along, drifts towards light and shocks
## anything it touches, draining batteries. Killed, it lets go of its whole
## charge at once: everything close by is shocked, hunters stunned - a jelly
## drifting past a pack is a weapon, and one burst right beside the sub is not.
## A glass bell with glowing canals, gonads and a ring of lights at its rim,
## frilled oral arms and long tentacles banded with stinging cells. It
## swims the way jellies do: the bell snaps shut, narrowing and drawing its
## rim in, and slowly relaxes; the tentacles sway and trail as it drifts.

const SHOCK_DRAIN := 12.0
const DISCHARGE_RADIUS := 4.5
const DISCHARGE_DAMAGE := 18.0
const DISCHARGE_STUN := 2.0
## Model space, X up (see [member Creature.upright]): the bell's rim and apex.
const RIM_X := 0.0
const TOP_X := 1.0
const RIM_R := 1.0
const TENTACLES := 16
## The bell's outer surface, (x, radius) from the apex down to the rim.
const OUTER := [Vector2(TOP_X, 0.0), Vector2(0.985, 0.2), Vector2(0.93, 0.45), Vector2(0.8, 0.7),
	Vector2(0.58, 0.88), Vector2(0.3, 0.97), Vector2(0.08, RIM_R)]
## Pulses a second, and the bell squeeze over one (0..1 of the cycle): it
## snaps shut in the first third and relaxes over the rest.
const PULSE_RATE := 2.2 / TAU
## The share of each pulse its bell spends snapping shut (the stroke that
## drives it).
const SQUEEZE := 0.28

var _pulse_t := 0.0
var _drift := Vector2.ZERO
var _discharged := false


func setup() -> void:
	species = &"jelly"
	max_hp = 16.0
	radius = 0.9
	mass = 0.9
	contact_damage = 8.0
	salvage_drop = 2
	hostile = false
	upright = true
	# Bell and tentacles, top to bottom.
	body_span = 4.5
	glow_color = level.biome.glow_color.lerp(Color(1.0, 0.5, 0.9), 0.4)
	super.setup()
	_pulse_t = level.rng.randf() * 3.0
	_drift = Vector2(level.rng.randf_range(-1, 1), level.rng.randf_range(-0.3, 0.3)).normalized() * 0.6


func build_model() -> void:
	var glow := glow_color
	var flesh := species_material(func(m: ShaderMaterial) -> void:
		_style(m)
		m.set_shader_parameter(&"back_color", Color(0.5, 0.45, 0.68))
		m.set_shader_parameter(&"belly_color", Color(0.62, 0.55, 0.82))
		m.set_shader_parameter(&"glow_color", glow)
		m.set_shader_parameter(&"glow_strength", 1.6)
		m.set_shader_parameter(&"rim_strength", 0.5)
		m.set_shader_parameter(&"roughness", 0.1)
		m.set_shader_parameter(&"metallic", 0.0)
		m.set_shader_parameter(&"glass_alpha", 0.07)
		m.set_shader_parameter(&"glass_rim", 0.5)
		m.set_shader_parameter(&"glass_fin", 0.8), &"flesh", GLASS_SHADER)
	var lights := species_material(func(m: ShaderMaterial) -> void:
		_style(m)
		m.set_shader_parameter(&"back_color", Color(0.78, 0.72, 0.92))
		m.set_shader_parameter(&"belly_color", Color(0.78, 0.72, 0.92))
		m.set_shader_parameter(&"glow_color", glow)
		m.set_shader_parameter(&"glow_strength", 2.4)
		m.set_shader_parameter(&"glow_pulse", 0.35)
		m.set_shader_parameter(&"rim_strength", 0.3)
		m.set_shader_parameter(&"roughness", 0.3)
		m.set_shader_parameter(&"metallic", 0.0), &"lights")
	add_visual(_flesh_mesh(), flesh)
	# Draws from the level's random stream exactly as the jelly always has, so
	# a seed still grows the same world.
	var seed_value := 0
	for i in 7:
		seed_value = seed_value * 31 + int(level.rng.randf_range(1.6, 2.8) * 1000.0)
	add_visual(_lights_mesh(seed_value), lights)


## The swim both materials share: a bell that barely moves while the
## tentacles below it sway side to side in slow waves, growing to their tips.
static func _style(m: ShaderMaterial) -> void:
	m.set_shader_parameter(&"body_length", 7.0)
	m.set_shader_parameter(&"swim_amp", 0.35)
	m.set_shader_parameter(&"swim_freq", 2.5)
	m.set_shader_parameter(&"swim_wave", 1.4)
	m.set_shader_parameter(&"swim_vertical", 1.0)
	m.set_shader_parameter(&"swim_head", 0.44)
	m.set_shader_parameter(&"swim_still", 0.4)
	m.set_shader_parameter(&"bend_pivot", 0.6)
	m.set_shader_parameter(&"bell_top", TOP_X)
	m.set_shader_parameter(&"bell_rim", RIM_X)
	m.set_shader_parameter(&"flutter_amp", 0.05)
	m.set_shader_parameter(&"flutter_freq", 5.0)
	m.set_shader_parameter(&"flutter_wave", 6.0)


## The glass: the bell, a thick dome scalloped into lappets at its rim, and
## four frilled oral arms hanging from its centre.
static func _flesh_mesh() -> ArrayMesh:
	var inner := [Vector2(RIM_X, 0.97), Vector2(0.06, 0.88), Vector2(0.24, 0.78), Vector2(0.46, 0.6),
		Vector2(0.62, 0.36), Vector2(0.68, 0.0)]
	var parts := [[_revolve(OUTER + inner, 40)]]
	for k in 4:
		var base := PackedVector2Array()
		var edge := PackedVector2Array()
		for i in 44:
			var f := i / 43.0
			var x := lerpf(0.5, -1.7, f)
			var w := lerpf(0.06, 0.2, sin(PI * minf(f * 1.4, 1.0) * 0.5)) * (1.0 - smoothstep(0.8, 1.0, f) * 0.7)
			base.append(Vector2(x, 0.03))
			# The frill: the arm's free edge ruffled into soft folds.
			edge.append(Vector2(x, 0.03 + w * (1.0 + 0.3 * sin(x * 11.0 + k * 1.7) + 0.12 * sin(x * 27.0 + k))))
		var arm := BodyKit.membrane(base, edge, 0.02, 0, 0.5, 3)
		parts.append([arm, Transform3D(Basis(Vector3.RIGHT, PI * 0.25 + PI * 0.5 * k), Vector3.ZERO)])
	return BodyKit.merged(parts)


## What glows: eight canals running down the bell, four horseshoe gonads
## seen through it, a ring of lights round the rim, and the tentacles, each
## a long thread banded with batteries of stinging cells.
static func _lights_mesh(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var parts := []
	for k in 8:
		var a := TAU * (k + 0.5) / 8.0
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		for i in 9:
			var f := i / 8.0
			var x := lerpf(0.95, 0.06, f)
			var r := _bell_r(x) * 0.95
			pts.append(Vector3(x, cos(a) * r, sin(a) * r))
			radii.append(0.014)
		parts.append([_glowing(_tube(pts, radii, 4), 0.4)])
	for k in 4:
		var a := TAU * k / 4.0
		var c := Vector2(cos(a), sin(a)) * 0.28
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		for i in 13:
			var b := a + PI + lerpf(-2.4, 2.4, i / 12.0)
			var q := c + Vector2(cos(b), sin(b)) * 0.13
			pts.append(Vector3(0.7, q.x, q.y))
			radii.append(0.035)
		parts.append([_glowing(_tube(pts, radii, 5), 1.0)])
	var bead := MeshKit.ball(0.03, 1.0, 6, 4)
	for k in 32:
		var a := TAU * k / 32.0
		parts.append([bead, Transform3D(Basis(), Vector3(RIM_X + 0.03, cos(a) * RIM_R * 0.985, sin(a) * RIM_R * 0.985))])
	for k in TENTACLES:
		var a := TAU * (k + 0.5) / TENTACLES
		var length := rng.randf_range(2.6, 3.5)
		var lean := Vector2(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.12, 0.12))
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		var root := Vector2(cos(a), sin(a)) * RIM_R * 0.94
		for i in 25:
			var f := i / 24.0
			var o := root * (1.0 - f * 0.25) + lean * f * f + Vector2(sin(f * 7.0 + k), cos(f * 5.0 + k)) * 0.04 * f
			pts.append(Vector3(RIM_X + 0.02 - length * f, o.x, o.y))
			radii.append(lerpf(0.022, 0.006, f))
		var thread := _tube(pts, radii, 4)
		# Bands of stinging cells glow down its length.
		parts.append([MeshKit.painted(thread, func(v: Vector3) -> Color:
			var d := (RIM_X - v.x) / length
			var band := 1.0 - smoothstep(0.0, 0.3, absf(fposmod(d * 11.0, 1.0) - 0.5) * 2.0 - 0.4)
			return Color(0.06 + 0.75 * band * (1.0 - d * 0.5), 0.0, minf(d * 3.0, 1.0)))])
	return BodyKit.merged(parts)


## The bell's outer radius at height [param x].
static func _bell_r(x: float) -> float:
	for i in range(1, OUTER.size()):
		var a: Vector2 = OUTER[i - 1]
		var b: Vector2 = OUTER[i]
		if x >= b.x:
			return lerpf(a.y, b.y, (a.x - x) / (a.x - b.x))
	return RIM_R


static func _tube(pts: PackedVector3Array, radii: PackedFloat32Array, sides: int) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	MeshKit.tube(mesh, pts, radii, sides)
	return mesh


static func _glowing(mesh: ArrayMesh, glow: float) -> ArrayMesh:
	return MeshKit.painted(mesh, func(_v: Vector3) -> Color: return Color(glow, 0.0, 0.0))


## A surface of revolution about X through [param profile] ((x, radius)
## points, which may double back: out over the bell and back in under it),
## the rim's points scalloped into lappets.
static func _revolve(profile: Array, sides: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var n := profile.size()
	for i in n:
		var pt: Vector2 = profile[i]
		var d: Vector2 = profile[mini(i + 1, n - 1)] - profile[maxi(i - 1, 0)]
		var n2 := Vector2(d.y, -d.x).normalized()
		var under := 1.0 if i >= 7 else 0.0
		for j in sides + 1:
			var a := TAU * j / sides
			var r := pt.y
			var x := pt.x
			if i == 6 or i == 7:
				# Sixteen lappets round the rim.
				var lap := absf(sin(a * 8.0))
				r *= 1.0 - 0.03 * (1.0 - lap)
				x += 0.05 * (lap - 0.5)
			verts.append(Vector3(x, cos(a) * r, sin(a) * r))
			normals.append(Vector3(n2.x, n2.y * cos(a), n2.y * sin(a)))
			colors.append(Color(0.0, under, 0.0))
			uvs.append(Vector2(x, 0.0))
	var row := sides + 1
	for i in n - 1:
		for j in sides:
			var a := i * row + j
			indices.append_array([a, a + 1, a + row, a + 1, a + row + 1, a + row])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func behave(delta: float) -> void:
	_pulse_t += delta
	var desired := _drift + Vector2(0.0, -0.12)
	var sub := level.player
	if sub and sub.illuminates(pos, 2.0) and pos.distance_to(sub.pos) < 16.0:
		desired += (sub.pos - pos).normalized() * 1.4
	var flare := nearest_flare()
	if flare:
		desired += (flare.pos - pos).normalized() * 1.8
	steer(desired, 0.8, delta)
	# Each squeeze of its bell drives it up (as the bell is drawn: see
	# _update_visuals); between squeezes it coasts, and sinks back a little.
	if fposmod(_pulse_t * PULSE_RATE, 1.0) < SQUEEZE:
		vel.y += 1.6 * delta
	if level.field.sample(pos) < radius + 1.5:
		var n := level.field.normal(pos)
		if _drift.dot(n) < 0.0:
			_drift = _drift.reflect(n).normalized() * 0.6


func on_touch_player(sub: Submarine) -> void:
	sub.take_damage(contact_damage, pos, self)
	sub.run.battery = maxf(sub.run.battery - SHOCK_DRAIN, 0.0)
	Fx.flash(level, pos, glow_color, 8.0, 0.25)
	Audio.play_at(&"jelly_shock", pos, 0.0)


func die() -> void:
	# A discharge can set off another jelly's, and that one can reach back:
	# each lets go only once.
	if not alive or _discharged:
		return
	_discharged = true
	Fx.shockwave(level, pos, DISCHARGE_RADIUS, glow_color)
	Audio.play_at(&"shock", pos, 0.0, 0.05, 1.3)
	for e in level.targets_in_radius(pos, DISCHARGE_RADIUS):
		var c := e as Creature
		if c and c != self and c.alive:
			c.stun(DISCHARGE_STUN)
			c.take_damage(DISCHARGE_DAMAGE, pos, &"shock")
	var sub := level.player
	if sub and sub.alive and sub.pos.distance_to(pos) < DISCHARGE_RADIUS:
		sub.run.battery = maxf(sub.run.battery - SHOCK_DRAIN, 0.0)
		Fx.flash(level, sub.pos, glow_color, 6.0, 0.25)
	super.die()


func _update_visuals(delta: float) -> void:
	super._update_visuals(delta)
	# The bell snaps shut as the pulse drives it up, then slowly relaxes.
	var cycle := fposmod(_pulse_t * PULSE_RATE, 1.0)
	var squeeze := smoothstep(0.0, SQUEEZE, cycle) if cycle < SQUEEZE else 1.0 - smoothstep(SQUEEZE, 0.95, cycle)
	# The tentacles trail behind as it drifts (the model's +Y is the world's
	# left: see Creature.upright).
	var trail := clampf(vel.x * 0.07, -0.14, 0.14)
	for v in visuals:
		v.set_instance_shader_parameter(&"bell_squeeze", squeeze)
		v.set_instance_shader_parameter(&"bend", trail)
