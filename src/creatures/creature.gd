class_name Creature
extends Entity
## Base for all creatures: health, damage, stun/blind, sonar marks, senses,
## steering and the shared visual material. Subclasses implement [method think]
## (perception, a few times a second) and [method behave] (steering, every tick).

const SHADER := preload("res://src/fx/shaders/creature.gdshader")
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
## Hurt once, it knows the sub is there for good: no second ambush.
var _wary := false
## The spine's current curvature (see [member flex]) and the heading it was
## measured from.
var _bend := 0.0
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
	_swim_clock += delta * (0.6 + vel.length() * 0.15)
	if upright:
		# Leans gently into its drift (smoothed: a pulsing swimmer's speed
		# changes every frame).
		_roll = lerpf(_roll, clampf(vel.x * 0.06, -0.4, 0.4), 1.0 - exp(-2.5 * delta))
		model.basis = Basis(Vector3.BACK, PI * 0.5 - _roll)
		_update_instance_params()
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


## Bends the spine into the arc the creature is turning along: its heading
## turning at w radians a second while it swims at v is a path of curvature
## w / v, which a body lying along that path follows nose to tail.
func _update_bend(delta: float) -> void:
	var heading := facing.angle()
	var turn := wrapf(heading - _last_heading, -PI, PI) / maxf(delta, 0.001)
	_last_heading = heading
	if flex <= 0.0:
		return
	var span := body_span if body_span > 0.0 else maxf(reach * 2.0, radius * 2.0)
	# No more than about 40 degrees from the pivot to either end.
	var limit := 1.4 / maxf(span, 0.5)
	var k := clampf(turn / maxf(vel.length(), 1.5), -limit, limit) * flex
	_bend = lerpf(_bend, k, 1.0 - exp(-6.0 * delta))
	# Rolled over to face left, the model's +Y is the other side of the turn.
	var local := _bend * cos(_roll)
	for v in visuals:
		v.set_instance_shader_parameter(&"bend", local)
	for r: Array in _riders:
		(r[0] as Node3D).transform = _bent_transform(r[1], local, flex_pivot)


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

## Shared material per species and biome, configured once.
func species_material(config: Callable) -> ShaderMaterial:
	var key := StringName("%s/%s" % [species, level.biome.id])
	if _materials.has(key):
		return _materials[key]
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	config.call(mat)
	_materials[key] = mat
	return mat


## A pair of eyes on either flank of the head. Glowing eyes read in the dark;
## glossy ones catch the lamp.
func add_eyes(at: Vector3, eye_radius: float, color: Color, glow := 0.0) -> void:
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


func add_visual(mesh: Mesh, mat: Material, xf := Transform3D.IDENTITY) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(mi)
	visuals.append(mi)
	if mat is ShaderMaterial and (mat as ShaderMaterial).shader == SHADER:
		mi.set_instance_shader_parameter(&"body_offset", xf.origin)
	return mi
