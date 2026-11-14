class_name Shoal
extends Creature
## A school of small glowing fish simulated as boids and drawn with one
## MultiMesh. The shoal is scannable but not targetable; it scatters from
## fast-moving submarines and lunging hunters, and flashes when startled.
## Lancers pick fish off it.
## The fish are lanternfish: blunt-headed and big-eyed, silver below and dark
## above, rows of lights down the belly in the colour of the zone. Each
## swims its own stroke, quickening and bending into its turns.

const FISH_SPEED := 4.0
const PANIC_SPEED := 9.0
## Model space: x from the tail to the snout. Stations as in
## [method BodyKit.body].
const BODY := [[-0.175, 0.008, 0.012, 0.012, 0.0], [-0.14, 0.013, 0.02, 0.019, 0.0],
	[-0.08, 0.025, 0.037, 0.035, 0.0], [0.0, 0.035, 0.051, 0.049, 0.0], [0.08, 0.039, 0.055, 0.051, 0.0],
	[0.14, 0.035, 0.049, 0.043, 0.0], [0.18, 0.026, 0.036, 0.029, -0.003], [0.205, 0.009, 0.015, 0.012, -0.006]]
const BODY_LENGTH := 0.45
const SWIM_FREQ := 14.0
## Tightest a fish curls into a turn (radians per metre of body).
const BEND_LIMIT := 2.3

var fish_pos := PackedVector2Array()
var fish_vel := PackedVector2Array()
## A big, harmless creature this school shelters under (a manta), or null.
var follow: Creature
## Waypoints a migrating school swims along (see the "migration" zone event),
## back and forth; with none it wanders round where it started.
var route := PackedVector2Array()
## The waypoint on [member route] it is making for.
var leg := 0
var _multimesh: MultiMesh
var _goal := Vector2.ZERO
var _panic := 0.0
var _home := Vector2.ZERO
## Where the last hunter lunged from (Vector2.INF if none).
var _scare_from := Vector2.INF
var _leg_step := 1
## Each fish's own stroke (cycles), its phase offset, bend, climb or dive,
## and how it is turned round (as Creature turns: through the depth, eased
## on a spring) with its sideways curl.
var _fish_clock := PackedFloat32Array()
var _fish_phase := PackedFloat32Array()
var _fish_bend := PackedFloat32Array()
var _fish_heading := PackedFloat32Array()
var _fish_yaw := PackedFloat32Array()
var _fish_yaw_v := PackedFloat32Array()
var _fish_side := PackedFloat32Array()
var _fish_curl := PackedFloat32Array()
var _age := 0.0


func setup() -> void:
	species = &"shoal"
	max_hp = 1.0
	radius = 3.0
	contact_damage = 0.0
	hostile = false
	salvage_drop = 0
	glow_color = level.biome.glow_color
	super.setup()
	targetable = false
	_home = pos
	_goal = wander_point(_home, 15.0)
	var count := level.rng.randi_range(14, 24)
	for i in count:
		fish_pos.append(pos + Vector2(level.rng.randf_range(-2.5, 2.5), level.rng.randf_range(-1.5, 1.5)))
		fish_vel.append(Vector2(level.rng.randf_range(-1, 1), level.rng.randf_range(-0.3, 0.3)))
	_multimesh.instance_count = count
	for i in count:
		_fish_phase.append(level.rng.randf())
		_fish_clock.append(0.0)
		_fish_bend.append(0.0)
		_fish_heading.append(atan2(fish_vel[i].y, absf(fish_vel[i].x)))
		_fish_side.append(-PI if fish_vel[i].x < 0.0 else 0.0)
		_fish_yaw.append(_fish_side[i])
		_fish_yaw_v.append(0.0)
		_fish_curl.append(0.0)
		_multimesh.set_instance_custom_data(i, Color(_fish_phase[i], 0, 0, 0))


func build_model() -> void:
	var glow := glow_color
	var mat := species_material(func(m: ShaderMaterial) -> void: configure_material(m, glow))
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_custom_data = true
	_multimesh.mesh = fish_mesh()
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _multimesh
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The MultiMesh is in world space; keep it out of the model transform.
	mmi.top_level = true
	add_child(mmi)
	visuals.append(mmi)


## The school's material, its lights in [param glow].
static func configure_material(m: ShaderMaterial, glow: Color) -> void:
	m.set_shader_parameter(&"back_color", Color(0.05, 0.1, 0.13))
	m.set_shader_parameter(&"belly_color", Color(0.78, 0.83, 0.88))
	m.set_shader_parameter(&"glow_color", glow)
	m.set_shader_parameter(&"glow_strength", 3.2)
	m.set_shader_parameter(&"metallic", 0.65)
	m.set_shader_parameter(&"roughness", 0.24)
	m.set_shader_parameter(&"rim_strength", 0.3)
	m.set_shader_parameter(&"body_length", BODY_LENGTH)
	m.set_shader_parameter(&"swim_amp", 0.042)
	m.set_shader_parameter(&"swim_freq", SWIM_FREQ)
	m.set_shader_parameter(&"swim_wave", 13.0)
	m.set_shader_parameter(&"swim_vertical", 0.0)
	m.set_shader_parameter(&"swim_roll", 0.06)
	m.set_shader_parameter(&"fin_lag", 0.3)
	m.set_shader_parameter(&"anchored", true)
	m.set_shader_parameter(&"scale_size", 0.014)
	m.set_shader_parameter(&"scale_depth", 0.2)
	m.set_shader_parameter(&"scale_shade", 0.22)
	m.set_shader_parameter(&"scale_head_x", 0.15)
	m.set_shader_parameter(&"fin_color", Color(0.06, 0.09, 0.12, 0.85))
	# The eyes and mouth are drawn as "enamel": black, glossy.
	m.set_shader_parameter(&"tooth_color", Color(0.01, 0.012, 0.015))


## One lanternfish, kept light (a school draws dozens): a blunt head with a
## big black eye ringed in silver and a wide mouth, rows of lights down the
## lower flank and belly and a gland on the tail, one dorsal and a little
## fleshy one behind it, an anal fin, a forked tail and small pectorals.
static func fish_mesh() -> ArrayMesh:
	# The lights' glow spills along the lower flanks, so from across a cavern
	# a school reads as a drift of glimmers.
	var parts := [[BodyKit.body(BODY, 26, 12, func(t: float, a: float, _p: Vector3) -> float:
		var band := 1.0 - smoothstep(0.12, 0.3, absf(cos(a) + 0.45))
		return 0.1 * band * smoothstep(0.1, 0.25, t) * (1.0 - smoothstep(0.8, 0.95, t)))]]
	var bead := MeshKit.ball(0.005, 1.0, 5, 3)
	for sgn: float in [1.0, -1.0]:
		for i in 10:
			var x := lerpf(0.15, -0.13, i / 9.0)
			var low := BodyKit.at(BODY, x, 3)
			parts.append([bead, Transform3D(Basis(), Vector3(x, -low * 0.62, BodyKit.at(BODY, x, 1) * 0.8 * sgn)), x])
		for i in 7:
			var x := lerpf(0.12, -0.08, i / 6.0)
			var low := BodyKit.at(BODY, x, 3)
			parts.append([bead, Transform3D(Basis(), Vector3(x, -low * 0.93, BodyKit.at(BODY, x, 1) * 0.38 * sgn)), x])
		parts.append([MeshKit.ball(0.0065, 1.0, 5, 3), Transform3D(Basis().scaled(Vector3(1.8, 1.0, 1.0)),
			Vector3(-0.15, 0.012, 0.009 * sgn)), -0.15])
		# The eye: a black globe with a silver ring, bulging from the head.
		var eye := Vector3(0.17, 0.011, 0.02 * sgn)
		parts.append([BodyKit.enamel(MeshKit.ball(0.02, 0.0, 10, 6)), Transform3D(Basis().scaled(
			Vector3(1.0, 1.0, 0.6)), eye), eye.x])
		var ring := MeshKit.painted(MeshKit.lathe(PackedVector2Array([Vector2(0.0, 0.0155), Vector2(0.5, 0.0193),
			Vector2(1.0, 0.0155)]), 0.0012, 14, 2), func(_v: Vector3) -> Color: return Color(0.0, 0.3, 0.0))
		parts.append([ring, Transform3D(Basis(Vector3.UP, -PI * 0.5 * sgn), eye + Vector3(0.0, 0.0, 0.0105 * sgn)),
			eye.x])
		# The mouth: a wide dark gape running back under the eye.
		var mouth := ArrayMesh.new()
		MeshKit.tube(mouth, PackedVector3Array([Vector3(0.207, -0.006, 0.005 * sgn), Vector3(0.188, -0.015, 0.018 * sgn),
			Vector3(0.158, -0.021, 0.026 * sgn), Vector3(0.142, -0.022, 0.03 * sgn)]),
			PackedFloat32Array([0.0026, 0.0024, 0.002, 0.0012]), 4)
		parts.append([BodyKit.enamel(mouth), Transform3D.IDENTITY, 0.18])
	var dorsal_roots := PackedVector2Array()
	var dorsal_tips := PackedVector2Array()
	var anal_roots := PackedVector2Array()
	var anal_tips := PackedVector2Array()
	for i in 6:
		var f := i / 5.0
		var x := lerpf(0.05, -0.03, f)
		var top := BodyKit.at(BODY, x, 2)
		dorsal_roots.append(Vector2(x, top - 0.004))
		dorsal_tips.append(Vector2(x - 0.022, top + lerpf(0.042, 0.016, f)))
		x = lerpf(-0.02, -0.1, f)
		var low := BodyKit.at(BODY, x, 3)
		anal_roots.append(Vector2(x, -low + 0.004))
		anal_tips.append(Vector2(x - 0.02, -low - lerpf(0.024, 0.01, f)))
	parts.append([BodyKit.ray_fin(dorsal_roots, dorsal_tips, 0.15, 0.06, 0.0016, 0.003, 0.0, 2, 3)])
	parts.append([BodyKit.ray_fin(anal_roots, anal_tips, 0.12, 0.06, 0.0014, 0.003, 0.0, 2, 3)])
	# The little fleshy fin behind the dorsal.
	parts.append([BodyKit.membrane(PackedVector2Array([Vector2(-0.09, 0.024), Vector2(-0.105, 0.021),
		Vector2(-0.12, 0.018)]), PackedVector2Array([Vector2(-0.097, 0.031), Vector2(-0.11, 0.032),
		Vector2(-0.122, 0.022)]), 0.004, 0, 0.0, 2)])
	var tail_roots := PackedVector2Array()
	var tail_tips := PackedVector2Array()
	for i in 9:
		var f := i / 8.0
		var lobe := absf(f - 0.5) * 2.0
		tail_roots.append(Vector2(-0.168 + lobe * 0.006, lerpf(0.011, -0.011, f)))
		tail_tips.append(Vector2(lerpf(-0.205, -0.262, pow(lobe, 0.8)), lerpf(0.062, -0.062, f) * lerpf(0.2, 1.0, lobe)))
	parts.append([BodyKit.ray_fin(tail_roots, tail_tips, 0.05, 0.03, 0.0018, 0.003, 0.0, 2, 3)])
	var pec := BodyKit.ray_fin(PackedVector2Array([Vector2(0.13, 0.0), Vector2(0.125, -0.002), Vector2(0.12, -0.004)]),
		PackedVector2Array([Vector2(0.08, 0.01), Vector2(0.07, -0.006), Vector2(0.078, -0.02)]), 0.1, 0.05,
		0.0012, 0.003, 0.0, 2, 3)
	for sgn: float in [1.0, -1.0]:
		parts.append([pec, Transform3D(Basis(Vector3.RIGHT, sgn * 1.0), Vector3(0.0, -0.02, 0.03 * sgn))])
	return BodyKit.merged(parts)


func think() -> void:
	if is_instance_valid(follow) and follow.alive:
		# Keep to the water just under it, wherever it glides.
		_home = follow.pos
		_goal = follow.pos + Vector2(0.0, -1.8)
	elif not route.is_empty():
		if pos.distance_to(route[leg]) < 4.0:
			if leg + _leg_step < 0 or leg + _leg_step >= route.size():
				_leg_step = -_leg_step
			leg = clampi(leg + _leg_step, 0, route.size() - 1)
		_home = route[leg]
		_goal = route[leg]
	elif pos.distance_to(_goal) < 3.0:
		_goal = wander_point(_home, 18.0)
	var sub := level.player
	if sub and sub.alive and sub.pos.distance_to(pos) < 9.0 and sub.vel.length() > 3.5:
		if _panic <= 0.0:
			Audio.play_at(&"shoal_scatter", pos, -8.0)
		_panic = 1.5


## Startles the school away from [param from], e.g. a hunter lunging at it.
func scare(from: Vector2) -> void:
	if _panic <= 0.0:
		Audio.play_at(&"shoal_scatter", pos, -8.0)
	_panic = 1.5
	_scare_from = from


## A hunter catches one fish; the school is gone when the last one is.
func lose_fish() -> void:
	if fish_pos.is_empty():
		return
	var i := level.rng.randi() % fish_pos.size()
	fish_pos.remove_at(i)
	fish_vel.remove_at(i)
	_fish_clock.remove_at(i)
	_fish_phase.remove_at(i)
	_fish_bend.remove_at(i)
	_fish_heading.remove_at(i)
	_fish_yaw.remove_at(i)
	_fish_yaw_v.remove_at(i)
	_fish_side.remove_at(i)
	_fish_curl.remove_at(i)
	_multimesh.visible_instance_count = fish_pos.size()
	if fish_pos.is_empty():
		despawn()


func behave(delta: float) -> void:
	_panic = maxf(_panic - delta, 0.0)
	_age += delta
	var n := fish_pos.size()
	var center := Vector2.ZERO
	for p in fish_pos:
		center += p
	center /= maxf(n, 1)
	pos = center
	var sub := level.player
	var threats := PackedVector2Array()
	if sub and sub.alive:
		threats.append(sub.pos)
	if _panic > 0.0 and _scare_from != Vector2.INF:
		threats.append(_scare_from)
	var field := level.field
	var max_speed := PANIC_SPEED if _panic > 0.0 else FISH_SPEED
	# A school sheltering under something keeps up with it, pulled harder the
	# further it has fallen behind.
	var goal_pull := 1.2
	if is_instance_valid(follow):
		goal_pull = clampf(center.distance_to(_goal) * 0.6, 1.2, 5.0)
	for i in n:
		var p := fish_pos[i]
		var v := fish_vel[i]
		var sep := Vector2.ZERO
		var align := Vector2.ZERO
		for j in n:
			if i == j:
				continue
			var d := p - fish_pos[j]
			var dl := d.length_squared()
			if dl < 0.8:
				sep += d / maxf(dl, 0.05)
			if dl < 6.0:
				align += fish_vel[j]
		var steer_v := (center - p) * 0.6 + sep * 1.2 + align.normalized() * 0.8 + (_goal - center).normalized() * goal_pull
		# Each fish wanders a little on its own, so the school never sets
		# into a lattice.
		var ph := _fish_phase[i] * TAU
		steer_v += Vector2(sin(_age * 1.3 + ph), cos(_age * 0.9 + ph * 1.7)) * 1.1
		for threat in threats:
			var away := p - threat
			var dist := away.length()
			if dist < 8.0:
				steer_v += away / maxf(dist, 0.1) * (8.0 - dist) * 2.5
		var wall := field.sample(p)
		if wall < 1.5:
			steer_v += field.normal(p) * (1.5 - wall) * 8.0
		v += steer_v * delta * 3.0
		v = v.limit_length(max_speed)
		p += v * delta
		if field.sample(p) < 0.3:
			p = field.resolve_circle(p, 0.3)
		fish_pos[i] = p
		fish_vel[i] = v
		var depth := sin(i * 1.7) * 0.8 + sin(_age * 0.5 + _fish_phase[i] * TAU) * 0.25
		_multimesh.set_instance_transform(i, Transform3D(_swim_fish(i, v, delta), Vector3(p.x, p.y, depth)))
	vel = Vector2.ZERO
	for v in visuals:
		v.set_instance_shader_parameter(&"glow_boost", 1.0 + _panic * 2.0)


## Hushed by the Choir's song passing (see [member Creature.hush_at]): every
## fish slows to a hover, turned down towards where the song rose, its
## lights flaring.
func _hushed(delta: float) -> void:
	_age += delta
	for i in fish_pos.size():
		var down := (hush_from - fish_pos[i]).normalized()
		var v := fish_vel[i].lerp(down * 0.35, 1.0 - exp(-8.0 * delta))
		fish_vel[i] = v
		fish_pos[i] += v * delta
		var depth := sin(i * 1.7) * 0.8 + sin(_age * 0.5 + _fish_phase[i] * TAU) * 0.25
		_multimesh.set_instance_transform(i, Transform3D(_swim_fish(i, v, delta),
			Vector3(fish_pos[i].x, fish_pos[i].y, depth)))
	# Their lights flare as the song takes them, and dim as it lets go.
	var held := (level.time - hush_at) / maxf(hush_end - hush_at, 0.01)
	for vis in visuals:
		vis.set_instance_shader_parameter(&"glow_boost", 1.0 + 4.0 * sin(clampf(held, 0.0, 1.0) * PI))
	_update_visuals(delta)


## Paces fish [param i]'s own stroke: faster the faster it goes, harder
## when the school bolts, its body curled into the turn it is swimming; and
## turns it, round through the depth when it turns back (see creature.gd).
## Returns how it is turned.
func _swim_fish(i: int, v: Vector2, delta: float) -> Basis:
	var speed := v.length()
	var elev := _fish_heading[i]
	if speed > 0.1:
		elev = atan2(v.y, absf(v.x))
		if v.x < -0.2 * speed:
			_fish_side[i] = -PI
		elif v.x > 0.2 * speed:
			_fish_side[i] = 0.0
	var climb := (elev - _fish_heading[i]) / maxf(delta, 0.001)
	_fish_heading[i] = elev
	var turned := _spring(_fish_yaw[i], _fish_yaw_v[i], _fish_side[i], 18.0, delta)
	_fish_yaw[i] = turned.x
	_fish_yaw_v[i] = turned.y
	var k := clampf(climb / maxf(speed, 1.0), -BEND_LIMIT, BEND_LIMIT)
	_fish_bend[i] = lerpf(_fish_bend[i], k, 1.0 - exp(-8.0 * delta))
	var ks := clampf(-turned.y / maxf(speed, 1.0), -BEND_LIMIT, BEND_LIMIT) * cos(elev)
	_fish_curl[i] = lerpf(_fish_curl[i], ks, 1.0 - exp(-10.0 * delta))
	var bolt := 1.0 if _panic > 0.0 else 0.0
	_fish_clock[i] = fposmod(_fish_clock[i] + delta * (0.6 + speed * 0.15) * (1.0 + 0.4 * bolt) * SWIM_FREQ / TAU, 1.0)
	var power := clampf(0.35 + speed / FISH_SPEED * 0.65, 0.35, 1.0) + 0.35 * bolt
	_multimesh.set_instance_custom_data(i, Color(_fish_clock[i] + _fish_phase[i], _fish_bend[i], power - 1.0,
		_fish_curl[i]))
	return Basis(Vector3.UP, _fish_yaw[i]) * Basis(Vector3.BACK, elev)


func _update_visuals(_delta: float) -> void:
	for v in visuals:
		v.set_instance_shader_parameter(&"marked", _marked / _mark_total if _marked > 0.0 else 0.0)
