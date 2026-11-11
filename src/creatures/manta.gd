class_name Manta
extends Creature
## Shelf manta: a gentle giant of the sunlit zones, gliding slowly from one
## open stretch of water to the next on wings wider than the sub is long. It
## bites nothing, pays no attention to noise or light, and banks away from a
## sub that crowds it. Hurt, it beats away fast. The camera sees the cave side
## on, so the wings are held tilted towards it to show their spread.
## Built as the animal is: one disc, body and wings together, thick over the
## body and thinning to swept-back pointed tips; a wide mouth across the
## front of the head between two rolled horns, eyes at the corners of the
## head, a whip tail with a small dorsal fin at its root. Its skin is
## painted (tools/art/manta_skin.py): a near-black back with a ragged white
## chevron over each shoulder, scarred and freckled, and a white belly with
## gill slits, its own scatter of spots and grey-edged wings.
## It swims as mantas do: a few slow, deep beats, each wing curling up and
## down as one with the stroke running back from its leading edge and out
## to the trailing tip, then a long glide on outstretched wings; it bobs
## with each beat and banks round as it turns.

const SPEED := 2.4
const FLEE_SPEED := 6.5
## How close the sub may come before it banks away.
const PERSONAL_SPACE := 7.0
## How far it holds its wings towards the camera, in radians.
const TILT := 1.05
## How far it banks into a turn for each radian a second it turns at.
const BANK := 0.35
## How much bigger than the disc below it is drawn (and moves): a wingspan
## of over nine metres, a wonder of the shelf.
const SIZE := 1.35
## The disc: half its span (before [constant SIZE]), where the
## wings leave the body, and its leading and trailing edges and thickness,
## (z, x or metres) from the midline out to the wingtip.
const HALF_SPAN := 3.4
const WING_ROOT := 0.55
const LEAD := [Vector2(0.0, 1.0), Vector2(0.45, 0.98), Vector2(0.7, 0.86), Vector2(1.2, 0.63),
	Vector2(1.8, 0.35), Vector2(2.4, 0.01), Vector2(2.9, -0.37), Vector2(3.25, -0.72), Vector2(3.4, -0.95)]
const TRAIL := [Vector2(0.0, -1.0), Vector2(0.45, -0.96), Vector2(0.8, -0.8), Vector2(1.4, -0.72),
	Vector2(2.0, -0.75), Vector2(2.6, -0.82), Vector2(3.1, -0.9), Vector2(3.4, -0.95)]
const THICK := [Vector2(0.0, 0.42), Vector2(0.3, 0.38), Vector2(0.55, 0.27), Vector2(0.9, 0.14),
	Vector2(1.5, 0.075), Vector2(2.4, 0.045), Vector2(3.4, 0.012)]

## The disc's skin, painted by tools/art/manta_skin.py over this box (x of
## its front edge, z of one side, its length and span): see the creature
## shader's paint_top.
const PAINT_BOX := Vector4(1.1, -3.45, 2.2, 6.9)
const PAINT_BACK := preload("res://assets/creatures/manta_back.png")
const PAINT_BELLY := preload("res://assets/creatures/manta_belly.png")

static var _mesh: ArrayMesh

var _goal := Vector2.INF
var _goal_timer := 0.0
var _flee := 0.0
var _t := 0.0
var _tilt: Node3D
## The stroke: beats left in this bout, glide left, and beats so far.
var _bout := 2
var _glide := 0.0
var _beats := 0


func setup() -> void:
	species = &"manta"
	max_hp = 140.0
	radius = 2.3
	reach = 4.3
	mass = 6.0
	contact_damage = 0.0
	salvage_drop = 4
	hostile = false
	hearing = 0.0
	glow_color = Color(0.75, 0.9, 1.0)
	_turn_speed = 1.6
	# A big animal turning round takes its time.
	turn_rate = 2.8
	super.setup()
	_t = level.rng.randf() * TAU


func build_model() -> void:
	var mat := species_material(func(m: ShaderMaterial) -> void:
		m.set_shader_parameter(&"back_color", Color(0.045, 0.05, 0.065))
		m.set_shader_parameter(&"belly_color", Color(0.86, 0.88, 0.9))
		m.set_shader_parameter(&"glow_color", Color(0.75, 0.9, 1.0))
		m.set_shader_parameter(&"glow_strength", 0.0)
		m.set_shader_parameter(&"rim_strength", 0.2)
		m.set_shader_parameter(&"roughness", 0.42)
		m.set_shader_parameter(&"metallic", 0.0)
		m.set_shader_parameter(&"tooth_color", Color(0.025, 0.025, 0.03))
		# No sideways swimming: the swim clock drives the wings, one cycle a
		# beat, and the tail's sway.
		m.set_shader_parameter(&"swim_amp", 0.0)
		m.set_shader_parameter(&"swim_freq", TAU)
		m.set_shader_parameter(&"flap_amp", 0.68)
		m.set_shader_parameter(&"flap_rest", 0.06)
		m.set_shader_parameter(&"flap_root", WING_ROOT)
		m.set_shader_parameter(&"flap_span", HALF_SPAN - WING_ROOT)
		m.set_shader_parameter(&"flap_lag", 0.8)
		m.set_shader_parameter(&"flap_tip_lag", 0.9)
		m.set_shader_parameter(&"flutter_amp", 0.13)
		m.set_shader_parameter(&"flutter_freq", TAU)
		m.set_shader_parameter(&"flutter_wave", 2.2)
		m.set_shader_parameter(&"paint_top", PAINT_BACK)
		m.set_shader_parameter(&"paint_bottom", PAINT_BELLY)
		m.set_shader_parameter(&"paint_box", PAINT_BOX)
		m.set_shader_parameter(&"paint_relief", 0.003))
	_tilt = Node3D.new()
	# Back to the camera from the start (a specimen in the hangar never ticks).
	_tilt.basis = Basis(Vector3.RIGHT, TILT).scaled(Vector3.ONE * SIZE)
	model.add_child(_tilt)
	if _mesh == null:
		_mesh = _build_mesh()
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tilt.add_child(mi)
	visuals.append(mi)


# --- The model ---------------------------------------------------------------

static func _build_mesh() -> ArrayMesh:
	var parts := [[_disc()]]
	# Cephalic fins either side of the mouth, rolled up as it cruises:
	# flattened paddles, dark outside and pale where they curl under, their
	# tips blunt.
	var lobe := _cephalic()
	for side: float in [1.0, -1.0]:
		var aim := Basis(Vector3.UP, -0.16 * side) * Basis(Vector3.BACK, -0.12)
		parts.append([lobe, Transform3D(aim, Vector3(0.9, -0.01, 0.4 * side))])
		# Eyes, bulging from the sides of the head behind the fins.
		var eye := MeshKit.painted(MeshKit.ball(0.085, 0.0, 12, 8), func(_v: Vector3) -> Color:
			return Color(0.0, 0.0, 0.0, 0.3))
		parts.append([eye, Transform3D(Basis.from_scale(Vector3(1.0, 0.85, 0.8)),
			Vector3(_edge(LEAD, 0.6) - 0.1, 0.02, 0.6 * side))])
	# The whip tail, swaying more towards its tip, and the little dorsal fin
	# at its root.
	var tail_pts := PackedVector3Array()
	var tail_r := PackedFloat32Array()
	for i in 14:
		var f := i / 13.0
		tail_pts.append(Vector3(-0.85 - 2.1 * f, 0.02 + 0.06 * f * f, 0.0))
		tail_r.append(lerpf(0.06, 0.007, pow(f, 0.7)))
	var tail := ArrayMesh.new()
	MeshKit.tube(tail, tail_pts, tail_r, 7)
	parts.append([MeshKit.painted(tail, func(v: Vector3) -> Color:
		return Color(0.0, 0.08, clampf((-0.95 - v.x) / 1.9, 0.0, 1.0)))])
	var dorsal := MeshKit.fin(PackedVector2Array([Vector2(-0.7, 0.02), Vector2(-0.94, 0.21), Vector2(-1.02, 0.2),
		Vector2(-1.0, 0.02)]), 0.025, 0.0, 0.05)
	parts.append([dorsal])
	return MeshKit.merge(parts)


## A cephalic fin rolled up, along +X from its root: a flattened tube
## swelling a little then tapering to a blunt, rounded tip.
static func _cephalic() -> ArrayMesh:
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in 9:
		var f := i / 8.0
		pts.append(Vector3(0.55 * f, 0.0, 0.0))
		radii.append(0.06 * (1.0 + 0.15 * sin(f * PI)) * (1.0 - 0.45 * f * f))
	var tube := ArrayMesh.new()
	MeshKit.tube(tube, pts, radii, 12)
	var tip := MeshKit.ball(0.034, 0.0, 10, 6)
	var lobe := MeshKit.merge([[tube], [tip, Transform3D(Basis(), pts[8])]])
	lobe = MeshKit.transformed(lobe, Transform3D(Basis.from_scale(Vector3(1.0, 0.62, 1.0)), Vector3.ZERO))
	return MeshKit.painted(lobe, func(v: Vector3) -> Color:
		# Pale on the underside, where it curls; a little free towards the tip.
		return Color(0.0, 0.08 + 0.55 * smoothstep(0.0, -0.03, v.y), clampf(v.x * 0.25, 0.0, 0.12)))


## The disc, body and wings as one surface: round each span station a loop
## from the leading edge back over the top and forward under the belly,
## thick and blunt over the head, thin and sharp out on the wings.
static func _disc() -> ArrayMesh:
	var spans := 120
	var chords := 26
	var loop := chords * 2
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in spans + 1:
		var t := float(i) / spans * 2.0 - 1.0
		var z := HALF_SPAN * signf(t) * pow(absf(t), 1.25)
		var az := absf(z)
		var lead := _edge(LEAD, az)
		var trail := _edge(TRAIL, az)
		var thick := _edge(THICK, az)
		# Blunt over the head, where the mouth is, sharper out on the wings.
		var bluntness := lerpf(0.3, 0.5, smoothstep(0.3, 0.75, az))
		for k in loop:
			var top := k <= chords
			var c := pow(float(k if top else loop - k) / chords, 1.5)
			var shape := pow(c, bluntness) * pow(1.0 - c, 0.9) / _peak(bluntness)
			var x := lerpf(lead, trail, c)
			var y := thick * shape * (0.62 if top else -0.38)
			# The mouth: the front of the head drawn in a little, a gape
			# across it between the fins.
			var gape := (1.0 - smoothstep(0.0, 0.06, c)) * (1.0 - smoothstep(0.26, 0.36, az))
			x -= 0.05 * gape
			st.set_color(_paint(top))
			st.set_uv(Vector2(x, 0.0))
			st.add_vertex(Vector3(x, y, z))
	for i in spans:
		for k in loop:
			var a := i * loop + k
			var b := i * loop + (k + 1) % loop
			st.add_index(a)
			st.add_index(a + loop)
			st.add_index(b)
			st.add_index(b)
			st.add_index(a + loop)
			st.add_index(b + loop)
	st.generate_normals()
	return st.commit()


## The highest point of a chord shaped c^b (1 - c)^0.9, to scale it to one.
static func _peak(b: float) -> float:
	var c := b / (b + 0.9)
	return pow(c, b) * pow(1.0 - c, 0.9)


## Where a smooth curve through [param pts] ((z, value) pairs) stands at
## [param z].
static func _edge(pts: Array, z: float) -> float:
	var n := pts.size()
	for i in range(1, n):
		var b: Vector2 = pts[i]
		if z <= b.x or i == n - 1:
			var a: Vector2 = pts[i - 1]
			var before: Vector2 = pts[maxi(i - 2, 0)]
			var after: Vector2 = pts[mini(i + 1, n - 1)]
			var f := clampf((z - a.x) / maxf(b.x - a.x, 0.0001), 0.0, 1.0)
			return cubic_interpolate(a.y, b.y, before.y, after.y, f)
	return (pts[n - 1] as Vector2).y


## The disc's own colour, dark above and pale below (its skin is painted
## over it: see [constant PAINT_BOX]).
static func _paint(top: bool) -> Color:
	return Color(0.0, 0.0 if top else 1.0, 0.0)


# --- Behaviour ----------------------------------------------------------------

func behave(delta: float) -> void:
	_t += delta
	_flee = maxf(_flee - delta, 0.0)
	_goal_timer -= delta
	if _goal == Vector2.INF or _goal_timer <= 0.0 or pos.distance_to(_goal) < 6.0:
		_pick_goal()
	var speed := FLEE_SPEED if _flee > 0.0 else SPEED
	var desired := (_goal - pos).normalized() * speed
	var sub := level.player
	if sub and sub.alive:
		var away := pos - sub.pos
		if away.length() < PERSONAL_SPACE * 2.0:
			Wonders.witness("manta")
		if away.length() < PERSONAL_SPACE:
			desired += away.normalized() * speed * (1.0 - away.length() / PERSONAL_SPACE) * 2.0
	steer(desired, 0.6 if _flee <= 0.0 else 1.5, delta)


## Somewhere roomy in clear sight to glide to next, a good way off.
func _pick_goal() -> void:
	_goal_timer = level.rng.randf_range(12.0, 20.0)
	for _i in 12:
		var p := level.layout.random_open_point(level.rng, 5.5, PackedVector2Array([pos]), 14.0)
		if p != Vector2.INF and level.field.line_of_sight(pos, p, radius):
			_goal = p
			return
	_goal = wander_point(pos, 14.0)


func on_damaged(_amount: float, from: Vector2) -> void:
	_flee = 5.0
	_goal = pos + (pos - from).normalized() * 30.0
	_goal_timer = 5.0


# --- Swimming -----------------------------------------------------------------

## Beat and glide: a bout of two or three slow, deep beats, then a glide of
## a few seconds on outstretched wings (a bout always ends with the wings
## level, so the glide settles out of the stroke, never stops it short).
## Bolting, it beats hard and fast without a pause.
func _update_stroke(delta: float) -> void:
	var rate := 0.42
	var want := 1.0
	if _flee > 0.0:
		rate = 0.95
		want = 1.3
		_glide = 0.0
	elif _glide > 0.0:
		_glide -= delta
		rate = 0.2
		want = 0.07
	_swim_clock += delta * rate
	var beats := floori(_swim_clock + _phase / TAU)
	if beats != _beats:
		_beats = beats
		if _flee <= 0.0 and _glide <= 0.0:
			_bout -= 1
			if _bout <= 0:
				# Varied from one glide to the next without touching the
				# level's random stream.
				var h := fposmod(sin(beats * 12.9898 + _phase * 78.233) * 43758.5453, 1.0)
				_glide = 1.8 + h * 2.2
				_bout = 2 + int(h * 2.0)
	var ease := 3.0 if want > _swim_power else 1.4
	_swim_power = lerpf(_swim_power, want, 1.0 - exp(-ease * delta))


## Holds its back to the camera, banking into its turns (turning round
## towards the camera, it rolls its back towards where it is turning); it
## bobs with each beat, rising as its wings sweep down.
func _update_visuals(delta: float) -> void:
	super._update_visuals(delta)
	var roll := TILT * _side() - clampf(_yaw_v * BANK, -0.9, 0.9)
	var ph := _swim_clock * TAU + _phase
	var pitch := 0.035 * cos(ph) * _swim_power
	_tilt.basis = (Basis(Vector3.RIGHT, roll) * Basis(Vector3.BACK, pitch)).scaled(Vector3.ONE * SIZE)
	_tilt.position = _tilt.basis.y * (-0.08 * sin(ph - 0.5) * _swim_power)
