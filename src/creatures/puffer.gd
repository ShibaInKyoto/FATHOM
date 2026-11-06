class_name Puffer
extends Creature
## Spined puffer: a slow, curious reef fish that gulps water and swells into
## a ball of spines when anything rushes or roars past. Swollen, it hurts
## whatever touches it, lancers included; harpooned while swollen it bursts
## and sprays spines at everything nearby. Drifting past gently keeps it calm.
## A porcupinefish: blunt and big-eyed, spotted, a beak for a mouth, its
## spines lying flat; it swims stiff-bodied, fluttering the soft fins on its
## back and belly, and hovers to keep its eyes on anything nearby. Startled
## it gulps water and swells, wobbling, into a ball, its spines standing out
## straight; it bobs there helpless and slowly sags back. One mesh holds
## both shapes (see BodyKit.morph).

enum State { CALM, PUFFED }

const CALM_RADIUS := 0.65
const PUFFED_RADIUS := 1.15
const PUFF_TIME := 5.0
## Startled by the sub this close (plus part of its noise radius) ...
const STARTLE_RANGE := 3.0
## ... when the sub is at least this loud, or almost touching.
const STARTLE_NOISE := 7.0
const SPINE_DAMAGE := 12.0
const NOVA_RADIUS := 4.5
const NOVA_DAMAGE := 30.0

## The body calm and swollen (x from the tail to the beak; stations as in
## [method BodyKit.body]): the beak stays where it is and the ball swells
## out behind it.
const CALM := [[-0.62, 0.05, 0.07, 0.07, 0.02], [-0.5, 0.1, 0.13, 0.12, 0.02], [-0.3, 0.24, 0.28, 0.26, 0.02],
	[-0.05, 0.36, 0.4, 0.38, 0.0], [0.2, 0.42, 0.44, 0.4, -0.01], [0.42, 0.4, 0.4, 0.33, -0.02],
	[0.58, 0.32, 0.3, 0.22, -0.03], [0.68, 0.2, 0.18, 0.12, -0.04], [0.73, 0.07, 0.07, 0.05, -0.04],
	[0.745, 0.01, 0.01, 0.01, -0.04]]
const PUFFED := [[-1.24, 0.05, 0.07, 0.07, 0.0], [-1.12, 0.13, 0.15, 0.14, 0.0], [-1.0, 0.44, 0.44, 0.44, 0.0],
	[-0.75, 0.72, 0.72, 0.72, 0.0], [-0.45, 0.86, 0.86, 0.86, 0.0], [-0.18, 0.9, 0.9, 0.9, 0.0],
	[0.12, 0.86, 0.86, 0.85, 0.0], [0.4, 0.72, 0.72, 0.7, -0.01], [0.6, 0.5, 0.5, 0.46, -0.02],
	[0.7, 0.28, 0.28, 0.24, -0.03], [0.74, 0.08, 0.08, 0.06, -0.04], [0.745, 0.01, 0.01, 0.01, -0.04]]
## Where the eyes sit (along the body, and how far round from the back).
const EYE_X := 0.5
const EYE_A := 1.12
const EYE_X_PUFFED := 0.4
const SPINES := 96
const JAW_HINGE := Vector3(0.69, -0.06, 0.0)

static var _spine_mesh: Mesh
## Leathery, finely pebbled skin, shared by every puffer.
static var _skin_tex: NoiseTexture2D

var state := State.CALM
var _timer := 0.0
## How swollen (0 calm, 1 a ball; it overshoots a little as it wobbles), and
## how fast it is swelling or sagging.
var _inflation := 0.0
var _inflation_v := 0.0
var _home := Vector2.ZERO
var _target := Vector2.ZERO
var _spike_cooldown := 0.0
var _dying := false
var _body: MeshInstance3D
var _jaw: MeshInstance3D
var _spine_mat: StandardMaterial3D
var _gape := 0.0
var _t := 0.0
## Each eye's place calm and swollen (model space).
var _eye_calm: Array[Transform3D] = []
var _eye_puffed: Array[Transform3D] = []


func setup() -> void:
	species = &"puffer"
	max_hp = 18.0
	radius = CALM_RADIUS
	mass = 0.8
	contact_damage = SPINE_DAMAGE
	hearing = 0.45
	salvage_drop = 3
	hostile = false
	glow_color = Color(1.0, 0.85, 0.4)
	_turn_speed = 3.0
	body_span = 1.36
	super.setup()
	_home = pos
	_target = wander_point(_home, 9.0)


func build_model() -> void:
	var mat := species_material(func(m: ShaderMaterial) -> void:
		m.set_shader_parameter(&"back_color", Color(0.5, 0.44, 0.27))
		m.set_shader_parameter(&"belly_color", Color(0.86, 0.84, 0.74))
		m.set_shader_parameter(&"glow_color", Color(1.0, 0.85, 0.4))
		m.set_shader_parameter(&"glow_strength", 1.6)
		m.set_shader_parameter(&"roughness", 0.55)
		m.set_shader_parameter(&"metallic", 0.0)
		m.set_shader_parameter(&"rim_strength", 0.3)
		m.set_shader_parameter(&"skin_pits", 0.003)
		m.set_shader_parameter(&"skin_tex", _skin())
		m.set_shader_parameter(&"skin_tex_scale", 5.0)
		m.set_shader_parameter(&"skin_tex_depth", 0.0015)
		m.set_shader_parameter(&"skin_tex_shade", 0.1)
		m.set_shader_parameter(&"mottle", 0.5)
		m.set_shader_parameter(&"spots", 0.85)
		m.set_shader_parameter(&"spot_size", 0.11)
		# A dark band down through each eye, and saddles over the nape, the
		# middle of the back and in front of the tail, running down the flanks.
		m.set_shader_parameter(&"blotch_at", [Vector4(0.49, 0.05, 0.3, 0.5), Vector4(0.24, 0.42, 0.0, 0.45),
			Vector4(-0.08, 0.4, 0.0, 0.45), Vector4(-0.4, 0.22, 0.0, 0.4)])
		m.set_shader_parameter(&"blotch_size", [Vector3(0.07, 0.32, 0.26), Vector3(0.1, 0.3, 0.4),
			Vector3(0.1, 0.32, 0.42), Vector3(0.08, 0.2, 0.3)])
		m.set_shader_parameter(&"fin_color", Color(0.6, 0.52, 0.3, 0.75))
		m.set_shader_parameter(&"tooth_color", Color(0.86, 0.82, 0.7)))
	_body = add_visual(BodyKit.morph(_build(CALM, false), _build(PUFFED, true)), mat)
	# The lower half of the beak, which gulps.
	var jaw := MeshKit.transformed(MeshKit.ball(1.0, 0.0, 10, 6), Transform3D(
		Basis().scaled(Vector3(0.05, 0.026, 0.06)), Vector3(0.05, 0.0, 0.0)))
	_jaw = add_visual(BodyKit.enamel(jaw), mat, Transform3D(Basis(), JAW_HINGE))
	add_eyes(_eye_at(CALM, EYE_X, EYE_A).origin, 0.088, Color(0.86, 0.74, 0.28), 0.0, Eye.FISH)
	for r: Array in _riders.slice(-2):
		var sgn := signf((r[1] as Transform3D).origin.z)
		_eye_calm.append(r[1])
		var t := _eye_at(PUFFED, EYE_X_PUFFED, EYE_A)
		_eye_puffed.append(Transform3D((r[1] as Transform3D).basis, Vector3(t.origin.x, t.origin.y, t.origin.z * sgn)))
	if _spine_mesh == null:
		_spine_mesh = MeshKit.spike(0.045, 0.4, 0.0, 5)
	_spine_mat = StandardMaterial3D.new()
	_spine_mat.albedo_color = Color(0.86, 0.82, 0.7)
	_spine_mat.roughness = 0.45


## Leathery skin, pebbled: soft cells, built once.
static func _skin() -> NoiseTexture2D:
	if _skin_tex == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_CELLULAR
		noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
		noise.frequency = 0.045
		noise.seed = 23
		_skin_tex = NoiseTexture2D.new()
		_skin_tex.width = 256
		_skin_tex.height = 256
		_skin_tex.seamless = true
		_skin_tex.generate_mipmaps = true
		_skin_tex.normalize = true
		_skin_tex.noise = noise
	return _skin_tex


## The eye's place on a body of [param stations]: on the skin at
## [param x], [param a] round from the back, sunk a little into it.
static func _eye_at(stations: Array, x: float, a: float) -> Transform3D:
	var p := BodyKit.surface(stations, x, a)
	return Transform3D(Basis(), p - _normal(stations, x, a) * 0.025)


## The skin's outward normal on a body of [param stations].
static func _normal(stations: Array, x: float, a: float) -> Vector3:
	var round := BodyKit.surface(stations, x, a + 0.02) - BodyKit.surface(stations, x, a - 0.02)
	var along := BodyKit.surface(stations, x + 0.01, a) - BodyKit.surface(stations, x - 0.01, a)
	return round.cross(along).normalized()


## The whole fish on a body of [param stations], calm or swollen: the same
## parts in the same order either way, only placed differently, so the two
## can be morphed between. Spines lie flat calm and stand out swollen.
static func _build(stations: Array, swollen: bool) -> ArrayMesh:
	var x0: float = stations[0][0]
	var parts := [[BodyKit.body(stations, 40, 24)]]
	# The spines, spread evenly over the body behind the head (not near the
	# eyes or the beak): skin-coloured, their tips pale bone, glowing faintly.
	var spine := ArrayMesh.new()
	MeshKit.tube(spine, PackedVector3Array([Vector3.ZERO, Vector3(0.45, 0.0, 0.0), Vector3(0.75, 0.0, 0.0),
		Vector3(1.0, 0.0, 0.0)]), PackedFloat32Array([1.0, 0.6, 0.35, 0.05]), 5)
	spine = MeshKit.painted(spine, func(v: Vector3) -> Color:
		return Color(0.5 * smoothstep(0.7, 1.0, v.x), 0.15, 0.0, 1.0 if v.x < 0.6 else 0.0))
	var golden := PI * (3.0 - sqrt(5.0))
	var eye := BodyKit.surface(CALM, EYE_X, EYE_A)
	for i in SPINES:
		var u := (i + 0.5) / SPINES
		var a := fposmod(i * golden, TAU)
		var xc := lerpf(-0.4, 0.6, u)
		var at_calm := BodyKit.surface(CALM, xc, a)
		if Vector3(at_calm.x, at_calm.y, absf(at_calm.z)).distance_to(eye) < 0.16:
			continue
		var x := xc if not swollen else lerpf(-0.92, 0.55, u)
		var at := BodyKit.surface(stations, x, a)
		var n := _normal(stations, x, a)
		var dir: Vector3
		var length: float
		var width := 0.03
		if swollen:
			dir = (n - Vector3(0.12, 0.0, 0.0)).normalized()
			length = 0.34 * lerpf(1.0, 0.7, smoothstep(0.3, 0.55, x))
		else:
			# Lying flat, pointing back, just raised off the skin.
			var back := (BodyKit.surface(stations, x - 0.02, a) - BodyKit.surface(stations, x + 0.02, a)).normalized()
			dir = (back + n * 0.12).normalized()
			length = 0.11
			width = 0.018
		var side := dir.cross(n if absf(dir.dot(n)) < 0.95 else Vector3.UP).normalized()
		var up := side.cross(dir)
		var basis := Basis(dir * length, up * width, side * width)
		parts.append([spine, Transform3D(basis, at - n * 0.01), xc])
	# The soft fins on its back and belly, set far back, and the tail fan.
	for up: float in [1.0, -1.0]:
		var x := -0.36 if not swollen else -0.86
		var a := 0.0 if up > 0.0 else PI
		var at := BodyKit.surface(stations, x, a)
		var slope := BodyKit.surface(stations, x + 0.02, a) - BodyKit.surface(stations, x - 0.02, a)
		var tilt := atan2(slope.y, slope.x)
		var roots := PackedVector2Array()
		var tips := PackedVector2Array()
		for k in 6:
			var f := k / 5.0
			roots.append(Vector2(-0.16 * f, 0.0))
			tips.append(Vector2(-0.16 * f - 0.12, lerpf(0.2, 0.12, f) * up))
		parts.append([BodyKit.ray_fin(roots, tips, 0.12, 0.04, 0.008, 0.01, 0.0, 2, 4),
			Transform3D(Basis(Vector3.BACK, tilt), at - Vector3(0.0, 0.02 * up, 0.0)), x - 0.08])
	var tail_x: float = x0 + 0.06
	var roots := PackedVector2Array()
	var tips := PackedVector2Array()
	for k in 7:
		var f := k / 6.0
		roots.append(Vector2(0.0, lerpf(0.05, -0.05, f)))
		var ang := lerpf(0.7, -0.7, f)
		tips.append(Vector2(-cos(ang), sin(ang)) * 0.26)
	parts.append([BodyKit.ray_fin(roots, tips, 0.1, 0.04, 0.008, 0.01, 0.0, 2, 4),
		Transform3D(Basis(), Vector3(tail_x, BodyKit.at(stations, tail_x, 4), 0.0)), tail_x])
	# Pectorals, behind the eyes.
	var pec := BodyKit.ray_fin(PackedVector2Array([Vector2(0.0, 0.05), Vector2(0.0, 0.0), Vector2(0.0, -0.05)]),
		PackedVector2Array([Vector2(-0.16, 0.1), Vector2(-0.19, 0.0), Vector2(-0.15, -0.09)]), 0.1, 0.04, 0.007,
		0.01, 0.0, 2, 4)
	for sgn: float in [1.0, -1.0]:
		var x := 0.3 if not swollen else 0.26
		var at := BodyKit.surface(stations, x, PI * 0.58)
		at.z *= sgn
		parts.append([pec, Transform3D(Basis(Vector3.UP, -0.5 * sgn) * Basis(Vector3.RIGHT, sgn * 1.2), at), x])
	# The beak's upper half and the dark lips round it.
	var beak := MeshKit.transformed(MeshKit.ball(1.0, 0.0, 10, 6), Transform3D(
		Basis().scaled(Vector3(0.05, 0.03, 0.065)), Vector3(0.74, -0.025, 0.0)))
	parts.append([BodyKit.enamel(beak), Transform3D.IDENTITY, 0.72])
	return BodyKit.merged(parts)


func is_hostile() -> bool:
	return state == State.PUFFED


func think() -> void:
	match state:
		State.CALM:
			if _startled():
				puff()
			elif pos.distance_to(_target) < 1.5:
				_target = wander_point(_home, 9.0)
		State.PUFFED:
			_timer -= THINK_INTERVAL
			if _timer <= 0.0:
				if _startled():
					_timer = 1.5
				else:
					state = State.CALM
					radius = CALM_RADIUS


func _startled() -> bool:
	var sub := level.player
	if sub and sub.alive:
		var d := pos.distance_to(sub.pos)
		if d < STARTLE_RANGE + sub.noise_radius * 0.4 and (sub.noise_radius > STARTLE_NOISE or d < radius + 2.6):
			return true
	if level.loudest_noise_at(pos, hearing, self) != null:
		return true
	for e in level.targets_in_radius(pos, 3.0):
		if e != self and e is Creature and e.vel.length() > 7.0:
			return true
	return false


## Swells up into a ball of spines.
func puff() -> void:
	if state == State.PUFFED:
		_timer = PUFF_TIME
		return
	state = State.PUFFED
	_timer = PUFF_TIME
	radius = PUFFED_RADIUS
	Audio.play_at(&"puffer_puff", pos, -2.0)
	Fx.bubble_burst(level, pos, 12, 0.6)


func behave(delta: float) -> void:
	_t += delta
	_spike_cooldown = maxf(_spike_cooldown - delta, 0.0)
	match state:
		State.CALM:
			# Curious: near the sub it hovers, sculling, and keeps its eyes on
			# it (backing or sidling as it drifts); otherwise it wanders.
			var sub := level.player
			var watching := sub != null and sub.alive and pos.distance_to(sub.pos) < 9.0
			seek(_target, 0.7 if watching else 1.5, 1.2, delta)
			lock_facing = watching
			if watching:
				var look := (sub.pos - pos).normalized()
				_turn_towards(look.rotated(sin(_t * 0.8) * 0.15), 3.0, delta)
		State.PUFFED:
			# Swollen with water it can barely swim; it bobs where it is.
			lock_facing = true
			vel = vel.lerp(Vector2(0.0, 0.3), 1.0 - exp(-2.0 * delta))
			if _spike_cooldown <= 0.0:
				_spike_creatures()


## Swollen spines hurt any creature pressed against them.
func _spike_creatures() -> void:
	for e in level.targets_in_radius(pos, radius + 0.3):
		var c := e as Creature
		if c and c != self and not c is Puffer:
			c.take_damage(SPINE_DAMAGE, pos, &"spines")
			_spike_cooldown = 0.5


func _update_visuals(delta: float) -> void:
	# Swells fast, wobbling past full and back; sags back slowly.
	var target := 1.0 if state == State.PUFFED else 0.0
	var w := 15.0 if target > _inflation else 3.0
	var damping := 0.45 if target > _inflation else 0.8
	_inflation_v += (w * w * (target - _inflation) - 2.0 * damping * w * _inflation_v) * delta
	_inflation += _inflation_v * delta
	if _inflation < 0.0 or _inflation > 1.3:
		_inflation = clampf(_inflation, 0.0, 1.3)
		_inflation_v = 0.0
	# Gulping water as it swells; calm, its beak works now and then.
	var want := 0.0
	if state == State.PUFFED and _inflation < 0.95:
		want = 0.55 * absf(sin(_t * 26.0))
	elif state == State.CALM:
		want = 0.25 * maxf(sin(_t * 1.7), 0.0) ** 3.0
	_gape = lerpf(_gape, want, 1.0 - exp(-30.0 * delta))
	var k := clampf(_inflation, 0.0, 1.0)
	for i in mini(_eye_calm.size(), 2):
		var r: Array = _riders[_riders.size() - 2 + i]
		r[1] = _eye_calm[i].interpolate_with(_eye_puffed[i], k)
	super._update_visuals(delta)
	_body.set_instance_shader_parameter(&"puff", _inflation)
	_jaw.rotation.z = -_gape
	# Swollen, it tumbles a little, helpless.
	if _inflation > 0.01:
		model.basis = model.basis * Basis(Vector3.BACK, sin(_t * 0.9) * 0.25 * k) \
			* Basis(Vector3.RIGHT, sin(_t * 0.7 + 1.0) * 0.2 * k)


## Swollen, it can hardly beat its tail; its fins beat frantically instead
## (their flutter runs with the swim clock).
func _update_stroke(delta: float) -> void:
	super._update_stroke(delta)
	var k := clampf(_inflation, 0.0, 1.0)
	_swim_power = lerpf(_swim_power, 0.12, k)
	_swim_clock += delta * 1.6 * k


func on_touch_player(sub: Submarine) -> void:
	if state == State.PUFFED:
		sub.take_damage(SPINE_DAMAGE, pos, self)
	else:
		puff()


func on_damaged(_amount: float, _from: Vector2) -> void:
	if alive:
		puff()


func on_harpoon_hit(harpoon: Node, damage: float) -> HarpoonReaction:
	if state == State.PUFFED:
		take_damage(max_hp * 3.0, level.player.pos if level.player else pos, &"harpoon")
		return HarpoonReaction.IGNORE
	return super.on_harpoon_hit(harpoon, damage)


func die() -> void:
	if not alive or _dying:
		return
	_dying = true
	if state == State.PUFFED:
		_spine_nova()
	super.die()


## Bursting while swollen sprays spines at everything close by.
func _spine_nova() -> void:
	Audio.play_at(&"puffer_burst", pos, 0.0)
	Fx.shockwave(level, pos, NOVA_RADIUS, Color(0.5, 0.45, 0.3), 0.35)
	Fx.rubble(level, pos, _spine_mesh, _spine_mat, 10)
	level.emit_noise(pos, 12.0, self)
	for e in level.targets_in_radius(pos, NOVA_RADIUS):
		var c := e as Creature
		if c and c != self:
			c.take_damage(NOVA_DAMAGE, pos, &"spines")
	var sub := level.player
	if sub and sub.alive and sub.pos.distance_to(pos) < NOVA_RADIUS * 0.7:
		sub.take_damage(SPINE_DAMAGE * 0.7, pos, self)
