class_name Lamplighter
extends Guardian
## The Lamplighter: a matriarch angler the size of a whale, hanging in the
## dark of the Twilight Reef's exit chamber with only her lure showing. She
## sees light and nothing else. A lamp seen from afar draws a charge (her lure
## goes dark first); anything that drifts up to the lure is snapped up, and
## the lure itself pulls the sub in until a sonar ping breaks its spell. Her
## scales turn every blow, but a lamp held in her eyes up close, or a flare
## fed to her, dazzles her long enough to wound; then she shuts her eyes to
## light for a while. Wounded, she charges again and again, and learns to
## douse her lure and hunt in the dark, lighting it only to strike.

enum State { DORMANT, STALK, WINDUP, CHARGE, SNAP, FEED, DAZZLED, RECOVER, LURK, DEAD }

## Model scale.
const SIZE := 1.7
const SIGHT_RANGE := 36.0
## Seconds of seeing a lamp from afar before she commits to a charge.
const SPOT_TIME := 0.7
const WINDUP_TIME := 0.9
const CHARGE_TIME := 1.3
const CHARGE_DAMAGE := 28.0
## Anything this close to the lure is in reach of a snap.
const SNAP_REACH := 6.5
const SNAP_WINDUP := 0.45
const SNAP_TIME := 0.35
const SNAP_DAMAGE := 20.0
## A lamp held on her eyes from within this range dazzles her.
const DAZZLE_RANGE := 15.0
const PULL_RANGE := 20.0
## Seconds a ping frees the sub from the lure.
const TRANCE_BREAK := 4.0
## Per phase (thirds of her health).
const CHARGE_SPEED: Array[float] = [21.0, 24.0, 27.0]
const PULL: Array[float] = [2.6, 3.4, 4.2]
## Charges she follows a charge with, if she still sees light.
const FOLLOW_UPS: Array[int] = [0, 1, 2]
## Seconds between dark hunts (none before she is wounded).
const LURK_EVERY: Array[float] = [INF, 16.0, 11.0]
const LURK_SPEED := 7.0
const LURK_MAX := 6.0
## Seconds of her lure dark before she can strike out of it.
const LURK_STRIKE := 7.5
const DAZZLE_NEED: Array[float] = [0.9, 1.1, 1.3]
const DAZZLE_TIME: Array[float] = [4.2, 3.6, 3.0]
const LURE_COLOR := Color(0.55, 1.0, 0.92)

var state := State.DORMANT
var phase := 0
## Progress (seconds) of the lamp held on her eyes.
var dazzle := 0.0

var _timer := 0.0
var _cooldown := 0.0
var _charges_left := 0
var _lurk_in := INF
var _spot := 0.0
var _trance_free := 0.0
var _dir := Vector2.RIGHT
var _snapping := false
var _flare: Flare
var _orbit := 0.0
var _t := 0.0
var _jaw_open := 0.0
var _lure_k := 1.0
var _shrink := 1.0
var _taught_lurk := false
var _taught_guard := false
var _taught_pull := false
var _taught_ping := false
var _jaw: Node3D
var _rod: Node3D
var _esca: MeshInstance3D
var _esca_mat: StandardMaterial3D
var _lure_light: OmniLight3D


func setup() -> void:
	species = &"lamplighter"
	title = "THE LAMPLIGHTER"
	max_hp = 300.0
	radius = 3.4
	mass = 50.0
	contact_damage = 12.0
	salvage_drop = 60
	glow_color = LURE_COLOR
	ambushable = false
	pos = level.field.resolve_circle(lair_center + Vector2(lair_radius.x * 0.35, -lair_radius.y * 0.1), radius + 0.5)
	facing = Vector2.LEFT
	super.setup()
	active_radius = 1000.0
	_orbit = level.rng.randf() * TAU
	Events.sonar_pinged.connect(_on_ping)


func build_model() -> void:
	var mat := species_material(func(m: ShaderMaterial) -> void:
		m.set_shader_parameter(&"back_color", Color(0.08, 0.07, 0.08))
		m.set_shader_parameter(&"belly_color", Color(0.24, 0.19, 0.18))
		m.set_shader_parameter(&"glow_color", LURE_COLOR)
		m.set_shader_parameter(&"glow_strength", 1.6)
		m.set_shader_parameter(&"rim_strength", 0.45)
		m.set_shader_parameter(&"roughness", 0.75)
		m.set_shader_parameter(&"body_length", 5.6)
		m.set_shader_parameter(&"swim_amp", 0.07)
		m.set_shader_parameter(&"swim_freq", 2.2))
	var body := MeshKit.lathe(PackedVector2Array([Vector2(0.0, 0.15), Vector2(0.2, 0.55), Vector2(0.45, 1.3),
			Vector2(0.7, 1.75), Vector2(0.88, 1.6), Vector2(1.0, 0.9)]), 5.6, 18, 18, 1.0, 0.75,
		func(t: float, a: float) -> float:
			# A row of photophores along each flank.
			var flank := absf(cos(a)) < 0.16 and fmod(t * 14.0, 1.0) < 0.3 and t > 0.25 and t < 0.8
			return 0.9 if flank else 0.0)
	var tail := MeshKit.fin(PackedVector2Array([Vector2(0, 0), Vector2(-1.3, 1.2), Vector2(-0.9, 0.0),
			Vector2(-1.3, -1.2)]), 0.06, 0.15)
	var dorsal := MeshKit.fin(PackedVector2Array([Vector2(0.6, 0), Vector2(-0.2, 0.9), Vector2(-1.1, 0.6),
			Vector2(-1.4, 0.0)]), 0.05)
	var pectoral := MeshKit.fin(PackedVector2Array([Vector2(0, 0), Vector2(-0.7, 0.5), Vector2(-0.9, -0.2)]), 0.04)
	add_visual(MeshKit.merge([[body], [tail, Transform3D(Basis(), Vector3(-2.7, 0, 0))],
		[dorsal, Transform3D(Basis(), Vector3(0.2, 1.55, 0))],
		[pectoral, Transform3D(Basis(Vector3.UP, 0.4), Vector3(0.3, -0.5, 1.1))],
		[pectoral, Transform3D(Basis(Vector3.UP, -0.4), Vector3(0.3, -0.5, -1.1))]]), mat)
	# Needle teeth in pale bone, so a lamp catches the open mouth.
	var bone := StandardMaterial3D.new()
	bone.albedo_color = Color(0.85, 0.82, 0.72)
	bone.roughness = 0.35
	bone.rim_enabled = true
	bone.rim = 0.4
	model.add_child(_teeth(Vector3(1.45, -0.5, 0.0), -1.0, 0.85, bone))
	# The lower jaw hangs from a hinge so it can gape.
	_jaw = Node3D.new()
	_jaw.position = Vector3(0.7, -0.6, 0.0)
	model.add_child(_jaw)
	var jaw_mesh := MeshKit.lathe(PackedVector2Array([Vector2(0.0, 1.0), Vector2(0.7, 0.85), Vector2(1.0, 0.35)]),
		2.4, 14, 6, 0.32, 0.85)
	_jaw.add_child(_visual_on(MeshKit.transformed(jaw_mesh, Transform3D(Basis(), Vector3(1.2, 0, 0))), mat))
	_jaw.add_child(_teeth(Vector3(0.85, 0.2, 0.0), 1.0, 0.75, bone))
	# The rod arches up and forward from the brow; the lure hangs at its tip.
	_rod = Node3D.new()
	_rod.position = Vector3(2.0, 1.3, 0.0)
	model.add_child(_rod)
	var rod_mesh := ArrayMesh.new()
	MeshKit.tube(rod_mesh, PackedVector3Array([Vector3(0, 0, 0), Vector3(0.3, 1.1, 0), Vector3(1.0, 1.7, 0),
			Vector3(1.7, 1.6, 0), Vector3(2.1, 1.1, 0)]), PackedFloat32Array([0.14, 0.11, 0.08, 0.06, 0.05]), 6)
	_rod.add_child(_visual_on(rod_mesh, mat))
	_esca = MeshInstance3D.new()
	_esca.mesh = MeshKit.sphere(0.34, 12, 6)
	_esca_mat = MeshKit.emissive_material(LURE_COLOR, 6.0)
	_esca.material_override = _esca_mat
	_esca.position = Vector3(2.1, 0.8, 0.0)
	_rod.add_child(_esca)
	_lure_light = OmniLight3D.new()
	_lure_light.light_color = LURE_COLOR
	_lure_light.omni_range = 16.0
	_lure_light.light_energy = 2.6
	_lure_light.light_volumetric_fog_energy = 2.5
	_lure_light.position = Vector3(0.0, 0.0, 0.8)
	_esca.add_child(_lure_light)
	add_eyes(Vector3(2.1, 0.75, 0.95), 0.16, Color(0.75, 0.95, 0.55), 0.6)


## A row of needle teeth along both sides of a jaw, pointing up (+1) or down (-1).
func _teeth(at: Vector3, pointing: float, spread: float, mat: Material) -> MeshInstance3D:
	var parts := []
	for i in 7:
		var length := 0.95 - absf(i - 3.0) * 0.1
		for side: float in [-1.0, 1.0]:
			parts.append([MeshKit.spike(0.09, length, 0.0, 4), Transform3D(Basis(Vector3.BACK, pointing * PI * 0.5),
				at + Vector3(i * 0.2, 0.0, side * (spread - i * 0.06)))])
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.merge(parts)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _visual_on(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visuals.append(mi)
	return mi


## Where her mouth is (the business end).
func head_pos() -> Vector2:
	return pos + facing * 2.6 * SIZE


func lure_pos() -> Vector2:
	if _esca == null or not _esca.is_inside_tree():
		return head_pos()
	var p := _esca.global_position
	return Vector2(p.x, p.y)


func is_hostile() -> bool:
	return state != State.DORMANT and state != State.DEAD


func think() -> void:
	var sub := level.player
	match state:
		State.DORMANT:
			if sub and sub.alive and in_lair(sub.pos, 1.1):
				_awaken()
		State.STALK:
			if _cooldown > 0.0:
				return
			# With her eyes shut to light, a flare is nothing to her.
			var flare := _flare_in_lair() if stun_guard <= 0.0 else null
			if flare:
				_flare = flare
				state = State.FEED
				return
			if sub == null or not sub.alive:
				return
			if _lurk_in <= 0.0:
				_begin_lurk()
				return
			_look_for(sub)
		State.LURK:
			if sub and sub.alive and (head_pos().distance_to(sub.pos) < LURK_STRIKE or _timer <= 0.0):
				_strike_from_dark(sub)


## Decides what to do about the sub: be dazzled, snap, or charge its light.
func _look_for(sub: Submarine) -> void:
	var head := head_pos()
	var d := head.distance_to(sub.pos)
	if sub.illuminates(head, 1.5) and d < DAZZLE_RANGE and stun_guard <= 0.0:
		dazzle += THINK_INTERVAL
		_spot = 0.0
		if dazzle >= DAZZLE_NEED[phase]:
			_be_dazzled()
		return
	dazzle = maxf(dazzle - THINK_INTERVAL * 0.5, 0.0)
	if sub.pos.distance_to(lure_pos()) < SNAP_REACH or (sub.lamp_on and d < SNAP_REACH):
		_begin_snap(sub.pos)
		return
	if sub.lamp_on and d < SIGHT_RANGE and level.field.line_of_sight(head, sub.pos):
		_spot += THINK_INTERVAL
		if _spot >= SPOT_TIME:
			_begin_windup()
	else:
		_spot = maxf(_spot - THINK_INTERVAL, 0.0)


func behave(delta: float) -> void:
	_t += delta
	_timer -= delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	_trance_free = maxf(_trance_free - delta, 0.0)
	if state == State.STALK:
		_lurk_in -= delta
	var jaw_target := 0.08
	var lure_target := 1.0
	var sub := level.player
	match state:
		State.DORMANT:
			vel = Vector2.ZERO
		State.STALK:
			lock_facing = false
			_orbit += delta * (0.12 + phase * 0.04)
			var drift := lair_center + Vector2(cos(_orbit) * lair_radius.x * 0.5, sin(_orbit * 1.3) * lair_radius.y * 0.35)
			seek(drift, 3.2 + phase * 0.6, 1.0, delta)
			_pull(sub, delta)
		State.WINDUP:
			lock_facing = true
			vel = vel.lerp(Vector2.ZERO, 1.0 - exp(-4.0 * delta))
			if sub and sub.alive:
				facing = facing.slerp((sub.pos - head_pos()).normalized(), 1.0 - exp(-5.0 * delta)).normalized()
			lure_target = 0.0
			jaw_target = 0.4
			if _timer <= 0.0:
				_charge()
		State.CHARGE:
			vel = _dir * CHARGE_SPEED[phase]
			jaw_target = 1.0
			lure_target = 0.3
			if _timer <= 0.0:
				_end_charge(1.1)
		State.SNAP:
			jaw_target = 1.0
			if not _snapping:
				vel = vel.lerp(Vector2.ZERO, 1.0 - exp(-6.0 * delta))
				jaw_target = 0.6
				if _timer <= 0.0:
					_snapping = true
					_timer = SNAP_TIME
					vel = _dir * 17.0
					Audio.play_at(&"lurelight_snap", pos, 4.0, 0.03, 0.55)
			elif _timer <= 0.0:
				_recover(0.8)
		State.FEED:
			lock_facing = false
			jaw_target = 0.7
			if _flare == null or not is_instance_valid(_flare) or not _flare.alive:
				state = State.STALK
			else:
				seek(_flare.pos - facing * 2.4 * SIZE, 11.0, 2.5, delta)
				if head_pos().distance_to(_flare.pos) < 2.6:
					_swallow_flare()
		State.DAZZLED:
			lock_facing = true
			vel = vel.lerp(-facing * 2.5, 1.0 - exp(-2.0 * delta))
			jaw_target = 0.85 + 0.15 * sin(_t * 11.0)
			lure_target = 0.3 + 0.7 * absf(sin(_t * 17.0))
			if _timer <= 0.0:
				_recover(0.6)
				_cooldown = 1.0
				raise_guard()
				if not _taught_guard:
					_taught_guard = true
					Events.toast.emit("She has shut her eyes to your light - for now.", UiTheme.WARN)
		State.LURK:
			# Lure doused, gliding in on where the sub was last lit.
			lock_facing = false
			lure_target = 0.0
			jaw_target = 0.3
			if sub and sub.alive:
				seek(sub.pos - facing * 2.0 * SIZE, LURK_SPEED, 1.5, delta)
		State.RECOVER:
			vel = vel.lerp(Vector2.ZERO, 1.0 - exp(-2.5 * delta))
			if _timer <= 0.0:
				state = State.STALK
				lock_facing = false
		State.DEAD:
			vel = vel.lerp(Vector2(0.0, -1.2), 1.0 - exp(-1.0 * delta))
			lure_target = 0.0
			_shrink = maxf(_timer / 3.0, 0.01)
			if _timer <= 0.0:
				despawn()
	_jaw_open = lerpf(_jaw_open, jaw_target, 1.0 - exp(-10.0 * delta))
	_lure_k = lerpf(_lure_k, lure_target, 1.0 - exp(-(3.0 if lure_target < _lure_k else 6.0) * delta))


## The lure draws the sub towards it until a ping breaks the spell.
func _pull(sub: Submarine, delta: float) -> void:
	if sub == null or not sub.alive or _trance_free > 0.0 or not in_lair(sub.pos, 1.1):
		return
	var to := lure_pos() - sub.pos
	var d := to.length()
	if d > PULL_RANGE or d < 1.5:
		return
	sub.vel += to / d * PULL[phase] * delta
	if not _taught_pull:
		_taught_pull = true
		Events.toast.emit("Her lure is pulling you in. Ping to break the spell.", UiTheme.WARN)


func _on_ping(origin: Vector2, ping_range: float) -> void:
	if not active or origin.distance_to(pos) > ping_range:
		return
	_trance_free = TRANCE_BREAK
	if not _taught_ping:
		_taught_ping = true
		Events.toast.emit("The ping broke the spell. Run dark - she charges any light she sees from afar.",
			UiTheme.GOOD)


func _flare_in_lair() -> Flare:
	for f in level.flares:
		var flare := f as Flare
		if flare and flare.alive and in_lair(flare.pos, 1.2):
			return flare
	return null


func _begin_windup(follow_up := false) -> void:
	state = State.WINDUP
	_timer = WINDUP_TIME * (1.0 - phase * 0.12) * (0.55 if follow_up else 1.0)
	_spot = 0.0
	if not follow_up:
		_charges_left = FOLLOW_UPS[phase]
	Audio.play_at(&"lancer_windup", pos, 3.0, 0.03, 0.45)


## A charge is over: she turns straight into another while she still sees
## light (and has charges left in her), else she recovers.
func _end_charge(rest: float) -> void:
	var sub := level.player
	if _charges_left > 0 and sub and sub.alive and (sub.lamp_on or head_pos().distance_to(sub.pos) < DAZZLE_RANGE):
		_charges_left -= 1
		_begin_windup(true)
	else:
		_recover(rest)


## Douses her lure and glides in on the sub in the dark.
func _begin_lurk() -> void:
	state = State.LURK
	_timer = LURK_MAX
	_lurk_in = LURK_EVERY[phase]
	Audio.play_at(&"creak", pos, 0.0, 0.03, 0.5)
	if not _taught_lurk:
		_taught_lurk = true
		Events.toast.emit("Her lure went dark. She is coming for you - keep moving, ping to find her.",
			UiTheme.DANGER)


## Her lure flares right in the pilot's face, and she snaps.
func _strike_from_dark(sub: Submarine) -> void:
	_lure_k = 1.6
	Fx.flash(level, lure_pos(), LURE_COLOR, 18.0, 0.35)
	_trance_free = 0.0
	_begin_snap(sub.pos)


func _charge() -> void:
	state = State.CHARGE
	_timer = CHARGE_TIME
	var sub := level.player
	_dir = (sub.pos - head_pos()).normalized() if sub else facing
	facing = _dir
	Audio.play_at(&"lancer_dash", pos, 4.0, 0.03, 0.45)


func _begin_snap(at: Vector2) -> void:
	state = State.SNAP
	lock_facing = true
	_snapping = false
	_timer = SNAP_WINDUP
	_dir = (at - head_pos()).normalized()
	facing = facing.slerp(_dir, 0.6).normalized()


func _be_dazzled() -> void:
	state = State.DAZZLED
	_timer = DAZZLE_TIME[phase]
	dazzle = 0.0
	_spot = 0.0
	Fx.flash(level, head_pos(), Color(1.0, 1.0, 0.9), 14.0, 0.4)
	Fx.float_text(level, head_pos() + Vector2(0.0, 3.0), "DAZZLED", UiTheme.GOOD)
	Audio.play_at(&"stalker_roar", pos, 2.0, 0.03, 0.8)
	Events.toast.emit("Dazzled! Strike now.", UiTheme.GOOD)


func _swallow_flare() -> void:
	_flare.despawn()
	_flare = null
	Fx.flash(level, head_pos(), Color(1.0, 0.45, 0.25), 18.0, 0.6)
	Fx.bubble_burst(level, head_pos(), 25, 1.5)
	_be_dazzled()


func _recover(time: float) -> void:
	state = State.RECOVER
	_timer = time
	_snapping = false


## A charge that meets rock ends there, with a jolt.
func move_and_collide_field(delta: float, bounce := 0.1) -> Vector2:
	if state == State.DORMANT:
		return Vector2.ZERO
	var hit := super.move_and_collide_field(delta, bounce)
	if state == State.CHARGE and hit != Vector2.ZERO:
		Events.shake_requested.emit(0.6)
		Audio.play_at(&"impact_rock", pos, 4.0, 0.03, 0.6)
		level.emit_noise(pos, 18.0, self)
		_end_charge(1.0)
	return hit


func on_touch_player(sub: Submarine) -> void:
	match state:
		State.DORMANT, State.DEAD, State.DAZZLED:
			return
		State.CHARGE:
			sub.take_damage(CHARGE_DAMAGE, pos, self)
			sub.vel += _dir * 8.0
			_end_charge(1.0)
		State.SNAP:
			if _snapping:
				sub.take_damage(SNAP_DAMAGE, pos, self)
				_recover(0.8)
		_:
			sub.take_damage(contact_damage, pos, self)


func take_damage(amount: float, from: Vector2, kind: StringName = &"") -> void:
	if state == State.DEAD:
		return
	if state == State.DORMANT:
		_awaken()
	if state != State.DAZZLED:
		deflect(from, "Her scales turn everything. Dazzle her first: your lamp in her eyes up close, " +
			"or a flare.", 0.7)
		return
	super.take_damage(amount, from, kind)
	var frac := hp / max_hp
	var want := 0 if frac > 0.66 else (1 if frac > 0.33 else 2)
	if alive and want > phase:
		phase = want
		_enrage()


func die() -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	_timer = 3.0
	reward_defeat("The Lamplighter's light goes out.")


func _awaken() -> void:
	if active:
		return
	state = State.STALK
	_cooldown = 1.5
	wake("She sees only light. Run dark, and dazzle her up close.", 0.7, &"angler")


## Each roar brings drifter jellies to her light (one, then two), and her next
## dark hunt sooner.
func _enrage() -> void:
	Audio.play_at(&"stalker_roar", pos, 4.0, 0.03, 0.65)
	Events.shake_requested.emit(0.6)
	Fx.flash(level, lure_pos(), LURE_COLOR, 24.0, 0.6)
	_lurk_in = minf(_lurk_in, 4.0)
	for i in phase:
		var jelly: Creature = LevelPopulator.SPECIES[&"jelly"].new()
		jelly.pos = lure_pos() + Vector2(level.rng.randf_range(-5.0, 5.0), 3.0)
		if level.field.sample(jelly.pos) > 1.5:
			level.add_entity(jelly)
		else:
			jelly.free()


func _update_visuals(delta: float) -> void:
	super._update_visuals(delta)
	model.basis = model.basis.scaled(Vector3.ONE * SIZE * _shrink)
	if state == State.DAZZLED:
		# Reeling: she rolls and shakes her head.
		model.basis = model.basis * Basis(Vector3.RIGHT, sin(_t * 9.0) * 0.25) * Basis(Vector3.BACK, sin(_t * 13.0) * 0.08)
	_jaw.rotation.z = -_jaw_open * 0.75
	_rod.rotation.z = sin(_t * 1.3) * 0.1 + sin(_t * 0.47) * 0.06
	_esca_mat.emission_energy_multiplier = 0.4 + 6.0 * _lure_k
	_lure_light.light_energy = 2.8 * _lure_k
