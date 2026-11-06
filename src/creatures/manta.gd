class_name Manta
extends Creature
## Shelf manta: a gentle giant of the sunlit zones, gliding slowly from one
## open stretch of water to the next on wings wider than the sub is long. It
## bites nothing, pays no attention to noise or light, and banks away from a
## sub that crowds it. Hurt, it beats away fast. The camera sees the cave side
## on, so the wings are held tilted towards it to show their spread.

const SPEED := 2.4
const FLEE_SPEED := 6.5
## How close the sub may come before it banks away.
const PERSONAL_SPACE := 7.0
## How far it holds its wings towards the camera, in radians.
const TILT := 1.05
## Model scale: a wingspan of about seven metres.
const SIZE := 1.3

var _goal := Vector2.INF
var _goal_timer := 0.0
var _flee := 0.0
var _t := 0.0
var _tilt: Node3D
var _wings: Array[Node3D] = []


func setup() -> void:
	species = &"manta"
	max_hp = 140.0
	radius = 1.7
	reach = 3.2
	mass = 6.0
	contact_damage = 0.0
	salvage_drop = 4
	hostile = false
	hearing = 0.0
	glow_color = Color(0.75, 0.9, 1.0)
	_turn_speed = 1.6
	super.setup()
	_t = level.rng.randf() * TAU


func build_model() -> void:
	var mat := species_material(func(m: ShaderMaterial) -> void:
		m.set_shader_parameter(&"back_color", Color(0.09, 0.12, 0.2))
		m.set_shader_parameter(&"belly_color", Color(0.86, 0.9, 0.92))
		m.set_shader_parameter(&"glow_color", Color(0.75, 0.9, 1.0))
		m.set_shader_parameter(&"glow_strength", 0.0)
		m.set_shader_parameter(&"rim_strength", 0.45)
		m.set_shader_parameter(&"roughness", 0.5)
		m.set_shader_parameter(&"body_length", 3.0)
		m.set_shader_parameter(&"swim_amp", 0.03)
		m.set_shader_parameter(&"swim_freq", 1.2)
		m.set_shader_parameter(&"swim_wave", 0.8)
		m.set_shader_parameter(&"swim_vertical", 0.0))
	_tilt = Node3D.new()
	_tilt.scale = Vector3.ONE * SIZE
	# Back to the camera from the start (a specimen in the hangar never ticks).
	_tilt.rotation.x = TILT
	model.add_child(_tilt)
	# A flat, broad body along +X (the head), flattened top to bottom.
	var body := MeshKit.lathe(PackedVector2Array([Vector2(0.0, 0.05), Vector2(0.2, 0.42), Vector2(0.55, 0.62),
		Vector2(0.85, 0.5), Vector2(1.0, 0.25)]), 2.8, 18, 12, 0.32, 1.0)
	_add_part(body, mat, Transform3D.IDENTITY)
	# Wings: broad, swept-back triangles off either side, each on its own pivot
	# along the body so it can beat.
	var wing_outline := PackedVector2Array([Vector2(1.05, 0.0), Vector2(0.45, 1.3), Vector2(-0.45, 3.0),
		Vector2(-0.8, 3.05), Vector2(-0.72, 2.2), Vector2(-1.0, 1.0), Vector2(-1.3, 0.0)])
	var wing := MeshKit.fin(wing_outline, 0.08, 0.0, 0.12)
	for side: float in [1.0, -1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(0.0, 0.0, side * 0.45)
		_tilt.add_child(pivot)
		_wings.append(pivot)
		var mi := MeshInstance3D.new()
		mi.mesh = wing
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The fin is drawn in XY; lay it out along +Z (or -Z) from the pivot.
		mi.basis = Basis(Vector3.RIGHT, side * PI * 0.5)
		pivot.add_child(mi)
		visuals.append(mi)
	# Cephalic fins curling forward either side of the mouth, and a long whip tail.
	var horn := MeshKit.fin(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.55, 0.1), Vector2(0.6, 0.22),
		Vector2(0.05, 0.18)]), 0.06, 0.0, 0.2)
	for side: float in [1.0, -1.0]:
		_add_part(horn, mat, Transform3D(Basis(Vector3.RIGHT, side * PI * 0.5) * Basis(Vector3.BACK, -0.25),
			Vector3(1.25, 0.0, side * 0.32)))
	var tail := MeshKit.spike(0.07, 2.6)
	_add_part(tail, mat, Transform3D(Basis(Vector3.UP, PI), Vector3(-1.2, 0.0, 0.0)))
	# Eyes on the tilted body, so they stay put on it.
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.03, 0.03, 0.04)
	eye_mat.roughness = 0.05
	for side: float in [1.0, -1.0]:
		var eye := MeshInstance3D.new()
		eye.mesh = MeshKit.sphere(0.09, 8, 4)
		eye.material_override = eye_mat
		eye.position = Vector3(1.05, 0.1, side * 0.5)
		_tilt.add_child(eye)


func _add_part(mesh: Mesh, mat: Material, xf: Transform3D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tilt.add_child(mi)
	visuals.append(mi)


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
	# Slow, deep wingbeats, quicker when it bolts.
	var beat := sin(_t * (1.1 if _flee <= 0.0 else 3.2)) * 0.38
	for i in _wings.size():
		_wings[i].rotation.x = beat * (1.0 if i == 0 else -1.0)
	# Its dark back held towards the camera whichever way it heads (turned
	# round to face left, the model's sides swap).
	_tilt.rotation.x = TILT * _side()


## Somewhere roomy in clear sight to glide to next, a good way off.
func _pick_goal() -> void:
	_goal_timer = level.rng.randf_range(12.0, 20.0)
	for _i in 12:
		var p := level.layout.random_open_point(level.rng, 4.0, PackedVector2Array([pos]), 14.0)
		if p != Vector2.INF and level.field.line_of_sight(pos, p, radius):
			_goal = p
			return
	_goal = wander_point(pos, 14.0)


func on_damaged(_amount: float, from: Vector2) -> void:
	_flee = 5.0
	_goal = pos + (pos - from).normalized() * 30.0
	_goal_timer = 5.0
