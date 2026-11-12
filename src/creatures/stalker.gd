class_name Stalker
extends Creature
## Apex hunter. Patrols the zone, investigates noise, charges any lit sub it
## sees and is drawn off by flares. Retreats after taking heavy damage.

enum State { PATROL, INVESTIGATE, HUNT, DISTRACTED, FLEE }

const PATROL_SPEED := 3.5
const INVESTIGATE_SPEED := 7.0
const HUNT_SPEED := 11.0
const SIGHT := 24.0
## The body's sections from tail to snout: x, half width, height above and
## depth below the spine, spine height (see [method BodyKit.body]). Deep
## shoulders behind a heavy head, a long tapering tail.
const BODY: Array = [[-3.5, 0.05, 0.1, 0.1, 0.0], [-3.05, 0.16, 0.28, 0.26, 0.0], [-2.1, 0.38, 0.6, 0.52, 0.02],
	[-0.9, 0.56, 0.9, 0.76, 0.05], [0.35, 0.64, 1.0, 0.8, 0.08], [1.5, 0.6, 0.9, 0.7, 0.05],
	[2.35, 0.52, 0.74, 0.44, 0.0], [3.0, 0.38, 0.54, 0.3, -0.06], [3.55, 0.1, 0.16, 0.1, -0.14]]
## Where the lower jaw hinges (model space), and how long it is.
const JAW_HINGE := Vector3(1.95, -0.34, 0.0)
const JAW_LENGTH := 1.5
## How far the jaw hangs open at rest (radians).
const REST_GAPE := 0.13
const BODY_LENGTH := 7.0

var state := State.PATROL
var _target := Vector2.ZERO
var _timer := 0.0
var _bite_cooldown := 0.0
var _recent_damage := 0.0
var _flare: Flare
var _announced := false
var _jaw: MeshInstance3D
var _t := 0.0
## Where it wants to go: it turns its body that way and swims the way it
## points (see [method steer]).
var _want := Vector2.ZERO


## How close this Stalker is to attacking (0 calm .. 1 hunting), for the
## heartbeat that plays under it.
func menace() -> float:
	if not alive:
		return 0.0
	match state:
		State.HUNT:
			return 1.0
		State.INVESTIGATE:
			return 0.45
	return 0.0


func setup() -> void:
	species = &"stalker"
	max_hp = 230.0
	radius = 1.6
	reach = BODY_LENGTH * 0.5
	mass = 20.0
	contact_damage = 30.0
	hearing = 1.6
	salvage_drop = 30
	glow_color = Color(1.0, 0.25, 0.2)
	_turn_speed = 3.0
	flex = 1.0
	body_span = BODY_LENGTH
	super.setup()
	lock_facing = true
	_target = _patrol_point()


func build_model() -> void:
	var mat := species_material(func(m: ShaderMaterial) -> void:
		m.set_shader_parameter(&"back_color", Color(0.05, 0.06, 0.08))
		m.set_shader_parameter(&"belly_color", Color(0.2, 0.18, 0.21))
		m.set_shader_parameter(&"glow_color", Color(1.0, 0.22, 0.12))
		m.set_shader_parameter(&"glow_strength", 3.2)
		m.set_shader_parameter(&"glow_pulse", 0.25)
		m.set_shader_parameter(&"metallic", 0.15)
		m.set_shader_parameter(&"roughness", 0.52)
		m.set_shader_parameter(&"rim_strength", 0.35)
		m.set_shader_parameter(&"body_length", BODY_LENGTH)
		m.set_shader_parameter(&"swim_amp", 0.55)
		m.set_shader_parameter(&"swim_freq", 3.2)
		m.set_shader_parameter(&"swim_wave", 0.9)
		m.set_shader_parameter(&"swim_vertical", 0.0)
		m.set_shader_parameter(&"swim_roll", 0.05)
		m.set_shader_parameter(&"fin_lag", 0.35)
		m.set_shader_parameter(&"bend_pivot", 0.4)
		m.set_shader_parameter(&"anchored", true)
		m.set_shader_parameter(&"flutter_amp", 0.07)
		m.set_shader_parameter(&"flutter_freq", 7.0)
		m.set_shader_parameter(&"scale_size", 0.15)
		m.set_shader_parameter(&"scale_head_x", 2.05)
		m.set_shader_parameter(&"skin_pits", 0.006)
		m.set_shader_parameter(&"scale_depth", 0.15)
		m.set_shader_parameter(&"scale_shade", 0.28)
		m.set_shader_parameter(&"tooth_color", Color(0.78, 0.72, 0.62)))
	flex_pivot = 0.4
	var parts := [[BodyKit.body(BODY, 64, 28)]]
	# Two rows of photophore beads down each flank, and three glowing gill slits.
	var bead := MeshKit.ball(0.055, 1.0, 8, 5)
	for sgn: float in [1.0, -1.0]:
		for i in 15:
			var x := lerpf(-2.6, 1.75, i / 14.0)
			var w := BodyKit.at(BODY, x, 1)
			parts.append([bead, Transform3D(Basis(), Vector3(x, BodyKit.at(BODY, x, 4) + 0.05, (w + 0.01) * sgn))])
		for i in 9:
			var x := lerpf(-1.7, 1.2, i / 8.0)
			var low := BodyKit.at(BODY, x, 4) - BodyKit.at(BODY, x, 3) * 0.6
			parts.append([bead, Transform3D(Basis().scaled(Vector3.ONE * 0.8),
				Vector3(x, low, BodyKit.at(BODY, x, 1) * 0.84 * sgn))])
		for gx: float in [2.0, 2.15, 2.3]:
			var w := BodyKit.at(BODY, gx, 1)
			var slit := PackedVector3Array([Vector3(gx + 0.04, 0.3, w * 0.86 * sgn), Vector3(gx - 0.02, 0.0,
				(w + 0.015) * sgn), Vector3(gx + 0.02, -0.28, w * 0.86 * sgn)])
			var arc := ArrayMesh.new()
			MeshKit.tube(arc, slit, PackedFloat32Array([0.012, 0.022, 0.012]), 5)
			parts.append([MeshKit.painted(arc, func(_v: Vector3) -> Color: return Color(0.55, 0.0, 0.0))])
	# The dorsal sail: raked spines glowing towards their tips, the membrane
	# notched between them.
	var roots := PackedVector2Array()
	var tips := PackedVector2Array()
	for i in 9:
		var f := i / 8.0
		var x := lerpf(1.55, -1.9, f)
		var top := BodyKit.at(BODY, x, 2) + BodyKit.at(BODY, x, 4)
		var h := lerpf(0.55, 1.35, sin(PI * pow(f, 0.8))) * (1.0 - f * 0.25)
		roots.append(Vector2(x, top - 0.1))
		tips.append(Vector2(x - 0.5 - h * 0.4, top + h))
	parts.append([BodyKit.ray_fin(roots, tips, 0.24, 0.1, 0.045, 0.03, 0.85)])
	# A deeply forked tail, its rays fanning from the root.
	roots = PackedVector2Array()
	tips = PackedVector2Array()
	for i in 11:
		var f := i / 10.0
		var lobe := absf(f - 0.5) * 2.0
		roots.append(Vector2(-3.22 + lobe * 0.12, lerpf(0.24, -0.22, f)))
		tips.append(Vector2(lerpf(-4.1, -5.15, pow(lobe, 0.75)), lerpf(1.75, -1.6, f) * lerpf(0.3, 1.0, lobe)))
	parts.append([BodyKit.ray_fin(roots, tips, 0.05, 0.03, 0.04, 0.04, 0.45)])
	# Swept pectorals, pelvics and an anal fin: small fans of soft rays.
	var pec := BodyKit.ray_fin(_fan(Vector2(1.45, 0.02), Vector2(1.0, 0.06), 6),
		PackedVector2Array([Vector2(0.9, -0.42), Vector2(0.35, -0.74), Vector2(-0.2, -0.88), Vector2(-0.68, -0.84),
		Vector2(-1.02, -0.62), Vector2(-1.18, -0.34)]), 0.12, 0.02, 0.028, 0.03)
	for sgn: float in [1.0, -1.0]:
		parts.append([pec, Transform3D(Basis(Vector3.RIGHT, sgn * 1.12), Vector3(0.15, -0.3, 0.52 * sgn))])
	var pelvic := BodyKit.ray_fin(_fan(Vector2(-0.35, 0.0), Vector2(-0.6, 0.0), 4),
		PackedVector2Array([Vector2(-0.7, -0.42), Vector2(-0.95, -0.5), Vector2(-1.15, -0.45), Vector2(-1.25, -0.3)]),
		0.12, 0.02, 0.024, 0.025)
	for sgn: float in [1.0, -1.0]:
		parts.append([pelvic, Transform3D(Basis(Vector3.RIGHT, sgn * 0.55), Vector3(0.0, -0.76, 0.22 * sgn))])
	parts.append([BodyKit.ray_fin(_fan(Vector2(-1.7, -0.52), Vector2(-2.55, -0.26), 5),
		PackedVector2Array([Vector2(-2.0, -1.0), Vector2(-2.3, -0.98), Vector2(-2.55, -0.86), Vector2(-2.8, -0.68),
		Vector2(-2.98, -0.48)]), 0.15, 0.02, 0.026, 0.025)])
	# A heavy brow ridge over each eye.
	for sgn: float in [1.0, -1.0]:
		parts.append([MeshKit.ball(0.16, 0.0, 10, 6), Transform3D(Basis(Vector3.BACK, -0.25).scaled(Vector3(2.0, 0.55,
			0.7)), Vector3(2.72, 0.47, 0.33 * sgn))])
	# The upper teeth, fixed in the skull.
	for sgn: float in [1.0, -1.0]:
		# Along the outside of the lower jaw, an overbite of needles.
		for t: Array in BodyKit.teeth_row(Vector3(2.4, -0.3, 0.43 * sgn), Vector3(3.36, -0.12, 0.13 * sgn), 8,
				0.36, Vector3(0.0, -1.0, 0.06 * sgn), 3 if sgn > 0.0 else 4):
			parts.append([BodyKit.enamel(t[0]), t[1], (t[1] as Transform3D).origin.x])
	add_visual(BodyKit.merged(parts), mat)
	# The lower jaw, hinged under the head, with its own teeth.
	var jaw_body := BodyKit.body([[0.0, 0.4, 0.14, 0.32, -0.04], [0.6, 0.36, 0.12, 0.27, -0.08],
		[1.1, 0.25, 0.08, 0.18, -0.05], [JAW_LENGTH, 0.07, 0.04, 0.05, 0.0]], 16, 16)
	var jaw_parts := [[jaw_body]]
	for sgn: float in [1.0, -1.0]:
		for t: Array in BodyKit.teeth_row(Vector3(0.4, 0.1, 0.27 * sgn), Vector3(1.4, 0.03, 0.08 * sgn), 7,
				0.42, Vector3(0.0, 1.0, 0.12 * sgn), 5 if sgn > 0.0 else 6):
			jaw_parts.append([BodyKit.enamel(t[0]), t[1], (t[1] as Transform3D).origin.x])
	_jaw = add_visual(BodyKit.merged(jaw_parts), mat, Transform3D(Basis(Vector3.BACK, -REST_GAPE), JAW_HINGE))
	add_eyes(Vector3(2.8, 0.3, 0.39), 0.14, Color(1.0, 0.2, 0.06), 3.0, Eye.HUNTER)


## [param count] fin ray roots evenly along a fin's base from [param a] to [param b].
static func _fan(a: Vector2, b: Vector2, count: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in count:
		out.append(a.lerp(b, i / maxf(count - 1.0, 1.0)))
	return out


func _patrol_point() -> Vector2:
	var p := level.layout.random_open_point(level.rng, 4.0)
	return p if p != Vector2.INF else pos


func think() -> void:
	_recent_damage = maxf(_recent_damage - 10.0 * THINK_INTERVAL, 0.0)
	if state == State.FLEE:
		return
	var sub := level.player
	if sub and sub.alive and (can_see_player(SIGHT) or player_in_range(6.0)):
		if state != State.HUNT:
			alert()
			state = State.HUNT
			_timer = 6.0
			Audio.play_at(&"stalker_roar", pos, 4.0)
			Events.shake_requested.emit(0.35)
			if not _announced:
				_announced = true
				Events.toast.emit("Something huge is hunting you. Kill the lamp, or throw a flare.", UiTheme.DANGER)
		else:
			_timer = 6.0
		_target = sub.pos
		return
	var flare := nearest_flare()
	if flare and flare.lure_strength(pos) > 0.15:
		state = State.DISTRACTED
		_flare = flare
		return
	var heard := heard_noise()
	if heard != Vector2.INF and state != State.HUNT:
		state = State.INVESTIGATE
		_target = heard
		_timer = 8.0


func behave(delta: float) -> void:
	_t += delta
	_bite_cooldown = maxf(_bite_cooldown - delta, 0.0)
	var jaw_open := 0.05
	match state:
		State.PATROL:
			seek(_target, PATROL_SPEED, 1.2, delta)
			if pos.distance_to(_target) < 4.0:
				_target = _patrol_point()
		State.INVESTIGATE:
			seek(_target, INVESTIGATE_SPEED, 1.8, delta)
			_timer -= delta
			if pos.distance_to(_target) < 4.0 or _timer <= 0.0:
				state = State.PATROL
				_target = _patrol_point()
		State.HUNT:
			_timer -= delta
			var sub := level.player
			if sub and sub.alive:
				var lead := sub.pos + sub.vel * 0.4
				seek(lead, HUNT_SPEED, 2.2, delta)
				jaw_open = 0.45 if pos.distance_to(sub.pos) < 8.0 else 0.15
			if _timer <= 0.0:
				state = State.INVESTIGATE
				_target = sub.pos if sub else pos
				_timer = 6.0
		State.DISTRACTED:
			if _flare == null or not is_instance_valid(_flare) or not _flare.alive:
				state = State.PATROL
				_target = _patrol_point()
			else:
				var orbit := _flare.pos + Vector2(cos(_t * 0.8), sin(_t * 0.8)) * 6.0
				seek(orbit, INVESTIGATE_SPEED, 1.6, delta)
		State.FLEE:
			_timer -= delta
			var sub := level.player
			var away := (pos - sub.pos).normalized() if sub else Vector2.UP
			steer(away * HUNT_SPEED, 2.0, delta)
			if _timer <= 0.0:
				state = State.PATROL
				_target = _patrol_point()
	# It turns at its own pace towards where it wants to go.
	if _want.length_squared() > 0.04:
		_turn_towards(_want.normalized(), _turn_speed, delta)
	# Even at rest the mouth hangs a little open, the teeth showing.
	_jaw.rotation.z = lerpf(_jaw.rotation.z, -(jaw_open + REST_GAPE), 1.0 - exp(-8.0 * delta))


func on_touch_player(sub: Submarine) -> void:
	if _bite_cooldown > 0.0:
		return
	_bite_cooldown = 1.6
	sub.take_damage(contact_damage, pos, self)
	Audio.play_at(&"stalker_bite", pos, 2.0)
	# Pushes off after a bite (and has to come round again), so the player
	# has a window to react.
	vel = (pos - sub.pos).normalized() * 3.0


## A beast this size swims the way it points: wanting to go another way, it
## turns its body first, and drives through the water only as far as its
## body points that way (barely at all mid-turn, as it swings round through
## the depth); its fins steer it a little whatever way it points.
func steer(desired: Vector2, agility: float, delta: float) -> void:
	desired += avoid_walls(desired) * maxf(desired.length(), 2.0)
	_want = desired
	var speed := desired.length()
	var b := model.global_basis.x.normalized() if model else Vector3(facing.x, facing.y, 0.0)
	# Seen side on, its body shortens as it turns towards the camera.
	var body := Vector2(b.x, b.y)
	var drive := Vector2.ZERO
	if speed > 0.001 and body.length() > 0.05:
		drive = body * maxf(body.normalized().dot(desired / speed), 0.0) * speed
	vel = vel.lerp(drive.lerp(desired, 0.2), 1.0 - exp(-agility * delta))


func on_damaged(amount: float, from: Vector2) -> void:
	_recent_damage += amount
	if _recent_damage > 70.0:
		state = State.FLEE
		_timer = 5.0
		_recent_damage = 0.0
		Audio.play_at(&"stalker_roar", pos, 0.0)
	elif state != State.HUNT and state != State.FLEE:
		# Struck, it knows where the blow came from: it hunts, not wonders.
		alert()
		state = State.HUNT
		_target = from
		_timer = 6.0


func on_pinged(origin: Vector2) -> void:
	if state == State.PATROL:
		state = State.INVESTIGATE
		_target = origin
		_timer = 8.0
