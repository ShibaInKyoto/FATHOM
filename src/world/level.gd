class_name Level
extends Node3D
## One zone of the dive: terrain, environment, and every entity in it.
## The level ticks its entities, routes noise to listeners and runs sonar.

signal exit_reached

## How long a noise event stays audible to creatures (seconds).
const NOISE_LIFETIME := 0.35
const SONAR_SPEED := 42.0
## The echo's speed (ECHO_SPEED in sonar.gdshaderinc).
const ECHO_SPEED := 16.0
## How hard, and from how far, the water rushing down the way down pulls.
const EXIT_PULL := 4.0
const EXIT_PULL_RADIUS := 9.0
## How long a pulse of the Choir's song holds the creatures it passes.
const HUSH_TIME := 1.0

var layout: LevelLayout
var field: TerrainField
var biome: BiomeDef
var zone := 0
var player: Submarine
var rng := RandomNumberGenerator.new()
var terrain: TerrainRenderer
var environment_rig: LevelEnvironment
var entities: Array[Entity] = []
## Recent noise events: {pos: Vector2, radius: float, time: float, source: Node}.
var noises: Array[Dictionary] = []
var time := 0.0
var depth_range := Vector2.ZERO
var pressure := 0
## Active zone event id (see [ZoneEvents]), or &"".
var event: StringName = &""
## Base water current for the "currents" event, in m/s.
var current := Vector2.ZERO
## Zone event effects, against the usual: how far creatures can see, how far
## a ping reaches, how fast creatures move and how fast the sub's cells drain.
var sight_scale := 1.0
var sonar_scale := 1.0
var creature_pace := 1.0
var drain_scale := 1.0
## Every flare currently burning (creatures that hunt light are drawn to them).
var flares: Array[Entity] = []
## Set once a sonar ping has reached the descent; the HUD compass then shows it.
var exit_known := false
## The final encounter, present only on the hadal floor.
var boss: ChoirBoss
## The lair guardian (the Lamplighter or the Blind Mother) where there is
## one; the exit stays sealed while it lives.
var guardian: Guardian
var exit_sealed := false
## Where scattered boulders near the play plane sit (see [PropScatter]), so
## things placed on the floor later can keep clear of them.
var boulders := PackedVector2Array()
## Floor that set pieces keep for themselves: no props are scattered there.
var clearings: Array[Rect2] = []
## The props that shut or lean aside as the sub passes (see [PropScatter]).
var prop_life: PropLife
var descent_marker: DescentMarker
## Set while a ping no hunter would follow is going out (see [method ping]).
var silent_ping := false
## How fast the ping under way travels (the echo's is slower).
var ping_speed := SONAR_SPEED

var _pending_remove: Array[Entity] = []
## The violet marks of the Choir's song on the creatures it holds.
var _hush_fx: HushFx
var _ping_slot := 0
var _exit_triggered := false
var _told_sealed := false


func build(zone_layout: LevelLayout, quality: int, pressure_level := 0, zone_event: StringName = &"") -> void:
	layout = zone_layout
	field = layout.field
	biome = layout.biome
	zone = layout.zone
	pressure = pressure_level
	rng.seed = layout.zone_seed ^ 0x5eed
	event = zone_event
	if event == &"currents":
		var a := (rng.randf() - 0.5) * PI * 0.8 + (0.0 if rng.randf() < 0.5 else PI)
		current = Vector2(cos(a), sin(a) * 0.4) * 2.6
	match event:
		&"silt":
			sight_scale = 0.5
		&"magnetic":
			sonar_scale = 0.55
		&"warm":
			creature_pace = 1.2
			drain_scale = 0.6
	depth_range = BiomeLibrary.zone_depth_range(zone)

	environment_rig = LevelEnvironment.new()
	add_child(environment_rig)
	if event == &"blackout":
		environment_rig.ambient_scale = 0.35
	elif event == &"bloom":
		environment_rig.ambient_scale = 1.35
	elif event == &"silt":
		environment_rig.fog_scale = 0.4
	environment_rig.setup(biome, layout.size())
	environment_rig.apply_quality(quality)

	terrain = TerrainRenderer.new()
	add_child(terrain)
	terrain.build(layout, quality)

	if layout.has_exit:
		descent_marker = DescentMarker.new()
		add_child(descent_marker)
		descent_marker.position = Vector3(layout.exit.x, layout.exit.y, 0.0)

	for i in 4:
		RenderingServer.global_shader_parameter_set(StringName("sonar_ping%d" % i), Vector4(0, 0, -100, 0))
	RenderingServer.global_shader_parameter_set(&"echo_ping", Vector4(0, 0, -100, 0))
	RenderingServer.global_shader_parameter_set(&"sonar_time", 0.0)


func size() -> Vector2:
	return layout.size()


## Water current at a point; banded so it reads as streams, not wind.
func current_at(p: Vector2) -> Vector2:
	var flow := Vector2.ZERO
	if current != Vector2.ZERO:
		flow = current * (0.55 + 0.45 * sin(p.y * 0.08 + time * 0.25))
	# The water rushing down into the way down sucks at whatever comes near.
	if layout and layout.has_exit and not exit_sealed:
		var to := layout.exit - p
		var dist := to.length()
		if dist < EXIT_PULL_RADIUS and dist > 0.01:
			flow += (to / dist + Vector2(0.0, -0.5)).normalized() * EXIT_PULL * pow(1.0 - dist / EXIT_PULL_RADIUS, 2.0)
	return flow


## Depth in meters shown on the HUD for a world-space height.
func depth_at(y: float) -> float:
	return lerpf(depth_range.x, depth_range.y, clampf(-y / size().y, 0.0, 1.0))


## 0 at the top of the biome, 1 at its bottom (drives water color).
func biome_progress(y: float) -> float:
	var part := float(zone % BiomeLibrary.ZONES_PER_BIOME)
	return (part + clampf(-y / size().y, 0.0, 1.0)) / BiomeLibrary.ZONES_PER_BIOME


func add_entity(e: Entity) -> Entity:
	e.level = self
	add_child(e)
	entities.append(e)
	e.setup()
	return e


func remove_entity(e: Entity) -> void:
	_pending_remove.append(e)


func tick(delta: float) -> void:
	time += delta
	RenderingServer.global_shader_parameter_set(&"sonar_time", time)
	var focus := player.pos if player else layout.start
	if prop_life and player:
		prop_life.tick(delta, player.pos, player.vel)
	for e in entities:
		if e.alive and e.pos.distance_squared_to(focus) < e.active_radius * e.active_radius:
			e.tick(delta)
			e.sync_transform()
	if not _pending_remove.is_empty():
		for e in _pending_remove:
			entities.erase(e)
			flares.erase(e)
		_pending_remove.clear()
	while not noises.is_empty() and time - noises[0].time > NOISE_LIFETIME:
		noises.pop_front()
	if player and environment_rig:
		environment_rig.update_depth(biome_progress(player.pos.y))
	if layout.has_exit and not exit_sealed and player and not _exit_triggered and player.alive \
			and player.pos.distance_to(layout.exit) < 5.0:
		_exit_triggered = true
		exit_reached.emit()
	elif exit_sealed and not _told_sealed and player and player.pos.distance_to(layout.exit) < 8.0:
		_told_sealed = true
		var who := guardian.title.capitalize() if is_instance_valid(guardian) else "Its guardian"
		Events.toast.emit("The way down is sealed. %s must fall first." % who, UiTheme.DANGER)


func seal_exit() -> void:
	exit_sealed = true
	if descent_marker:
		descent_marker.set_sealed(true)


func unseal_exit() -> void:
	exit_sealed = false
	if descent_marker:
		descent_marker.set_sealed(false)


func emit_noise(p: Vector2, radius: float, source: Node = null) -> void:
	if radius <= 0.5:
		return
	noises.append({"pos": p, "radius": radius, "time": time, "source": source})
	Events.noise_emitted.emit(p, radius, source)


## Loudest recent noise audible at [param p] (noise radius scaled by
## [param hearing]), ignoring noises made by [param ignore]. Returns null if none.
func loudest_noise_at(p: Vector2, hearing := 1.0, ignore: Node = null) -> Variant:
	var best: Variant = null
	var best_margin := 0.0
	for n in noises:
		if n.source == ignore:
			continue
		var margin: float = n.radius * hearing - p.distance_to(n.pos)
		if margin > best_margin:
			best_margin = margin
			best = n
	return best


## Fires a sonar ping: drives the terrain shader and marks entities in range.
## A [param silent] ping (a whale's clicks, the echo from below) charts and
## marks like any other, but no hunter turns towards it.
## [param echo]: the Hadal Trench's echo, drawn as its own slowed, violet
## wave (see sonar.gdshaderinc) and marking what it reaches at its own pace.
func ping(origin: Vector2, ping_range: float, mark_time: float, silent := false, echo := false) -> void:
	silent_ping = silent
	ping_speed = ECHO_SPEED if echo else SONAR_SPEED
	if echo:
		RenderingServer.global_shader_parameter_set(&"echo_ping", Vector4(origin.x, origin.y, time, ping_range))
	else:
		var slot := StringName("sonar_ping%d" % _ping_slot)
		_ping_slot = (_ping_slot + 1) % 4
		RenderingServer.global_shader_parameter_set(slot, Vector4(origin.x, origin.y, time, ping_range))
	for e in entities:
		if e.alive and e.pos.distance_to(origin) < ping_range:
			e.on_sonar(origin, mark_time)
	if layout.has_exit and not exit_known and origin.distance_to(layout.exit) < ping_range:
		exit_known = true
		var delay := origin.distance_to(layout.exit) / SONAR_SPEED
		get_tree().create_timer(delay).timeout.connect(func() -> void:
			Events.toast.emit("Sonar contact: the descent", UiTheme.GOOD)
			Audio.play(&"sonar_contact", -4.0))
	silent_ping = false
	ping_speed = SONAR_SPEED
	Events.sonar_pinged.emit(origin, ping_range)


## A pulse of the Choir's song rising from [param origin] (the echo, or the
## tone over Meridian Deep): every creature within [param reach] is hushed
## for a moment as the pulse passes it, turned down towards the song. Not
## the Choir's own, a guardian, or anything in a guardian's lair or the
## Choir's arena; and none while a boss fight is on.
func choir_wave(origin: Vector2, reach: float) -> void:
	if boss and boss.active or guardian and guardian.active:
		return
	for e in entities:
		var c := e as Creature
		if c == null or not c.alive or c.entranced or c is Guardian or c is ChoirOrgan or c is ChoirHeart:
			continue
		var d := c.pos.distance_to(origin)
		if d > reach or in_boss_room(c.pos):
			continue
		c.hush_at = time + d / ECHO_SPEED
		c.hush_end = c.hush_at + HUSH_TIME
		c.hush_from = origin
		if not c is Shoal:
			if _hush_fx == null:
				_hush_fx = HushFx.new()
				_hush_fx.level = self
				add_child(_hush_fx)
			_hush_fx.mark(c)


## Whether [param p] is in the Choir's arena or a guardian's lair.
func in_boss_room(p: Vector2) -> bool:
	for room: LevelLayout.Chamber in layout.chambers:
		if room.kind == &"arena" or (room.kind == &"exit" and guardian != null):
			var d := (p - room.center) / room.radius
			if d.length_squared() < 1.2:
				return true
	return false


func targets_in_radius(p: Vector2, r: float) -> Array[Entity]:
	var out: Array[Entity] = []
	for e in entities:
		if e.alive and e.targetable and e.pos.distance_squared_to(p) < (r + e.radius) * (r + e.radius):
			out.append(e)
	return out


## First targetable entity a segment passes through (for fast projectiles).
func first_target_on_segment(a: Vector2, b: Vector2, extra_radius := 0.0, ignore: Entity = null) -> Entity:
	var best: Entity = null
	var best_t := INF
	var ab := b - a
	var len2 := maxf(ab.length_squared(), 0.0001)
	for e in entities:
		if not e.alive or not e.targetable or e == ignore:
			continue
		var t := clampf((e.pos - a).dot(ab) / len2, 0.0, 1.0)
		var r := e.radius + extra_radius
		if (a + ab * t).distance_squared_to(e.pos) < r * r and t < best_t:
			best_t = t
			best = e
	return best
