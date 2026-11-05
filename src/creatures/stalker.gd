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
const JAW_HINGE := Vector3(1.95, -0.4, 0.0)
const JAW_LENGTH := 1.5
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
		m.set_shader_parameter(&"swim_amp", 0.3)
		m.set_shader_parameter(&"swim_freq", 3.2)
		m.set_shader_parameter(&"swim_wave", 0.9)
		m.set_shader_parameter(&"bend_pivot", 0.4)
		m.set_shader_parameter(&"anchored", true)
		m.set_shader_parameter(&"flutter_amp", 0.07)
		m.set_shader_parameter(&"flutter_freq", 7.0)
		m.set_shader_parameter(&"scale_size", 0.17)
		m.set_shader_parameter(&"scale_depth", 0.24)
		m.set_shader_parameter(&"scale_shade", 0.22)
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
	# The dorsal sail: a membrane on raked spines, their tips glowing.
	var base := PackedVector2Array()
	var edge := PackedVector2Array()
	for i in 9:
		var f := i / 8.0
		var x := lerpf(1.55, -1.9, f)
		var top := BodyKit.at(BODY, x, 2) + BodyKit.at(BODY, x, 4)
		base.append(Vector2(x, top - 0.12))
		var h := lerpf(0.5, 1.25, sin(PI * pow(f, 0.8))) * (1.0 - f * 0.25)
		edge.append(Vector2(x - 0.55 - h * 0.35, top + h))
	parts.append([BodyKit.membrane(base, edge, 0.05, 8, 0.0, 6)])
	for i in 9:
		var tip := edge[i] + (edge[i] - base[i]).normalized() * 0.18
		parts.append([MeshKit.spike(0.05, base[i].distance_to(tip), 0.8, 5),
			Transform3D(Basis(Vector3.BACK, (tip - base[i]).angle()), Vector3(base[i].x, base[i].y, 0.0)), base[i].x])
	# A deeply forked tail.
	var tb := PackedVector2Array()
	var te := PackedVector2Array()
	for i in 9:
		var f := i / 8.0
		tb.append(Vector2(-3.25 + absf(f - 0.5) * 0.25, lerpf(0.26, -0.24, f)))
		var lobe := absf(f - 0.5) * 2.0
		te.append(Vector2(lerpf(-4.05, -5.15, pow(lobe, 0.7)), lerpf(1.75, -1.6, f) * lerpf(0.35, 1.0, lobe)))
	parts.append([BodyKit.membrane(tb, te, 0.06, 9, 0.12, 7)])
	# Long swept pectorals, and small pelvic and anal fins.
	var pb := PackedVector2Array([Vector2(1.45, 0.0), Vector2(1.2, 0.02), Vector2(0.95, 0.04), Vector2(0.7, 0.05)])
	var pe := PackedVector2Array([Vector2(0.75, -0.35), Vector2(0.0, -0.62), Vector2(-0.7, -0.75), Vector2(-1.15,
		-0.6)])
	var pec := BodyKit.membrane(pb, pe, 0.05, 5, 0.0, 6)
	for sgn: float in [1.0, -1.0]:
		parts.append([pec, Transform3D(Basis(Vector3.RIGHT, sgn * 1.05), Vector3(0.15, -0.3, 0.5 * sgn))])
	var vb := PackedVector2Array([Vector2(-0.4, 0.0), Vector2(-0.7, 0.0), Vector2(-1.0, 0.0)])
	var ve := PackedVector2Array([Vector2(-0.75, -0.45), Vector2(-1.05, -0.55), Vector2(-1.25, -0.4)])
	for sgn: float in [1.0, -1.0]:
		parts.append([BodyKit.membrane(vb, ve, 0.04, 3, 0.0, 4), Transform3D(Basis(Vector3.RIGHT, sgn * 0.5),
			Vector3(0.0, -0.78, 0.25 * sgn))])
	var ab := PackedVector2Array([Vector2(-1.7, -0.5), Vector2(-2.1, -0.38), Vector2(-2.5, -0.26)])
	var ae := PackedVector2Array([Vector2(-2.05, -1.05), Vector2(-2.45, -0.9), Vector2(-2.75, -0.6)])
	parts.append([BodyKit.membrane(ab, ae, 0.04, 4, 0.0, 4)])
	# The upper teeth, fixed in the skull.
	for sgn: float in [1.0, -1.0]:
		for t: Array in BodyKit.teeth_row(Vector3(2.35, -0.36, 0.3 * sgn), Vector3(3.32, -0.16, 0.08 * sgn), 7,
				0.36, Vector3.DOWN, 3 if sgn > 0.0 else 4):
			parts.append([BodyKit.enamel(t[0]), t[1], (t[1] as Transform3D).origin.x])
	add_visual(BodyKit.merged(parts), mat)
	# The lower jaw, hinged under the head, with its own teeth.
	var jaw_body := BodyKit.body([[0.0, 0.4, 0.14, 0.32, -0.04], [0.6, 0.36, 0.12, 0.27, -0.08],
		[1.1, 0.25, 0.08, 0.18, -0.05], [JAW_LENGTH, 0.07, 0.04, 0.05, 0.0]], 16, 16)
	var jaw_parts := [[jaw_body]]
	for sgn: float in [1.0, -1.0]:
		for t: Array in BodyKit.teeth_row(Vector3(0.45, 0.1, 0.26 * sgn), Vector3(1.38, 0.03, 0.07 * sgn), 6,
				0.3, Vector3.UP, 5 if sgn > 0.0 else 6):
			jaw_parts.append([BodyKit.enamel(t[0]), t[1], (t[1] as Transform3D).origin.x])
	_jaw = add_visual(BodyKit.merged(jaw_parts), mat, Transform3D(Basis(), JAW_HINGE))
	add_eyes(Vector3(2.82, 0.3, 0.4), 0.13, Color(1.0, 0.3, 0.15), 4.0)


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
	_jaw.rotation.z = lerpf(_jaw.rotation.z, -jaw_open, 1.0 - exp(-8.0 * delta))


func on_touch_player(sub: Submarine) -> void:
	if _bite_cooldown > 0.0:
		return
	_bite_cooldown = 1.6
	sub.take_damage(contact_damage, pos, self)
	Audio.play_at(&"stalker_bite", pos, 2.0)
	# Peel away after a bite so the player has a window to react.
	vel = (pos - sub.pos).normalized() * 6.0


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
