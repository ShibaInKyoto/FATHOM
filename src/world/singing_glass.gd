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
## Obsidian blades round the seam's rim.
const BLADES := 20
const SHARDS := 34
const GLOW := Color(0.72, 0.55, 1.0)
const SHADER := preload("res://src/fx/shaders/obsidian.gdshader")

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
## The lens of glass sealing the way, and what is left of its rim once broken.
var _plug: MeshInstance3D
var _broken: MeshInstance3D
var _mat: ShaderMaterial
var _light: OmniLight3D
var _crack := 0.0
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


func _exit_tree() -> void:
	if Events.sonar_pinged.is_connected(_on_ping):
		Events.sonar_pinged.disconnect(_on_ping)


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


## The seam: a lens of black volcanic glass set into the rock across the
## way in, broken into big glossy fracture facets, bristling at its rim
## with blades of obsidian; and, hidden until it shatters, the jagged edge
## it will leave round the opening.
func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(wall)
	_rig = Node3D.new()
	_rig.top_level = true
	add_child(_rig)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter(&"glow_color", GLOW)
	_plug = MeshInstance3D.new()
	_plug.mesh = _lens(rng)
	_plug.material_override = _mat
	_rig.add_child(_plug)
	var rim := MeshInstance3D.new()
	rim.mesh = _blades(rng, false)
	rim.material_override = _mat
	_rig.add_child(rim)
	_broken = MeshInstance3D.new()
	_broken.mesh = _blades(rng, true)
	_broken.material_override = _mat
	_broken.visible = false
	_rig.add_child(_broken)
	_light = OmniLight3D.new()
	_light.light_color = GLOW
	_light.omni_range = 9.0
	var front := wall - normal * 1.2
	_light.position = Vector3(front.x, front.y, 2.0)
	_rig.add_child(_light)
	_apply()


## The seam's half-widths: across the way in, and along it.
func _half_size() -> Vector2:
	return Vector2(NECK_RADIUS + 0.4, WALL * 0.5 + 0.5)


## Where a point [param s] across the seam and [param d] along it (from its
## middle) lies, in the play plane.
func _seam_point(s: float, d: float) -> Vector2:
	return wall + normal * (WALL * 0.5 + d) + _tangent * s


## How far out of the rock towards the camera its face stands there.
func _rock_face(p: Vector2) -> float:
	var depth := -minf(level.field.sample(p), 0.0)
	return TerrainRenderer.ROCK_HEIGHT * tanh(depth / 2.0) - 0.15


## The lens: a dome over the seam's oval, flush with the rock at its edge,
## its face broken into a few big fracture planes (each a little curved, as
## glass breaks). UV: where on the oval (-1..1 across, -1..1 along).
func _lens(rng: RandomNumberGenerator) -> ArrayMesh:
	var half := _half_size()
	# The fracture planes: a seed point each, a tilt and a lift.
	var seeds := []
	for k in 11:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 0.85
		seeds.append([Vector2(cos(a), sin(a)) * r, Vector2(rng.randf_range(-0.9, 0.9), rng.randf_range(-0.8, 0.8)),
			rng.randf_range(-0.3, 0.3)])
	var rings := 14
	var around := 40
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in rings + 1:
		var r := float(i) / rings
		for j in around:
			var a := TAU * j / around
			var q := Vector2(cos(a), sin(a)) * r
			var p := _seam_point(q.x * half.x, q.y * half.y)
			# The nearest fracture plane shapes the face here.
			var best: Array = seeds[0]
			for sd: Array in seeds:
				if (sd[0] as Vector2).distance_squared_to(q) < (best[0] as Vector2).distance_squared_to(q):
					best = sd
			var off: Vector2 = q - best[0]
			var facet: float = best[2] + off.dot(best[1]) - off.length_squared() * 0.3
			var z := _rock_face(p) + (0.35 * (1.0 - r * r) + facet * (1.0 - pow(r, 3.0)))
			verts.append(Vector3(p.x, p.y, z))
			uvs.append(q)
	for i in rings:
		for j in around:
			var a := i * around + j
			var b := i * around + (j + 1) % around
			indices.append_array([a, a + around, b, b, a + around, b + around])
	return _commit(verts, uvs, indices)


## Blades of obsidian round the seam's rim, standing out of the rock and
## leaning outwards; or, [param broken], the jagged edge left round the
## opening once the glass has gone: slivers leaning in over the hole.
func _blades(rng: RandomNumberGenerator, broken: bool) -> ArrayMesh:
	var half := _half_size()
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var count := BLADES + (10 if broken else 0)
	for k in count:
		var a := TAU * (k + rng.randf_range(-0.3, 0.3)) / count
		var q := Vector2(cos(a), sin(a)) * rng.randf_range(0.9, 1.08)
		var foot2 := _seam_point(q.x * half.x, q.y * half.y)
		var foot := Vector3(foot2.x, foot2.y, _rock_face(foot2) - 0.2)
		var out := (_tangent * q.x + normal * q.y).normalized() * (-1.0 if broken else 1.0)
		var lean := rng.randf_range(0.2, 0.7) if not broken else rng.randf_range(0.5, 1.1)
		var dir := (Vector3(out.x, out.y, 0.0) * lean + Vector3(0.0, 0.0, 1.0)).normalized()
		var length := rng.randf_range(0.5, 1.4) * (0.7 if broken else 1.0)
		var width := length * rng.randf_range(0.18, 0.3)
		# A blade: a flat-faced shard narrowing to a point, a little twisted.
		var side := dir.cross(Vector3(out.x, out.y, 0.0) if out != Vector2.ZERO else Vector3.UP).normalized()
		side = side.rotated(dir, rng.randf_range(-0.6, 0.6))
		var thick := dir.cross(side).normalized() * width * 0.35
		var tip := foot + dir * length + side * width * rng.randf_range(-0.4, 0.4)
		var start := verts.size()
		for v: Vector3 in [foot - side * width, foot + side * width, foot + thick, foot - thick, tip]:
			verts.append(v)
			uvs.append(Vector2(q.x, q.y) * 1.2)
		for t: Array in [[0, 2, 4], [2, 1, 4], [1, 3, 4], [3, 0, 4], [0, 1, 2], [0, 3, 1]]:
			indices.append_array([start + t[0], start + t[1], start + t[2]])
	return _commit(verts, uvs, indices)


static func _commit(verts: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var st := SurfaceTool.new()
	st.create_from_arrays(arrays)
	st.generate_normals()
	return st.commit()


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
	# The second note sets cracks running through it.
	_crack = maxf(_crack, 0.45 if rings >= 2 else 0.0)
	Audio.play_at(&"glass_ring", pos, -4.0 + rings * 1.5, 0.0, CHORD[rings - 1])
	Fx.shockwave(level, pos, 2.5 + rings, GLOW, 0.6)
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
	_plug.visible = false
	_broken.visible = true
	var sub := level.player
	if sub and sub.alive:
		sub.run.research += RESEARCH
		sub.show_gain(RESEARCH, " research", UiTheme.ACCENT)
	Events.toast.emit("The chord shatters the glass. The chamber behind it lies open.", UiTheme.GOOD)


## The glass bursts: shards of it fly out of the seam towards the light,
## tumbling and glinting, still lit from within, and sink away.
func _burst() -> void:
	var half := _half_size()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(wall) + 9
	var shard_mat := ShaderMaterial.new()
	shard_mat.shader = SHADER
	shard_mat.set_shader_parameter(&"glow_color", GLOW)
	shard_mat.set_shader_parameter(&"ring", 0.9)
	var shapes: Array[ArrayMesh] = []
	for k in 4:
		shapes.append(_shard_mesh(rng))
	for k in SHARDS:
		var q := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf())
		var p := _seam_point(q.x * half.x, q.y * half.y)
		var mi := MeshInstance3D.new()
		mi.mesh = shapes[k % shapes.size()]
		mi.material_override = shard_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		level.add_child(mi)
		var start := Vector3(p.x, p.y, _rock_face(p) + 0.3)
		mi.global_position = start
		mi.scale = Vector3.ONE * rng.randf_range(0.25, 0.6)
		mi.rotation = Vector3(rng.randf(), rng.randf(), rng.randf()) * TAU
		# Out of the rock, towards the camera and away from the middle.
		var away := (_tangent * q.x + normal * q.y) * rng.randf_range(1.5, 4.0)
		var flight := Vector3(away.x, away.y + rng.randf_range(0.0, 2.0), rng.randf_range(1.0, 3.5))
		var time := rng.randf_range(1.6, 2.6)
		var tween := mi.create_tween().set_parallel(true)
		tween.tween_property(mi, ^"global_position", start + flight, time * 0.45).set_ease(Tween.EASE_OUT) \
			.set_trans(Tween.TRANS_CUBIC)
		# Then it sinks, slowly.
		tween.tween_property(mi, ^"global_position:y", start.y + flight.y - 2.5, time * 0.55).set_delay(time * 0.45) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
		tween.tween_property(mi, ^"rotation", mi.rotation + Vector3(rng.randf_range(-6, 6), rng.randf_range(-6, 6),
			rng.randf_range(-3, 3)), time)
		tween.tween_property(mi, ^"scale", Vector3.ONE * 0.01, 0.6).set_delay(time - 0.6)
		tween.chain().tween_callback(mi.queue_free)
	for k in 5:
		Fx.sparkle(level, _seam_point(lerpf(-half.x, half.x, k / 4.0), 0.0), GLOW)


## A shard of glass: a thin, sharp-edged flake.
static func _shard_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var outline := PackedVector2Array()
	var n := rng.randi_range(4, 6)
	for i in n:
		var a := TAU * i / n + rng.randf_range(-0.3, 0.3)
		outline.append(Vector2(cos(a) * rng.randf_range(0.4, 1.0), sin(a) * rng.randf_range(0.25, 0.6)))
	return MeshKit.fin(outline, 0.08)


func _apply() -> void:
	_mat.set_shader_parameter(&"crack", _crack)
	if shattered:
		_light.light_energy = 0.0
		_mat.set_shader_parameter(&"ring", 0.05 + 1.6 * _flare)
		return
	var ring := _ringing / RING_TIME
	var shimmer := 0.85 + 0.15 * sin(_t * (9.0 + rings * 4.0))
	var glow := 0.012 * (1.0 + sin(_t * 0.9)) + (0.35 + 0.35 * rings) * ring * shimmer + 1.6 * _flare
	_mat.set_shader_parameter(&"ring", glow)
	_mat.set_shader_parameter(&"note", float(maxi(rings, 1)))
	_mat.set_shader_parameter(&"ringing", ring)
	_light.light_energy = 0.05 + 0.9 * ring * rings + 2.0 * _flare
	# Ringing, the whole seam hums.
	var hum := 0.025 * ring * sin(_t * 70.0)
	_rig.position = Vector3(_tangent.x, _tangent.y, 0.0) * hum
