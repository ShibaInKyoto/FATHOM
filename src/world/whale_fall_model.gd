class_name WhaleFallModel
extends RefCounted
## The bones of a sperm whale fallen to the floor, built to fit the stretch of
## floor it lies on: the great scooped skull at one end, its narrow toothed
## lower jaw fallen beside it, the backbone running off to the tail in
## vertebrae that shrink and scatter towards the end, ribs splayed and half
## collapsed to either side, a flipper's bones lying fanned out, and loose
## teeth and fragments in the silt. Also where the bone-eating worms grow.
## Everything is in world space; [param floor_at] (x, z) gives the floor's
## height there.

## A whale's full length, which the stretch of floor is scaled against.
const WHALE := 16.0
## Of the stretch of floor, how much the skull takes, from the head end.
const SKULL_SHARE := 0.32
const BONE := Color(0.88, 0.85, 0.76)
const TOOTH := Color(0.96, 0.93, 0.84)


## Builds the bones along [param line] (floor points under the backbone, tail
## first, at depth [param depth]); returns {"mesh": ArrayMesh, "tufts":
## Array of Transform3D where worms grow, "middle": Vector3}.
static func build(line: PackedVector3Array, floor_at: Callable, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var k := PropKit.new()
	var length := _length(line)
	var s := clampf(length / (WHALE * 1.05), 0.65, 1.15)
	var skull_from := length * (1.0 - SKULL_SHARE)
	# The skull: its back at skull_from along the line, its beak at the end.
	var back := _point(line, skull_from)
	var tip := _point(line, length - 0.2)
	# It lies along the floor's slope.
	var tilt := Vector3(tip.x - back.x, (tip.y - back.y) * 0.8, 0.0).normalized()
	var fwd := Vector3(signf(tilt.x), 0.0, 0.0)
	var skull_len := minf(back.distance_to(tip), 5.4 * s)
	_skull(k, Vector3(back.x, floor_at.call(back.x, back.z) - 0.12, back.z), tilt, skull_len, s)
	# The lower jaw, fallen out in front of the skull and twisted aside.
	var jaw_at := back + fwd * skull_len * 0.25 + Vector3(0, 0, 2.3 * s)
	var jaw_dir := fwd.rotated(Vector3.UP, -0.35 * signf(fwd.x))
	_jaw(k, jaw_at, jaw_dir, skull_len * 0.92, s, floor_at, rng)
	# The backbone, from the neck back to the tail.
	var neck := skull_from - 0.15 * s
	var vertebrae := _backbone(k, line, neck, s, floor_at, rng)
	# A flipper's bones, fanned out on the near side by the chest.
	if vertebrae.size() > 4:
		var chest: Dictionary = vertebrae[3]
		_flipper(k, chest.at + Vector3(0, 0, 1.6 * s), -fwd, s, floor_at, rng)
	# Loose teeth and broken pieces in the silt about it.
	for i in 12:
		var along := rng.randf_range(length * 0.25, length)
		var p := _point(line, along) + Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.5, 3.0) * s)
		_fragment(k, p, s, floor_at, rng)
	_stain(k, floor_at)
	var mesh := k.commit()
	return {"mesh": mesh, "tufts": _tufts(k, floor_at, rng), "middle": _point(line, length * 0.55)}


# --- The skull ---------------------------------------------------------------

## A sperm whale's skull: a deep basin walled at the back by a high curved
## crest, sweeping forward into a long flat beak with a groove down its top;
## its nostril opens to the left of the basin. Its back at [param at], its
## beak along [param fwd].
static func _skull(k: PropKit, at: Vector3, fwd: Vector3, length: float, s: float) -> void:
	var side := fwd.cross(Vector3.UP).normalized()
	var up := side.cross(fwd).normalized()
	# Stations along it: (fraction, half width, crest height, basin floor).
	var stations := [
		[0.0, 0.72, 1.8, 1.8], [0.025, 0.95, 2.05, 1.1], [0.07, 1.06, 2.1, 0.62], [0.18, 1.12, 1.9, 0.5],
		[0.3, 1.06, 1.5, 0.5], [0.42, 0.9, 1.0, 0.5], [0.55, 0.7, 0.64, 0.46], [0.7, 0.55, 0.5, 0.4],
		[0.85, 0.42, 0.4, 0.33], [0.95, 0.3, 0.3, 0.26], [1.0, 0.16, 0.18, 0.16]]
	var rings: Array[PackedVector3Array] = []
	var steps := 26
	for i in steps + 1:
		var u := float(i) / steps
		var st := _station(stations, u)
		var w: float = st.x * s
		var crest: float = st.y * s
		var basin: float = st.z * s
		var ring := PackedVector3Array()
		for p in _section(w, crest, basin, u):
			ring.append(at + fwd * u * length + side * p.x + up * p.y)
		rings.append(ring)
	k.surface = PropModels.BONE
	k.root = at
	var nostril := at + fwd * length * 0.32 - side * 0.35 * s + up * 0.6 * s
	_loft(k, rings, func(p: Vector3) -> Color:
		var hole := 1.0 - smoothstep(0.15 * s, 0.4 * s, Vector2(p.x - nostril.x, p.z - nostril.z).length())
		var rel := p - at
		var u := clampf(rel.dot(fwd) / length, 0.0, 1.0)
		var across := absf(rel.dot(side)) / maxf(_station(stations, u).x * s, 0.01)
		var height := rel.dot(up)
		# Shade the hollows as the light can't reach them: deep in the basin,
		# in the temples and underneath.
		var deep := (1.0 - smoothstep(0.55, 0.85, across)) * (1.0 - smoothstep(0.35, 0.9, u)) \
			* (1.0 - smoothstep(0.5 * s, 1.2 * s, height))
		var temple := smoothstep(0.85, 1.0, across) * smoothstep(0.05, 0.14, u) * (1.0 - smoothstep(0.22, 0.32, u)) \
			* (1.0 - smoothstep(0.3 * s, 0.9 * s, absf(height - 0.6 * s)))
		var under := 1.0 - smoothstep(0.0, 0.25 * s, height)
		var g := (0.92 + 0.08 * sin(p.x * 3.1 + p.z * 2.3)) * (1.0 - deep * 0.4 - temple * 0.35 - under * 0.25)
		return Color(BONE.r * g * (1.0 - hole * 0.75), BONE.g * g * (1.0 - hole * 0.78),
			BONE.b * g * (1.0 - hole * 0.8), 0.0))
	# Caps: the back wall and the tip of the beak.
	_cap(k, rings[0], -fwd)
	_cap(k, rings[steps], fwd)
	# The knuckles at the back that the backbone hinged on.
	for sgn: float in [-1.0, 1.0]:
		k.blob(at - fwd * 0.08 * s + side * sgn * 0.24 * s + up * 0.55 * s, fwd * 0.16 * s,
			up * 0.2 * s, side * 0.14 * s, BONE * 0.95, 8, 5, 0.0)
	k.root = Vector3.ZERO
	k.surface = 0.0


## Linear blend of the skull's [param stations] at fraction [param u]:
## (half width, crest height, basin floor).
static func _station(stations: Array, u: float) -> Vector3:
	for i in range(1, stations.size()):
		var b: Array = stations[i]
		if u <= b[0]:
			var a: Array = stations[i - 1]
			var f := smoothstep(a[0], b[0], u)
			return Vector3(lerpf(a[1], b[1], f), lerpf(a[2], b[2], f), lerpf(a[3], b[3], f))
	var last: Array = stations.back()
	return Vector3(last[1], last[2], last[3])


## The skull's cross-section at fraction [param u]: round from the bottom,
## up its right wall to the crest, down into the basin, over and back down
## the left (x across, y up; same number of points every time).
static func _section(w: float, crest: float, basin: float, u: float) -> PackedVector2Array:
	# The temple: a deep hollow low on each side behind where the eye was.
	var temple := 1.0 - 0.16 * smoothstep(0.05, 0.12, u) * (1.0 - smoothstep(0.22, 0.32, u))
	# Thin walls round a deep basin; down the beak, a groove along the top.
	var groove := basin - 0.06 * smoothstep(0.4, 0.7, u) * crest
	var pts := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(w * 0.6, 0.0), Vector2(w * 0.92, crest * 0.06),
		Vector2(w * temple, crest * 0.35), Vector2(w * 0.99, crest * 0.75), Vector2(w * 0.95, crest * 0.95),
		Vector2(w * 0.89, crest), Vector2(w * 0.82, crest * 0.97), Vector2(w * 0.75, lerpf(crest, basin, 0.6)),
		Vector2(w * 0.6, lerpf(crest, basin, 0.92)), Vector2(w * 0.32, basin), Vector2(0.0, groove)])
	var out := pts.duplicate()
	for i in range(pts.size() - 2, 0, -1):
		out.append(Vector2(-pts[i].x, pts[i].y))
	out.append(Vector2(0.0, 0.0))
	return out


## Joins [param rings] (all as long) into a surface, normals worked out from
## its neighbours, painted by [param paint] (position).
static func _loft(k: PropKit, rings: Array[PackedVector3Array], paint: Callable) -> void:
	var n := rings.size()
	var m := rings[0].size()
	var start := k.verts.size()
	for i in n:
		for j in m:
			var p := rings[i][j]
			var along := rings[mini(i + 1, n - 1)][j] - rings[maxi(i - 1, 0)][j]
			var round := rings[i][(j + 1) % (m - 1)] - rings[i][(j + m - 2) % (m - 1)]
			# The sections run anticlockwise, so this points out of the bone.
			var nrm := along.cross(round).normalized()
			k.add(p, nrm, paint.call(p), 0.0)
	for i in n - 1:
		for j in m - 1:
			var a := start + i * m + j
			k.quad(a, a + 1, a + m + 1, a + m)


## Closes [param ring] with a fan, facing [param out].
static func _cap(k: PropKit, ring: PackedVector3Array, out: Vector3) -> void:
	var centre := Vector3.ZERO
	for p in ring:
		centre += p
	centre /= ring.size()
	var c := k.add(centre, out, BONE * 0.85, 0.0)
	var first := k.verts.size()
	for p in ring:
		k.add(p, out, BONE * 0.88, 0.0)
	for j in ring.size() - 1:
		k.tri(c, first + j, first + j + 1)


# --- The lower jaw -------------------------------------------------------------

## The lower jaw: two arms from the hinges joining into one long narrow rod,
## two rows of conical teeth along it. Its hinge end at [param at], lying
## along [param dir] on the floor.
static func _jaw(k: PropKit, at: Vector3, dir: Vector3, length: float, s: float, floor_at: Callable,
		rng: RandomNumberGenerator) -> void:
	var side := dir.cross(Vector3.UP).normalized()
	var lift := func(p: Vector3, r: float) -> Vector3:
		return Vector3(p.x, floor_at.call(p.x, p.z) + r * 0.7, p.z)
	var bone := func(t: float, _a: float) -> Color: return BONE * (0.95 - 0.08 * t)
	var join := at + dir * length * 0.38
	for sgn: float in [-1.0, 1.0]:
		var hinge: Vector3 = lift.call(at + side * sgn * 0.62 * s, 0.15 * s)
		var mid: Vector3 = lift.call(at + dir * length * 0.2 + side * sgn * 0.32 * s, 0.13 * s)
		var meet: Vector3 = lift.call(join + side * sgn * 0.05 * s, 0.12 * s)
		_bone(k, PackedVector3Array([hinge, hinge.lerp(mid, 0.5), mid, meet]),
			PackedFloat32Array([0.12 * s, 0.14 * s, 0.12 * s, 0.11 * s]), 8, bone, Callable(), Vector3.UP, 1.5)
		# The knuckle it hinged on.
		k.blob(hinge - dir * 0.05 * s + Vector3.UP * 0.12 * s, dir * 0.13 * s, Vector3.UP * 0.12 * s,
			side * 0.11 * s, BONE * 0.9, 8, 5, 0.0)
	var rod := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in 7:
		var t := i / 6.0
		var r := lerpf(0.14, 0.07, t) * s
		rod.append(lift.call(join.lerp(at + dir * length, t), r))
		radii.append(r)
	_bone(k, rod, radii, 8, bone, Callable(), Vector3.UP, 1.6)
	# Teeth: two rows up the rod, big at the back, small at the tip.
	var count := 18
	for i in count:
		var t := (i + 0.5) / count
		var base: Vector3 = rod[0].lerp(rod[6], t)
		for sgn: float in [-1.0, 1.0]:
			if rng.randf() < 0.12:
				continue
			var root := base + side * sgn * 0.055 * s + Vector3.UP * lerpf(0.13, 0.07, t) * s
			var h := lerpf(0.2, 0.11, t) * s * rng.randf_range(0.8, 1.15)
			var lean := (Vector3.UP - dir * 0.25 + side * sgn * 0.15).normalized()
			_bone(k, PackedVector3Array([root, root + lean * h * 0.55, root + lean * h - dir * 0.03 * s]),
				PackedFloat32Array([0.045 * s, 0.035 * s, 0.0]), 6, func(_t: float, _a: float) -> Color: return TOOTH)


# --- The backbone --------------------------------------------------------------

## The vertebrae from [param neck] along [param line] back to its start (the
## tail), each lying on the floor, its spine and wings shaped for where it
## sits (low and fused at the neck, tall over the loins, shrinking to knobs at
## the tail), the ribs fallen from the chest. Returns each one's place.
static func _backbone(k: PropKit, line: PackedVector3Array, neck: float, s: float, floor_at: Callable,
		rng: RandomNumberGenerator) -> Array:
	var out := []
	var d := neck
	var i := 0
	while d > 0.3:
		var t := clampf(1.0 - d / neck, 0.0, 1.0)
		var r := (0.21 + 0.09 * smoothstep(0.0, 0.32, t) - 0.25 * smoothstep(0.42, 1.0, t)) * s
		r = maxf(r, 0.05 * s)
		var span := r * 1.15
		d -= span * 0.5
		if d <= 0.2:
			break
		var p := _point(line, d)
		var ahead := _point(line, d + 0.3)
		var back_dir := (p - ahead).normalized()
		# The last of the tail lies scattered: knocked aside, tipped over.
		var loose := smoothstep(0.75, 1.0, t)
		var jog := Vector3(0, 0, rng.randf_range(-0.08, 0.08) + rng.randf_range(-0.6, 0.6) * loose) * s
		var at := p + jog
		at.y = floor_at.call(at.x, at.z) + r * 0.62
		var tip := rng.randf_range(-0.12, 0.12) + rng.randf_range(-1.0, 1.0) * loose
		var up := Vector3.UP.rotated(back_dir, tip)
		var turn := rng.randf_range(-0.12, 0.12) + rng.randf_range(-0.8, 0.8) * loose
		var along := back_dir.rotated(Vector3.UP, turn)
		_vertebra(k, at, along, up, r, t, s, rng)
		out.append({"at": at, "r": r, "t": t, "along": along})
		# Eleven pairs of ribs on the chest.
		if i >= 2 and i <= 12:
			var size := sin(PI * (i - 1.5) / 11.0) * 0.45 + 0.6
			for sgn: float in [-1.0, 1.0]:
				if rng.randf() < 0.1:
					continue
				_rib(k, at, along, r, sgn, 2.3 * s * size, floor_at, rng)
		d -= span * 0.5 + 0.07 * s
		i += 1
	return out


## One vertebra at [param at]: a spool-shaped body along [param along], a
## spine raked back over it, and a wing to each side.
static func _vertebra(k: PropKit, at: Vector3, along: Vector3, up: Vector3, r: float, t: float, s: float,
		rng: RandomNumberGenerator) -> void:
	var side := along.cross(up).normalized()
	up = side.cross(along).normalized()
	var half := r * 0.55
	var g := rng.randf_range(0.9, 1.04)
	var bone := func(_t: float, _a: float) -> Color: return BONE * g
	_bone(k, PackedVector3Array([at - along * half, at - along * half * 0.8, at, at + along * half * 0.8,
		at + along * half]), PackedFloat32Array([r * 0.92, r * 1.02, r * 0.86, r * 1.02, r * 0.92]), 12, bone)
	# The spine: low at the neck, tallest over the loins, gone at the tail.
	var tall := r * (0.7 + 1.9 * smoothstep(0.0, 0.12, t) + 0.6 * smoothstep(0.15, 0.4, t)) \
		* (1.0 - smoothstep(0.55, 0.9, t))
	if tall > 0.05 * s:
		var foot := at + up * r * 0.85
		var top := foot + up * tall + along * tall * 0.35
		_bone(k, PackedVector3Array([foot, foot.lerp(top, 0.5) + along * 0.02, top]),
			PackedFloat32Array([r * 0.42, r * 0.3, r * 0.16]), 6, bone, Callable(), side, 0.35)
	# The wings: short on the chest, broad over the loins.
	var wing := r * (1.1 + 1.2 * smoothstep(0.2, 0.4, t)) * (1.0 - smoothstep(0.6, 0.85, t))
	if wing > 0.05 * s:
		for sgn: float in [-1.0, 1.0]:
			var root := at + side * sgn * r * 0.7
			var end := root + side * sgn * wing - up * r * 0.25 - along * wing * 0.1
			_bone(k, PackedVector3Array([root, root.lerp(end, 0.55), end]),
				PackedFloat32Array([r * 0.36, r * 0.28, r * 0.18]), 6, bone, Callable(), up, 0.35)


## A rib fallen from the vertebra at [param at] to side [param sgn]: out,
## over in a low arch and down to the floor, raked back, some standing up
## more than others, a few snapped with the broken end lying nearby.
static func _rib(k: PropKit, at: Vector3, along: Vector3, r: float, sgn: float, length: float, floor_at: Callable,
		rng: RandomNumberGenerator) -> void:
	var side := along.cross(Vector3.UP).normalized() * sgn
	var start := at + side * r * 1.2 + Vector3.UP * r * 0.3
	var stand := rng.randf_range(0.45, 1.0) if rng.randf() < 0.75 else rng.randf_range(0.1, 0.4)
	var end := start + side * length * 0.78 + along * length * 0.4
	end.y = floor_at.call(end.x, end.z) + 0.04
	var c1 := start + side * length * 0.32 + Vector3.UP * (length * 0.42 * stand + 0.15)
	var c2 := end + Vector3.UP * length * 0.3 * stand - side * length * 0.12
	var snapped := rng.randf_range(0.45, 0.75) if rng.randf() < 0.25 else 1.0
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	var n := 11
	for i in n + 1:
		var u := float(i) / n * snapped
		var p := _bezier(start, c1, c2, end, u)
		p.y = maxf(p.y, floor_at.call(p.x, p.z) + 0.03)
		pts.append(p)
		radii.append(lerpf(0.095, 0.055, u) * length / 2.3)
	# A strap, thin across its curve and broad along the body.
	var face := (c1 - start).cross(end - start).normalized()
	var across := face.cross((c1 - start).normalized()).normalized()
	var bone := func(t: float, _a: float) -> Color: return BONE * (0.97 - 0.06 * t)
	_bone(k, pts, radii, 7, bone, Callable(), across, 0.5)
	if snapped < 1.0:
		# The broken-off end, lying flat beside where it fell.
		var a := _bezier(start, c1, c2, end, snapped + 0.05)
		var b := end + along * rng.randf_range(-0.3, 0.3)
		var drop := Vector3(0, 0, rng.randf_range(-0.4, 0.4))
		var piece := PackedVector3Array()
		var piece_r := PackedFloat32Array()
		for j in 5:
			var u := j / 4.0
			var p := a.lerp(b, u) + drop
			p.y = floor_at.call(p.x, p.z) + 0.05
			piece.append(p)
			piece_r.append(lerpf(0.07, 0.05, u) * length / 2.3)
		_bone(k, piece, piece_r, 6, bone, Callable(), Vector3.UP, 0.5)


static func _bezier(a: Vector3, b: Vector3, c: Vector3, d: Vector3, t: float) -> Vector3:
	var u := 1.0 - t
	return a * u * u * u + b * 3.0 * u * u * t + c * 3.0 * u * t * t + d * t * t * t


# --- The flipper and the scraps ------------------------------------------------

## A flipper's bones lying on the floor at [param at]: the broad shoulder
## blade, the short arm bones and five short fingers fanned out along
## [param dir].
static func _flipper(k: PropKit, at: Vector3, dir: Vector3, s: float, floor_at: Callable,
		rng: RandomNumberGenerator) -> void:
	var side := dir.cross(Vector3.UP).normalized()
	var on_floor := func(p: Vector3, h: float) -> Vector3:
		return Vector3(p.x, floor_at.call(p.x, p.z) + h, p.z)
	var bone := func(_t: float, _a: float) -> Color: return BONE * 0.93
	# The shoulder blade: a broad flat fan.
	var blade: Vector3 = on_floor.call(at - dir * 0.5 * s, 0.06 * s)
	k.blob(blade, dir * 0.55 * s, Vector3.UP * 0.05 * s, side * 0.48 * s, BONE * 0.9, 12, 4, 0.0)
	var shoulder: Vector3 = on_floor.call(at, 0.12 * s)
	var elbow: Vector3 = on_floor.call(at + dir * 0.45 * s + side * 0.1 * s, 0.1 * s)
	var wrist: Vector3 = on_floor.call(at + dir * 0.95 * s + side * 0.15 * s, 0.07 * s)
	_bone(k, PackedVector3Array([shoulder, elbow]), PackedFloat32Array([0.14 * s, 0.11 * s]), 8, bone)
	for sgn: float in [-1.0, 1.0]:
		_bone(k, PackedVector3Array([elbow + side * sgn * 0.06 * s, wrist + side * sgn * 0.08 * s]),
			PackedFloat32Array([0.06 * s, 0.05 * s]), 6, bone)
	for f in 5:
		var spread := (f - 2.0) * 0.22 + rng.randf_range(-0.05, 0.05)
		var way := dir.rotated(Vector3.UP, spread)
		var p := wrist + side * (f - 2.0) * 0.07 * s
		var bones := 3 + (1 if f == 1 or f == 2 else 0)
		for j in bones:
			var q: Vector3 = on_floor.call(p + way * 0.16 * s, 0.035 * s)
			_bone(k, PackedVector3Array([p, q]), PackedFloat32Array([0.04 * s, 0.032 * s]), 5, bone)
			p = q + way * 0.02 * s


## A loose piece in the silt at [param p]: a tooth, a broken scrap of rib, or
## a flat growth plate off a vertebra.
static func _fragment(k: PropKit, p: Vector3, s: float, floor_at: Callable, rng: RandomNumberGenerator) -> void:
	var way := Vector3(cos(rng.randf() * TAU), 0.0, sin(rng.randf() * TAU)).normalized()
	var y: float = floor_at.call(p.x, p.z)
	match rng.randi() % 3:
		0:
			var root := Vector3(p.x, y + 0.04 * s, p.z)
			_bone(k, PackedVector3Array([root, root + way * 0.12 * s, root + way * 0.2 * s + Vector3.UP * 0.03 * s]),
				PackedFloat32Array([0.045 * s, 0.035 * s, 0.0]), 6, func(_t: float, _a: float) -> Color: return TOOTH)
		1:
			var a := Vector3(p.x, y + 0.05 * s, p.z)
			var b := a + way * rng.randf_range(0.4, 0.8) * s
			b.y = floor_at.call(b.x, b.z) + 0.05 * s
			_bone(k, PackedVector3Array([a, a.lerp(b, 0.5) + Vector3.UP * 0.05 * s, b]),
				PackedFloat32Array([0.06 * s, 0.055 * s, 0.045 * s]), 6,
				func(_t: float, _a: float) -> Color: return BONE * 0.88, Callable(), Vector3.UP, 0.5)
		_:
			var c := Vector3(p.x, y + 0.03 * s, p.z)
			var tilt := Vector3.UP.rotated(way, rng.randf_range(0.1, 0.5))
			k.blob(c, way * 0.18 * s, tilt * 0.035 * s, tilt.cross(way) * 0.18 * s, BONE * 0.9, 10, 3, 0.0)


# --- Finish ------------------------------------------------------------------

## A bone along [param pts]: a tube with its ends rounded off (arguments as
## [method PropKit.tube]).
static func _bone(k: PropKit, pts: PackedVector3Array, radii: PackedFloat32Array, sides: int, paint: Callable,
		shape: Callable = Callable(), up0 := Vector3.ZERO, flat := 1.0) -> void:
	var n := pts.size()
	var head := (pts[0] - pts[1]).normalized()
	var tail := (pts[n - 1] - pts[n - 2]).normalized()
	var out := PackedVector3Array([pts[0] + head * radii[0] * 0.5, pts[0] + head * radii[0] * 0.3])
	var out_r := PackedFloat32Array([radii[0] * 0.15, radii[0] * 0.75])
	out.append_array(pts)
	out_r.append_array(radii)
	var r_end := radii[n - 1]
	if r_end > 0.001:
		out.append_array([pts[n - 1] + tail * r_end * 0.3, pts[n - 1] + tail * r_end * 0.5])
		out_r.append_array([r_end * 0.75, r_end * 0.15])
	k.tube(out, out_r, sides, paint, shape, up0, flat)

## Darkens each bone where it lies in the silt, as it would be stained.
static func _stain(k: PropKit, floor_at: Callable) -> void:
	for i in k.verts.size():
		var p := k.verts[i]
		var above := p.y - float(floor_at.call(p.x, p.z))
		var dim := lerpf(0.5, 1.0, smoothstep(0.0, 0.45, above))
		var c := k.colors[i]
		k.colors[i] = Color(c.r * dim, c.g * dim * 0.98, c.b * dim * 0.94, c.a)


## Where the bone-eating worms grow: on the bones' upper faces, clear of the
## silt, their plumes standing out along the bone's normal.
static func _tufts(k: PropKit, floor_at: Callable, rng: RandomNumberGenerator) -> Array:
	var out := []
	var tries := 0
	while out.size() < 220 and tries < 6000:
		tries += 1
		var i := rng.randi() % k.verts.size()
		var p := k.verts[i]
		var n := k.normals[i]
		if n.y < -0.2 or p.y - float(floor_at.call(p.x, p.z)) < 0.08:
			continue
		var y := n.normalized()
		var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
		var basis := Basis(x, y, x.cross(y)).rotated(y, rng.randf() * TAU)
		out.append(Transform3D(basis.scaled(Vector3.ONE * rng.randf_range(0.45, 0.9)), p))
	return out


## One tuft of bone-eating worms: a few pale stalks splaying out of the bone,
## each crowned with a blood-red plume (UV.y how far up it a point is).
static func tuft(seed_value: int) -> ArrayMesh:
	var k := PropKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	k.stir = 1.0
	for i in 7:
		var a := TAU * i / 7.0 + rng.randf_range(-0.3, 0.3)
		var lean := rng.randf_range(0.15, 0.6)
		var dir := (Vector3.UP + Vector3(cos(a), 0.0, sin(a)) * lean).normalized()
		var base := Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.0, 0.03)
		var h := rng.randf_range(0.12, 0.2)
		_bone(k, PackedVector3Array([base - dir * 0.02, base + dir * h * 0.5, base + dir * h, base + dir * (h + 0.035)]),
			PackedFloat32Array([0.012, 0.009, 0.022, 0.0]), 4, func(_t: float, _a: float) -> Color: return Color.WHITE)
	return k.commit()


## A hagfish: a slimy eel with a flat-finned tail and a fringe of barbels
## round its blind face, along +x with its head at the front (COLOR.g: belly).
static func hagfish() -> ArrayMesh:
	var profile := PackedVector2Array([Vector2(0.0, 0.006), Vector2(0.06, 0.04), Vector2(0.25, 0.058),
		Vector2(0.7, 0.056), Vector2(0.9, 0.047), Vector2(0.97, 0.034), Vector2(1.0, 0.012)])
	var body := MeshKit.lathe(profile, 1.1, 8, 16, 1.15, 0.85)
	var parts := [[body]]
	# A low fin round the tail.
	var fin := MeshKit.fin(PackedVector2Array([Vector2(-0.55, 0.0), Vector2(-0.44, 0.055), Vector2(-0.22, 0.045),
		Vector2(-0.15, 0.0), Vector2(-0.22, -0.04), Vector2(-0.44, -0.045)]), 0.008)
	parts.append([fin])
	for i in 4:
		var a := (i - 1.5) * 0.5
		var barbel := MeshKit.spike(0.009, 0.07)
		parts.append([barbel, Transform3D(Basis(Vector3.UP, a * 0.6) * Basis(Vector3.BACK, a * 0.4 - 0.2),
			Vector3(0.54, -0.008, 0.0))])
	return MeshKit.merge(parts)


## The length of [param line].
static func _length(line: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, line.size()):
		total += line[i].distance_to(line[i - 1])
	return total


## The point [param d] along [param line].
static func _point(line: PackedVector3Array, d: float) -> Vector3:
	var left := maxf(d, 0.0)
	for i in range(1, line.size()):
		var step := line[i].distance_to(line[i - 1])
		if left <= step:
			return line[i - 1].lerp(line[i], left / maxf(step, 0.0001))
		left -= step
	return line[line.size() - 1]
