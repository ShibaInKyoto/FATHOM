class_name PropLife
extends RefCounted
## The scattered props that answer the sub. Anemones and tubeworms shut
## quickly when it comes close, stay shut while it lingers and open again
## slowly a while after it has gone; kelp in the hull's way leans aside and
## swings back once it has passed. Each prop's state rides in the w of its
## instance custom data, which prop.gdshaderinc reads: how far it has shut
## (0..1), or how far it leans across its stalk (-1..1).

enum Kind { SHY, LEAN }

## Within this of the sub a shy prop shuts; it opens again only once the
## sub is beyond SHY_CLEAR and OPEN_DELAY has passed.
const SHY_NEAR := 4.5
const SHY_CLEAR := 7.0
const SHUT_TIME := 0.5
const OPEN_DELAY := 2.0
const OPEN_TIME := 3.5
## How far round the sub's middle the hull pushes stalks aside.
const HULL := 2.4
## The lean's spring: stiffness and damping (a little under critical, so a
## stalk swings back just past upright before it settles).
const LEAN_STIFF := 7.0
const LEAN_DAMP := 4.0
## Batches further than this from the sub are left alone while at rest.
const REACH := 16.0

var _batches: Array[Batch] = []


## Registers the props of [param mm] (whose transforms and base custom data
## are [param xforms] and [param customs]); [param height] is how tall a
## LEAN prop's stalk stands before scaling.
func add(mm: MultiMesh, kind: Kind, xforms: Array, customs: Array, height := 1.0) -> void:
	var b := Batch.new()
	b.mm = mm
	b.kind = kind
	for i in xforms.size():
		var xf: Transform3D = xforms[i]
		var foot := Vector2(xf.origin.x, xf.origin.y)
		var top := xf * Vector3(0.0, height, 0.0)
		b.feet.append(foot)
		b.tops.append(Vector2(top.x, top.y))
		# Only stalks standing near the play plane are in the hull's way.
		b.touch.append(clampf(1.0 - (absf(xf.origin.z) - 0.8), 0.0, 1.0))
		b.base.append(customs[i])
		b.bounds = Rect2(foot, Vector2.ZERO) if i == 0 else b.bounds.expand(foot)
		b.bounds = b.bounds.expand(Vector2(top.x, top.y))
	b.state.resize(xforms.size())
	b.shown.resize(xforms.size())
	b.motion.resize(xforms.size())
	_batches.append(b)


## Steps every prop near the sub at [param sub_pos], moving at [param sub_vel].
func tick(delta: float, sub_pos: Vector2, sub_vel := Vector2.ZERO) -> void:
	for b in _batches:
		if not b.awake and not b.bounds.grow(REACH).has_point(sub_pos):
			continue
		b.awake = false
		for i in b.state.size():
			var now := _shy(b, i, delta, sub_pos) if b.kind == Kind.SHY else _lean(b, i, delta, sub_pos, sub_vel)
			b.state[i] = now
			if absf(now) > 0.0005 or absf(b.motion[i]) > 0.0005:
				b.awake = true
			# Only tell the renderer when it has visibly moved, or come to rest.
			var shown := b.shown[i]
			if absf(now - shown) > 0.002 or (now == 0.0 and shown != 0.0):
				b.shown[i] = now
				var c: Color = b.base[i]
				b.mm.set_instance_custom_data(i, Color(c.r, c.g, c.b, now))


## The state of prop [param i] in [param mm]: how far it has shut, or leans.
func state_of(mm: MultiMesh, i: int) -> float:
	for b in _batches:
		if b.mm == mm:
			return b.state[i]
	return 0.0


## How far prop [param i] of [param b] has shut. Its motion slot holds the
## time left before it may open again.
func _shy(b: Batch, i: int, delta: float, sub_pos: Vector2) -> float:
	var shut := b.state[i]
	var d := b.feet[i].distance_to(sub_pos)
	if d < SHY_NEAR or (d < SHY_CLEAR and shut > 0.0):
		if d < SHY_NEAR:
			shut = minf(shut + delta / SHUT_TIME, 1.0)
		b.motion[i] = OPEN_DELAY
	else:
		b.motion[i] = maxf(b.motion[i] - delta, 0.0)
		if b.motion[i] <= 0.0:
			shut = maxf(shut - delta / OPEN_TIME, 0.0)
	return shut


## How far stalk [param i] of [param b] leans across itself, out of the
## hull's way: carried along the way the sub is going (or, if it is barely
## moving across the stalk, pushed off to the nearer side); its motion slot
## holds how fast it is swinging.
func _lean(b: Batch, i: int, delta: float, sub_pos: Vector2, sub_vel: Vector2) -> float:
	var foot := b.feet[i]
	var stalk := b.tops[i] - foot
	var along := clampf((sub_pos - foot).dot(stalk) / maxf(stalk.length_squared(), 0.0001), 0.0, 1.0)
	var side := Vector2(stalk.y, -stalk.x).normalized()
	var across := (sub_pos - (foot + stalk * along)).dot(side)
	var want := 0.0
	if absf(across) < HULL and along > 0.0:
		var drift := sub_vel.dot(side)
		var way := signf(drift) if absf(drift) > 0.5 else -signf(across)
		want = way * (1.0 - absf(across) / HULL) * b.touch[i]
	var lean := b.state[i]
	var swing := b.motion[i]
	# Stepped in small slices so a long frame cannot set it ringing.
	var steps := ceili(delta / 0.02)
	var dt := delta / steps
	for _s in steps:
		swing += ((want - lean) * LEAN_STIFF - swing * LEAN_DAMP) * dt
		lean += swing * dt
	b.motion[i] = swing
	return clampf(lean, -1.2, 1.2)


class Batch:
	var mm: MultiMesh
	var kind := Kind.SHY
	var bounds := Rect2()
	var feet := PackedVector2Array()
	var tops := PackedVector2Array()
	var touch := PackedFloat32Array()
	var base: Array[Color] = []
	var state := PackedFloat32Array()
	var shown := PackedFloat32Array()
	var motion := PackedFloat32Array()
	var awake := false
