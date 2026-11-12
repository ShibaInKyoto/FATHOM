class_name Ironclad
extends Guardian
## The Ironclad: a colossal armoured isopod that rules the hottest lair in the
## Abyssal Vents and seals the way down. It crawls the lair floor towards
## whatever it hears (and, through the floor, feels the sub moving over), and
## rears up to crush anything that comes close; out of reach, it spits
## scalding water from the vents it has swallowed. Its plates turn harpoons
## and torpedoes alike - but not the vents in its lair: caught in an
## eruption, the shell cracks open, glowing, for a few seconds. Then it is
## tempered against the heat for a while. While it hunts it pays the vents
## no mind; left to patrol, it waits for a rumbling vent to blow over before
## crossing it. Lure it across a vent as it erupts, then strike while it burns.
## Its model is built by [IroncladModel]. It walks its seven pairs of legs in
## a ripple down each side, in time with its pace, the body bobbing a little
## with each step and chewing as it goes, feeling about with its long
## feelers; it turns round on the spot through the depth, rears up on its
## hind legs with its front legs pawing and its mandibles agape, and crushes
## down. Scalded, its shell splits open, the plates lifting over the
## blazing flesh beneath while it shudders and scrabbles; building up to
## spit, its plates heave and its chimneys flare. Asleep it lies low on
## splayed legs; dead it rolls onto its back, legs curling.

enum State { DORMANT, CRAWL, REAR, SLAM, SCALDED, SPIT, DEAD }

## Model scale.
const SIZE := 1.7
## Height of the body centre above the floor.
const RIDE := 2.2
## Share of a vent's own scald that gets through.
const VENT_ARMOR := 0.25
const REAR_TIME := 0.8
const SLAM_SPEED := 17.0
const SLAM_TIME := 0.55
const SLAM_DAMAGE := 28.0
const SLAM_RANGE := 9.0
const SCALD_TIME := 1.0
## The highest step it climbs on its way to a sound.
const CLIMB := 6.0
## Seconds it stands listening where a sound led it before patrolling on.
const LINGER := 3.5
## Per phase (thirds of its health): crawl speed, seconds the shell stays
## cracked, rest after a slam.
const CRAWL_SPEED: Array[float] = [3.5, 4.5, 5.5]
const OPEN_TIME: Array[float] = [4.5, 3.8, 3.2]
const REST: Array[float] = [1.4, 1.0, 0.7]
## Feeling the sub move over the lair floor, it closes in at this share of its pace.
const STALK_PACE := 0.7
## Out of reach of a slam: seconds of warning, then scalding globs (one per
## phase reached), every so often.
const SPIT_WINDUP := 0.8
const SPIT_EVERY: Array[float] = [5.5, 4.5, 3.6]
const SPIT_SPEED := 10.0

var state := State.DORMANT
var phase := 0
## Seconds left with the shell cracked open by heat.
var exposed := 0.0
## +1 when heading right.
var heading := 1.0
var _timer := 0.0
var _cooldown := 0.0
var _goal_x := 0.0
var _chasing := false
var _linger := 0.0
var _stride := 0.0
var _slam_dir := Vector2.UP
var _t := 0.0
var _spit_cd := 3.0
var _was_exposed := false
var _taught_heat := false
var _shrink := 1.0
var _shell: MeshInstance3D
var _feelers: Array[MeshInstance3D] = []
var _jaws: Array[MeshInstance3D] = []
## The walk: the gait clock, how hard it walks, how far its legs fold in
## (out, below 0); how far it has sunk down on them, and how far its shell
## has split open.
var _gait := 0.0
var _gait_amp := 0.0
var _tuck := 0.0
var _crouch := 0.0
var _open := 0.0
## How far its head is raised (radians), and how fast; how far it has
## rolled over onto its back; how wide its mandibles are open; the kick of
## spitting.
var _lean := 0.0
var _lean_v := 0.0
var _over := 0.0
var _over_v := 0.0
var _jaw := 0.0
var _recoil := 0.0
## The lowest the body ever rides: just above the lair's lowest floor away
## from the fissure, so it bridges the drop instead of climbing down into it.
var _lowest := -INF


func setup() -> void:
	species = &"ironclad"
	title = "THE IRONCLAD"
	max_hp = 360.0
	radius = 2.0
	mass = 80.0
	contact_damage = 12.0
	salvage_drop = 75
	glow_color = Color(1.0, 0.45, 0.12)
	hearing = 2.0
	ambushable = false
	super.setup()
	active_radius = 1000.0
	lock_facing = true
	# On the lair floor, on whichever side of the fissure the floor is higher
	# (the flatter part of the bowl), facing the middle.
	var best := Vector2(lair_center.x, lair_center.y)
	for side: float in [-1.0, 1.0]:
		var x := lair_center.x + side * lair_radius.x * 0.5
		var fy := _floor_y(x, lair_center.y)
		if fy != -INF and (best.x == lair_center.x or fy + RIDE > best.y):
			best = Vector2(x, fy + RIDE)
	pos = level.field.resolve_circle(best, radius + 0.3)
	var lowest := INF
	for k in 13:
		var x := lair_center.x + (k / 6.0 - 1.0) * lair_radius.x * 0.85
		if absf(x - level.layout.exit.x) < 6.0:
			continue
		var fy := _floor_y(x, lair_center.y)
		if fy != -INF:
			lowest = minf(lowest, fy)
	_lowest = (lowest if lowest != INF else pos.y - RIDE) + RIDE - 0.5
	heading = -signf(pos.x - lair_center.x) if absf(pos.x - lair_center.x) > 0.5 else 1.0
	_goal_x = pos.x
	facing = Vector2(heading, 0.0)


func build_model() -> void:
	var mat := species_material(func(m: ShaderMaterial) -> void:
		m.set_shader_parameter(&"back_color", Color(0.1, 0.095, 0.09))
		m.set_shader_parameter(&"belly_color", Color(0.5, 0.45, 0.31))
		m.set_shader_parameter(&"glow_color", Color(1.0, 0.42, 0.1))
		m.set_shader_parameter(&"glow_strength", 1.6)
		m.set_shader_parameter(&"metallic", 0.35)
		m.set_shader_parameter(&"roughness", 0.42)
		m.set_shader_parameter(&"rim_strength", 0.3)
		m.set_shader_parameter(&"body_length", 4.7)
		m.set_shader_parameter(&"swim_amp", 0.0)
		m.set_shader_parameter(&"tooth_color", Color(0.05, 0.045, 0.04))
		m.set_shader_parameter(&"stride", 0.3)
		m.set_shader_parameter(&"leg_lift", 0.28)
		m.set_shader_parameter(&"paint_top", IroncladModel.SKIN)
		m.set_shader_parameter(&"paint_wrap", true)
		m.set_shader_parameter(&"paint_box", IroncladModel.PAINT_BOX)
		m.set_shader_parameter(&"paint_relief", 0.006)
		# The long feelers quiver towards their tips.
		m.set_shader_parameter(&"flutter_amp", 0.05)
		m.set_shader_parameter(&"flutter_freq", 2.2)
		m.set_shader_parameter(&"flutter_wave", 1.5))
	_shell = add_visual(IroncladModel.mesh(), mat)
	for sgn: float in [1.0, -1.0]:
		var side := Vector3(1.0, 1.0, sgn)
		_feelers.append(add_visual(IroncladModel.feeler(sgn), mat,
			Transform3D(Basis(), IroncladModel.FEELER_ROOT * side)))
		_jaws.append(add_visual(IroncladModel.mandible(sgn), mat, Transform3D(Basis(), IroncladModel.JAW_ROOT * side)))


func think() -> void:
	var sub := level.player
	match state:
		State.DORMANT:
			if sub and sub.alive and in_lair(sub.pos, 1.15):
				_awaken()
		State.CRAWL:
			if _cooldown <= 0.0 and sub and sub.alive and sub.pos.distance_to(pos) < SLAM_RANGE \
					and level.field.line_of_sight(pos, sub.pos):
				_rear(sub.pos)
				return
			if _spit_cd <= 0.0 and sub and sub.alive and in_lair(sub.pos, 1.1) \
					and level.field.line_of_sight(_spout(), sub.pos):
				_begin_spit()
				return
			var heard := _heard()
			if heard != Vector2.INF:
				_goal_x = clampf(heard.x, lair_center.x - lair_radius.x * 0.85, lair_center.x + lair_radius.x * 0.85)
				_chasing = true
			elif sub and sub.alive and in_lair(sub.pos, 1.1):
				# Quiet, but it feels the sub's wake through the floor.
				_goal_x = clampf(sub.pos.x, lair_center.x - lair_radius.x * 0.85, lair_center.x + lair_radius.x * 0.85)
				_chasing = true
			elif absf(_goal_x - pos.x) < 1.0:
				if _chasing:
					_chasing = false
					_linger = LINGER
				elif _linger <= 0.0:
					_goal_x = lair_center.x + level.rng.randf_range(-0.75, 0.75) * lair_radius.x


func behave(delta: float) -> void:
	_t += delta
	_timer -= delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	exposed = maxf(exposed - delta, 0.0)
	if _was_exposed and exposed <= 0.0:
		# The shell closes, tempered: the heat cannot crack it again for a while.
		raise_guard()
	_was_exposed = exposed > 0.0
	_linger = maxf(_linger - delta, 0.0)
	if state == State.CRAWL:
		_spit_cd -= delta
	match state:
		State.DORMANT:
			vel = Vector2.ZERO
		State.CRAWL:
			_crawl(delta)
		State.REAR:
			vel = vel.lerp(Vector2.ZERO, 1.0 - exp(-6.0 * delta))
			var sub := level.player
			if sub and sub.alive:
				_slam_dir = (sub.pos - pos).normalized()
			facing = facing.slerp(Vector2(heading, 0.0).lerp(_slam_dir, 0.6).normalized(), 1.0 - exp(-6.0 * delta))
			if _timer <= 0.0:
				_slam()
		State.SLAM:
			vel = _slam_dir * SLAM_SPEED
			if _timer <= 0.0:
				state = State.CRAWL
				_cooldown = REST[phase]
		State.SCALDED:
			vel = vel.lerp(Vector2.ZERO, 1.0 - exp(-5.0 * delta))
			if _timer <= 0.0:
				state = State.CRAWL
		State.SPIT:
			vel = vel.lerp(Vector2.ZERO, 1.0 - exp(-6.0 * delta))
			var target := level.player
			if target and target.alive:
				facing = facing.slerp(Vector2(heading, 0.0).lerp((target.pos - pos).normalized(), 0.5).normalized(),
					1.0 - exp(-5.0 * delta))
			if _timer <= 0.0:
				_spit()
		State.DEAD:
			vel = vel.lerp(Vector2(0.0, -1.0), 1.0 - exp(-1.0 * delta))
			_shrink = maxf(_timer / 3.0, 0.01)
			if _timer <= 0.0:
				despawn()


## Walks along the floor towards the goal, holding its height above the rock
## (and bridging the fissure in the middle of the lair). Left to patrol, it
## waits for a rumbling vent ahead to blow over.
func _crawl(delta: float) -> void:
	var dx := _goal_x - pos.x
	if absf(dx) > 0.5:
		heading = signf(dx)
	var speed := CRAWL_SPEED[phase] * clampf(absf(dx) / 2.0, 0.0, 1.0) * (1.0 if _heard() != Vector2.INF else STALK_PACE)
	if not _chasing and _vent_ahead():
		speed = 0.0
	# Rock ahead: climb it if there is water over it (a step, or the lip of
	# the fissure it has been knocked into), else stop there.
	var climb := 0.0
	while absf(dx) > 0.5 and climb < CLIMB and level.field.sample(pos + Vector2(heading * 3.4, climb)) < 1.0:
		climb += 0.5
	if climb >= CLIMB or climb > 0.0 and level.field.sample(pos + Vector2(0.0, climb)) < radius * 0.8:
		speed = 0.0
		_goal_x = pos.x
		climb = 0.0
	elif climb > 0.0:
		speed *= 0.4
	var fy := _floor_y(pos.x + heading * 1.5, pos.y)
	var want_y := maxf(fy + RIDE if fy != -INF and fy > pos.y - RIDE - 3.0 else pos.y, _lowest)
	if climb > 0.0:
		want_y = maxf(want_y, pos.y + climb + 0.5)
	else:
		# Carried up off the floor (a slam aimed upwards), it sinks back down
		# onto the floor under it - but never into the fissure, which it bridges.
		var under := _floor_y(pos.x, pos.y)
		var over_fissure := absf(pos.x - level.layout.exit.x) < 6.0
		if under != -INF and not over_fissure and under + RIDE >= _lowest and pos.y - under > RIDE + 3.0:
			want_y = under + RIDE
	vel.x = lerpf(vel.x, heading * speed, 1.0 - exp(-4.0 * delta))
	vel.y = lerpf(vel.y, clampf((want_y - pos.y) * 4.0, -8.0, 8.0), 1.0 - exp(-6.0 * delta))
	# Every stride shakes the floor; heard (and felt) across the lair.
	_stride += absf(vel.x) * delta
	if _stride > 2.2:
		_stride = 0.0
		Audio.play_at(&"plate_step", pos + Vector2(0.0, -RIDE), -4.0, 0.08)
	var slope := clampf((want_y - pos.y) * 0.25, -0.35, 0.35)
	var want := Vector2(heading, slope * heading).normalized()
	# Turning back, it turns round on the spot (see _turn_body), never
	# rearing up over the top.
	if want.x * facing.x < 0.0:
		facing.x = -facing.x
	facing = facing.slerp(want, 1.0 - exp(-5.0 * delta)).normalized()


## The loudest recent noise it can hear, or INF. The vents' roar is the
## sound of its own lair: it never goes looking for an eruption.
func _heard() -> Vector2:
	var best := Vector2.INF
	var best_margin := 0.0
	for n in level.noises:
		# A noise can outlive whatever made it.
		if n.source == self or is_instance_valid(n.source) and n.source is ThermalVent:
			continue
		var margin: float = n.radius * hearing - pos.distance_to(n.pos)
		if margin > best_margin:
			best_margin = margin
			best = n.pos
	return best


func _vent_ahead() -> bool:
	for e in level.entities:
		var v := e as ThermalVent
		if v and v.state != ThermalVent.State.DORMANT:
			var dx := v.pos.x - pos.x
			if signf(dx) == heading and absf(dx) < 5.0 and absf(v.pos.y - pos.y) < 6.0:
				return true
	return false


## The floor's height at [param x] below [param above] (plus a little), or
## -INF over the fissure.
func _floor_y(x: float, above: float) -> float:
	return MeridianStation.floor_below(level.field, Vector2(x, above + 2.0), lair_radius.y * 1.6)


func on_touch_player(sub: Submarine) -> void:
	if state == State.DEAD or state == State.DORMANT:
		return
	if state == State.SLAM:
		sub.take_damage(SLAM_DAMAGE, pos, self)
		sub.vel += _slam_dir * 10.0
		state = State.CRAWL
		_cooldown = REST[phase]
	else:
		sub.take_damage(contact_damage, pos, self)


func take_damage(amount: float, from: Vector2, kind: StringName = &"") -> void:
	if state == State.DEAD:
		return
	if state == State.DORMANT:
		_awaken()
	if kind == &"vent":
		if stun_guard > 0.0 and exposed <= 0.0:
			# Tempered: the heat rolls off it.
			deflect(from, "")
			return
		amount *= VENT_ARMOR
		_crack()
	elif exposed <= 0.0:
		deflect(from, "Its plates turn everything. Lure it into a vent's eruption to crack the shell.", 0.5)
		return
	super.take_damage(amount, from, kind)
	if kind == &"vent":
		# The heat shows in its blazing seams, not as a blow.
		_flash = minf(_flash, 0.2)
	var frac := hp / max_hp
	var want := 0 if frac > 0.66 else (1 if frac > 0.33 else 2)
	if alive and state != State.DEAD and want > phase:
		phase = want
		_enrage()


func die() -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	_timer = 3.0
	reward_defeat("The Ironclad's shell has gone cold.")


func is_hostile() -> bool:
	return state != State.DORMANT and state != State.DEAD


## A vent's heat splits the plates open.
func _crack() -> void:
	var fresh := exposed <= 0.0
	exposed = OPEN_TIME[phase]
	if fresh:
		state = State.SCALDED
		_timer = SCALD_TIME
		Audio.play_at(&"rock_shatter", pos, 2.0, 0.05, 0.7)
		Fx.sparks(level, pos + Vector2(0.0, 1.5))
		Events.shake_requested.emit(0.4)
		if not _taught_heat:
			_taught_heat = true
			Events.toast.emit("The heat cracked its shell - strike now!", UiTheme.GOOD)


func _update_visuals(delta: float) -> void:
	var speed := absf(vel.x) if state == State.CRAWL else vel.length()
	var amp := 0.0
	var pace := 1.0
	var tuck := 0.0
	var crouch := 0.0
	var open := 0.0
	var jaw := 0.0
	var glow := 0.45 + 0.12 * sin(_t * 1.5)
	match state:
		State.DORMANT:
			# Sunk low on splayed legs, the heat in its seams breathing slowly.
			crouch = 1.0
			tuck = -0.7
			glow = 0.3 + 0.12 * sin(_t * 0.8)
		State.CRAWL:
			amp = clampf(speed / 2.0, 0.0, 1.0)
			# A step for every 1.1 m or so it walks (as far as its feet
			# sweep), so its feet stay planted on the floor.
			pace = 0.4 + speed * 2.8
			jaw = 0.08 + 0.1 * maxf(sin(_t * 4.0), 0.0) * amp
		State.REAR:
			# Up on its hind legs, the front ones pawing, mandibles agape.
			amp = 0.8
			pace = 11.0
			tuck = -0.35
			jaw = 0.8
			glow = 1.4
		State.SLAM:
			amp = 0.3
			pace = 6.0
			tuck = -0.5
			jaw = 1.0
		State.SCALDED:
			# Scrabbling, sagging in the heat.
			amp = 0.6
			pace = 14.0
			crouch = 0.45
			tuck = -0.45
			jaw = 0.7
		State.SPIT:
			# The plates heave as the pressure builds.
			open = 0.16 + 0.1 * sin(_t * 14.0)
			crouch = 0.25
			tuck = -0.25
			glow = 1.8 + 0.6 * sin(_t * 18.0)
		State.DEAD:
			var left := clampf(_timer / 3.0, 0.0, 1.0)
			amp = 0.5 * left
			pace = 5.0
			tuck = 1.0
			jaw = 0.5
			glow = 0.5 * left
	if exposed > 0.0:
		open = maxf(open, 0.9 + 0.1 * sin(_t * 9.0))
		glow = 3.2 + 0.9 * sin(_t * 11.0)
	_gait += delta * pace
	var ease := 1.0 - exp(-6.0 * delta)
	_gait_amp = lerpf(_gait_amp, amp, ease)
	_tuck = lerpf(_tuck, tuck, ease)
	_crouch = lerpf(_crouch, crouch, 1.0 - exp(-3.0 * delta))
	_open = lerpf(_open, open, 1.0 - exp(-(10.0 if open > _open else 2.5) * delta))
	_jaw = lerpf(_jaw, jaw, 1.0 - exp(-8.0 * delta))
	_recoil = maxf(_recoil - delta * 0.6, 0.0)
	super._update_visuals(delta)
	var s := SIZE * _shrink
	model.basis = model.basis.scaled(Vector3.ONE * s)
	# Standing on the floor (RIDE below its middle), raised or lowered about
	# its hind feet (its front feet, head down) so they stay put; sunk on its
	# legs; bobbing with its steps; on its back, lying on its shell.
	var turned := Basis(Vector3.UP, _yaw)
	var pivot := Vector3(-1.5 if _lean > 0.0 else 1.6, IroncladModel.FLOOR, 0.0)
	var lift := (turned * pivot - turned * Basis(Vector3.BACK, _lean) * pivot) * s
	var y := -RIDE - IroncladModel.FLOOR * s - _crouch * 0.28 * s + sin(_gait * 2.0) * 0.02 * s * _gait_amp
	y += (1.0 - cos(_over)) * 0.12 * s
	var shake := sin(_t * 47.0) * 0.04 * s if state == State.SCALDED else 0.0
	model.position = Vector3(shake, y, 0.0) + lift
	for v in visuals:
		v.set_instance_shader_parameter(&"gait", _gait)
		v.set_instance_shader_parameter(&"gait_amp", _gait_amp)
		v.set_instance_shader_parameter(&"leg_tuck", _tuck)
		v.set_instance_shader_parameter(&"glow_boost", glow)
	_shell.set_instance_shader_parameter(&"puff", _open)
	_pose_feelers()
	for k in 2:
		var sgn := 1.0 if k == 0 else -1.0
		var chew := sin(_t * 9.0 + k * PI) * 0.05 * _gait_amp if state == State.CRAWL else 0.0
		_jaws[k].basis = Basis(Vector3.UP, -(_jaw * 0.45 + chew) * sgn)


## Its long feelers sweep about as it walks; raised and spread as it rears,
## laid back asleep, thrashing scalded, drooping dead.
func _pose_feelers() -> void:
	var raise := 0.06 + 0.06 * sin(_t * 1.7)
	var spread := 0.05 * sin(_t * 0.9)
	match state:
		State.DORMANT:
			raise = -0.08 + 0.03 * sin(_t * 0.6)
			spread = -0.1
		State.REAR, State.SLAM:
			raise = 0.3
			spread = 0.25
		State.SCALDED:
			raise = 0.15 + 0.2 * sin(_t * 13.0)
			spread = 0.2 * sin(_t * 9.0)
		State.SPIT:
			raise = 0.12
			spread = 0.15
		State.DEAD:
			raise = -0.3
			spread = 0.3
	for k in 2:
		var sgn := 1.0 if k == 0 else -1.0
		var own := sin(_t * 1.3 + k * 2.1) * 0.06
		_feelers[k].basis = Basis(Vector3.UP, (spread + own) * sgn) * Basis(Vector3.BACK, -(raise + own * 0.5))


## Faces its way along the floor: turning back, it turns round on the spot
## through the depth; its head rises and falls with the floor's slope, rears
## up and crushes down; dead, it rolls over onto its back.
func _turn_body(delta: float) -> void:
	if facing.x < -0.2:
		_yaw_target = -PI
	elif facing.x > 0.2:
		_yaw_target = 0.0
	var lean := _lean_target()
	var over := PI if state == State.DEAD else 0.0
	if is_nan(_elev) or delta <= 0.0:
		_elev = 0.0
		_yaw = _yaw_target
		_yaw_v = 0.0
		_lean = lean
		_lean_v = 0.0
		_over = over
		_over_v = 0.0
	else:
		var y := _spring(_yaw, _yaw_v, _yaw_target, 5.0, delta)
		_yaw = y.x
		_yaw_v = y.y
		var l := _spring(_lean, _lean_v, lean, 18.0 if state == State.SLAM else 7.0, delta)
		_lean = l.x
		_lean_v = l.y
		var o := _spring(_over, _over_v, over, 2.5, delta)
		_over = o.x
		_over_v = o.y
	model.basis = Basis(Vector3.UP, _yaw) * Basis(Vector3.BACK, _lean) * Basis(Vector3.RIGHT, _over)


## How far its head should be raised now.
func _lean_target() -> float:
	var elev := atan2(facing.y, absf(facing.x))
	match state:
		State.REAR:
			return clampf(elev * 0.5 + 0.3, 0.25, 0.65)
		State.SLAM:
			return clampf(atan2(_slam_dir.y, absf(_slam_dir.x)) - 0.3, -0.45, 0.7)
		State.SPIT:
			return clampf(elev * 0.5, -0.2, 0.45) + _recoil
		State.DEAD, State.DORMANT:
			return 0.0
	return clampf(elev, -0.45, 0.5) + _recoil


## Shown as a specimen (the codex): up on its legs, its shell shut.
func reveal() -> void:
	state = State.CRAWL
	_crouch = 0.0
	_tuck = 0.0
	_gait_amp = 0.0
	_elev = NAN
	_update_visuals(0.0)


func _awaken() -> void:
	if active:
		return
	state = State.CRAWL
	_cooldown = 1.5
	wake("Its plates turn everything. The vents do not.", 0.45, &"furnace")


func _rear(at: Vector2) -> void:
	state = State.REAR
	_timer = REAR_TIME * (1.0 - phase * 0.15)
	_slam_dir = (at - pos).normalized()
	alert()
	Audio.play_at(&"lancer_windup", pos, 3.0, 0.03, 0.45)


func _slam() -> void:
	state = State.SLAM
	_timer = SLAM_TIME
	Audio.play_at(&"lancer_dash", pos, 4.0, 0.03, 0.5)
	level.emit_noise(pos, 14.0, self)


## Where the scalding water leaves its shell: the mouth of its tallest
## chimney.
func _spout() -> Vector2:
	if model == null:
		return pos + Vector2(0.0, 1.4 * SIZE)
	var mouth := model.transform * IroncladModel.chimney_mouth(0)
	return pos + Vector2(mouth.x, mouth.y)


func _begin_spit() -> void:
	state = State.SPIT
	_timer = SPIT_WINDUP
	Audio.play_at(&"vent_rumble", pos, 2.0, 0.03, 1.3)
	Fx.silt(level, _spout(), 1.5, Color(1.0, 0.5, 0.2))


## Globs of scalding water, fanned out at the sub (one more per phase).
func _spit() -> void:
	state = State.CRAWL
	_spit_cd = SPIT_EVERY[phase]
	var sub := level.player
	if sub == null or not sub.alive:
		return
	var aim := (sub.pos - _spout()).normalized()
	_recoil = 0.18
	Audio.play_at(&"vent_erupt", pos, -2.0, 0.05, 1.5)
	Fx.silt(level, _spout(), 1.2, Color(1.0, 0.55, 0.25))
	for i in phase + 1:
		var glob := ScaldGlob.new()
		glob.pos = _spout()
		glob.vel = aim.rotated((i - phase * 0.5) * 0.18) * SPIT_SPEED
		glob.shooter = self
		level.add_entity(glob)


func _enrage() -> void:
	Audio.play_at(&"stalker_roar", pos, 4.0, 0.03, 0.45)
	Events.shake_requested.emit(0.6)
	# Its brood spills out from under the plates.
	for side: float in [-1.0, 1.0]:
		var p := level.field.resolve_circle(pos + Vector2(side * 2.5, -0.8), 0.6)
		var brood: Creature = LevelPopulator.SPECIES[&"isopod"].new()
		brood.pos = p
		# World +y is up: they land on the lair floor.
		brood.set(&"wall_normal", Vector2(0.0, 1.0))
		level.add_entity(brood)
