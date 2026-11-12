class_name Lancer
extends Creature
## Needle-nosed hunter that strikes at sound. Investigates noise, winds up
## (its stripe flares as a tell) and dashes in a straight line; a dash that
## ends in rock leaves it stunned. Left alone it hunts shoals, and while it
## feeds it pays the sub no attention.

enum State { WANDER, INVESTIGATE, WINDUP, DASH, RECOVER }

const DASH_SPEED := 23.0
const WINDUP_TIME := 0.55
const DASH_TIME := 0.55
const HUNT_RANGE := 12.0
## Seconds a dash into rock leaves it reeling.
const BONK_STUN := 1.8
## Seconds spent swallowing a caught fish.
const FEED_TIME := 3.0
## The body's sections from tail to beak tip (see [method BodyKit.body]): a
## long torpedo drawn out into a needle beak.
const BODY: Array = [[-1.3, 0.03, 0.06, 0.06, 0.0], [-1.12, 0.06, 0.11, 0.1, 0.0], [-0.7, 0.13, 0.21, 0.19, 0.0],
	[-0.1, 0.165, 0.29, 0.26, 0.0], [0.45, 0.165, 0.29, 0.25, 0.0], [0.8, 0.135, 0.22, 0.17, -0.01],
	[1.02, 0.085, 0.13, 0.08, -0.03], [1.25, 0.04, 0.06, 0.035, -0.04], [1.46, 0.01, 0.015, 0.01, -0.045]]
const BODY_LENGTH := 2.76
## The lower jaw: its hinge (model space) and how far it gapes at rest.
const JAW_HINGE := Vector3(0.78, -0.1, 0.0)
const REST_GAPE := 0.05

var state := State.WANDER
var _timer := 0.0
var _target := Vector2.ZERO
var _dash_dir := Vector2.RIGHT
var _home := Vector2.ZERO
## The shoal it is lunging at, if the dash is a hunt rather than an attack.
var _prey: Shoal
var _hunt_cooldown := 0.0
var _jaw: MeshInstance3D
var _gape := 0.0


func setup() -> void:
	species = &"lancer"
	max_hp = 30.0
	radius = 0.7
	mass = 1.6
	contact_damage = 14.0
	hearing = 1.2
	salvage_drop = 4
	glow_color = Color(0.5, 0.9, 1.0)
	_turn_speed = 8.0
	flex = 1.0
	flex_pivot = 0.15
	body_span = BODY_LENGTH
	super.setup()
	_home = pos
	_target = wander_point(_home, 12.0)
	_hunt_cooldown = level.rng.randf_range(3.0, 10.0)


func build_model() -> void:
	var mat := species_material(func(m: ShaderMaterial) -> void:
		m.set_shader_parameter(&"back_color", Color(0.1, 0.16, 0.24))
		m.set_shader_parameter(&"belly_color", Color(0.66, 0.72, 0.76))
		m.set_shader_parameter(&"glow_color", Color(0.4, 0.9, 1.0))
		m.set_shader_parameter(&"glow_strength", 2.2)
		m.set_shader_parameter(&"metallic", 0.45)
		m.set_shader_parameter(&"roughness", 0.34)
		m.set_shader_parameter(&"rim_strength", 0.35)
		m.set_shader_parameter(&"body_length", BODY_LENGTH)
		m.set_shader_parameter(&"swim_amp", 0.18)
		m.set_shader_parameter(&"swim_head", 0.15)
		m.set_shader_parameter(&"swim_freq", 9.0)
		m.set_shader_parameter(&"swim_wave", 2.2)
		m.set_shader_parameter(&"swim_vertical", 0.0)
		m.set_shader_parameter(&"swim_roll", 0.05)
		m.set_shader_parameter(&"fin_lag", 0.35)
		m.set_shader_parameter(&"bend_pivot", 0.15)
		m.set_shader_parameter(&"anchored", true)
		m.set_shader_parameter(&"flutter_amp", 0.025)
		m.set_shader_parameter(&"flutter_freq", 11.0)
		m.set_shader_parameter(&"scale_size", 0.06)
		m.set_shader_parameter(&"scale_depth", 0.15)
		m.set_shader_parameter(&"scale_shade", 0.24)
		m.set_shader_parameter(&"scale_head_x", 0.86)
		m.set_shader_parameter(&"skin_pits", 0.002)
		m.set_shader_parameter(&"tooth_color", Color(0.86, 0.84, 0.78))
		m.set_shader_parameter(&"fin_color", Color(0.07, 0.1, 0.14, 0.9))
		m.set_shader_parameter(&"bars", 0.5)
		m.set_shader_parameter(&"bar_freq", 2.4))
	var parts := [[BodyKit.body(BODY, 56, 22)]]
	# The tell: a glowing stripe down each flank that flares as it winds up.
	for sgn: float in [1.0, -1.0]:
		var line := PackedVector3Array()
		var radii := PackedFloat32Array()
		for i in 15:
			var x := lerpf(-1.05, 0.82, i / 14.0)
			line.append(Vector3(x, BodyKit.at(BODY, x, 4) + 0.01, (BodyKit.at(BODY, x, 1) - 0.004) * sgn))
			radii.append(0.017 * sin(PI * clampf(i / 14.0 * 1.15, 0.05, 1.0)))
		var stripe := ArrayMesh.new()
		MeshKit.tube(stripe, line, radii, 6)
		parts.append([MeshKit.painted(stripe, func(_v: Vector3) -> Color: return Color(1.0, 0.0, 0.0))])
	# Two dorsals (the first spiny), an anal fin under the second, a deep
	# stiff fork of a tail, small pectorals and pelvics.
	var roots := PackedVector2Array()
	var tips := PackedVector2Array()
	for i in 5:
		var x := lerpf(0.3, -0.02, i / 4.0)
		var top := BodyKit.at(BODY, x, 2) + BodyKit.at(BODY, x, 4)
		roots.append(Vector2(x, top - 0.03))
		tips.append(Vector2(x - 0.14, top + lerpf(0.3, 0.12, i / 4.0)))
	parts.append([BodyKit.ray_fin(roots, tips, 0.22, 0.06, 0.012, 0.012, 0.0)])
	roots = PackedVector2Array()
	tips = PackedVector2Array()
	for i in 5:
		var x := lerpf(-0.42, -0.72, i / 4.0)
		var top := BodyKit.at(BODY, x, 2) + BodyKit.at(BODY, x, 4)
		roots.append(Vector2(x, top - 0.03))
		tips.append(Vector2(x - 0.16, top + lerpf(0.24, 0.09, i / 4.0)))
	parts.append([BodyKit.ray_fin(roots, tips, 0.08, 0.02, 0.01, 0.012)])
	roots = PackedVector2Array()
	tips = PackedVector2Array()
	for i in 5:
		var x := lerpf(-0.4, -0.72, i / 4.0)
		var low := BodyKit.at(BODY, x, 4) - BodyKit.at(BODY, x, 3)
		roots.append(Vector2(x, low + 0.03))
		tips.append(Vector2(x - 0.16, low - lerpf(0.2, 0.08, i / 4.0)))
	parts.append([BodyKit.ray_fin(roots, tips, 0.08, 0.02, 0.01, 0.012)])
	roots = PackedVector2Array()
	tips = PackedVector2Array()
	for i in 9:
		var f := i / 8.0
		var lobe := absf(f - 0.5) * 2.0
		roots.append(Vector2(-1.22 + lobe * 0.04, lerpf(0.06, -0.06, f)))
		tips.append(Vector2(lerpf(-1.42, -1.8, pow(lobe, 0.8)), lerpf(0.5, -0.47, f) * lerpf(0.15, 1.0, lobe)))
	parts.append([BodyKit.ray_fin(roots, tips, 0.04, 0.02, 0.014, 0.014, 0.35)])
	var pec := BodyKit.ray_fin(PackedVector2Array([Vector2(0.72, 0.0), Vector2(0.67, 0.01), Vector2(0.62, 0.02),
		Vector2(0.57, 0.02)]), PackedVector2Array([Vector2(0.52, -0.14), Vector2(0.4, -0.2), Vector2(0.3, -0.2),
		Vector2(0.24, -0.15)]), 0.1, 0.02, 0.008, 0.01)
	for sgn: float in [1.0, -1.0]:
		parts.append([pec, Transform3D(Basis(Vector3.RIGHT, sgn * 1.1), Vector3(0.0, -0.08, 0.13 * sgn))])
	var pelvic := BodyKit.ray_fin(PackedVector2Array([Vector2(0.1, 0.0), Vector2(0.04, 0.0), Vector2(-0.02, 0.0)]),
		PackedVector2Array([Vector2(-0.04, -0.12), Vector2(-0.1, -0.13), Vector2(-0.14, -0.1)]), 0.1, 0.02, 0.007, 0.01)
	for sgn: float in [1.0, -1.0]:
		parts.append([pelvic, Transform3D(Basis(Vector3.RIGHT, sgn * 0.6), Vector3(0.0, -0.24, 0.06 * sgn))])
	# Fine teeth along the upper beak.
	for sgn: float in [1.0, -1.0]:
		for t: Array in BodyKit.teeth_row(Vector3(0.9, -0.06, 0.055 * sgn), Vector3(1.38, -0.035, 0.012 * sgn), 16,
				0.04, Vector3(0.0, -1.0, 0.08 * sgn), 7 if sgn > 0.0 else 8, false):
			parts.append([BodyKit.enamel(t[0]), t[1], (t[1] as Transform3D).origin.x])
	add_visual(BodyKit.merged(parts), mat)
	# The lower jaw: a needle reaching just past the beak, gaping as it strikes.
	var jaw_parts := [[BodyKit.body([[0.0, 0.07, 0.03, 0.06, 0.0], [0.3, 0.05, 0.022, 0.04, 0.005],
		[0.6, 0.025, 0.013, 0.02, 0.01], [0.74, 0.006, 0.005, 0.006, 0.012]], 18, 12)]]
	for sgn: float in [1.0, -1.0]:
		for t: Array in BodyKit.teeth_row(Vector3(0.14, 0.02, 0.04 * sgn), Vector3(0.66, 0.016, 0.01 * sgn), 16,
				0.035, Vector3(0.0, 1.0, 0.08 * sgn), 9 if sgn > 0.0 else 10, false):
			jaw_parts.append([BodyKit.enamel(t[0]), t[1], (t[1] as Transform3D).origin.x])
	_jaw = add_visual(BodyKit.merged(jaw_parts), mat, Transform3D(Basis(Vector3.BACK, -REST_GAPE), JAW_HINGE))
	add_eyes(Vector3(0.83, 0.045, 0.095), 0.06, Color(0.85, 0.72, 0.42), 0.0, Eye.FISH)


func think() -> void:
	match state:
		State.WANDER, State.INVESTIGATE:
			if player_in_range(13.0) and (can_see_player(13.0) or level.player.noise_radius > 4.0):
				_begin_windup(level.player.pos)
				return
			_hunt_cooldown -= THINK_INTERVAL
			if state == State.WANDER and _hunt_cooldown <= 0.0:
				_hunt_cooldown = level.rng.randf_range(8.0, 14.0)
				var prey := _nearest_shoal()
				if prey:
					_begin_hunt(prey)
					return
			var heard := heard_noise()
			if heard != Vector2.INF:
				state = State.INVESTIGATE
				_target = heard
			elif state == State.WANDER and pos.distance_to(_target) < 2.0:
				_target = wander_point(_home, 14.0)


func _nearest_shoal() -> Shoal:
	for e in level.entities:
		var shoal := e as Shoal
		if shoal and shoal.alive and shoal.pos.distance_to(pos) < HUNT_RANGE \
				and level.field.line_of_sight(pos, shoal.pos):
			return shoal
	return null


## Winds up at a shoal. Unlike an attack this is not noticing the sub, so a
## hunting or feeding lancer can still be ambushed.
func _begin_hunt(prey: Shoal) -> void:
	_prey = prey
	state = State.WINDUP
	lock_facing = true
	_timer = WINDUP_TIME
	_target = prey.pos
	Audio.play_at(&"lancer_windup", pos, -6.0)


func _begin_windup(at: Vector2) -> void:
	_prey = null
	alert()
	state = State.WINDUP
	lock_facing = true
	_timer = WINDUP_TIME
	_target = at
	Audio.play_at(&"lancer_windup", pos, -2.0)


func behave(delta: float) -> void:
	match state:
		State.WANDER:
			seek(_target, 2.5, 2.0, delta)
		State.INVESTIGATE:
			seek(_target, 6.0, 3.0, delta)
			if pos.distance_to(_target) < 2.5:
				state = State.WANDER
				_target = wander_point(pos, 10.0)
		State.WINDUP:
			_timer -= delta
			# Track the target while winding up, coiling back a little.
			if is_instance_valid(_prey) and _prey.alive:
				_target = _prey.pos
			elif level.player and level.player.alive:
				_target = level.player.pos
			var to := (_target - pos).normalized()
			_turn_towards(to, 10.0, delta)
			vel = vel.lerp(-to * 0.7, 1.0 - exp(-4.0 * delta))
			_set_glow(1.0 + (1.0 - _timer / WINDUP_TIME) * 3.0)
			if _timer <= 0.0:
				state = State.DASH
				lock_facing = false
				_timer = DASH_TIME
				_dash_dir = to
				Audio.play_at(&"lancer_dash", pos, 0.0)
				level.emit_noise(pos, 10.0, self)
				if is_instance_valid(_prey):
					_prey.scare(pos)
		State.DASH:
			_timer -= delta
			vel = _dash_dir * DASH_SPEED
			if is_instance_valid(_prey) and _prey.alive and pos.distance_to(_prey.pos) < 2.5:
				_catch()
			elif level.field.sample(pos + _dash_dir * (radius + 0.6)) < 0.3:
				# Straight into the rock: it is left reeling.
				_prey = null
				state = State.RECOVER
				_timer = 1.3
				_set_glow(1.0)
				vel = -_dash_dir * 3.0
				stun(BONK_STUN)
				Audio.play_at(&"impact_rock", pos, -4.0, 0.05, 1.4)
				Fx.float_text(level, pos + Vector2(0.0, 1.5), "STUNNED", UiTheme.GOOD)
			elif _timer <= 0.0:
				_prey = null
				state = State.RECOVER
				_timer = 1.3
				_set_glow(1.0)
		State.RECOVER:
			_timer -= delta
			vel = vel.lerp(Vector2.ZERO, 1.0 - exp(-3.0 * delta))
			if _timer <= 0.0:
				state = State.WANDER
				_target = wander_point(pos, 10.0)


## Snaps a fish out of the shoal and drifts while it swallows.
func _catch() -> void:
	_prey.lose_fish()
	Fx.ichor(level, pos + _dash_dir, _prey.glow_color, 8)
	_prey = null
	state = State.RECOVER
	_timer = FEED_TIME
	_set_glow(1.0)


func on_touch_player(sub: Submarine) -> void:
	# Only a dash really hurts; brushing past a lancer just nips.
	sub.take_damage(contact_damage if state == State.DASH else 4.0, pos, self)
	if state == State.DASH:
		state = State.RECOVER
		_timer = 1.3
		vel = -_dash_dir * 6.0
		_set_glow(1.0)


func on_damaged(_amount: float, from: Vector2) -> void:
	if state == State.WANDER or state == State.INVESTIGATE:
		_begin_windup(from)


func _update_visuals(delta: float) -> void:
	super._update_visuals(delta)
	if _jaw:
		var want := 0.32 if state == State.WINDUP else (0.5 if state == State.DASH else 0.0)
		_gape = lerpf(_gape, want, 1.0 - exp(-10.0 * delta))
		_jaw.rotation.z = -(REST_GAPE + _gape)


func _set_glow(boost: float) -> void:
	for v in visuals:
		v.set_instance_shader_parameter(&"glow_boost", boost)
