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
## An angler grown old and vast: where a lurelight is naked velvet, she is
## armoured in thick dark scales, her head warty, a crest of bony knobs
## along her skull, and eyes that see nothing but light, with lids that
## squeeze shut when a lamp dazzles her and stay narrowed while she guards
## against it. Her rod is long, and its lamp is caged in glassy ribs like a
## lantern's; a beard of glowing branched barbels hangs from her chin, lit
## and doused with the lure. Her mouth is a cavern ringed with glass fangs.
## Stalking, she sculls slowly, breathing through her jaw, her lure swinging
## and twitching on its rod; winding up, she draws back and her lure goes
## dark; charging, she beats hard, gaping, the lure swept back; lurking, it
## is folded dark over her head.

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
## Model space (before [constant SIZE]): x from the tail to the snout.
## Stations as in [method BodyKit.body]: a lurelight's shape (see
## [Lurelight]), grown and drawn out a little longer: round and deep, the
## head as big as the body, its underside cut away in front by the mouth.
const BODY := [[-2.9, 0.09, 0.16, 0.16, 0.11], [-2.31, 0.27, 0.47, 0.4, 0.14], [-1.32, 0.65, 1.08, 0.94, 0.18],
	[-0.22, 0.97, 1.58, 1.33, 0.14], [0.66, 1.12, 1.76, 1.19, 0.11], [1.54, 1.08, 1.66, 0.76, 0.07],
	[2.24, 0.9, 1.37, 0.4, 0.04], [2.77, 0.65, 0.94, 0.22, 0.0], [3.08, 0.32, 0.47, 0.13, -0.02],
	[3.23, 0.04, 0.05, 0.04, -0.04]]
const BODY_LENGTH := 6.13
## The lower jaw's hinge and the jaw (jaw space, x from the hinge forward):
## deep under the throat, sweeping up to a chin jutting past the snout.
const HINGE := Vector3(0.62, -0.68, 0.0)
const JAW := [[-0.11, 0.76, 0.18, 0.36, -0.04], [0.66, 0.94, 0.18, 0.54, 0.0], [1.54, 0.83, 0.16, 0.54, 0.14],
	[2.31, 0.58, 0.14, 0.4, 0.4], [2.86, 0.29, 0.13, 0.23, 0.65], [3.12, 0.09, 0.07, 0.09, 0.76]]
const JAW_LEN := 3.12
const EYE_AT := Vector3(2.42, 0.66, 0.74)
const EYE_R := 0.15
## Where the rod leaves the brow, and where its lamp hangs at rest.
const ROD_BASE := Vector3(2.16, 1.51, 0.0)
const TIP_REST := Vector3(4.9, 1.7, 0.0)

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
var _jaw: MeshInstance3D
var _body: MeshInstance3D
var _rod_mesh := ArrayMesh.new()
var _cheek_mesh := ArrayMesh.new()
var _esca: Node3D
var _esca_mat: StandardMaterial3D
var _cage_mat: StandardMaterial3D
var _lure_light: OmniLight3D
var _lids: Array[Node3D] = []
## How far shut her eyes are, and where the lamp is (model space) and how
## fast it is moving, and the next twitch.
var _shut := 0.0
var _tip := TIP_REST
var _tip_v := Vector3.ZERO
var _twitch_wait := 2.0


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
	body_span = BODY_LENGTH
	flex = 0.3
	flex_pivot = 0.6
	var mat := species_material(func(m: ShaderMaterial) -> void:
		m.set_shader_parameter(&"back_color", Color(0.045, 0.042, 0.05))
		m.set_shader_parameter(&"belly_color", Color(0.15, 0.1, 0.09))
		m.set_shader_parameter(&"glow_color", LURE_COLOR)
		m.set_shader_parameter(&"glow_strength", 1.8)
		m.set_shader_parameter(&"rim_strength", 0.35)
		m.set_shader_parameter(&"roughness", 0.55)
		m.set_shader_parameter(&"metallic", 0.22)
		# Armour: thick overlapping scales over the body, bare pitted skin on
		# the head.
		m.set_shader_parameter(&"scale_size", 0.17)
		m.set_shader_parameter(&"scale_depth", 0.5)
		m.set_shader_parameter(&"scale_shade", 0.45)
		m.set_shader_parameter(&"scale_head_x", 1.3)
		m.set_shader_parameter(&"skin_pits", 0.02)
		m.set_shader_parameter(&"skin_tex", Lurelight._skin())
		m.set_shader_parameter(&"skin_tex_scale", 1.1)
		m.set_shader_parameter(&"skin_tex_depth", 0.03)
		m.set_shader_parameter(&"skin_tex_shade", 0.3)
		m.set_shader_parameter(&"mottle", 0.35)
		m.set_shader_parameter(&"body_length", BODY_LENGTH)
		# A slow, heavy beat of the tail end, the great head steady.
		m.set_shader_parameter(&"swim_amp", 0.5)
		m.set_shader_parameter(&"swim_freq", 1.9)
		m.set_shader_parameter(&"swim_wave", 1.1)
		m.set_shader_parameter(&"swim_vertical", 0.0)
		m.set_shader_parameter(&"swim_head", 0.04)
		m.set_shader_parameter(&"swim_still", 0.18)
		m.set_shader_parameter(&"fin_lag", 0.4)
		m.set_shader_parameter(&"bend_pivot", 0.6)
		m.set_shader_parameter(&"anchored", true)
		m.set_shader_parameter(&"flutter_amp", 0.16)
		m.set_shader_parameter(&"flutter_freq", 3.2)
		m.set_shader_parameter(&"flutter_wave", 2.6)
		m.set_shader_parameter(&"fin_color", Color(0.05, 0.05, 0.06, 1.0))
		m.set_shader_parameter(&"tooth_color", Color(0.66, 0.74, 0.78)))
	_body = add_visual(_body_mesh(), mat)
	_jaw = add_visual(_jaw_mesh(), mat, Transform3D(Basis(), HINGE))
	# The corners of the mouth, stretching as it gapes, and the dark throat.
	var cheeks := MeshInstance3D.new()
	cheeks.mesh = _cheek_mesh
	cheeks.material_override = mat
	cheeks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(cheeks)
	visuals.append(cheeks)
	var throat := MeshInstance3D.new()
	throat.mesh = MeshKit.sphere(1.0, 16, 8)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.03, 0.006, 0.012)
	dark.roughness = 0.9
	dark.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	throat.material_override = dark
	throat.transform = Transform3D(Basis().scaled(Vector3(1.1, 0.43, 0.68)), Vector3(1.76, -0.36, 0.0))
	model.add_child(throat)
	# Great eyes that see light, under lids that can shut.
	add_eyes(EYE_AT, EYE_R, Color(0.72, 0.9, 0.5), 0.5, Eye.FISH)
	var lid_mat := StandardMaterial3D.new()
	lid_mat.albedo_color = Color(0.06, 0.055, 0.065)
	lid_mat.roughness = 0.6
	lid_mat.metallic = 0.25
	lid_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var lid_mesh := SphereMesh.new()
	lid_mesh.radius = EYE_R * 1.25
	lid_mesh.height = EYE_R * 1.25
	lid_mesh.is_hemisphere = true
	lid_mesh.radial_segments = 18
	lid_mesh.rings = 6
	for k in 2:
		var eye: Node3D = _riders[_riders.size() - 2 + k][0]
		var lid := MeshInstance3D.new()
		lid.mesh = lid_mesh
		lid.material_override = lid_mat
		lid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eye.add_child(lid)
		_lids.append(lid)
	# The rod (rebuilt as it bends) and its lamp: a glowing bulb in a cage of
	# glassy ribs, filaments trailing below.
	var rod := MeshInstance3D.new()
	rod.mesh = _rod_mesh
	rod.material_override = mat
	rod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(rod)
	visuals.append(rod)
	_esca = Node3D.new()
	model.add_child(_esca)
	var bulb := MeshInstance3D.new()
	bulb.mesh = MeshKit.sphere(0.26, 18, 10)
	_esca_mat = MeshKit.emissive_material(LURE_COLOR, 6.0)
	bulb.material_override = _esca_mat
	_esca.add_child(bulb)
	_cage_mat = StandardMaterial3D.new()
	_cage_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cage_mat.albedo_color = Color(0.55, 0.9, 0.82, 0.55)
	_cage_mat.roughness = 0.1
	_cage_mat.emission_enabled = true
	_cage_mat.emission = Color(0.35, 0.85, 0.72)
	_cage_mat.emission_energy_multiplier = 1.2
	var cage := MeshInstance3D.new()
	cage.mesh = _lantern()
	cage.material_override = _cage_mat
	cage.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_esca.add_child(cage)
	_lure_light = OmniLight3D.new()
	_lure_light.light_color = LURE_COLOR
	_lure_light.omni_range = 16.0
	_lure_light.light_energy = 2.6
	_lure_light.light_volumetric_fog_energy = 2.5
	_lure_light.position = Vector3(0.0, 0.0, 0.8)
	_esca.add_child(_lure_light)
	_pose_lure()
	_rebuild_cheeks()


## The body: armoured, a crest of bony knobs along the skull, rows of
## photophores down each flank, ragged fins, and long glass fangs down the
## upper jaw.
static func _body_mesh() -> ArrayMesh:
	var parts := [[BodyKit.body(BODY, 64, 30)]]
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	# Two rows of photophores down each flank: small glowing beads.
	var bead := MeshKit.ball(0.05, 1.0, 8, 5)
	for sgn: float in [1.0, -1.0]:
		for row in 2:
			for i in 11:
				var x := lerpf(1.7, -1.5, i / 10.0) + rng.randf_range(-0.04, 0.04)
				var a := PI * (0.52 + 0.14 * row) + rng.randf_range(-0.02, 0.02)
				var at := BodyKit.surface(BODY, x, a if sgn > 0.0 else TAU - a)
				parts.append([bead, Transform3D(Basis(), at * Vector3(1.0, 1.0, 0.985)), x])
	# The crest: bony knobs down the midline of the skull.
	for i in 7:
		var x := lerpf(2.75, 1.2, i / 6.0)
		var top := BodyKit.at(BODY, x, 4) + BodyKit.at(BODY, x, 2)
		var knob := BodyKit.tooth(0.07 + 0.02 * sin(i * 1.7), 0.2 + rng.randf_range(0.0, 0.1), 0.3, 6)
		var aim := Basis(Vector3.BACK, PI + 0.35)
		parts.append([MeshKit.painted(knob, func(_v: Vector3) -> Color: return Color(0.0, 0.15, 0.0)),
			Transform3D(aim, Vector3(x, top - 0.02, 0.0)), x])
	# Fins: a ragged spiny dorsal down the back, a soft anal fin, a broad
	# tail fan and paddle pectorals behind the gills.
	var roots := PackedVector2Array()
	var tips := PackedVector2Array()
	for i in 11:
		var f := i / 10.0
		var x := lerpf(0.4, -1.95, f)
		var edge := BodyKit.at(BODY, x, 4) + BodyKit.at(BODY, x, 2)
		roots.append(Vector2(x, edge - 0.05))
		tips.append(Vector2(x - 0.2, edge + lerpf(0.75, 0.25, f) * (0.8 + 0.4 * absf(sin(i * 2.3)))))
	parts.append([BodyKit.ray_fin(roots, tips, 0.25, 0.08, 0.03, 0.03, 0.0, 2, 5)])
	roots = PackedVector2Array()
	tips = PackedVector2Array()
	for i in 6:
		var f := i / 5.0
		var x := lerpf(-1.1, -2.0, f)
		var edge := BodyKit.at(BODY, x, 4) - BodyKit.at(BODY, x, 3)
		roots.append(Vector2(x, edge + 0.05))
		tips.append(Vector2(x - 0.3, edge - lerpf(0.55, 0.25, f)))
	parts.append([BodyKit.ray_fin(roots, tips, 0.2, 0.06, 0.025, 0.03, 0.0, 2, 4)])
	roots = PackedVector2Array()
	tips = PackedVector2Array()
	for i in 11:
		var f := i / 10.0
		roots.append(Vector2(-2.78, lerpf(0.3, -0.06, f)))
		var a := lerpf(0.8, -0.8, f)
		var reach := lerpf(1.0, 1.15, 1.0 - absf(f - 0.5) * 2.0) * (0.85 + 0.25 * absf(sin(i * 1.9)))
		tips.append(Vector2(-2.78, 0.12) + Vector2(-cos(a), sin(a)) * reach)
	parts.append([BodyKit.ray_fin(roots, tips, 0.22, 0.06, 0.03, 0.03, 0.0, 2, 6)])
	var pec := BodyKit.ray_fin(PackedVector2Array([Vector2(0.1, 0.16), Vector2(0.04, 0.08), Vector2(-0.02, 0.0),
		Vector2(-0.08, -0.08), Vector2(-0.14, -0.16)]), PackedVector2Array([Vector2(-0.5, 0.5), Vector2(-0.68, 0.26),
		Vector2(-0.74, 0.0), Vector2(-0.66, -0.26), Vector2(-0.48, -0.44)]), 0.18, 0.06, 0.02, 0.025, 0.0, 2, 5)
	for sgn: float in [1.0, -1.0]:
		parts.append([pec, Transform3D(Basis(Vector3.UP, -0.5 * sgn), Vector3(0.26, -0.18, 1.0 * sgn)), 0.26])
	# Long glass fangs down the upper jaw, the longest at the front.
	for sgn: float in [1.0, -1.0]:
		for t: Array in BodyKit.teeth_row(_upper_lip(1.32, sgn), _upper_lip(2.99, sgn), 11, 0.56,
				Vector3(0.15, -1.0, -0.35 * sgn), 21 if sgn > 0.0 else 22):
			parts.append([BodyKit.enamel(t[0]), t[1], (t[1] as Transform3D).origin.x])
	return BodyKit.merged(parts)


## The lower jaw (jaw space): a deep scoop with fangs along its rim leaning
## in to the throat, and under the chin a beard of glowing branched barbels
## that sway (vertex colour B) and glow with the lure.
static func _jaw_mesh() -> ArrayMesh:
	var parts := [[BodyKit.body(JAW, 44, 26)]]
	for sgn: float in [1.0, -1.0]:
		for t: Array in BodyKit.teeth_row(_jaw_rim(0.55, sgn), _jaw_rim(2.86, sgn), 12, 0.68,
				Vector3(-0.25, 1.0, -0.45 * sgn), 23 if sgn > 0.0 else 24):
			parts.append([BodyKit.enamel(t[0]), t[1], (t[1] as Transform3D).origin.x])
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for k in 9:
		var u := lerpf(1.9, 2.9, rng.randf())
		var root := Vector3(u, BodyKit.at(JAW, u, 4) - BodyKit.at(JAW, u, 3) * 0.7, rng.randf_range(-0.3, 0.3))
		var length := rng.randf_range(0.6, 1.3)
		var bend := Vector3(rng.randf_range(-0.25, 0.1), 0.0, rng.randf_range(-0.2, 0.2))
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		for i in 7:
			var f := i / 6.0
			pts.append(root + Vector3(0.0, -length * f, 0.0) + bend * f * f)
			radii.append(lerpf(0.035, 0.01, f))
		var stalk := ArrayMesh.new()
		MeshKit.tube(stalk, pts, radii, 5)
		parts.append([MeshKit.painted(stalk, func(v: Vector3) -> Color:
			var f := clampf((root.y - v.y) / length, 0.0, 1.0)
			return Color(0.15 + 0.6 * f, 0.4, f * 0.8))])
		# A twig or two off each, and a glowing bead at every tip.
		var bead := MeshKit.ball(0.05, 1.0, 6, 4)
		parts.append([MeshKit.painted(bead, func(_v: Vector3) -> Color: return Color(1.0, 0.4, 0.8)),
			Transform3D(Basis(), pts[6])])
		for b in 2:
			var from := pts[2 + b * 2]
			var dir := Vector3(rng.randf_range(-0.4, 0.4), -0.6, rng.randf_range(-0.5, 0.5)).normalized()
			var twig := PackedVector3Array([from, from + dir * 0.18, from + dir * 0.34 + Vector3(0, -0.06, 0)])
			var twig_mesh := ArrayMesh.new()
			MeshKit.tube(twig_mesh, twig, PackedFloat32Array([0.015, 0.011, 0.008]), 4)
			parts.append([MeshKit.painted(twig_mesh, func(_v: Vector3) -> Color: return Color(0.5, 0.4, 0.7))])
			parts.append([MeshKit.painted(MeshKit.ball(0.03, 1.0, 5, 3), func(_v: Vector3) -> Color:
				return Color(1.0, 0.4, 0.8)), Transform3D(Basis(), twig[2])])
	return BodyKit.merged(parts)


## The lamp's cage: glassy ribs curving round the bulb from its stalk to
## a point below it, like a lantern's, and filaments trailing beneath.
static func _lantern() -> ArrayMesh:
	var parts := []
	for k in 6:
		var a := TAU * k / 6.0
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		for i in 9:
			var f := i / 8.0
			var r := 0.36 * sin(PI * f) + 0.03
			pts.append(Vector3(cos(a) * r, 0.42 - 0.84 * f, sin(a) * r))
			radii.append(0.022)
		var rib := ArrayMesh.new()
		MeshKit.tube(rib, pts, radii, 4)
		parts.append([rib])
	for k in 5:
		var a := TAU * k / 5.0 + 0.3
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		for i in 7:
			var f := i / 6.0
			pts.append(Vector3(cos(a) * 0.1 * (1.0 + f), -0.42 - f * (0.5 + 0.12 * k), sin(a) * 0.1 * (1.0 + f)))
			radii.append(lerpf(0.018, 0.006, f))
		var thread := ArrayMesh.new()
		MeshKit.tube(thread, pts, radii, 4)
		parts.append([thread])
	return MeshKit.merge(parts)


## The upper jaw's edge on side [param sgn] at model x [param x].
static func _upper_lip(x: float, sgn: float) -> Vector3:
	var hw := BodyKit.at(BODY, x, 1)
	return Vector3(x, BodyKit.at(BODY, x, 4) - BodyKit.at(BODY, x, 3) * 0.8, hw * 0.75 * sgn)


## The lower jaw's rim on side [param sgn], [param u] along it (jaw space).
static func _jaw_rim(u: float, sgn: float) -> Vector3:
	return Vector3(u, BodyKit.at(JAW, u, 4) + BodyKit.at(JAW, u, 2) * 0.8, BodyKit.at(JAW, u, 1) * 0.88 * sgn)


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
			# Reeling from the light: a jolt back as it strikes her, then she
			# hangs there dazed, sinking a little, until she shakes it off.
			var reel := exp(-(DAZZLE_TIME[phase] - _timer) * 3.0)
			vel = vel.lerp(-facing * 2.5 * reel + Vector2(0.0, -0.35), 1.0 - exp(-3.0 * delta))
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
	elif state == State.WINDUP:
		# Drawing back to charge, head up.
		model.basis = model.basis * Basis(Vector3.BACK, 0.12 * clampf(1.0 - _timer / WINDUP_TIME, 0.0, 1.0))
	# Breathing: the jaw pumps slowly while she stalks.
	var breath := 0.06 * pow(0.5 + 0.5 * sin(_t * 1.2), 2.0) if state == State.STALK else 0.0
	_jaw.rotation.z = -(_jaw_open + breath) * 0.75
	_pose_eyes(delta)
	_swing_lure(delta)
	_pose_lure()
	_rebuild_cheeks()
	# (Unshaded, the bulb shows its colour as it is: dimmed with the light,
	# so doused it is dark.)
	_esca_mat.albedo_color = LURE_COLOR * (0.06 + 0.94 * minf(_lure_k, 1.0))
	_esca_mat.emission_energy_multiplier = 0.2 + 6.0 * _lure_k
	_cage_mat.emission_energy_multiplier = 0.05 + 1.1 * _lure_k
	_cage_mat.albedo_color.a = 0.25 + 0.3 * minf(_lure_k, 1.0)
	_lure_light.light_energy = 2.8 * _lure_k
	# The beard and the flank lights burn with the lure.
	_jaw.set_instance_shader_parameter(&"glow_boost", 0.1 + 1.2 * _lure_k)
	_body.set_instance_shader_parameter(&"glow_boost", 0.15 + 0.85 * _lure_k)


## Her lids: squeezed shut, fluttering, while she reels; narrowed while she
## guards against light; open otherwise. Each lid turns down over its eye
## from inside the brow.
func _pose_eyes(delta: float) -> void:
	var want := 0.0
	if state == State.DAZZLED:
		want = 1.0 - 0.06 * absf(sin(_t * 23.0))
	elif stun_guard > 0.0 and active:
		want = 0.62
	elif state == State.DEAD:
		want = 1.0
	_shut = lerpf(_shut, want, 1.0 - exp(-(14.0 if want > _shut else 5.0) * delta))
	for k in _lids.size():
		var sgn := 1.0 if k == 0 else -1.0
		# Open, the lid's dome points up and in, hidden in the brow; shut, it
		# points out over the eye.
		var angle := lerpf(-1.1, PI * 0.5, _shut) * sgn
		_lids[k].basis = Basis(Vector3.RIGHT, angle)


## The lamp swings on its rod, on a spring: dangling ahead of the mouth,
## swaying in slow loops and bobbing, twitching now and then; swept back as
## she charges, folded back over her head as she lurks, flicked up out of
## the way as she snaps.
func _swing_lure(delta: float) -> void:
	var rest := TIP_REST + Vector3(sin(_t * 0.5) * 0.3, sin(_t * 0.9) * 0.2 + sin(_t * 0.31) * 0.12,
		sin(_t * 0.7 + 0.6) * 0.4)
	match state:
		State.CHARGE:
			rest = Vector3(3.0, 2.8, 0.0)
		State.WINDUP:
			rest = Vector3(3.9, 2.4, 0.0)
		State.SNAP, State.FEED:
			rest = Vector3(3.7, 3.0, 0.0)
		State.LURK, State.DEAD:
			rest = Vector3(2.1, 2.9, 0.0)
		State.STALK:
			_twitch_wait -= delta
			if _twitch_wait <= 0.0:
				_twitch_wait = 1.6 + fposmod(sin(_t * 7.31) * 43758.5, 2.8)
				var r := fposmod(sin(_t * 3.17) * 12345.6, 1.0)
				_tip_v += Vector3(lerpf(-3.5, 4.0, r), lerpf(2.6, -2.2, fposmod(r * 7.0, 1.0)),
					lerpf(-2.5, 2.5, fposmod(r * 13.0, 1.0)))
	_tip_v += ((rest - _tip) * 40.0 - _tip_v * 6.0) * delta
	_tip += _tip_v * delta


## Bends the rod from the brow to where the lamp is: up and forward, then
## arching down to it.
func _pose_lure() -> void:
	var tip := _tip
	var c1 := ROD_BASE + Vector3(0.55, 1.45, 0.0)
	var c2 := tip + Vector3(-0.33, 1.0, 0.0)
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in 21:
		var t := i / 20.0
		var a := 1.0 - t
		pts.append(ROD_BASE * a * a * a + c1 * 3.0 * a * a * t + c2 * 3.0 * a * t * t + tip * t * t * t)
		# Jointed: a swelling every few segments.
		radii.append(lerpf(0.11, 0.04, t) * (1.0 + 0.25 * maxf(sin(t * PI * 7.0), 0.0) ** 6))
	MeshKit.tube(_rod_mesh, pts, radii, 8)
	_esca.position = tip - Vector3(0.0, 0.42, 0.0)


## The corners of the mouth: skin from the upper jaw's edge down to the
## lower jaw's rim, from the hinge forward, stretching into a web as the
## mouth gapes.
func _rebuild_cheeks() -> void:
	var rot := Basis(Vector3.BACK, _jaw.rotation.z)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := 8
	var cols := 5
	var at := 0
	for sgn: float in [1.0, -1.0]:
		var grid := PackedVector3Array()
		for k in rows + 1:
			var t := k / float(rows)
			for j in cols + 1:
				var f := j / float(cols)
				var u := 1.2 * t * (1.0 - 0.4 * sin(PI * f) * t)
				var rim := HINGE + rot * _jaw_rim(u, sgn)
				var lip := _upper_lip(HINGE.x + u + 0.26, sgn)
				var p := lip.lerp(rim, f)
				p.z += sgn * sin(PI * f) * (0.04 + 0.15 * _jaw_open) * sin(PI * 0.5 * t)
				grid.append(p)
		for side in 2:
			st.set_smooth_group(side + (2 if sgn < 0.0 else 0))
			for g in grid:
				st.set_color(Color(0.0, 0.4, 0.0) if side == 0 else Color(0.0, 1.0, 0.0))
				st.set_uv(Vector2(g.x, 0.5))
				st.add_vertex(g)
			var start := at + side * grid.size()
			var outward := (side == 0) != (sgn > 0.0)
			for k in rows:
				for j in cols:
					var a := start + k * (cols + 1) + j
					var quad := [a, a + 1, a + cols + 1, a + 1, a + cols + 2, a + cols + 1] if outward \
						else [a, a + cols + 1, a + 1, a + 1, a + cols + 1, a + cols + 2]
					for i: int in quad:
						st.add_index(i)
		at += grid.size() * 2
	st.generate_normals()
	_cheek_mesh.clear_surfaces()
	st.commit(_cheek_mesh)
