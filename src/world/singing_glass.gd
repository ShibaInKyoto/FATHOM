class_name SingingGlass
extends Entity
## In the first Abyssal Vents zone a seam of volcanic glass seals a chamber off
## the main tunnel, a cache glinting in the dark behind it. Glass rings at its
## own note (log_06: "sing the right note at a wine glass and it shatters"):
## every sonar ping that reaches it sets it ringing, and pinged again while it
## still rings it rings higher. Three in a row, a rising chord, and it
## shatters, opening the way in. The Choir asks the same of the sub at the
## bottom: answer it, and keep answering.

const ZONE := BiomeLibrary.FURNACE_ZONE - 1
## How long it rings after a ping reaches it: the next ping must land within this.
const RING_TIME := 6.5
## The chord it rings, as pitch scales of its note: a major triad.
const CHORD: Array[float] = [1.0, 1.26, 1.5]
## Chamber sizes to try, largest first.
const POCKET_SIZES: Array[float] = [4.0, 3.2, 2.7]
## The rock between the tunnel and the chamber: the glass seam.
const WALL := 2.2
const NECK_RADIUS := 2.2
const OPEN_TIME := 0.9
const RESEARCH := 8
## Flakes of glass the chord bursts it into.
const SHARDS := 26
const GLOW := Color(0.72, 0.55, 1.0)
const SHARD_SHADER := preload("res://src/fx/shaders/obsidian.gdshader")
## How far round the neck the glass seam reaches: across the way in, and
## beyond the rock on either face of it.
const SEAM_MARGIN := Vector2(1.0, 0.9)

## Hints shown once per session: on first coming near, and on the first ring.
static var _explained := false
static var _ring_explained := false

## Where the seam meets the tunnel, and the way into the rock from there.
var wall: Vector2
var normal: Vector2
var chamber: Vector2
var pocket_radius := 4.0
var rings := 0
var shattered := false
var _tangent: Vector2
var _lobe := Vector2.INF
var _ringing := 0.0
var _flare := 0.0
var _arrivals := PackedFloat32Array()
var _neck: TrenchShift.Morph
var _open := -1.0
var _rig: Node3D
var _light: OmniLight3D
## Where the last note struck the glass (metres across and along the seam
## from its centre) and when; when it cracked (-1 not yet).
var _strike := Vector2.ZERO
var _strike_time := -100.0
var _crack_time := -1.0
var _t := 0.0


## Seals a chamber off a straight stretch of the main tunnel; returns the
## glass, or null if the rock nowhere along it will hold one.
static func place(level: Level, rng: RandomNumberGenerator, avoid: PackedVector2Array) -> SingingGlass:
	var path := level.layout.main_path
	if path.size() < 12:
		return null
	# The middle of the zone first; then anywhere but its ends.
	var middle := _shuffled(int(path.size() * 0.25), int(path.size() * 0.75), rng)
	var wide := _shuffled(int(path.size() * 0.12), int(path.size() * 0.88), rng)
	for size_r in POCKET_SIZES:
		for order in [middle, wide]:
			for i: int in order:
				var glass := _site(level, i, avoid, size_r)
				if glass:
					level.add_entity(glass)
					return glass
	return null


static func _shuffled(from: int, to: int, rng: RandomNumberGenerator) -> Array[int]:
	var order: Array[int] = []
	for i in range(from, to):
		order.append(i)
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp := order[i]
		order[i] = order[j]
		order[j] = tmp
	return order


## A seam beside main-path point [param i] sealing a chamber of radius
## [param pocket_r], or null if the rock there will not hold one.
static func _site(level: Level, i: int, avoid: PackedVector2Array, pocket_r: float) -> SingingGlass:
	var layout := level.layout
	var path := layout.main_path
	var field := level.field
	var size := layout.size()
	var p := path[i]
	var tangent := (path[mini(i + 2, path.size() - 1)] - path[maxi(i - 2, 0)]).normalized()
	var sides: Array[float] = [1.0, -1.0]
	if i % 2 == 1:
		sides.reverse()
	for side in sides:
		var n := tangent.orthogonal() * side
		var reach := 0.0
		while reach < 12.0 and field.sample(p + n * reach) > 0.3:
			reach += 0.5
		if reach >= 12.0 or reach < 1.5:
			continue
		var wall_at := p + n * reach
		var c := wall_at + n * (pocket_r + WALL)
		var margin := pocket_r + 3.0
		if c.x < margin or c.x > size.x - margin or c.y > -margin or c.y < -(size.y - margin):
			continue
		# Solid all round but for the seam, so the chamber opens only into this tunnel.
		if field.sample(c) > -(pocket_r + WALL - 0.4):
			continue
		# A flat face of rock: open water all along the front of the seam.
		if field.sample(wall_at - n * 1.2 + tangent * 1.8) < 0.3 or field.sample(wall_at - n * 1.2 - tangent * 1.8) < 0.3:
			continue
		if c.distance_to(layout.start) < 25.0 or c.distance_to(layout.exit) < 20.0:
			continue
		# Clear of anything placed on the wall the neck will open through.
		if LevelPopulator.in_guarded_room(level, c) or _near_any(wall_at, avoid, 7.0) or _near_any(c, avoid, 7.0):
			continue
		var glass := SingingGlass.new()
		glass.wall = wall_at
		glass.normal = n
		glass.chamber = c
		glass.pocket_radius = pocket_r
		glass._tangent = tangent
		var lobe := c + tangent * 2.0 + n * 1.0
		if field.sample(lobe) < -(pocket_r * 0.7 + 1.2):
			glass._lobe = lobe
		glass.pos = wall_at + n * (WALL * 0.5)
		return glass
	return null


static func _near_any(p: Vector2, points: PackedVector2Array, dist: float) -> bool:
	for q in points:
		if q.distance_squared_to(p) < dist * dist:
			return true
	return false


func setup() -> void:
	radius = 0.0
	active_radius = 120.0
	_carve_chamber()
	_furnish()
	_build()
	Events.sonar_pinged.connect(_on_ping)


## Hollows out the sealed chamber behind the seam.
func _carve_chamber() -> void:
	var shapes: Array[Array] = [[chamber, chamber, pocket_radius]]
	if _lobe != Vector2.INF:
		shapes.append([_lobe, _lobe, pocket_radius * 0.7])
	var m := TrenchShift.build_morph(level.field, shapes, false)
	_blend(m, 1.0)
	Events.terrain_changed.emit(m.bounds)


func _blend(m: TrenchShift.Morph, k: float) -> void:
	var values := PackedFloat32Array()
	values.resize(m.changed.size())
	for j in values.size():
		values[j] = m.from[j] + m.delta[j] * k
	level.field.write_indices(m.changed, values)
	if level.terrain:
		level.terrain.refresh_cells(level.field, m.changed)


## A cache waits in the chamber, lit by a glow bulb on its floor.
func _furnish() -> void:
	var cache := SalvageCache.new()
	cache.pos = chamber
	cache.salvage = int(level.rng.randi_range(9, 13) * (1.0 + level.zone * 0.35))
	cache.rich = true
	level.add_entity(cache)
	var floor_y := MeridianStation.floor_below(level.field, chamber, pocket_radius + 1.5)
	if floor_y != -INF:
		var bulb := GlowBulb.new()
		bulb.pos = Vector2(chamber.x + 1.2, floor_y + 0.5)
		# World +y is up.
		bulb.normal = Vector2(0.0, 1.0)
		bulb.color = GLOW
		level.add_entity(bulb)


## The seam itself is drawn by the terrain (see terrain.gdshader): the rock
## there fused black and smooth, then obsidian, so the glass is part of the
## wall rather than set on it. Here: the light it casts as it rings.
func _build() -> void:
	_rig = Node3D.new()
	_rig.top_level = true
	add_child(_rig)
	_light = OmniLight3D.new()
	_light.light_color = GLOW
	_light.omni_range = 9.0
	var front := wall - normal * 1.2
	_light.position = Vector3(front.x, front.y, 2.0)
	_rig.add_child(_light)
	if level.terrain:
		var m := level.terrain.material
		m.set_shader_parameter(&"glass_seam", Vector4(pos.x, pos.y, NECK_RADIUS + SEAM_MARGIN.x,
			WALL * 0.5 + SEAM_MARGIN.y))
		m.set_shader_parameter(&"glass_axis", Vector4(_tangent.x, _tangent.y, normal.x, normal.y))
		m.set_shader_parameter(&"glass_color", GLOW)
	_apply()


func _exit_tree() -> void:
	if Events.sonar_pinged.is_connected(_on_ping):
		Events.sonar_pinged.disconnect(_on_ping)
	if level and is_instance_valid(level.terrain):
		level.terrain.material.set_shader_parameter(&"glass_seam", Vector4.ZERO)


## Where a point [param s] across the seam and [param d] along it (from its
## middle) lies, in the play plane.
func _seam_point(s: float, d: float) -> Vector2:
	return pos + _tangent * s + normal * d


## [param p] in the seam's own terms: metres across and along from its middle.
func _seam_local(p: Vector2) -> Vector2:
	var d := p - pos
	return Vector2(d.dot(_tangent), d.dot(normal))


func _on_ping(origin: Vector2, ping_range: float) -> void:
	# Only the sub's own sonar is a note it answers.
	var sub := level.player
	if sub == null or origin.distance_to(sub.pos) > 1.5:
		return
	var d := origin.distance_to(pos)
	if shattered or d > ping_range:
		return
	_arrivals.append(level.time + d / Level.SONAR_SPEED)


func tick(delta: float) -> void:
	_t += delta
	var sub := level.player
	if not _explained and not shattered and sub and sub.alive and sub.pos.distance_to(pos) < 18.0:
		_explained = true
		Events.toast.emit("Volcanic glass seals off a chamber here. Glass sings back - try your sonar on it.",
			UiTheme.ACCENT)
	var now := level.time
	var k := 0
	while k < _arrivals.size():
		if _arrivals[k] <= now:
			_arrivals.remove_at(k)
			_ring()
		else:
			k += 1
	if _ringing > 0.0:
		_ringing = maxf(_ringing - delta, 0.0)
		if _ringing == 0.0 and not shattered:
			rings = 0
	_flare = maxf(_flare - delta * 2.5, 0.0)
	if _open >= 0.0:
		_open = minf(_open + delta / OPEN_TIME, 1.0)
		_blend(_neck, smoothstep(0.0, 1.0, _open))
		if _open >= 1.0:
			_open = -1.0
			Events.terrain_changed.emit(_neck.bounds)
	_apply()


## A ping has reached the glass: it rings, a note higher if it was still ringing.
func _ring() -> void:
	if shattered:
		return
	rings = rings + 1 if _ringing > 0.0 else 1
	_ringing = RING_TIME
	_flare = 1.0
	# The note strikes the face of the glass towards the sub.
	var sub_at := level.player.pos if level.player else wall - normal * 4.0
	var half := Vector2(NECK_RADIUS, WALL * 0.5) * 0.7
	var towards := _seam_local(sub_at)
	_strike = towards.normalized() * minf(towards.length(), 1.0) * half if towards != Vector2.ZERO else Vector2.ZERO
	_strike_time = level.time
	# The second note sets cracks running through it from there.
	if rings == 2:
		_crack_time = level.time
	Audio.play_at(&"glass_ring", pos, -4.0 + rings * 1.5, 0.0, CHORD[rings - 1])
	Fx.shockwave(level, pos, 2.0 + rings * 0.7, GLOW, 0.35)
	if rings >= CHORD.size():
		_shatter()
		return
	var sub := level.player
	if sub and sub.alive and sub.pos.distance_to(pos) < 45.0:
		if rings == 1 and not _ring_explained:
			_ring_explained = true
			Events.toast.emit("The glass rings! Ping again before it falls silent.", UiTheme.ACCENT)
		elif rings == 2:
			Events.toast.emit("It rings higher. Once more!", UiTheme.ACCENT)


func _shatter() -> void:
	shattered = true
	_arrivals.clear()
	Wonders.witness("glass")
	_neck = TrenchShift.build_morph(level.field, [[wall - normal * 1.0, chamber, NECK_RADIUS]], false)
	_open = 0.0
	Audio.play_at(&"glass_shatter", pos, 2.0, 0.0)
	level.emit_noise(pos, 20.0, self)
	Fx.flash(level, pos, GLOW, 14.0, 0.5)
	Fx.shockwave(level, pos, 7.0, GLOW, 0.7)
	_burst()
	Events.shake_requested.emit(0.45)
	Settings.rumble_pulse(0.3, 0.4)
	var sub := level.player
	if sub and sub.alive:
		sub.run.research += RESEARCH
		sub.show_gain(RESEARCH, " research", UiTheme.ACCENT)
	Events.toast.emit("The chord shatters the glass. The chamber behind it lies open.", UiTheme.GOOD)


## The glass bursts: curved flakes of it fly out of the seam towards the
## light, tumbling and flashing as they turn, lit from within and cooling as
## they go, and sink away.
func _burst() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(wall) + 9
	var shapes: Array[ArrayMesh] = []
	for k in 5:
		shapes.append(_shard_mesh(rng))
	for k in SHARDS:
		var q := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf())
		var p := _seam_point(q.x * NECK_RADIUS, q.y * WALL * 0.5)
		var mi := MeshInstance3D.new()
		mi.mesh = shapes[k % shapes.size()]
		var m := ShaderMaterial.new()
		m.shader = SHARD_SHADER
		m.set_shader_parameter(&"glow_color", GLOW)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		level.add_child(mi)
		var start := Vector3(p.x, p.y, 1.6 + rng.randf_range(0.0, 0.6))
		mi.global_position = start
		var size := rng.randf_range(0.18, 0.5) * (1.6 if k < 4 else 1.0)
		mi.scale = Vector3.ONE * size
		mi.rotation = Vector3(rng.randf(), rng.randf(), rng.randf()) * TAU
		# Out of the rock, towards the camera and away from the middle.
		var away := (_tangent * q.x + normal * q.y) * rng.randf_range(1.5, 4.5)
		var flight := Vector3(away.x, away.y + rng.randf_range(0.0, 1.5), rng.randf_range(1.5, 4.0))
		var time := rng.randf_range(2.0, 3.2)
		var tween := mi.create_tween().set_parallel(true)
		tween.tween_property(mi, ^"global_position", start + flight, time * 0.4).set_ease(Tween.EASE_OUT) \
			.set_trans(Tween.TRANS_CUBIC)
		# Then it sinks, slowly, rocking as it goes.
		tween.tween_property(mi, ^"global_position:y", start.y + flight.y - 2.2, time * 0.6).set_delay(time * 0.4) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		var spin := Vector3(rng.randf_range(-7, 7), rng.randf_range(-7, 7), rng.randf_range(-4, 4))
		tween.tween_property(mi, ^"rotation", mi.rotation + spin, time).set_ease(Tween.EASE_OUT) \
			.set_trans(Tween.TRANS_QUAD)
		# Lit from within, then cooling to black glass.
		tween.tween_method(func(v: float) -> void: m.set_shader_parameter(&"ring", v), 1.6, 0.0, time * 0.45) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
		tween.tween_property(mi, ^"scale", Vector3.ONE * 0.001, 0.5).set_delay(time - 0.5)
		tween.chain().tween_callback(mi.queue_free)
	for k in 5:
		Fx.sparkle(level, _seam_point(lerpf(-NECK_RADIUS, NECK_RADIUS, k / 4.0), 0.0), GLOW)


## A flake of obsidian: a few straight broken edges round a curved, thin
## shell, thickest in the middle and sharp at its edge (about a metre across
## before scaling, its convex face towards +Z).
static func _shard_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	# The outline: corners at uneven angles and reaches, joined straight.
	var corners := rng.randi_range(4, 6)
	var angles: Array[float] = []
	for i in corners:
		angles.append(TAU * (i + rng.randf_range(-0.3, 0.3)) / corners)
	var reach: Array[float] = []
	for i in corners:
		reach.append(rng.randf_range(0.45, 1.0))
	var outline := PackedVector2Array()
	var per_edge := 4
	for i in corners:
		var a := Vector2.from_angle(angles[i]) * reach[i]
		var b := Vector2.from_angle(angles[(i + 1) % corners]) * reach[(i + 1) % corners]
		for k in per_edge:
			outline.append(a.lerp(b, float(k) / per_edge))
	var bend := rng.randf_range(0.14, 0.26)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var rings := 3
	var n := outline.size()
	for face in 2:
		var sgn := 1.0 if face == 0 else -1.0
		var start := verts.size()
		verts.append(Vector3(0.0, 0.0, bend * 0.5 + 0.05 * sgn))
		normals.append(Vector3(0.0, 0.0, sgn))
		uvs.append(Vector2.ZERO)
		for i in range(1, rings + 1):
			var r := float(i) / rings
			for j in n:
				var p := outline[j] * r
				var d2 := p.length_squared()
				var z := bend * 0.5 * (1.0 - d2) + 0.05 * (1.0 - r * r) * sgn
				verts.append(Vector3(p.x, p.y, z))
				normals.append(Vector3(p.x * bend * sgn, p.y * bend * sgn, sgn).normalized())
				uvs.append(Vector2(r, 0.0))
		for j in n:
			var j1 := (j + 1) % n
			indices.append_array([start, start + 1 + j, start + 1 + j1])
			for i in rings - 1:
				var a := start + 1 + i * n
				var b := a + n
				indices.append_array([a + j, b + j, b + j1, a + j, b + j1, a + j1])
	# (Drawn from both sides: obsidian.gdshader culls nothing.)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _apply() -> void:
	var ring := _ringing / RING_TIME
	var shimmer := 0.85 + 0.15 * sin(_t * (9.0 + rings * 4.0))
	var glow := (0.25 + 0.3 * rings) * ring * shimmer + 1.4 * _flare
	if shattered:
		glow = 1.4 * _flare
	_light.light_energy = (0.9 * ring * rings + 2.0 * _flare) if not shattered else 2.0 * _flare
	if level.terrain == null:
		return
	var m := level.terrain.material
	m.set_shader_parameter(&"glass_ring", Vector4(glow, ring if not shattered else 0.0, float(maxi(rings, 1)),
		1.0 if shattered else 0.0))
	m.set_shader_parameter(&"glass_strike", Vector4(_strike.x, _strike.y, _strike_time, _crack_time))
