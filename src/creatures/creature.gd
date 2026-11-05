class_name Creature
extends Entity
## Base for all creatures: health, damage, stun/blind, sonar marks, senses,
## steering and the shared visual material. Subclasses implement [method think]
## (perception, a few times a second) and [method behave] (steering, every tick).

## Eye styles for [method add_eyes]: a plain glossy (or glowing) ball, a
## hunter's glowing ring round a slit, a fish's metallic iris round a pupil.
enum Eye { PLAIN, HUNTER, FISH }

const SHADER := preload("res://src/fx/shaders/creature.gdshader")
## The same material, see-through (see creature_glass.gdshader).
const GLASS_SHADER := preload("res://src/fx/shaders/creature_glass.gdshader")
const THINK_INTERVAL := 0.2
## Harpoon damage multiplier against a creature that has not noticed the sub.
const AMBUSH_MULT := 2.0
## Seconds after noticing the sub before a creature counts as unaware again.
const AWARE_TIME := 6.0
## How far a hurt creature's cry carries to others of its kind.
const ALARM_RADIUS := 10.0

static var _materials: Dictionary[StringName, ShaderMaterial] = {}

var species: StringName
var max_hp := 30.0
var hp := 30.0
var contact_damage := 10.0
var scannable := true
## Creatures lighter than this are dragged in by the harpoon.
var mass := 1.0
## How far the body reaches from its middle (a long eel or wide wings), when
## that is more than [member radius]: it keeps that far from the rock.
var reach := 0.0
var glow_color := Color(0.4, 1.0, 0.9)
## Multiplier applied to noise radii when listening.
var hearing := 1.0
var salvage_drop := 3
var hostile := true

var model: Node3D
var visuals: Array[GeometryInstance3D] = []
var facing := Vector2.RIGHT
## Upright creatures (jellies) keep their model vertical instead of facing
## their velocity.
var upright := false
## When true, [member facing] is controlled by the subclass, not velocity.
var lock_facing := false
## Bosses cannot be caught unaware.
var ambushable := true
## Held by the Choir's tone (see [StationAudience]): hangs still facing
## [member entranced_facing], deaf to everything, and bites nothing, until
## something hurts or bumps it.
var entranced := false
var entranced_facing := Vector2(0.0, -1.0)  # World +y is up: facing the floor.
## How far the spine bends into the curve the creature turns along (0 rigid,
## 1 all the way), and the point of the body (model X) that stays put.
var flex := 0.0
var flex_pivot := 0.0
## The body's length along model X, which limits how far it can curl.
var body_span := 0.0

var _stun := 0.0
var _blind := 0.0
var _marked := 0.0
var _mark_total := 1.0
var _flash := 0.0
var _noticed_at := -100.0
var _alert := 0.0
var _think_timer := 0.0
var _touch_cooldown := 0.0
var _phase := 0.0
var _turn_speed := 6.0
var _roll := 0.0
## Swim stroke so far (see creature.gdshader).
var _swim_clock := 0.0
## How hard it swims: a drifting creature barely beats its tail, a cruising
## one swims fully, and a burst (a dash, a hard turn) kicks harder still.
var _swim_power := 0.5
var _kick := 0.0
var _last_speed := 0.0
## The body's swim settings, read once from its material so rigid riders
## swim with the skin (see [method _swum_transform]).
var _stroke := PackedFloat32Array()
## Hurt once, it knows the sub is there for good: no second ambush.
var _wary := false
## The spine's current curvature (see [member flex]) and the heading it was
## measured from.
var _bend := 0.0
var _local_bend := 0.0
var _last_heading := 0.0
## Rigid parts carried by the bending body (eyes, lures): each node and its
## resting transform.
var _riders: Array = []


func setup() -> void:
	targetable = true
	hp = max_hp * Pressure.creature_health(level.pressure)
	max_hp = hp
	hearing *= Pressure.hearing(level.pressure) * (1.6 if level.event == &"quiet" else 1.0)
	_phase = level.rng.randf() * TAU
	_think_timer = level.rng.randf() * THINK_INTERVAL
	model = Node3D.new()
	add_child(model)
	build_model()
	for v in visuals:
		v.set_instance_shader_parameter(&"phase", _phase)


## Override: create meshes under [member model] and register them in [member visuals].
func build_model() -> void:
	pass


## Override: perception and decisions, called every [constant THINK_INTERVAL].
func think() -> void:
	pass


## Override: steering for this tick.
func behave(_delta: float) -> void:
	pass


func tick(delta: float) -> void:
	_flash = maxf(_flash - delta * 4.0, 0.0)
	_alert = maxf(_alert - delta, 0.0)
	_marked = maxf(_marked - delta, 0.0)
	_blind = maxf(_blind - delta, 0.0)
	_touch_cooldown = maxf(_touch_cooldown - delta, 0.0)
	if entranced:
		_hang(delta)
		return
	if _stun > 0.0:
		_stun -= delta
		vel = vel.lerp(Vector2.ZERO, 1.0 - exp(-3.0 * delta))
	else:
		_think_timer -= delta
		if _think_timer <= 0.0:
			_think_timer += THINK_INTERVAL
			think()
		behave(delta)
	vel += level.current_at(pos) * delta * 0.6
	move_and_collide_field(delta * level.creature_pace, 0.2)
	_check_player_contact()
	_update_visuals(delta)


## Entranced: still in the water but for a slow bob, turning with the rest.
func _hang(delta: float) -> void:
	vel = Vector2(0.0, sin(level.time * 0.7 + _phase) * 0.12)
	pos += vel * delta
	if not upright:
		facing = facing.slerp(entranced_facing, 1.0 - exp(-2.0 * delta)).normalized()
	var sub := level.player
	if sub and sub.alive and pos.distance_squared_to(sub.pos) < pow(radius + Submarine.RADIUS + 0.2, 2.0):
		_wake()
	_update_visuals(delta)


## Breaks the trance: it notices the sub and acts on its own again.
func _wake() -> void:
	if not entranced:
		return
	entranced = false
	alert()


func _check_player_contact() -> void:
	var sub := level.player
	if sub == null or not sub.alive or _touch_cooldown > 0.0 or _stun > 0.0:
		return
	if pos.distance_squared_to(sub.pos) < pow(radius + Submarine.RADIUS, 2.0):
		_touch_cooldown = 0.8
		on_touch_player(sub)
		if sub.stats.contact_zap > 0.0:
			take_damage(sub.stats.contact_zap, sub.pos, &"zap")


## Override for contact behaviour; default bites for [member contact_damage].
func on_touch_player(sub: Submarine) -> void:
	if contact_damage > 0.0:
		sub.take_damage(contact_damage, pos, self)


func _update_visuals(delta: float) -> void:
	_update_stroke(delta)
	if upright:
		# Leans gently into its drift (smoothed: a pulsing swimmer's speed
		# changes every frame).
		_roll = lerpf(_roll, clampf(vel.x * 0.06, -0.4, 0.4), 1.0 - exp(-2.5 * delta))
		model.basis = Basis(Vector3.BACK, PI * 0.5 - _roll)
		_update_instance_params()
		_pose_riders()
		return
	if not lock_facing and vel.length_squared() > 0.04:
		facing = facing.slerp(vel.normalized(), 1.0 - exp(-_turn_speed * delta)).normalized()
	# Roll around the body axis first so the dorsal side stays up when
	# heading left, then turn to the heading.
	var target_roll := PI if facing.x < 0.0 else 0.0
	_roll = lerp_angle(_roll, target_roll, 1.0 - exp(-5.0 * delta))
	model.basis = Basis(Vector3.BACK, facing.angle()) * Basis(Vector3.RIGHT, _roll)
	_update_bend(delta)
	_update_instance_params()
	_pose_riders()


## Paces the swim stroke. Fish beat faster the faster they go; their swing
## grows from a lazy flick at a hover to a full stroke at about a body length
## a second, and a sudden burst of speed or a hard turn adds a kick that dies
## away over a second or so.
func _update_stroke(delta: float) -> void:
	var speed := vel.length()
	var span := _span()
	var surge := (speed - _last_speed) / maxf(delta, 0.001) / span
	_last_speed = speed
	_kick = maxf(_kick * exp(-2.0 * delta), clampf(surge * 0.05, 0.0, 0.6))
	var want := clampf(0.3 + speed / span * 0.6, 0.3, 1.0) + _kick
	var rate := 8.0 if want > _swim_power else 2.5
	_swim_power = lerpf(_swim_power, want, 1.0 - exp(-rate * delta))
	_swim_clock += delta * (0.6 + speed * 0.15) * (1.0 + _kick)


## The body's length along model X (see [member body_span]).
func _span() -> float:
	return body_span if body_span > 0.0 else maxf(maxf(reach * 2.0, radius * 2.0), 0.5)


## Bends the spine into the arc the creature is turning along: its heading
## turning at w radians a second while it swims at v is a path of curvature
## w / v, which a body lying along that path follows nose to tail.
func _update_bend(delta: float) -> void:
	var heading := facing.angle()
	var turn := wrapf(heading - _last_heading, -PI, PI) / maxf(delta, 0.001)
	_last_heading = heading
	# A hard turn is a burst of swimming too.
	_kick = maxf(_kick, clampf(absf(turn) * 0.12 - 0.15, 0.0, 0.5))
	if flex <= 0.0:
		return
	# No more than about 30 degrees from the pivot to either end.
	var limit := 1.05 / _span()
	var k := clampf(turn / maxf(vel.length(), 1.5), -limit, limit) * flex
	_bend = lerpf(_bend, k, 1.0 - exp(-6.0 * delta))
	# Rolled over to face left, the model's +Y is the other side of the turn.
	_local_bend = _bend * cos(_roll)
	for v in visuals:
		v.set_instance_shader_parameter(&"bend", _local_bend)


## Moves the rigid riders (eyes) with the swimming, bending body.
func _pose_riders() -> void:
	for r: Array in _riders:
		(r[0] as Node3D).transform = _bent_transform(_swum_transform(r[1]), _local_bend, flex_pivot)


## Where a rigid part resting at [param rest] lands on the swimming body:
## rolled with the beat and carried off the line and turned with the spine
## section it rides on, as creature.gdshader moves the skin around it.
func _swum_transform(rest: Transform3D) -> Transform3D:
	if _stroke.is_empty():
		# The shader's own defaults, then whatever the body's material sets.
		_stroke = PackedFloat32Array([0.12, 7.0, 2.5, 2.0, 0.2, 0.25, 0.25, 0.0])
		var mat := visuals[0].material_override as ShaderMaterial if not visuals.is_empty() else null
		if mat:
			var names := [&"swim_amp", &"swim_freq", &"swim_wave", &"body_length", &"swim_head", &"swim_still",
				&"swim_vertical", &"swim_roll"]
			for i in names.size():
				var val: Variant = mat.get_shader_parameter(names[i])
				if val != null:
					_stroke[i] = float(val)
	var st := _stroke
	var ph := _swim_clock * st[1] + _phase
	var x := rest.origin.x
	var l := maxf(st[3], 0.01)
	var xc := clampf(x, -0.65 * l, 0.5 * l)
	var u := 0.5 - xc / l
	var um := minf(st[5], 0.4)
	var ea := (1.0 - st[4]) / (1.0 - 2.0 * um)
	var env := ea * (u - um) * (u - um) + st[4] - ea * um * um
	var w := ph + xc * st[2]
	var amp := st[0] * _swim_power
	var slope := amp * (-2.0 * ea * (u - um) / l * sin(w) + env * st[2] * cos(w))
	var d := amp * env * sin(w) + slope * (x - xc)
	var v := st[6]
	var roll := Basis(Vector3.RIGHT, st[7] * _swim_power * sin(ph))
	var turn := Basis(Vector3.BACK, atan(slope * v)) * Basis(Vector3.UP, -atan(slope * (1.0 - v)))
	var o := turn * (roll * rest.origin - Vector3(x, 0.0, 0.0))
	return Transform3D(turn * roll * rest.basis, Vector3(x, d * v, d * (1.0 - v)) + o)


## Where a rigid part resting at [param rest] (model space) lands when the
## spine has curvature [param k] about model X [param pivot]: carried along
## the same arc as creature.gdshader, turned with the body's section there.
static func _bent_transform(rest: Transform3D, k: float, pivot: float) -> Transform3D:
	if absf(k) < 0.0001:
		return rest
	var s := rest.origin.x - pivot
	var h := rest.origin.y
	var th := k * s
	var a := sin(th) / th if absf(th) > 0.001 else 1.0
	var b := (1.0 - cos(th)) / th if absf(th) > 0.001 else th * 0.5
	var o := Vector3(pivot + s * a - h * sin(th), s * b + h * cos(th), rest.origin.z)
	return Transform3D(Basis(Vector3.BACK, th) * rest.basis, o)


## Carries [param node] (a rigid part on the model) along with the body as
## it bends.
func _carry(node: Node3D) -> void:
	_riders.append([node, node.transform])


func _update_instance_params() -> void:
	for v in visuals:
		v.set_instance_shader_parameter(&"marked", _marked / _mark_total if _marked > 0.0 else 0.0)
		v.set_instance_shader_parameter(&"hit_flash", _flash)
		v.set_instance_shader_parameter(&"swim_clock", _swim_clock)
		v.set_instance_shader_parameter(&"swim_power", _swim_power)


# --- Damage and status -------------------------------------------------------

func take_damage(amount: float, from: Vector2, _kind: StringName = &"") -> void:
	if not alive:
		return
	_wake()
	_raise_alarm()
	hp -= amount
	_flash = 1.0
	vel += (pos - from).normalized() * clampf(amount * 0.25, 1.0, 8.0) / maxf(mass, 0.5)
	Fx.ichor(level, pos, glow_color, 10)
	Audio.play_at(&"creature_hit", pos, -3.0)
	on_damaged(amount, from)
	if hp <= 0.0:
		die()


## Override to react to being hurt (flee, retaliate...).
func on_damaged(_amount: float, _from: Vector2) -> void:
	pass


func die() -> void:
	if not alive:
		return
	Events.hitstop.emit(0.06 if radius < 1.5 else 0.12)
	Fx.flash(level, pos, glow_color, 6.0 + radius * 4.0, 0.35)
	Fx.ichor(level, pos, glow_color, 30)
	Fx.bubble_burst(level, pos, 20, radius)
	Audio.play_at(&"creature_die", pos, 0.0)
	Events.creature_killed.emit(species, pos)
	if level.player:
		level.player.run.kills += 1
	Pickup.scatter(level, pos, &"salvage", salvage_drop, radius)
	despawn()


func stun(duration: float) -> void:
	_stun = maxf(_stun, duration)


func blind(duration: float) -> void:
	_blind = maxf(_blind, duration)


func is_stunned() -> bool:
	return _stun > 0.0


## Flags that this creature has just noticed the player (HUD shows a "!").
func alert() -> void:
	if _alert <= 0.0:
		Audio.play_at(&"alert", pos, -6.0)
	_alert = 1.4
	_noticed_at = level.time


## True if this creature has not noticed the sub recently (and has never
## been hurt): harpooning it then is an ambush.
func is_unaware() -> bool:
	return ambushable and not _wary and level.time - _noticed_at > AWARE_TIME


## Hurt: it is on its guard from now on, and so are others of its kind close by.
func _raise_alarm() -> void:
	if _wary:
		return
	_wary = true
	_noticed_at = level.time
	for e in level.targets_in_radius(pos, ALARM_RADIUS):
		var other := e as Creature
		if other and other != self and other.alive and other.species == species and not other._wary:
			other._wary = true
			other._noticed_at = level.time
			other.alert()


func alert_fraction() -> float:
	return _alert / 1.4


func is_marked() -> bool:
	return _marked > 0.0


func mark_fraction() -> float:
	return _marked / _mark_total


func is_hostile() -> bool:
	return hostile


func on_sonar(origin: Vector2, mark_time: float) -> void:
	var delay := pos.distance_to(origin) / Level.SONAR_SPEED
	_marked = mark_time + delay
	_mark_total = _marked
	if not level.silent_ping:
		on_pinged(origin)


## Override: hunters may turn towards the source of a ping.
func on_pinged(_origin: Vector2) -> void:
	pass


func on_harpoon_hit(_harpoon: Node, damage: float) -> HarpoonReaction:
	if is_unaware():
		damage *= AMBUSH_MULT
		Fx.float_text(level, pos + Vector2(0.0, radius + 1.0), "AMBUSH", UiTheme.WARN)
		if level.player:
			level.player.run.ambushes += 1
	take_damage(damage, level.player.pos if level.player else pos, &"harpoon")
	if not alive:
		return HarpoonReaction.IGNORE
	# The barb bites, then pulls free: a creature is struck, not reeled in.
	return HarpoonReaction.STICK


# --- Senses ------------------------------------------------------------------

func player_in_range(r: float) -> bool:
	var sub := level.player
	return sub != null and sub.alive and pos.distance_squared_to(sub.pos) < r * r


## Sees the submarine: lit subs are visible from far, dark ones only up close.
func can_see_player(sight_range: float) -> bool:
	if _blind > 0.0:
		return false
	var sub := level.player
	if sub == null or not sub.alive:
		return false
	var d := pos.distance_to(sub.pos)
	var effective := (sight_range if sub.lamp_on else sight_range * 0.3) * level.sight_scale
	if d > effective:
		return false
	return level.field.line_of_sight(pos, sub.pos)


## Recent loud noise this creature can hear, as a position, or Vector2.INF.
func heard_noise() -> Vector2:
	if _blind > 0.0:
		return Vector2.INF
	var n: Variant = level.loudest_noise_at(pos, hearing, self)
	return n.pos if n != null else Vector2.INF


## Strongest burning flare that draws this creature, or null.
func nearest_flare() -> Flare:
	var best: Flare = null
	var best_s := 0.0
	for f in level.flares:
		var flare := f as Flare
		if flare and flare.alive:
			var s := flare.lure_strength(pos)
			if s > best_s:
				best_s = s
				best = flare
	return best


# --- Steering ----------------------------------------------------------------

## Accelerates towards a desired velocity with wall avoidance.
func steer(desired: Vector2, agility: float, delta: float) -> void:
	desired += avoid_walls(desired) * maxf(desired.length(), 2.0)
	vel = vel.lerp(desired, 1.0 - exp(-agility * delta))


func seek(target: Vector2, speed: float, agility: float, delta: float) -> void:
	var to := target - pos
	var d := to.length()
	var desired := to / d * speed * clampf(d / 3.0, 0.2, 1.0) if d > 0.01 else Vector2.ZERO
	steer(desired, agility, delta)


## Push away from rock ahead and around, scaled 0..~1.5.
func avoid_walls(heading: Vector2) -> Vector2:
	var field := level.field
	var push := Vector2.ZERO
	var body := maxf(radius, reach * 0.8)
	var d0 := field.sample(pos)
	if d0 < body + 2.0:
		push += field.normal(pos) * (1.0 - (d0 - body) / 2.0)
	if heading.length_squared() > 0.01:
		var ahead := pos + heading.normalized() * (body + 3.0)
		var d1 := field.sample(ahead)
		if d1 < body + 1.0:
			push += field.normal(ahead) * 0.8
	return push


## A random reachable point near [param center] for wandering.
func wander_point(center: Vector2, spread: float) -> Vector2:
	for _i in 8:
		var p := center + Vector2(level.rng.randf_range(-spread, spread), level.rng.randf_range(-spread, spread))
		if level.field.sample(p) > maxf(radius, reach * 0.8) + 1.0 and level.field.line_of_sight(pos, p, radius * 0.5):
			return p
	return pos


# --- Visual helpers ------------------------------------------------------------

## Shared material per species and biome, configured once; a species drawn
## with more than one (see-through flesh over solid bones) names each
## [param part] and may draw it with another [param shader].
func species_material(config: Callable, part := &"", shader: Shader = SHADER) -> ShaderMaterial:
	var key := StringName("%s/%s/%s" % [species, level.biome.id, part])
	if _materials.has(key):
		return _materials[key]
	var mat := ShaderMaterial.new()
	mat.shader = shader
	config.call(mat)
	_materials[key] = mat
	return mat


## A pair of eyes on either flank of the head. Glowing eyes read in the dark;
## glossy ones catch the lamp.
## [param style] [constant Eye.HUNTER] gives glossy black globes with a
## glowing iris ring of [param color] round a slit pupil, [constant Eye.FISH]
## a metallic iris of [param color] round a round pupil, flush in the globe.
func add_eyes(at: Vector3, eye_radius: float, color: Color, glow := 0.0, style := Eye.PLAIN) -> void:
	if style == Eye.HUNTER:
		_hunter_eyes(at, eye_radius, color, glow)
		return
	if style == Eye.FISH:
		_fish_eyes(at, eye_radius, color, glow)
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.05
	mat.metallic = 0.3
	if glow > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = glow
	var pupil_mat := StandardMaterial3D.new()
	pupil_mat.albedo_color = Color(0.02, 0.02, 0.03)
	pupil_mat.roughness = 0.0
	for side: float in [1.0, -1.0]:
		var eye := MeshInstance3D.new()
		eye.mesh = MeshKit.sphere(eye_radius, 10, 6)
		eye.material_override = mat
		eye.position = Vector3(at.x, at.y, at.z * side)
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		model.add_child(eye)
		_carry(eye)
		if glow <= 0.0:
			var pupil := MeshInstance3D.new()
			pupil.mesh = MeshKit.sphere(eye_radius * 0.55, 8, 4)
			pupil.material_override = pupil_mat
			pupil.position = Vector3(eye_radius * 0.35, 0, eye_radius * 0.55 * side)
			eye.add_child(pupil)


## A hunter's eyes (see [method add_eyes]) at [param at]: glossy
## black globes with a glowing iris ring of [param iris] round a slit pupil,
## under a heavy brow. They ride the bending body like [method add_eyes].
func _hunter_eyes(at: Vector3, eye_radius: float, iris: Color, glow: float) -> void:
	var globe := StandardMaterial3D.new()
	globe.albedo_color = Color(0.02, 0.02, 0.025)
	globe.roughness = 0.04
	globe.metallic = 0.2
	var ring := StandardMaterial3D.new()
	ring.albedo_color = iris
	ring.emission_enabled = true
	ring.emission = iris
	ring.emission_energy_multiplier = glow
	ring.roughness = 0.3
	var slit := StandardMaterial3D.new()
	slit.albedo_color = Color(0.0, 0.0, 0.0)
	slit.roughness = 0.0
	for side: float in [1.0, -1.0]:
		var eye := Node3D.new()
		eye.position = Vector3(at.x, at.y, at.z * side)
		model.add_child(eye)
		var ball := MeshInstance3D.new()
		ball.mesh = MeshKit.sphere(eye_radius, 14, 8)
		ball.material_override = globe
		ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eye.add_child(ball)
		# The iris: a glowing ring just under the globe's surface, facing out.
		var iris_ring := MeshInstance3D.new()
		iris_ring.mesh = MeshKit.lathe(PackedVector2Array([Vector2(0.0, eye_radius * 0.3),
			Vector2(0.5, eye_radius * 0.72), Vector2(1.0, eye_radius * 0.3)]), eye_radius * 0.08, 20, 2)
		iris_ring.material_override = ring
		iris_ring.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5 * side), Vector3(0.0, 0.0, eye_radius * 0.9 * side))
		eye.add_child(iris_ring)
		var pupil := MeshInstance3D.new()
		pupil.mesh = MeshKit.sphere(eye_radius * 0.3, 8, 6)
		pupil.material_override = slit
		pupil.transform = Transform3D(Basis().scaled(Vector3(0.45, 1.25, 0.3)), Vector3(0.0, 0.0, eye_radius * 0.93 * side))
		eye.add_child(pupil)
		_carry(eye)


## A fish's eyes (see [method add_eyes]): a dark glossy globe with a
## metallic iris disc of [param iris] (glowing, given [param glow]) and a
## round pupil set flush in it.
func _fish_eyes(at: Vector3, eye_radius: float, iris: Color, glow := 0.0) -> void:
	var globe := StandardMaterial3D.new()
	globe.albedo_color = Color(0.03, 0.035, 0.04)
	globe.roughness = 0.03
	globe.metallic = 0.1
	var ring := StandardMaterial3D.new()
	ring.albedo_color = iris
	ring.metallic = 0.85 if glow <= 0.0 else 0.0
	ring.roughness = 0.22
	if glow > 0.0:
		ring.emission_enabled = true
		ring.emission = iris
		ring.emission_energy_multiplier = glow
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.0, 0.0, 0.0)
	black.roughness = 0.0
	for side: float in [1.0, -1.0]:
		var eye := Node3D.new()
		eye.position = Vector3(at.x, at.y, at.z * side)
		model.add_child(eye)
		var ball := MeshInstance3D.new()
		ball.mesh = MeshKit.sphere(eye_radius, 14, 8)
		ball.material_override = globe
		ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eye.add_child(ball)
		for disc: Array in [[ring, 0.74, 0.84], [black, 0.4, 0.97]]:
			var mi := MeshInstance3D.new()
			mi.mesh = MeshKit.sphere(eye_radius * float(disc[1]), 14, 6)
			mi.material_override = disc[0]
			mi.transform = Transform3D(Basis().scaled(Vector3(1.0, 1.0, 0.22)), Vector3(0.0, 0.0,
				eye_radius * float(disc[2]) * side))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			eye.add_child(mi)
		_carry(eye)


func add_visual(mesh: Mesh, mat: Material, xf := Transform3D.IDENTITY) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(mi)
	visuals.append(mi)
	if mat is ShaderMaterial and (mat as ShaderMaterial).shader in [SHADER, GLASS_SHADER]:
		mi.set_instance_shader_parameter(&"body_offset", xf.origin)
	return mi
