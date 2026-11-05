class_name LevelGenerator
extends RefCounted
## Procedurally generates one zone of the trench.
##
## The cave is built as a distance field: everything starts as solid rock and
## tunnels, chambers and shafts are carved with smooth-min SDF operations, so
## the result is (approximately) a true distance field without a separate
## distance transform. Noise then erodes the walls, a flood fill marks what the
## submarine can actually reach, and points of interest are collected.
##
## Pure data: safe to run on a worker thread.

const CELL := 0.5
## Distances deeper into the rock than this are clamped (meters).
const ROCK_CAP := 6.0
## Clearance the submarine needs to pass through a gap (meters).
const SUB_CLEARANCE := 1.15
const MARGIN := 14.0
const SMOOTH := 2.5
## Wall noise can pinch the main tunnel after it is carved; this much
## clearance (sub radius 1.15) is restored along the route afterwards.
const MIN_CORRIDOR := 2.2
## How a zone may be laid out, beyond the first zone and the guardians'
## (always classic): the classic zigzag; one great hall in the middle of the
## way down; a braid, where the way splits round a mass of rock and joins
## again; a shaft, dropping almost straight down past ledges.
const STYLES: Array[StringName] = [&"classic", &"classic", &"hall", &"braid", &"shaft"]
## A guardian's lair: its size, and how far its walls stay from the zone's
## sides (the solid rim would otherwise cut a straight wall through it).
const LAIR_ROOM := Vector2(25.0, 14.0)
const LAIR_SIDE_GAP := 10.0
## The part of a lair (as a share of its size) kept clear of every lump,
## spire and pillar, so its guardian can move through all of it.
const LAIR_CLEAR := 0.9

var _rng := RandomNumberGenerator.new()
var _w := 0
var _h := 0
## Distance to open water; positive inside rock. Negated into the final field.
var _rock := PackedFloat32Array()


## Generates a zone. Retries with derived seeds until the exit is reachable.
func generate(biome: BiomeDef, zone_seed: int, zone: int) -> LevelLayout:
	var layout: LevelLayout = null
	for attempt in 8:
		layout = _try_generate(biome, zone_seed + attempt * 7919, zone)
		if layout.is_reachable(layout.exit):
			layout.zone_seed = zone_seed
			return layout
	push_warning("LevelGenerator: exit unreachable after retries (seed %d)" % zone_seed)
	return layout


func _try_generate(biome: BiomeDef, zone_seed: int, zone: int) -> LevelLayout:
	_rng.seed = zone_seed
	var layout := LevelLayout.new()
	layout.biome = biome
	layout.zone = zone
	if BiomeLibrary.is_final_zone(zone):
		return _generate_arena(layout)

	var size := Vector2(_rng.randi_range(biome.zone_width.x, biome.zone_width.y),
		biome.zone_height + _rng.randi_range(-10, 20))
	_w = int(size.x / CELL) + 1
	_h = int(size.y / CELL) + 1
	_rock = PackedFloat32Array()
	_rock.resize(_w * _h)
	_rock.fill(ROCK_CAP)

	if zone > 0 and not BiomeLibrary.is_lair(zone):
		layout.style = STYLES[_rng.randi() % STYLES.size()]
	var waypoints := _plan_main_path(size, layout.style)
	var lair := BiomeLibrary.is_lair(zone)
	var exit_r := LAIR_ROOM if lair else Vector2(10.0, 7.0)
	if lair:
		# The lair stays clear of the zone's sides.
		var last := waypoints.size() - 1
		var lo := exit_r.x + LAIR_SIDE_GAP
		var hi := size.x - exit_r.x - LAIR_SIDE_GAP
		if hi > lo:
			waypoints[last] = Vector2(clampf(waypoints[last].x, lo, hi), waypoints[last].y)
	layout.start = waypoints[0]
	var exit_room := waypoints[waypoints.size() - 1]

	# Entry chamber and the shaft we descended through.
	_carve_ellipse(layout.start, Vector2(9.0, 7.0))
	_carve_capsule(layout.start, Vector2(layout.start.x, 3.0), 3.4, 4.2)
	layout.chambers.append(LevelLayout.Chamber.new(layout.start, Vector2(9.0, 7.0), &"spawn"))

	# Main tunnel along a Catmull-Rom spline through the waypoints.
	layout.main_path = _spline(waypoints, 3.0)
	_carve_path(layout.main_path, biome.tunnel_radius)

	for i in range(1, waypoints.size() - 1):
		if _rng.randf() < biome.chamber_chance:
			var r := Vector2(_rng.randf_range(biome.chamber_radius.x, biome.chamber_radius.y), 0.0)
			r.y = r.x * _rng.randf_range(0.55, 0.8)
			_carve_ellipse(waypoints[i], r)
			layout.chambers.append(LevelLayout.Chamber.new(waypoints[i], r, &"main"))
			if r.x > 13.0 and _rng.randf() < biome.pillar_chance:
				_try_add_pillar(layout.main_path, waypoints[i], r)

	match layout.style:
		&"hall":
			_carve_hall(layout, waypoints, size, biome)
		&"braid":
			_carve_braid(layout, waypoints, size, biome)
		&"shaft":
			_carve_ledges(layout, waypoints, size)

	# The exit: a room with a fissure dropping out of the bottom of the zone.
	_carve_ellipse(exit_room, exit_r)
	layout.chambers.append(LevelLayout.Chamber.new(exit_room, exit_r, &"exit"))
	_carve_capsule(exit_room, Vector2(exit_room.x, -size.y - 4.0), 3.6, 2.8)
	layout.exit = Vector2(exit_room.x, exit_room.y - exit_r.y - 4.0)

	_carve_branches(layout, waypoints, size, biome)
	_add_spires(layout, biome)
	_erode(biome, PackedFloat32Array([layout.start.x, exit_room.x]))
	if lair:
		# Erosion, and the spires and pillars of rooms next door, can leave rock
		# standing inside a lair, where its guardian would snag or even start
		# buried: clear all but its rim again.
		_carve_ellipse(exit_room, exit_r * LAIR_CLEAR)
	_keep_route_open(layout, exit_room)
	_build_field(layout)
	_flood_reachable(layout)
	_collect_anchors(layout)
	return layout


## The hadal floor: a short descent into one vast chamber where the Choir
## waits. There is no exit; the zone ends when the encounter does.
func _generate_arena(layout: LevelLayout) -> LevelLayout:
	var size := Vector2(150, 175)
	_w = int(size.x / CELL) + 1
	_h = int(size.y / CELL) + 1
	_rock = PackedFloat32Array()
	_rock.resize(_w * _h)
	_rock.fill(ROCK_CAP)
	layout.start = Vector2(size.x * 0.5 + _rng.randf_range(-12, 12), -10.0)
	var arena := Vector2(size.x * 0.5, -112.0)
	var arena_r := Vector2(40.0, 30.0)
	_carve_ellipse(layout.start, Vector2(9.0, 7.0))
	_carve_capsule(layout.start, Vector2(layout.start.x, 3.0), 3.4, 4.2)
	layout.chambers.append(LevelLayout.Chamber.new(layout.start, Vector2(9.0, 7.0), &"spawn"))
	var mid := Vector2(size.x * 0.5 + _rng.randf_range(-25, 25), -45.0)
	var waypoints := PackedVector2Array([layout.start, mid, arena + Vector2(0, arena_r.y * 0.6)])
	layout.main_path = _spline(waypoints, 3.0)
	_carve_path(layout.main_path, Vector2(5.0, 7.5))
	_carve_ellipse(mid, Vector2(13.0, 9.0))
	layout.chambers.append(LevelLayout.Chamber.new(mid, Vector2(13.0, 9.0), &"loot"))
	# A flat-floored gallery off the middle chamber, away from the way down,
	# where the ruins of Meridian Deep stand.
	var side := 1.0 if mid.x >= size.x * 0.5 else -1.0
	_carve_capsule(mid + Vector2(side * 6.0, -2.0), mid + Vector2(side * 33.0, -2.0), 6.0, 6.0)
	layout.chambers.append(LevelLayout.Chamber.new(mid + Vector2(side * 20.0, -2.0), Vector2(14.0, 6.0), &"station"))
	_carve_ellipse(arena, arena_r)
	layout.chambers.append(LevelLayout.Chamber.new(arena, arena_r, &"arena"))
	# A few broken columns of rock for cover.
	for i in 3:
		var c := arena + Vector2((i - 1) * 24.0 + _rng.randf_range(-3, 3), -arena_r.y * 0.55)
		_add_rock_capsule(c, c + Vector2(_rng.randf_range(-2, 2), _rng.randf_range(5, 9)), 2.4, 0.8)
	# The "exit" is the arena itself: the retry loop checks it is reachable.
	layout.exit = arena
	layout.has_exit = false
	_erode(layout.biome, PackedFloat32Array([layout.start.x]))
	_build_field(layout)
	_flood_reachable(layout)
	_collect_anchors(layout)
	return layout


# --- Layout planning -------------------------------------------------------

## Re-opens a comfortable corridor along the main route wherever erosion or
## spires pinched it (pillars are placed clear of the route to begin with).
func _keep_route_open(layout: LevelLayout, exit_room: Vector2) -> void:
	var path := layout.main_path
	for i in range(1, path.size()):
		_carve_capsule(path[i - 1], path[i], MIN_CORRIDOR, MIN_CORRIDOR, 1.0)
	_carve_capsule(exit_room, layout.exit, MIN_CORRIDOR, MIN_CORRIDOR, 1.0)


func _plan_main_path(size: Vector2, style: StringName) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var x := size.x * _rng.randf_range(0.35, 0.65)
	var y := -10.0
	pts.append(Vector2(x, y))
	while y > -(size.y - 40.0):
		y -= _rng.randf_range(20.0, 32.0)
		var dx := _rng.randf_range(-36.0, 36.0)
		if style == &"shaft":
			# Straight down, near enough, with a little lean.
			dx = _rng.randf_range(-9.0, 9.0)
		elif absf(dx) < 10.0:
			dx = signf(dx + 0.001) * 10.0
		x = clampf(x + dx, MARGIN + 4.0, size.x - MARGIN - 4.0)
		pts.append(Vector2(x, y))
	x = clampf(x + _rng.randf_range(-16.0, 16.0), MARGIN + 6.0, size.x - MARGIN - 6.0)
	pts.append(Vector2(x, -(size.y - 22.0)))
	return pts


func _carve_branches(layout: LevelLayout, waypoints: PackedVector2Array, size: Vector2,
		biome: BiomeDef) -> void:
	var count := _rng.randi_range(biome.branch_count.x, biome.branch_count.y)
	for _b in count:
		var i := _rng.randi_range(1, waypoints.size() - 2)
		var origin := waypoints[i]
		var side := 1.0 if origin.x < size.x * 0.5 else -1.0
		if _rng.randf() < 0.25:
			side = -side
		var end := origin + Vector2(side * _rng.randf_range(20.0, 40.0), _rng.randf_range(-14.0, 14.0))
		end.x = clampf(end.x, MARGIN + 6.0, size.x - MARGIN - 6.0)
		end.y = clampf(end.y, -(size.y - MARGIN - 8.0), -(MARGIN + 6.0))
		if end.distance_to(origin) < 14.0:
			continue
		var mid := (origin + end) * 0.5 + (end - origin).orthogonal().normalized() * _rng.randf_range(-8.0, 8.0)
		var path := _spline(PackedVector2Array([origin, mid, end]), 2.5)
		_carve_path(path, Vector2(3.2, 4.8))
		var r := Vector2(_rng.randf_range(7.0, 11.0), 0.0)
		r.y = r.x * _rng.randf_range(0.6, 0.85)
		_carve_ellipse(end, r)
		layout.chambers.append(LevelLayout.Chamber.new(end, r, &"loot"))
		# Occasionally loop back into the main path further down.
		if _rng.randf() < 0.3 and i + 1 < waypoints.size() - 1:
			var back := _spline(PackedVector2Array([end, (end + waypoints[i + 1]) * 0.5
					+ Vector2(0, _rng.randf_range(-6, 6)), waypoints[i + 1]]), 2.5)
			_carve_path(back, Vector2(3.0, 4.2))


## One great cavern on the way down, far bigger than the biome's rooms, with
## columns standing in it.
func _carve_hall(layout: LevelLayout, waypoints: PackedVector2Array, size: Vector2, biome: BiomeDef) -> void:
	var m := waypoints.size() / 2
	var r := Vector2(biome.chamber_radius.y * 1.55, 0.0)
	r.x = minf(r.x, size.x * 0.5 - MARGIN - 2.0)
	r.y = r.x * _rng.randf_range(0.55, 0.68)
	var center := waypoints[m]
	center.x = clampf(center.x, MARGIN + r.x + 1.0, size.x - MARGIN - r.x - 1.0)
	_carve_ellipse(center, r)
	# The way through still runs through the middle of it.
	_carve_capsule(waypoints[m], center, biome.tunnel_radius.x, biome.tunnel_radius.x)
	layout.chambers.append(LevelLayout.Chamber.new(center, r, &"main"))
	for _i in 3:
		_try_add_pillar(layout.main_path, center, r)


## The way splits round a mass of rock and joins again further down: a second
## route between two waypoints, swinging wide to one side, with a room on it.
func _carve_braid(layout: LevelLayout, waypoints: PackedVector2Array, size: Vector2, biome: BiomeDef) -> void:
	if waypoints.size() < 4:
		return
	var i := _rng.randi_range(1, waypoints.size() - 3)
	var a := waypoints[i]
	var b := waypoints[i + 2]
	var mid := waypoints[i + 1]
	var line_mid := (a + b) * 0.5
	# Swing away from the side the main route bulges to.
	var side := -signf(mid.x - line_mid.x + 0.001)
	var alt := Vector2(line_mid.x + side * _rng.randf_range(22.0, 30.0), line_mid.y + _rng.randf_range(-4.0, 4.0))
	if alt.x < MARGIN + 8.0 or alt.x > size.x - MARGIN - 8.0:
		alt.x = line_mid.x - side * _rng.randf_range(22.0, 30.0)
	alt.x = clampf(alt.x, MARGIN + 8.0, size.x - MARGIN - 8.0)
	var path := _spline(PackedVector2Array([a, alt, b]), 2.5)
	_carve_path(path, biome.tunnel_radius * 0.85)
	var r := Vector2(_rng.randf_range(7.0, 10.0), 0.0)
	r.y = r.x * 0.7
	_carve_ellipse(alt, r)
	layout.chambers.append(LevelLayout.Chamber.new(alt, r, &"loot"))


## Ledges off the sides of a shaft, each a little room of its own.
func _carve_ledges(layout: LevelLayout, waypoints: PackedVector2Array, size: Vector2) -> void:
	for i in range(1, waypoints.size() - 1):
		if _rng.randf() > 0.6:
			continue
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var at := waypoints[i] + Vector2(side * _rng.randf_range(11.0, 15.0), _rng.randf_range(-3.0, 1.0))
		if at.x < MARGIN + 6.0 or at.x > size.x - MARGIN - 6.0:
			# No room that side: the other.
			at.x = clampf(2.0 * waypoints[i].x - at.x, MARGIN + 6.0, size.x - MARGIN - 6.0)
		var r := Vector2(_rng.randf_range(5.0, 7.0), _rng.randf_range(3.2, 4.2))
		_carve_capsule(waypoints[i], at, 2.6, 2.6)
		_carve_ellipse(at, r)
		layout.chambers.append(LevelLayout.Chamber.new(at, r, &"loot"))


## Stands a rock column in a wide room, off to one side of the main route so
## the way through stays open. Gives up if no placement leaves enough room.
func _try_add_pillar(route: PackedVector2Array, room_center: Vector2, room_radius: Vector2) -> void:
	for _attempt in 4:
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var center := room_center + Vector2(side * _rng.randf_range(0.35, 0.65) * room_radius.x, 0.0)
		var top := center + Vector2(_rng.randf_range(-2, 2), room_radius.y + 2.0)
		var bottom := center + Vector2(_rng.randf_range(-2, 2), -room_radius.y - 2.0)
		var r := _rng.randf_range(1.6, 2.6)
		if _route_distance(route, top, bottom) > r * 1.4 + MIN_CORRIDOR + 0.5:
			_add_rock_capsule(top, bottom, r * 1.4, r)
			return


static func _route_distance(route: PackedVector2Array, a: Vector2, b: Vector2) -> float:
	var best := INF
	for p in route:
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return best


## Stalactites and stalagmites hanging into the larger rooms.
func _add_spires(layout: LevelLayout, biome: BiomeDef) -> void:
	var rooms := layout.chambers.filter(func(c: LevelLayout.Chamber) -> bool:
		return c.kind == &"main" or c.kind == &"loot")
	if rooms.is_empty():
		return
	for _i in biome.spire_count:
		var c: LevelLayout.Chamber = rooms[_rng.randi() % rooms.size()]
		var up := _rng.randf() < 0.55
		var x := c.center.x + _rng.randf_range(-0.7, 0.7) * c.radius.x
		var edge := c.center.y + (c.radius.y if up else -c.radius.y) * 1.1
		var length := _rng.randf_range(2.5, minf(6.5, c.radius.y * 0.75))
		var tip := Vector2(x + _rng.randf_range(-1.0, 1.0), edge + (-length if up else length))
		_add_rock_capsule(Vector2(x, edge), tip, _rng.randf_range(1.4, 2.4), 0.25)


# --- SDF carving -------------------------------------------------------------

static func _smin(a: float, b: float, k: float) -> float:
	var h := clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, h) - k * h * (1.0 - h)


func _bounds(lo: Vector2, hi: Vector2) -> Rect2i:
	var x0 := clampi(int(floor(lo.x / CELL)), 0, _w - 1)
	var x1 := clampi(int(ceil(hi.x / CELL)), 0, _w - 1)
	var y0 := clampi(int(floor(-hi.y / CELL)), 0, _h - 1)
	var y1 := clampi(int(ceil(-lo.y / CELL)), 0, _h - 1)
	return Rect2i(x0, y0, x1 - x0, y1 - y0)


func _carve_ellipse(c: Vector2, r: Vector2) -> void:
	var k := minf(r.x, r.y)
	# The scaled-distance approximation grows slower along the long axis, so
	# the bounds must grow with it to reach ROCK_CAP everywhere.
	var pad := r / k * (ROCK_CAP + SMOOTH)
	var b := _bounds(c - r - pad, c + r + pad)
	for iy in range(b.position.y, b.end.y + 1):
		var py := -iy * CELL
		var row := iy * _w
		for ix in range(b.position.x, b.end.x + 1):
			var q := Vector2(ix * CELL - c.x, py - c.y)
			var d := (Vector2(q.x / r.x, q.y / r.y).length() - 1.0) * k
			var i := row + ix
			_rock[i] = _smin(_rock[i], d, SMOOTH)


## Tapered capsule from a (radius ra) to b (radius rb). [param smooth] is the
## blend radius with existing features; 0 gives a hard union, which is what
## consecutive segments of one path need to avoid scalloped walls.
func _carve_capsule(a: Vector2, b: Vector2, ra: float, rb: float, smooth := SMOOTH) -> void:
	_apply_capsule(a, b, ra, rb, true, smooth)


func _add_rock_capsule(a: Vector2, b: Vector2, ra: float, rb: float) -> void:
	_apply_capsule(a, b, ra, rb, false, 1.2)


func _apply_capsule(a: Vector2, b: Vector2, ra: float, rb: float, carve: bool, smooth: float) -> void:
	var pad := maxf(ra, rb) + ROCK_CAP + SMOOTH
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(pad, pad)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(pad, pad)
	var bb := _bounds(lo, hi)
	var ab := b - a
	var len2 := maxf(ab.length_squared(), 0.0001)
	for iy in range(bb.position.y, bb.end.y + 1):
		var py := -iy * CELL
		var row := iy * _w
		for ix in range(bb.position.x, bb.end.x + 1):
			var p := Vector2(ix * CELL, py)
			var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
			var d := p.distance_to(a + ab * t) - lerpf(ra, rb, t)
			var i := row + ix
			if carve:
				_rock[i] = _smin(_rock[i], d, smooth) if smooth > 0.0 else minf(_rock[i], d)
			else:
				# Smooth max of rock distance and the solid capsule.
				_rock[i] = -_smin(-_rock[i], d, smooth)


func _carve_path(path: PackedVector2Array, radius_range: Vector2) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = _rng.randi()
	noise.frequency = 0.04
	var travelled := 0.0
	var prev_r := lerpf(radius_range.x, radius_range.y, noise.get_noise_1d(0.0) * 0.5 + 0.5)
	for i in range(1, path.size()):
		travelled += path[i].distance_to(path[i - 1])
		var r := lerpf(radius_range.x, radius_range.y, noise.get_noise_1d(travelled) * 0.5 + 0.5)
		_carve_capsule(path[i - 1], path[i], prev_r, r, 0.0)
		prev_r = r


## Uniform Catmull-Rom spline through [param pts], sampled every [param step] meters.
static func _spline(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n - 1:
		var p0 := pts[maxi(i - 1, 0)]
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p3 := pts[mini(i + 2, n - 1)]
		var segments := maxi(1, int(p1.distance_to(p2) / step))
		for s in segments:
			out.append(p1.cubic_interpolate(p2, p0, p3, float(s) / segments))
	out.append(pts[n - 1])
	return out


# --- Erosion and finalisation ------------------------------------------------

func _erode(biome: BiomeDef, shafts: PackedFloat32Array) -> void:
	var walls := _noise_bytes(biome.wall_noise_freq, 4, 12.0)
	var caverns := _noise_bytes(biome.cavern_noise_freq, 3, 30.0)
	var amp := biome.wall_noise_amp
	var threshold := biome.cavern_threshold
	for i in _rock.size():
		var v := _rock[i]
		# Large organic caverns; disconnected ones are sealed after the flood fill.
		var c := caverns[i] / 255.0
		if c > threshold - 0.1:
			v = _smin(v, (threshold - c) * 40.0, SMOOTH)
		var n := walls[i] / 127.5 - 1.0
		# Bias towards carving so tunnels never close up entirely.
		v += (n * 0.7 if n > 0.0 else n) * amp
		_rock[i] = minf(v, ROCK_CAP)
	_enforce_border(shafts)


## Keeps a solid rim around the zone, except where the entry and exit shafts
## leave through the top and bottom edges (x positions in [param shafts]).
func _enforce_border(shafts: PackedFloat32Array) -> void:
	const RIM := 4.0
	for iy in _h:
		var y := iy * CELL
		var dy := minf(y, (_h - 1) * CELL - y)
		for ix in _w:
			var x := ix * CELL
			var edge := minf(x, (_w - 1) * CELL - x)
			var near_shaft := false
			for sx in shafts:
				if absf(x - sx) < 7.0:
					near_shaft = true
			if not near_shaft:
				edge = minf(edge, dy)
			if edge < RIM + SMOOTH:
				var i := iy * _w + ix
				_rock[i] = maxf(_rock[i], RIM - edge)


func _noise_bytes(freq: float, octaves: int, warp: float) -> PackedByteArray:
	var noise := FastNoiseLite.new()
	noise.seed = _rng.randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = freq * CELL
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	noise.domain_warp_enabled = true
	noise.domain_warp_amplitude = warp
	noise.domain_warp_frequency = 0.02
	return noise.get_image(_w, _h, false, false, false).get_data()


func _build_field(layout: LevelLayout) -> void:
	var field := TerrainField.new(_w, _h, CELL)
	var data := field.data
	for i in _rock.size():
		data[i] = -_rock[i]
	field.data = data
	layout.field = field


func _flood_reachable(layout: LevelLayout) -> void:
	var field := layout.field
	var mask := PackedByteArray()
	mask.resize(_w * _h)
	var start_ix := roundi(layout.start.x / CELL)
	var start_iy := roundi(-layout.start.y / CELL)
	var queue := PackedInt32Array([start_iy * _w + start_ix])
	mask[queue[0]] = 1
	var head := 0
	var data := field.data
	while head < queue.size():
		var i := queue[head]
		head += 1
		var x := i % _w
		@warning_ignore("integer_division")
		var y := i / _w
		for d in 4:
			var nx := x + (1 if d == 0 else (-1 if d == 1 else 0))
			var ny := y + (1 if d == 2 else (-1 if d == 3 else 0))
			if nx < 0 or ny < 0 or nx >= _w or ny >= _h:
				continue
			var j := ny * _w + nx
			if mask[j] == 0 and data[j] > SUB_CLEARANCE:
				mask[j] = 1
				queue.append(j)
	layout.reachable = mask
	_seal_pockets(layout, queue)


## Seals open-water pockets that are not connected to the reachable cave at
## all (through any gap), so the player never sees water they cannot enter.
## Cracks and narrow gaps attached to the cave stay open.
func _seal_pockets(layout: LevelLayout, reachable_cells: PackedInt32Array) -> void:
	var data := layout.field.data
	var connected := PackedByteArray()
	connected.resize(_w * _h)
	var queue := reachable_cells.duplicate()
	for i in queue:
		connected[i] = 1
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var x := i % _w
		@warning_ignore("integer_division")
		var y := i / _w
		for d in 4:
			var nx := x + (1 if d == 0 else (-1 if d == 1 else 0))
			var ny := y + (1 if d == 2 else (-1 if d == 3 else 0))
			if nx < 0 or ny < 0 or nx >= _w or ny >= _h:
				continue
			var j := ny * _w + nx
			if connected[j] == 0 and data[j] > 0.0:
				connected[j] = 1
				queue.append(j)
	for i in data.size():
		if connected[i] == 0 and data[i] > 0.0:
			data[i] = -0.3 - data[i] * 0.5
	layout.field.data = data


func _collect_anchors(layout: LevelLayout) -> void:
	var field := layout.field
	for iy in range(0, _h, 3):
		for ix in range(0, _w, 3):
			var v := field.data[iy * _w + ix]
			if absf(v) > 0.8:
				continue
			var p := Vector2(ix * CELL, -iy * CELL)
			var n := field.normal(p)
			var surface := p - n * v
			if layout.is_reachable(surface + n * 1.8):
				layout.anchors.append(LevelLayout.Anchor.new(surface, n))
