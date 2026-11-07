class_name Siphonophore
extends Creature
## A drifting colony: a chain of glowing bells strung behind a swimming head,
## tens of meters long. Beautiful, slow and stinging along its whole length -
## and not something a harpoon can kill: a colony of thousands just closes
## round the wound. It stings whatever brushes it, hunters included, so it is
## a hazard to steer round, or to lead a pack of hunters through.
## The colony is drawn as the animal is built: at its head a little gas
## float and a stack of glass swimming bells that pulse by turns, driving it
## along; behind them one long stem, and strung along it the lanterns - each
## a clear, rounded shield of jelly over a feeding polyp that glows like a
## flame inside it, with a fishing tentacle hanging below, fringed with side
## branches tipped by glowing stinging knobs. The tentacles trail as the
## colony swims and snatch up short when it stings, and a wave of light runs
## down the chain from time to time, brightest where it has just stung.

const SEGMENTS := 18
const SPACING := 1.3
## What a sting does to another creature.
const CREATURE_STING := 14.0
## The lanterns ride the stem at every knot of the chain behind the head.
const FIRST_KNOT := 2
const LANTERNS := SEGMENTS - FIRST_KNOT
## Swimming bells: how many, and each one's length (model X, from its
## opening at 0 to its apex) and radius.
const BELLS := 6
const BELL_L := 0.64
const BELL_R := 0.32
## The head, from the float at its tip back to where the stem leaves it.
const HEAD_L := 2.15
const TENTACLE_L := 2.8
## The lanterns' size at full growth.
const LANTERN_SCALE := 1.25
## Where a lantern's tentacle hangs from (lantern space).
const TENTACLE_ROOT := Vector3(-0.02, -0.4, 0.04)
## Stem samples between knots.
const STEPS := 6
const STEM_SIDES := 6

static var _meshes: Dictionary[StringName, ArrayMesh] = {}

var segments := PackedVector2Array()
var _goal := Vector2.ZERO
var _home := Vector2.ZERO
var _t := 0.0
## The chain as drawn this frame (local to the creature): the rope's knots,
## swaying and weaving a little in depth.
var _points := PackedVector3Array()
var _last_points := PackedVector3Array()
## How far the creature (the chain's origin) moved since the last frame.
var _shift := Vector3.ZERO
var _clock := 0.0
var _spin := 0.0
var _pulse := 0.0
var _alarm := 0.0
var _bells: Array[MeshInstance3D] = []
## Each bell as it sits on the stem (about the point of the stem it hangs
## from), and how far down the stem that point is.
var _bell_rest: Array[Transform3D] = []
var _bell_at := PackedFloat32Array()
## The stem as drawn this frame: points along it and how far along each is.
var _curve := PackedVector3Array()
var _curve_s := PackedFloat32Array()
var _stem_mesh := ArrayMesh.new()
var _float: MeshInstance3D
var _shields: MultiMesh
var _polyps: MultiMesh
var _tentacles: MultiMesh
var _tentacle_node: MultiMeshInstance3D
## Per lantern: how its tentacle is being dragged through the water, how
## far it is drawn up, and how startled the lantern is.
var _drag := PackedVector2Array()
var _curl := PackedFloat32Array()
var _startle := PackedFloat32Array()
## Flashes running out from a sting: [knot, age].
var _flashes: Array[Vector2] = []


func setup() -> void:
	species = &"siphon"
	max_hp = 40.0
	radius = 0.9
	mass = 3.0
	contact_damage = 9.0
	salvage_drop = 7
	hostile = false
	glow_color = level.biome.glow_color.lerp(Color(0.6, 0.8, 1.0), 0.5)
	super.setup()
	# Weapons find nothing to hold on to (it can still be scanned).
	targetable = false
	_home = pos
	_goal = wander_point(_home, 25.0)
	for i in SEGMENTS:
		segments.append(pos + Vector2(-i * SPACING, 0))
	_drag.resize(LANTERNS)
	_curl.resize(LANTERNS)
	_startle.resize(LANTERNS)
	_clock = _phase * 3.0
	_lay_out(0.0)


func build_model() -> void:
	var glow := glow_color
	# The lanterns burn warm against the cold light of the stinging knobs.
	var warm := glow.lerp(Color(1.0, 0.6, 0.28), 0.7)
	var glass := species_material(func(m: ShaderMaterial) -> void:
		_glass(m, glow)
		m.set_shader_parameter(&"glow_strength", 2.4)
		m.set_shader_parameter(&"glass_alpha", 0.035)
		m.set_shader_parameter(&"glass_rim", 0.3)
		m.set_shader_parameter(&"bell_top", BELL_L)
		m.set_shader_parameter(&"bell_rim", 0.0), &"glass", GLASS_SHADER)
	var lantern_glass := species_material(func(m: ShaderMaterial) -> void:
		_glass(m, warm)
		m.set_shader_parameter(&"glow_strength", 2.0), &"lantern", GLASS_SHADER)
	var flesh := species_material(func(m: ShaderMaterial) -> void:
		_still(m)
		m.set_shader_parameter(&"back_color", Color(0.7, 0.26, 0.1))
		m.set_shader_parameter(&"belly_color", Color(0.86, 0.48, 0.24))
		m.set_shader_parameter(&"glow_color", warm)
		m.set_shader_parameter(&"glow_strength", 3.2)
		m.set_shader_parameter(&"glow_pulse", 0.15)
		m.set_shader_parameter(&"rim_strength", 0.35)
		m.set_shader_parameter(&"roughness", 0.32)
		m.set_shader_parameter(&"metallic", 0.0), &"flesh")
	var threads := species_material(func(m: ShaderMaterial) -> void:
		m.set_shader_parameter(&"back_color", Color(0.56, 0.42, 0.4))
		m.set_shader_parameter(&"belly_color", Color(0.64, 0.5, 0.46))
		m.set_shader_parameter(&"glow_color", glow)
		m.set_shader_parameter(&"glow_strength", 2.6)
		m.set_shader_parameter(&"rim_strength", 0.3)
		m.set_shader_parameter(&"roughness", 0.4)
		m.set_shader_parameter(&"metallic", 0.0)
		# Each hangs from its root (model +X) and sways in slow waves that
		# run down it, growing to its tip.
		m.set_shader_parameter(&"body_length", TENTACLE_L)
		m.set_shader_parameter(&"swim_amp", 0.42)
		m.set_shader_parameter(&"swim_freq", 1.1)
		m.set_shader_parameter(&"swim_wave", 1.7)
		m.set_shader_parameter(&"swim_vertical", 1.0)
		m.set_shader_parameter(&"swim_head", 0.0)
		m.set_shader_parameter(&"swim_still", 0.0)
		m.set_shader_parameter(&"bend_pivot", TENTACLE_L * 0.5)
		m.set_shader_parameter(&"flutter_amp", 0.06)
		m.set_shader_parameter(&"flutter_freq", 1.7)
		m.set_shader_parameter(&"flutter_wave", 2.0), &"threads")
	_build_meshes()
	# The head: the float and its ring of swimming bells, slowly turning,
	# each laid on the stem where it hangs so the head bends with it.
	_float = _part(_meshes[&"float"], flesh, model)
	for k in BELLS:
		# Two rows, one either side of the stem, each bell half a bell behind
		# the one across from it.
		var a := (0.0 if k % 2 == 0 else PI) + (0.3 if k % 4 < 2 else -0.3)
		var out := Vector3(0.0, cos(a), sin(a))
		var x := -0.36 - k * 0.3
		# Apex forward and in towards the stem, opening back and out.
		var axis := (Vector3.RIGHT - out * 0.3).normalized()
		var side := out - axis * out.dot(axis)
		var basis := Basis(axis, side.normalized(), axis.cross(side.normalized()))
		_bells.append(_part(_meshes[&"bell"], glass, self))
		_bell_rest.append(Transform3D(basis, out * 0.2 - axis * BELL_L * 0.5))
		_bell_at.append(-x)
	var stem := _part(_stem_mesh, flesh, self)
	stem.extra_cull_margin = 4.0
	_shields = _multimesh(_meshes[&"shield"], lantern_glass).multimesh
	_polyps = _multimesh(_meshes[&"polyp"], flesh).multimesh
	_tentacle_node = _multimesh(_meshes[&"tentacle"], threads)
	_tentacles = _tentacle_node.multimesh


## A part of the colony drawn with [param mat], under [param parent].
func _part(mesh: Mesh, mat: Material, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	visuals.append(mi)
	return mi


## One of [param mesh] at every lantern, each with its own light.
func _multimesh(mesh: Mesh, mat: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = LANTERNS
	for j in LANTERNS:
		mm.set_instance_color(j, Color.WHITE)
		mm.set_instance_custom_data(j, Color(0, 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	visuals.append(mmi)
	return mmi


## Glass and flesh hold their shape: the colony's sway is laid out on the CPU.
static func _still(m: ShaderMaterial) -> void:
	m.set_shader_parameter(&"swim_amp", 0.0)
	m.set_shader_parameter(&"flutter_amp", 0.0)


## Clear jelly, faintly blue, lit from within by [param light].
static func _glass(m: ShaderMaterial, light: Color) -> void:
	_still(m)
	m.set_shader_parameter(&"back_color", Color(0.62, 0.7, 0.82))
	m.set_shader_parameter(&"belly_color", Color(0.7, 0.76, 0.86))
	m.set_shader_parameter(&"glow_color", light)
	m.set_shader_parameter(&"glow_strength", 1.8)
	m.set_shader_parameter(&"rim_strength", 0.45)
	m.set_shader_parameter(&"roughness", 0.06)
	m.set_shader_parameter(&"metallic", 0.0)
	m.set_shader_parameter(&"glass_alpha", 0.06)
	m.set_shader_parameter(&"glass_rim", 0.4)
	m.set_shader_parameter(&"glass_fin", 0.8)


# --- Meshes -----------------------------------------------------------------

static func _build_meshes() -> void:
	if not _meshes.is_empty():
		return
	_meshes[&"bell"] = _bell_mesh(1.0, 0.55)
	_meshes[&"float"] = _float_mesh()
	_meshes[&"shield"] = _shield_mesh()
	_meshes[&"polyp"] = _polyp_mesh()
	_meshes[&"tentacle"] = _tentacle_mesh()


## A swimming bell (nectophore): a thick cup of clear jelly, squarish with
## four soft ridges, its apex at model +X and its opening at x = 0; four
## radial canals and a ring canal round the opening glow faintly through it.
static func _bell_mesh(size: float, canal_glow: float) -> ArrayMesh:
	var l := BELL_L * size
	var r := BELL_R * size
	var outer := [Vector2(l, 0.0), Vector2(0.97 * l, 0.35 * r), Vector2(0.88 * l, 0.66 * r),
		Vector2(0.7 * l, 0.88 * r), Vector2(0.45 * l, 0.98 * r), Vector2(0.2 * l, r), Vector2(0.05 * l, 0.95 * r),
		Vector2(0.0, 0.86 * r)]
	var inner := [Vector2(0.02 * l, 0.72 * r), Vector2(0.2 * l, 0.75 * r), Vector2(0.45 * l, 0.68 * r),
		Vector2(0.64 * l, 0.48 * r), Vector2(0.73 * l, 0.0)]
	var paint := func(x: float, a: float, under: bool) -> Color:
		var canal := 1.0 - smoothstep(0.0, 0.12, absf(fposmod(a + PI * 0.25, PI * 0.5) - PI * 0.25))
		var ring := 1.0 - smoothstep(0.02 * l, 0.08 * l, x)
		var lit := maxf(canal * 0.8 + 0.05, ring) if under else maxf(canal * 0.12, ring * 0.7)
		return Color(lit * canal_glow / 0.55, 0.2, 0.0)
	return _revolve(outer + inner, 32, paint, 0.85)


## The gas float at the very tip: a small, red-amber teardrop, its point
## glowing.
static func _float_mesh() -> ArrayMesh:
	var profile := PackedVector2Array([Vector2(0.0, 0.02), Vector2(0.12, 0.7), Vector2(0.45, 1.0),
		Vector2(0.8, 0.78), Vector2(1.0, 0.0)])
	var lit := func(t: float, _a: float) -> float: return 0.15 + 0.85 * smoothstep(0.7, 1.0, t)
	var drop := MeshKit.lathe(profile, 0.32, 12, 10, 0.11, 0.11, lit)
	return MeshKit.transformed(drop, Transform3D(Basis(), Vector3(0.08, 0.0, 0.0)))


## A lantern's glass: the bract, a clear rounded shield of jelly closed
## round the stem (model X along it) and the top of the polyp below it, a
## canal glowing along its crown and its lower half lit from within by the
## polyp, with a pair of small budding bells tucked inside.
static func _shield_mesh() -> ArrayMesh:
	var profile := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.06, 0.55), Vector2(0.28, 0.93),
		Vector2(0.55, 1.0), Vector2(0.82, 0.86), Vector2(0.95, 0.5), Vector2(1.0, 0.0)])
	var canal := func(t: float, a: float) -> float:
		return 0.45 * smoothstep(0.92, 1.0, cos(a)) * sin(PI * t) + 0.16 * pow(sin(PI * t), 2.0) * (0.5 - cos(a) * 0.5)
	var shield := MeshKit.lathe(profile, 0.76, 18, 14, 0.3, 0.32, canal)
	var parts := [[shield, Transform3D(Basis(), Vector3(0.0, -0.06, 0.0))]]
	var bud := _bell_mesh(0.3, 0.9)
	for s: float in [-1.0, 1.0]:
		var axis := Vector3(1.0, 0.2, -0.3 * s).normalized()
		var side := Vector3(0.0, 0.0, s).cross(axis).normalized()
		parts.append([bud, Transform3D(Basis(axis, side, axis.cross(side)), Vector3(0.1, -0.24, 0.12 * s))])
	return MeshKit.merge(parts)


## A lantern's flesh: the feeding polyp hanging from the stem, a slim stalk
## swelling into a stomach that glows like a flame and narrowing to a
## flared mouth, and the stub of its tentacle beside it.
static func _polyp_mesh() -> ArrayMesh:
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	var shape := [Vector2(0.0, 0.03), Vector2(-0.05, 0.06), Vector2(-0.12, 0.1), Vector2(-0.2, 0.085),
		Vector2(-0.28, 0.055), Vector2(-0.36, 0.04), Vector2(-0.45, 0.038), Vector2(-0.53, 0.06)]
	for i in shape.size():
		var y: float = shape[i].x
		pts.append(Vector3(-0.25 * y * y, y, 0.0))
		radii.append(shape[i].y)
	var polyp := ArrayMesh.new()
	MeshKit.tube(polyp, pts, radii, 9)
	var mouth := MeshKit.ball(0.045, 0.0, 9, 5)
	var stub := MeshKit.ball(0.03, 0.0, 6, 4)
	var mesh := MeshKit.merge([[polyp], [mouth, Transform3D(Basis(), pts[pts.size() - 1] + Vector3(0, 0.012, 0))],
		[stub, Transform3D(Basis(), TENTACLE_ROOT)]])
	return MeshKit.painted(mesh, func(v: Vector3) -> Color:
		var core := exp(-pow((v.y + 0.13) / 0.1, 2.0))
		return Color(0.08 + 0.92 * core, clampf(0.5 + v.z * 6.0, 0.0, 1.0), 0.0))


## A fishing tentacle, its root at model +X and its tip at -X: a fine thread
## fringed by side branches, each ending in a knob of stinging cells that
## glows. Threads and knobs flutter more the further down they hang.
static func _tentacle_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4021
	var top := TENTACLE_L * 0.5
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in 33:
		var f := i / 32.0
		pts.append(Vector3(top - TENTACLE_L * f, sin(f * 9.0) * 0.035 * f, cos(f * 7.0) * 0.03 * f))
		radii.append(lerpf(0.026, 0.013, f))
	var thread := ArrayMesh.new()
	MeshKit.tube(thread, pts, radii, 5)
	var parts := [[MeshKit.painted(thread, func(_v: Vector3) -> Color: return Color(0.03, 0.5, 0.0))]]
	var knob := MeshKit.ball(0.04, 1.0, 7, 4)
	for k in 14:
		var f := 0.1 + k * 0.064
		var root := Vector3(top - TENTACLE_L * f, sin(f * 9.0) * 0.035 * f, cos(f * 7.0) * 0.03 * f)
		var s := 1.0 if k % 2 == 0 else -1.0
		var dir := Vector3(-0.6, 0.65 * s, rng.randf_range(-0.45, 0.45)).normalized()
		var length := lerpf(0.3, 0.17, f) * rng.randf_range(0.85, 1.15)
		var twig := PackedVector3Array()
		var twig_r := PackedFloat32Array()
		for i in 5:
			var g := i / 4.0
			# Curling down at the end, as the branches hang.
			twig.append(root + dir * length * g + Vector3(-0.06 * g * g, 0.0, 0.0))
			twig_r.append(lerpf(0.012, 0.009, g))
		var branch := ArrayMesh.new()
		MeshKit.tube(branch, twig, twig_r, 4)
		var along := (twig[4] - twig[3]).normalized()
		var tip := twig[4] + along * 0.02
		var up := along.cross(Vector3.BACK if absf(along.z) < 0.9 else Vector3.UP).normalized()
		var knob_xf := Transform3D(Basis(along * 1.7, up, along.cross(up)), tip)
		parts.append([MeshKit.painted(branch, func(_v: Vector3) -> Color: return Color(0.08, 0.5, 0.0))])
		parts.append([knob, knob_xf])
	# Faint threads, bright knobs (MeshKit.ball paints them glowing); the
	# further down, the freer.
	var mesh := MeshKit.merge(parts)
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for i in verts.size():
		var f := clampf((top - verts[i].x) / TENTACLE_L, 0.0, 1.0)
		colors[i] = Color(colors[i].r * (1.0 - f * 0.35), 0.5, minf(0.15 + f * 1.4, 1.0))
	arrays[Mesh.ARRAY_COLOR] = colors
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


## A surface of revolution about X through [param profile] ((x, radius)
## points, which may double back: out over a bell and back in under it),
## its section squared off into four soft ridges and flattened to
## [param flat] across Z; [param paint] (x, angle, inside) colours it.
static func _revolve(profile: Array, sides: int, paint: Callable, flat := 1.0) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var n := profile.size()
	var turn := 0
	for i in range(1, n):
		if (profile[i] as Vector2).x > (profile[i - 1] as Vector2).x:
			turn = i
			break
	for i in n:
		var pt: Vector2 = profile[i]
		var d: Vector2 = profile[mini(i + 1, n - 1)] - profile[maxi(i - 1, 0)]
		var n2 := Vector2(d.y, -d.x).normalized()
		var inside := turn > 0 and i >= turn
		for j in sides + 1:
			var a := TAU * j / sides
			var r := pt.y * (1.0 + 0.035 * cos(4.0 * a))
			verts.append(Vector3(pt.x, cos(a) * r, sin(a) * r * flat))
			normals.append(Vector3(n2.x, n2.y * cos(a), n2.y * sin(a) / flat).normalized())
			colors.append(paint.call(pt.x, a, inside))
	# The inside first: drawn as glass, whatever is drawn first writes depth,
	# so the cavity has to be in before the wall over it, or it never shows.
	var row := sides + 1
	var order: Array[int] = []
	order.append_array(range(maxi(turn - 1, 0), n - 1))
	order.append_array(range(0, maxi(turn - 1, 0)))
	for i in order:
		for j in sides:
			var a := i * row + j
			indices.append_array([a, a + 1, a + row, a + 1, a + row + 1, a + row])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# --- Behaviour --------------------------------------------------------------

func think() -> void:
	if pos.distance_to(_goal) < 3.0:
		_goal = wander_point(_home, 28.0)
	_sting_creatures()


## Unkillable: blows pass through the colony.
func take_damage(_amount: float, _from: Vector2, _kind: StringName = &"") -> void:
	pass


## Hunters that brush the chain are stung (and remember it).
func _sting_creatures() -> void:
	var reach := SEGMENTS * SPACING
	for e in level.entities:
		var c := e as Creature
		if c == null or c == self or not c.alive or c is Siphonophore or c.pos.distance_to(pos) > reach + c.radius:
			continue
		for i in range(0, SEGMENTS, 2):
			if segments[i].distance_to(c.pos) < c.radius + 0.7:
				c.take_damage(CREATURE_STING, segments[i], &"sting")
				c.stun(0.8)
				Audio.play_at(&"jelly_shock", c.pos, -6.0)
				_stung(i)
				break


func behave(delta: float) -> void:
	_t += delta
	var dir := (_goal - pos).normalized()
	steer(dir * 1.6 + Vector2(0, sin(_t * 0.5) * 0.4), 0.6, delta)


func tick(delta: float) -> void:
	# Moves the head, then (in _update_visuals) drags the chain along after it.
	super.tick(delta)
	_sting_along_body()


func _sting_along_body() -> void:
	var sub := level.player
	if sub == null or not sub.alive or _touch_cooldown > 0.0:
		return
	for i in range(1, SEGMENTS):
		if segments[i].distance_squared_to(sub.pos) < pow(Submarine.RADIUS + 0.6, 2.0):
			_touch_cooldown = 1.0
			sub.take_damage(contact_damage, segments[i], self)
			_shock(sub)
			_stung(i)
			return


func on_touch_player(sub: Submarine) -> void:
	sub.take_damage(contact_damage, pos, self)
	_shock(sub)
	_stung(0)


func _shock(sub: Submarine) -> void:
	sub.run.battery = maxf(sub.run.battery - 6.0, 0.0)
	Audio.play_at(&"jelly_shock", sub.pos, -2.0)


## It has stung something at knot [param i]: the lanterns there snatch their
## tentacles up, a flash runs out along the chain both ways, and the bells
## beat harder for a while.
func _stung(i: int) -> void:
	if _flashes.size() < 6:
		_flashes.append(Vector2(i, 0.0))
	for j in LANTERNS:
		var near := 1.0 - absf(j + FIRST_KNOT - i) / 4.5
		_startle[j] = maxf(_startle[j], clampf(near, 0.0, 1.0))
	_alarm = 1.0


# --- Drawing ----------------------------------------------------------------

func _update_visuals(delta: float) -> void:
	_drag_rope(delta)
	_lay_out(delta)
	for v in visuals:
		v.set_instance_shader_parameter(&"marked", _marked / _mark_total if _marked > 0.0 else 0.0)
		v.set_instance_shader_parameter(&"hit_flash", _flash)
	_tentacle_node.set_instance_shader_parameter(&"swim_clock", _clock)
	_tentacle_node.set_instance_shader_parameter(&"swim_power", 1.0)


## The chain follows the head like a rope, drifting with the current.
## Near the head the stem is stiff: it leaves the head straight back from
## the way it swims and bends only gently, so the colony swings round in a
## smooth curve; further back it hangs looser.
func _drag_rope(delta: float) -> void:
	segments[0] = pos
	var behind := -vel.normalized() if vel.length_squared() > 0.01 else (segments[1] - pos).normalized()
	for i in range(1, SEGMENTS):
		var to := segments[i] - segments[i - 1]
		var d := to.length()
		if d > SPACING:
			segments[i] = segments[i - 1] + to / d * SPACING
		segments[i] += Vector2(0, -0.15 * delta) + level.current_at(segments[i]) * delta * 0.5
		var back := behind if i == 1 else (segments[i - 1] - segments[i - 2]).normalized()
		var stiff := lerpf(3.0, 0.4, smoothstep(1.0, 6.0, i))
		var straight := segments[i - 1] + back * segments[i].distance_to(segments[i - 1])
		segments[i] = segments[i].lerp(straight, 1.0 - exp(-stiff * delta))


## Lays the colony out along its chain: the head pointing down the line it
## swims, the stem a smooth curve through the knots, a lantern at each knot
## and its tentacle hanging below, dragged back through the water.
func _lay_out(delta: float) -> void:
	_clock += delta
	_alarm = maxf(_alarm - delta * 0.4, 0.0)
	for i in range(_flashes.size() - 1, -1, -1):
		_flashes[i] = Vector2(_flashes[i].x, _flashes[i].y + delta)
		if _flashes[i].y > 2.5:
			_flashes.remove_at(i)
	var origin := Vector3(pos.x, pos.y, 0.0)
	_shift = origin - (_last_points[SEGMENTS] if _last_points.size() > SEGMENTS else origin)
	_last_points = _points.duplicate()
	# Where the chain was laid out from, kept after its knots.
	_last_points.append(origin)
	_points.resize(SEGMENTS)
	for i in SEGMENTS:
		var a := segments[i]
		var b := segments[i - 1] if i > 0 else a + (a - segments[1])
		var heading := (b - a).normalized()
		# A slow wave travels down the colony so it undulates instead of
		# trailing rigidly, and it weaves a little in depth.
		var f := float(i) / SEGMENTS
		var sway := Vector2(-heading.y, heading.x) * sin(_clock * 1.3 - i * 0.55) * 0.5 * f
		var p := a + sway
		_points[i] = Vector3(p.x, p.y, sin(i * 0.9 + _clock) * 0.4 * (0.25 + 0.75 * f)) - origin
	# One smooth curve through every knot, head and all.
	_curve.resize(0)
	var last := SEGMENTS - 1
	for k in last:
		var p0 := _points[maxi(k - 1, 0)] if k > 0 else _points[0] * 2.0 - _points[1]
		var p3 := _points[mini(k + 2, last)]
		for s in STEPS:
			_curve.append(_points[k].cubic_interpolate(_points[k + 1], p0, p3, float(s) / STEPS))
	_curve.append(_points[last])
	_curve_s.resize(_curve.size())
	_curve_s[0] = 0.0
	for i in range(1, _curve.size()):
		_curve_s[i] = _curve_s[i - 1] + _curve[i].distance_to(_curve[i - 1])
	model.transform = _on_curve(0.0)
	_beat(delta)
	_build_stem()
	for j in LANTERNS:
		var at := (j + FIRST_KNOT) * STEPS
		_place_lantern(j, _curve[at], _tangent(at), delta)


## The stem's direction at curve point [param i].
func _tangent(i: int) -> Vector3:
	var n := _curve.size()
	return (_curve[mini(i + 1, n - 1)] - _curve[maxi(i - 1, 0)]).normalized()


## Where the stem is [param s] metres down from the head, square to it.
func _on_curve(s: float) -> Transform3D:
	var i := 1
	while i < _curve.size() - 1 and _curve_s[i] < s:
		i += 1
	var f := clampf((s - _curve_s[i - 1]) / maxf(_curve_s[i] - _curve_s[i - 1], 0.0001), 0.0, 1.0)
	var along := _tangent(i - 1).lerp(_tangent(i), f).normalized()
	var up := _up_across(along)
	return Transform3D(Basis(along, up, along.cross(up)), _curve[i - 1].lerp(_curve[i], f))


## The swimming bells beat by turns, faster the faster it swims (and hard
## after a sting), and the head turns slowly about its stem.
func _beat(delta: float) -> void:
	_spin += delta * 0.22
	var spun := Transform3D(Basis(Vector3.RIGHT, _spin), Vector3.ZERO)
	_pulse += delta * (0.6 + vel.length() * 0.45 + _alarm * 1.2)
	for k in BELLS:
		_bells[k].transform = _on_curve(_bell_at[k]) * spun * _bell_rest[k]
		var c := fposmod(_pulse + (0.5 if k % 2 == 1 else 0.0) + k * 0.07, 1.0)
		# Snaps shut, then slowly relaxes.
		var squeeze := smoothstep(0.0, 0.2, c) if c < 0.2 else 1.0 - smoothstep(0.2, 0.9, c)
		_bells[k].set_instance_shader_parameter(&"bell_squeeze", squeeze * 0.85)
		_bells[k].set_instance_shader_parameter(&"glow_boost", _glow_at(-0.5) * (0.85 + squeeze * 0.4))
	_float.set_instance_shader_parameter(&"glow_boost", _glow_at(0.0))


## The lantern at knot [param j], on the stem at [param at] heading along
## [param tangent], and its tentacle.
func _place_lantern(j: int, at: Vector3, tangent: Vector3, delta: float) -> void:
	# Young lanterns bud small just behind the head; the last few are smaller.
	var size := minf(1.0, 0.5 + j * 0.17) * (1.0 - 0.3 * smoothstep(11.0, 15.0, j))
	var up := _up_across(tangent)
	var twist := (0.35 if j % 2 == 0 else -0.35) + sin(_clock * 0.4 + j) * 0.12
	var basis := (Basis(tangent, up, tangent.cross(up)) * Basis(Vector3.RIGHT, twist)).scaled(
		Vector3.ONE * size * LANTERN_SCALE)
	var xf := Transform3D(basis, at)
	_shields.set_instance_transform(j, xf)
	_polyps.set_instance_transform(j, xf)
	# The tentacle is dragged back through the water as the lantern moves,
	# hanging below it otherwise, and drawn up short when it is startled.
	var knot := j + FIRST_KNOT
	if delta > 0.0 and _last_points.size() > SEGMENTS:
		# Through the water: its own motion less the current's.
		var v3 := (_points[knot] + _shift - _last_points[knot]) / delta
		var through := Vector2(v3.x, v3.y) - level.current_at(segments[knot])
		_drag[j] = _drag[j].lerp(through, 1.0 - exp(-2.5 * delta))
	_startle[j] = maxf(_startle[j] - delta * 0.3, 0.0)
	var rate := 12.0 if _startle[j] > _curl[j] else 1.2
	_curl[j] = lerpf(_curl[j], _startle[j], 1.0 - exp(-rate * delta))
	var hang := (Vector2(0.0, -1.0) - _drag[j] * 0.34).normalized()
	var x_axis := Vector3(-hang.x, -hang.y, 0.0)
	var y_axis := Vector3(-x_axis.y, x_axis.x, 0.0)
	# Every other one turned about itself, so no two hang alike.
	var flip := 1.0 if j % 2 == 0 else -1.0
	var across := _drag[j].dot(Vector2(y_axis.x, y_axis.y))
	var length := (1.0 - 0.62 * _curl[j]) * (1.0 + 0.06 * sin(_clock * 0.35 + j * 0.9)) * size
	var thick := lerpf(0.75, 1.0, size)
	var root := xf * TENTACLE_ROOT
	var t_basis := Basis(x_axis * length, y_axis * thick * flip, Vector3.BACK * thick * flip)
	_tentacles.set_instance_transform(j, Transform3D(t_basis, root - x_axis * length * TENTACLE_L * 0.5))
	_tentacles.set_instance_custom_data(j, Color(j * 0.37, clampf(-across * 0.06, -0.25, 0.25) * flip, 0.0, 0.0))
	var glow := _glow_at(knot) + _startle[j] * 0.6
	_shields.set_instance_color(j, Color(glow, 1.0, 1.0, 1.0))
	_polyps.set_instance_color(j, Color(glow, 1.0, 1.0, 1.0))
	_tentacles.set_instance_color(j, Color(glow, 1.0, 1.0, 1.0))


## How bright the colony glows at knot [param k]: a soft wave of light
## running down it every few seconds, and a flash racing out both ways from
## anything it has just stung.
func _glow_at(k: float) -> float:
	var wave := fposmod(_clock * 3.5 + _phase * 4.0, 34.0) - 4.0
	var g := 0.8 + 0.9 * exp(-pow((k - wave) / 1.6, 2.0))
	for f in _flashes:
		g += 2.2 * exp(-pow((absf(k - f.x) - f.y * 14.0) / 1.5, 2.0)) * exp(-f.y * 1.2)
	return g


## Square to [param along], leaning towards the world's up (and the camera,
## so it never flips over as the line turns through upright).
static func _up_across(along: Vector3) -> Vector3:
	var up := Vector3.UP - along * along.y + Vector3.BACK * 0.2
	return (up - along * along.dot(up)).normalized()


## Rebuilds the stem along the curve, thinning towards the tail.
func _build_stem() -> void:
	var samples := _curve
	var n := samples.size()
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	verts.resize(n * (STEM_SIDES + 1))
	normals.resize(verts.size())
	colors.resize(verts.size())
	for i in n:
		var along := _tangent(i)
		var up := _up_across(along)
		var side := along.cross(up)
		var f := float(i) / (n - 1)
		# Fine through the head, where the bells hide it, swelling smoothly to
		# its thickest just behind.
		var r := lerpf(0.013, lerpf(0.034, 0.018, f), smoothstep(HEAD_L - 0.3, HEAD_L + 0.6, _curve_s[i]))
		for s in STEM_SIDES + 1:
			var a := TAU * s / STEM_SIDES
			var dir := up * cos(a) + side * sin(a)
			var at := i * (STEM_SIDES + 1) + s
			verts[at] = samples[i] + dir * r
			normals[at] = dir
			colors[at] = Color(0.05, clampf(0.5 - cos(a) * 0.5, 0.0, 1.0), 0.0)
	var row := STEM_SIDES + 1
	for i in n - 1:
		for s in STEM_SIDES:
			var a := i * row + s
			indices.append_array([a, a + 1, a + row, a + 1, a + row + 1, a + row])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	_stem_mesh.clear_surfaces()
	_stem_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
