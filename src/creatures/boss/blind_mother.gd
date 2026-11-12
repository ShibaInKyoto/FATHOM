class_name BlindMother
extends Guardian
## The Blind Mother: a colossal eyeless eel coiled in a lair at the bottom of
## the Midnight Caverns, sealing the way down. She hunts by sound alone and
## lunges at whatever she hears. A lunge that ends in rock wedges her head in
## the wall and lays her glowing gills open; anywhere else her hide turns
## everything. Once she has torn free she is wary of the rock for a while:
## her next lunges glance off it. Ping beside a wall, slip away quietly - or
## fire a torpedo across the lair and let her chase the blast.
## A colossal cave eel, pale as something that has never seen light: her
## skin ghostly grey-white and wrinkled, her eyes milky and skinned over, a
## pair of long feelers trailing from her snout by its tube nostrils. Down
## each flank runs the line of pores she listens with, glowing faintly, and
## flaring when she hears something. Behind her head four gill slits each
## side, their flaps shut over glowing gills; they breathe a little as she
## prowls, flare as she listens, and gape wide, the gills blazing, when she
## is wedged in the rock. A ribbon fin runs down her back and her belly to a
## leaf of a tail. She swims in slow waves that run down her whole length;
## listening, she draws her head back into an S and her jaw falls open;
## lunging she straightens and gapes; wedged, she thrashes; dead, she rolls
## belly up as she sinks.

enum State { DORMANT, PROWL, AIM, LUNGE, STUCK, RECOVER, DEAD }

const SEGMENTS := 32
const SPACING := 1.15
## Model scale: she dwarfs everything else in the trench.
const SIZE := 1.6
## Model space (before [constant SIZE]): x from the neck, where the body
## joins, to the snout. Stations as in [method BodyKit.body]: a deep,
## muscular head tapering to a long snout, its underside cut away in front
## by the mouth.
const NECK_X := -1.0
const NECK_R := 1.3
const HEAD := [[NECK_X, NECK_R, NECK_R, NECK_R, 0.0], [-0.4, 1.16, 1.42, 1.2, 0.06], [0.3, 1.0, 1.4, 0.92, 0.1],
	[1.0, 0.84, 1.18, 0.6, 0.11], [1.7, 0.64, 0.9, 0.38, 0.08], [2.3, 0.42, 0.58, 0.25, 0.04],
	[2.75, 0.2, 0.29, 0.14, 0.0], [2.93, 0.04, 0.05, 0.04, -0.02]]
## The lower jaw's hinge, and the jaw (jaw space, x from the hinge forward).
const HINGE := Vector3(0.0, -0.66, 0.0)
const JAW := [[-0.15, 0.78, 0.18, 0.34, -0.02], [0.5, 0.84, 0.2, 0.42, 0.0], [1.2, 0.7, 0.19, 0.38, 0.1],
	[1.9, 0.5, 0.16, 0.3, 0.22], [2.5, 0.28, 0.12, 0.2, 0.32], [2.8, 0.06, 0.06, 0.06, 0.36]]
## Sections round her (body and head), and rings of the head behind the
## neck's.
const SIDES := 26
const HEAD_RINGS := 30
## Body samples between two segments of the rope.
const SUBDIVIDE := 3
## How fast she can swing her head round (radians a second), and faster
## still while she turns on something she has heard.
const TURN_MAX := 2.4
const AIM_TURN_MAX := 4.2
## How much room a bend of her body needs, as a share of her girth there:
## no joint folds tighter than that.
const BEND_ROOM := 1.35
## The most her roll twists from one segment to the next (radians).
const TWIST_MAX := 0.7
## How quickly a segment rolls over once it has come round.
const ROLL_RATE := 6.0
## Gill slits each side: how many, where the first is, how far apart, and
## how far round from the back their tops and bottoms are (radians).
const GILLS := 4
const GILL_X := -0.86
const GILL_STEP := 0.17
const GILL_A := Vector2(1.2, 2.05)
const AIM_TIME := 0.75
const LUNGE_MAX := 2.2
const LUNGE_DAMAGE := 32.0
const PROWL_SPEED := 5.0
## Per phase (thirds of her health): lunge speed, seconds stuck, rest between lunges.
const LUNGE_SPEED: Array[float] = [24.0, 27.0, 30.0]
const STUCK_TIME: Array[float] = [4.2, 3.6, 3.0]
const REST: Array[float] = [1.6, 1.1, 0.7]

var state := State.DORMANT
var phase := 0
var segments := PackedVector2Array()

var _timer := 0.0
var _cooldown := 0.0
var _target := Vector2.ZERO
var _lunge_dir := Vector2.RIGHT
var _wall_normal := Vector2.UP
var _orbit := 0.0
var _t := 0.0
var _taught_stuck := false
var _shrink := 1.0
var _body_mesh := ArrayMesh.new()
var _body_indices := PackedInt32Array()
var _body: MeshInstance3D
var _head: MeshInstance3D
var _jaw: MeshInstance3D
var _gills: MeshInstance3D
var _flaps: Array[Node3D] = []
var _cheek_mesh := ArrayMesh.new()
## The swim: the body's wave (how big, how fast, how far along it), how
## far she is coiled back to listen, and the coil's depth while asleep.
var _wave := 0.0
var _wave_amp := 0.35
var _wave_rate := 2.2
var _rear := 0.0
## Where her head points (radians, in the plane) and how fast it is
## swinging; how far she has rolled over to keep her back up as she comes
## round, and how far each segment of her has rolled (the head's roll
## passed down her as she swims on through the place she turned); and how
## far back each segment has slid to pass behind the rest where she crosses
## herself.
var _heading := NAN
var _heading_v := 0.0
var _flip := 0.0
var _flip_v := 0.0
var _rolls := PackedFloat32Array()
var _roll_to := PackedFloat32Array()
var _depth := PackedFloat32Array()
var _gape := 0.05
var _gill_open := 0.06
var _listen := 0.3



func setup() -> void:
	species = &"mother"
	title = "THE BLIND MOTHER"
	max_hp = 280.0
	radius = 2.3
	mass = 60.0
	contact_damage = 14.0
	salvage_drop = 70
	glow_color = Color(1.0, 0.5, 0.3)
	hearing = 2.4
	ambushable = false
	# Low in the lair, never in its rock (or she would lie buried, unseen).
	pos = level.field.resolve_circle(lair_center + Vector2(0.0, -lair_radius.y * 0.45), radius + 0.5)
	super.setup()
	active_radius = 1000.0
	_orbit = level.rng.randf() * TAU
	# Coiled on the lair floor until something wakes her.
	segments.resize(SEGMENTS)
	_rolls.resize(SEGMENTS)
	_roll_to.resize(SEGMENTS)
	_depth.resize(SEGMENTS)
	_lay_coil()
	_separate(0.0)
	_rebuild_body()


func build_model() -> void:
	var glow := glow_color
	var mat := species_material(func(m: ShaderMaterial) -> void:
		m.set_shader_parameter(&"back_color", Color(0.46, 0.49, 0.53))
		m.set_shader_parameter(&"belly_color", Color(0.7, 0.69, 0.68))
		m.set_shader_parameter(&"glow_color", glow)
		m.set_shader_parameter(&"glow_strength", 2.2)
		m.set_shader_parameter(&"rim_strength", 0.3)
		m.set_shader_parameter(&"roughness", 0.5)
		m.set_shader_parameter(&"metallic", 0.0)
		# Her skin's pattern rides on its own coordinates (she is rebuilt
		# every frame): wrinkles and blotches, and fine pits.
		m.set_shader_parameter(&"skin_on_uv", true)
		m.set_shader_parameter(&"skin_tex", MotherModel.skin())
		m.set_shader_parameter(&"skin_tex_scale", 0.42)
		m.set_shader_parameter(&"skin_tex_depth", 0.03)
		m.set_shader_parameter(&"skin_tex_shade", 0.5)
		m.set_shader_parameter(&"skin_pits", 0.006)
		m.set_shader_parameter(&"tooth_color", Color(0.78, 0.72, 0.56))
		# Her lateral line: pores down the middle of each flank.
		m.set_shader_parameter(&"pores", Vector4(0.0, 0.42, 0.075, 1.6))
		m.set_shader_parameter(&"swim_amp", 0.0)
		# Feelers and fins sway.
		m.set_shader_parameter(&"flutter_amp", 0.14)
		m.set_shader_parameter(&"flutter_freq", 3.0)
		m.set_shader_parameter(&"flutter_wave", 1.4)
		m.set_shader_parameter(&"fin_color", Color(0.62, 0.6, 0.64, 0.8)))
	var gill_mat := species_material(func(m: ShaderMaterial) -> void:
		m.set_shader_parameter(&"back_color", Color(0.45, 0.08, 0.06))
		m.set_shader_parameter(&"belly_color", Color(0.6, 0.14, 0.08))
		m.set_shader_parameter(&"glow_color", Color(1.0, 0.3, 0.1))
		m.set_shader_parameter(&"glow_strength", 1.6)
		m.set_shader_parameter(&"roughness", 0.25)
		m.set_shader_parameter(&"metallic", 0.0)
		m.set_shader_parameter(&"swim_amp", 0.0)
		m.set_shader_parameter(&"flutter_amp", 0.012)
		m.set_shader_parameter(&"flutter_freq", 7.0)
		m.set_shader_parameter(&"flutter_wave", 30.0), &"gills")
	if MotherModel.head_mesh == null:
		MotherModel.head_mesh = MotherModel.head_parts()
		MotherModel.jaw_mesh = MotherModel.jaw_parts()
	# The body and skull, one skin rebuilt every frame (see _rebuild_body).
	_body = MeshInstance3D.new()
	_body.mesh = _body_mesh
	_body.material_override = mat
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.extra_cull_margin = 40.0
	model.add_child(_body)
	visuals.append(_body)
	_head = add_visual(MotherModel.head_mesh, mat)
	_jaw = add_visual(MotherModel.jaw_mesh, mat, Transform3D(Basis(), HINGE))
	var cheeks := MeshInstance3D.new()
	cheeks.mesh = _cheek_mesh
	cheeks.material_override = mat
	cheeks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(cheeks)
	visuals.append(cheeks)
	var throat := MeshInstance3D.new()
	throat.mesh = MeshKit.sphere(1.0, 16, 8)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.05, 0.01, 0.015)
	dark.roughness = 0.9
	dark.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	throat.material_override = dark
	throat.transform = Transform3D(Basis().scaled(Vector3(1.1, 0.36, 0.62)), Vector3(1.0, -0.46, 0.0))
	model.add_child(throat)
	# Milky eyes, skinned over: she has never needed them.
	var milk := StandardMaterial3D.new()
	milk.albedo_color = Color(0.6, 0.64, 0.68)
	milk.roughness = 0.55
	for sgn: float in [1.0, -1.0]:
		var eye := MeshInstance3D.new()
		eye.mesh = MeshKit.sphere(0.12, 14, 8)
		eye.material_override = milk
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := PI * 0.36 if sgn > 0.0 else TAU - PI * 0.36
		var n := MotherModel.head_normal(1.55, a)
		# Flush with the skin, a clouded lens half sunk in it.
		eye.transform = Transform3D(Basis.looking_at(-n, Vector3.UP).scaled(Vector3(1.0, 0.8, 0.3)),
			MotherModel.head_point(1.55, a) - n * 0.01)
		model.add_child(eye)
	# The gills: glowing frills behind each slit, and the flaps over them,
	# each hinged at its front edge.
	_gills = add_visual(MotherModel.gill_frills(), gill_mat)
	for sgn: float in [1.0, -1.0]:
		for k in GILLS:
			_flaps.append(_flap(k, sgn, mat))
	_rebuild_cheeks()


## A gill flap on side [param sgn]: a curved plate of skin lying on the neck
## over slit [param k], on a hinge along its front edge (returned, turned
## by its rotation about its hinge to open).
func _flap(k: int, sgn: float, mat: Material) -> Node3D:
	var x0 := GILL_X + k * GILL_STEP
	var top := MotherModel.head_point(x0, GILL_A.x) * Vector3(1.0, 1.0, sgn)
	var bottom := MotherModel.head_point(x0, GILL_A.y) * Vector3(1.0, 1.0, sgn)
	var hinge := (top + bottom) * 0.5
	var axis := (bottom - top).normalized()
	var trail := MotherModel.head_point(x0 + 0.16, (GILL_A.x + GILL_A.y) * 0.5) * Vector3(1.0, 1.0, sgn) - hinge
	var outward := MotherModel.head_normal(x0 + 0.08, (GILL_A.x + GILL_A.y) * 0.5) * Vector3(1.0, 1.0, sgn)
	if axis.cross(trail).dot(outward) < 0.0:
		axis = -axis
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := 8
	var rows := 3
	for side in 2:
		for r in rows + 1:
			for c in cols + 1:
				var u := float(r) / rows
				var a := lerpf(GILL_A.x - 0.04, GILL_A.y + 0.04, float(c) / cols)
				var x := x0 - 0.01 + 0.165 * u
				var n := MotherModel.head_normal(x, a) * Vector3(1.0, 1.0, sgn)
				var p := MotherModel.head_point(x, a) * Vector3(1.0, 1.0, sgn) + n * (0.035 + 0.025 * u)
				st.set_normal(n if side == 0 else -n)
				# Its free edge rimmed with the glow of the gill under it.
				st.set_color(Color(0.6 * smoothstep(0.6, 1.0, u), smoothstep(0.1, -0.7, cos(a)), 0.0))
				st.set_uv(Vector2(HEAD[HEAD.size() - 1][0] - x, a * BodyKit.at(HEAD, x, 1) * 0.6))
				st.add_vertex(p - hinge)
		var base := side * (rows + 1) * (cols + 1)
		for r in rows:
			for c in cols:
				var a := base + r * (cols + 1) + c
				var quad := [a, a + 1, a + cols + 1, a + 1, a + cols + 2, a + cols + 1]
				if (side == 0) != (sgn < 0.0):
					quad = [a, a + cols + 1, a + 1, a + 1, a + cols + 1, a + cols + 2]
				for q: int in quad:
					st.add_index(q)
	var pivot := Node3D.new()
	pivot.position = hinge
	pivot.set_meta(&"axis", axis)
	model.add_child(pivot)
	var mi := MeshInstance3D.new()
	pivot.set_meta(&"mesh", mi)
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(mi)
	visuals.append(mi)
	return pivot


func think() -> void:
	var sub := level.player
	match state:
		State.DORMANT:
			if sub and sub.alive and in_lair(sub.pos, 1.15):
				_awaken()
		State.PROWL:
			if _cooldown <= 0.0:
				var heard := heard_noise()
				if heard != Vector2.INF:
					_begin_aim(heard)


func behave(delta: float) -> void:
	_t += delta
	_timer -= delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	match state:
		State.DORMANT:
			vel = Vector2.ZERO
		State.PROWL:
			_orbit += delta * (0.22 + phase * 0.06)
			var target := lair_center + Vector2(cos(_orbit) * lair_radius.x * 0.6, sin(_orbit) * lair_radius.y * 0.5)
			seek(target, PROWL_SPEED * (1.0 + phase * 0.2), 1.5, delta)
		State.AIM:
			vel = vel.lerp(Vector2.ZERO, 1.0 - exp(-4.0 * delta))
			_turn_towards((_target - pos).normalized(), 8.0, delta)
			if _timer <= 0.0:
				_lunge()
		State.LUNGE:
			vel = _lunge_dir * LUNGE_SPEED[phase]
			if _timer <= 0.0:
				# Missed everything: curl back round.
				_recover(-_lunge_dir)
		State.STUCK:
			vel = Vector2.ZERO
			if _timer <= 0.0:
				_recover(_wall_normal)
				raise_guard()
		State.RECOVER:
			vel = vel.lerp(_wall_normal * 6.0, 1.0 - exp(-3.0 * delta))
			if _timer <= 0.0:
				state = State.PROWL
				_cooldown = REST[phase]
		State.DEAD:
			vel = vel.lerp(Vector2(0.0, -1.5), 1.0 - exp(-1.0 * delta))
			_shrink = maxf(_timer / 3.0, 0.01)
			if _timer <= 0.0:
				despawn()


func tick(delta: float) -> void:
	super.tick(delta)
	_follow_body()
	_pass_roll(delta)
	_separate(delta)
	_rebuild_body()


## While stuck she does not move at all; during a lunge, rock stops her dead.
func move_and_collide_field(delta: float, bounce := 0.1) -> Vector2:
	if state == State.STUCK or state == State.DORMANT:
		return Vector2.ZERO
	var hit := super.move_and_collide_field(delta, bounce)
	if state == State.LUNGE and hit != Vector2.ZERO:
		_on_impact(hit)
	return hit


func on_touch_player(sub: Submarine) -> void:
	if state == State.DEAD or state == State.DORMANT:
		return
	if state == State.LUNGE:
		sub.take_damage(LUNGE_DAMAGE, pos, self)
		sub.vel += _lunge_dir * 9.0
	else:
		sub.take_damage(contact_damage, pos, self)


func take_damage(amount: float, from: Vector2, kind: StringName = &"") -> void:
	if state == State.DEAD:
		return
	if state == State.DORMANT:
		_awaken()
	if state != State.STUCK:
		deflect(from, "Her hide turns everything. Make her strike the rock, then hit her gills.")
		return
	super.take_damage(amount, from, kind)
	var frac := hp / max_hp
	var want := 0 if frac > 0.66 else (1 if frac > 0.33 else 2)
	if alive and state != State.DEAD and want > phase:
		phase = want
		_enrage()


func die() -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	_timer = 3.0
	reward_defeat("The Blind Mother is silent.")


func is_hostile() -> bool:
	return state != State.DORMANT and state != State.DEAD


func _update_visuals(delta: float) -> void:
	super._update_visuals(delta)
	var k := 1.0 - exp(-6.0 * delta) if delta > 0.0 else 1.0
	# What each part does in each state: the jaw, the gill flaps, the pores
	# she listens with, the swim's wave, and how far she rears back.
	var gape := 0.05 + 0.05 * (0.5 + 0.5 * sin(_t * 1.1))
	var gills := 0.05 + 0.06 * (0.5 + 0.5 * sin(_t * 1.3))
	var listen := 0.35
	var amp := 0.45
	var rate := 2.0 + vel.length() * 0.25
	var rear := 0.0
	var glow := 0.25
	var extra := Basis(Vector3.UP, 0.05 * sin(_t * 0.9)) * Basis(Vector3.BACK, 0.04 * sin(_t * 0.7))
	match state:
		State.DORMANT:
			gape = 0.04
			listen = 0.12
			amp = 0.08
			rate = 0.6
		State.AIM:
			var into := clampf(1.0 - _timer / (AIM_TIME * (1.0 - phase * 0.15)), 0.0, 1.0)
			gape = lerpf(0.1, 0.55, into)
			gills = 0.28
			listen = 1.2 + 0.6 * sin(_t * 14.0)
			amp = 0.25
			rate = 1.0
			rear = into
			glow = 1.0
			extra = Basis(Vector3.BACK, 0.16 * into) * Basis(Vector3.RIGHT, 0.06 * sin(_t * 3.0))
		State.LUNGE:
			gape = 0.78
			gills = 0.16
			listen = 0.7
			amp = 0.12
			rate = 5.0
			extra = Basis()
		State.STUCK:
			gape = 0.3 + 0.35 * absf(sin(_t * 5.5))
			gills = 0.95 + 0.12 * sin(_t * 5.0)
			listen = 0.25
			amp = 1.1
			rate = 7.0
			glow = 2.6 + 0.8 * sin(_t * 9.0)
			extra = Basis(Vector3.RIGHT, 0.14 * sin(_t * 9.0)) * Basis(Vector3.UP, 0.05 * sin(_t * 6.3))
		State.RECOVER:
			gape = 0.18
			gills = 0.4
			amp = 0.7
			rate = 4.0
			glow = 0.8
		State.DEAD:
			var gone := clampf(1.0 - _timer / 3.0, 0.0, 1.0)
			gape = 0.45
			gills = 0.6
			listen = 0.0
			amp = 0.2 * (1.0 - gone)
			rate = 1.0
			glow = 0.2 * (1.0 - gone)
			extra = Basis(Vector3.RIGHT, PI * 0.9 * smoothstep(0.0, 1.0, gone))
	_gape = lerpf(_gape, gape, 1.0 - exp(-(16.0 if gape > _gape else 6.0) * delta)) if delta > 0.0 else gape
	_gill_open = lerpf(_gill_open, gills, k)
	_listen = lerpf(_listen, listen, k)
	_wave_amp = lerpf(_wave_amp, amp, 1.0 - exp(-3.0 * delta)) if delta > 0.0 else amp
	_wave_rate = lerpf(_wave_rate, rate, k)
	_rear = lerpf(_rear, rear, k)
	_wave += _wave_rate * delta
	model.basis = (model.basis * extra).scaled(Vector3.ONE * SIZE * _shrink)
	_jaw.rotation.z = -_gape
	for f in _flaps:
		f.basis = Basis(f.get_meta(&"axis"), _gill_open)
		(f.get_meta(&"mesh") as GeometryInstance3D).set_instance_shader_parameter(&"glow_boost", glow)
	_gills.set_instance_shader_parameter(&"glow_boost", glow)
	_body.set_instance_shader_parameter(&"glow_boost", _listen)
	_head.set_instance_shader_parameter(&"glow_boost", _listen)
	_rebuild_cheeks()


func _awaken() -> void:
	if active:
		return
	state = State.PROWL
	_cooldown = 1.5
	wake("She hunts by sound alone. Make her strike the rock.")


func _begin_aim(target: Vector2) -> void:
	state = State.AIM
	_timer = AIM_TIME * (1.0 - phase * 0.15)
	_target = target
	Audio.play_at(&"lancer_windup", pos, 2.0, 0.03, 0.5)


func _lunge() -> void:
	state = State.LUNGE
	_timer = LUNGE_MAX
	_lunge_dir = (_target - pos).normalized() if _target.distance_to(pos) > 0.5 else facing
	facing = _lunge_dir
	Audio.play_at(&"lancer_dash", pos, 4.0, 0.03, 0.55)


func _on_impact(normal: Vector2) -> void:
	if stun_guard > 0.0:
		# Still wary of the rock: she glances off it and turns.
		Events.shake_requested.emit(0.4)
		Audio.play_at(&"impact_rock", pos, 2.0, 0.03, 0.6)
		Fx.sparks(level, pos - normal * radius)
		_recover(normal)
		return
	state = State.STUCK
	_timer = STUCK_TIME[phase]
	_wall_normal = normal
	vel = Vector2.ZERO
	Events.shake_requested.emit(0.8)
	Audio.play_at(&"impact_rock", pos, 6.0, 0.03, 0.5)
	Fx.sparks(level, pos - normal * radius)
	Fx.bubble_burst(level, pos, 30, 2.0)
	level.emit_noise(pos, 18.0, self)
	if not _taught_stuck:
		_taught_stuck = true
		Events.toast.emit("She's stuck in the rock - her gills are open!", UiTheme.GOOD)


func _recover(away: Vector2) -> void:
	state = State.RECOVER
	_timer = 0.9
	_wall_normal = away.normalized() if away.length_squared() > 0.01 else Vector2.UP


func _enrage() -> void:
	Audio.play_at(&"stalker_roar", pos, 4.0, 0.03, 0.5)
	Events.shake_requested.emit(0.6)
	# One lancer answers each of her roars.
	var p := level.layout.point_in_chamber(level.rng, LevelLayout.Chamber.new(lair_center, lair_radius, &"exit"), 2.0)
	var lancer: Creature = LevelPopulator.SPECIES[&"lancer"].new()
	lancer.pos = p
	level.add_entity(lancer)


## Each segment follows the one ahead like a rope; drawing back to listen,
## the ones behind her head bunch up into an S.
func _follow_body() -> void:
	if state == State.DORMANT:
		return
	var face := _face()
	segments[0] = pos + face * NECK_X * SIZE
	var dt := get_physics_process_delta_time() if is_inside_tree() else 1.0 / 60.0
	var lead := -face
	for i in range(1, SEGMENTS):
		var to := segments[i] - segments[i - 1]
		var d := to.length()
		var spacing := SPACING * (1.0 - 0.3 * _rear * (1.0 - smoothstep(4.0, 12.0, float(i))))
		if d > spacing:
			segments[i] = segments[i - 1] + to / d * spacing
		# A gentle stiffness: slack loops straighten out as she swims.
		var straight := segments[i - 1] + lead * minf(d, spacing)
		segments[i] = segments[i].lerp(straight, 1.0 - exp(-0.7 * dt))
		# And no joint bends tighter than her girth there allows, or her
		# skin would pinch into a kink on the inside of the bend.
		var dir := segments[i] - segments[i - 1]
		var length := dir.length()
		if length > 0.001:
			var most := clampf(spacing / (BEND_ROOM * _girth(float(i) / (SEGMENTS - 1))), 0.12, 1.2)
			var bend := lead.angle_to(dir)
			if absf(bend) > most:
				segments[i] = segments[i - 1] + lead.rotated(signf(bend) * most) * length
		lead = (segments[i] - segments[i - 1]).normalized()
		var p := segments[i]
		var push := level.field.sample(p)
		if push < 0.6:
			segments[i] = p + level.field.normal(p) * (0.6 - push)


## Her girth (radius, metres) [param t] of the way from her neck to her tail.
static func _girth(t: float) -> float:
	return lerpf(NECK_R, 0.2, pow(clampf(t, 0.0, 1.0), 0.9)) * SIZE


## Which way her head points, as drawn.
func _face() -> Vector2:
	return Vector2.from_angle(_heading) if not is_nan(_heading) else facing


## Turns her, never faster than a beast her size can swing round (faster
## while she turns on a sound), and always round in the plane: never the
## instant about-face of a fish turning through the depth.
func _turn_towards(dir: Vector2, rate: float, delta: float) -> void:
	var most := (AIM_TURN_MAX if state == State.AIM else TURN_MAX) * delta
	var angle := facing.angle_to(dir)
	facing = facing.rotated(clampf(angle * (1.0 - exp(-rate * delta)), -most, most)).normalized()


## Her head follows where she faces on a spring, round in the plane; as it
## comes round past straight up or down she rolls over along her length, so
## her back stays up and her jaw below.
func _turn_body(delta: float) -> void:
	var want := facing.angle()
	if is_nan(_heading) or delta <= 0.0:
		_heading = want
		_heading_v = 0.0
		_flip = 0.0 if facing.x >= 0.0 else PI
		_rolls.fill(_flip)
		_roll_to.fill(_flip)
	else:
		var target := _heading + wrapf(want - _heading, -PI, PI)
		var h := _spring(_heading, _heading_v, target, 11.0, delta)
		_heading = wrapf(h.x, -PI, PI)
		_heading_v = h.y
		var c := cos(_heading)
		var flip_to := _flip
		if c > 0.3:
			flip_to = 0.0
		elif c < -0.3:
			flip_to = PI
		var f := _spring(_flip, _flip_v, flip_to, 7.0, delta)
		_flip = f.x
		_flip_v = f.y
	model.basis = Basis(Vector3.BACK, _heading) * Basis(Vector3.RIGHT, _flip)


## Her roll travels down her with the turn: each segment rolls over to keep
## its own back up once it has come round past straight up or down itself,
## so she rolls only where she turns; and never twists more than a little
## from the one ahead, so a roll is a gentle corkscrew along her, never a
## pinch. (Coiled asleep, she lies as she lay down.)
func _pass_roll(delta: float) -> void:
	_rolls[0] = _flip
	if state == State.DORMANT:
		return
	var ease := 1.0 - exp(-ROLL_RATE * delta)
	for k in range(1, SEGMENTS):
		var ahead := (segments[k - 1] - segments[k]).normalized()
		if ahead.x > 0.3:
			_roll_to[k] = 0.0
		elif ahead.x < -0.3:
			_roll_to[k] = PI
		_rolls[k] = lerpf(_rolls[k], _roll_to[k], ease)
		_rolls[k] = clampf(_rolls[k], _rolls[k - 1] - TWIST_MAX, _rolls[k - 1] + TWIST_MAX)


## Where her body crosses over itself, the part further down it slides back
## behind the rest (and her head is always in front), easing in and out, so
## she never passes through herself; each segment's place is spread to its
## neighbours so the body slopes back smoothly.
func _separate(delta: float) -> void:
	var want := PackedFloat32Array()
	want.resize(SEGMENTS)
	want.fill(0.0)
	var face := _face()
	var head := [pos, pos + face * 1.6 * SIZE, pos + face * 3.2 * SIZE]
	for j in range(3, SEGMENTS):
		var rj := _girth(float(j) / (SEGMENTS - 1))
		for h: Vector2 in head:
			var need := rj + NECK_R * SIZE * 0.9
			var d := h.distance_to(segments[j])
			if d < need:
				want[j] = minf(want[j], -sqrt(need * need - d * d))
		for i in j - 3:
			var need := (rj + _girth(float(i) / (SEGMENTS - 1))) * 1.05
			var d := segments[i].distance_to(segments[j])
			if d < need:
				want[j] = minf(want[j], want[i] - sqrt(need * need - d * d))
	for _pass in 3:
		var spread := want.duplicate()
		for k in range(1, SEGMENTS - 1):
			spread[k] = minf(want[k], 0.25 * want[k - 1] + 0.5 * want[k] + 0.25 * want[k + 1])
		want = spread
	for k in SEGMENTS:
		if delta <= 0.0:
			_depth[k] = want[k]
		else:
			var rate := 6.0 if want[k] < _depth[k] else 1.5
			_depth[k] = lerpf(_depth[k], want[k], 1.0 - exp(-rate * delta))


## Asleep: coiled on the lair floor from her neck, round and round, each
## loop a little further back.
func _lay_coil() -> void:
	var heading := (-facing).angle()
	var at := pos + facing * NECK_X * SIZE
	for i in SEGMENTS:
		segments[i] = at
		heading += 0.3 - 0.004 * i
		at += Vector2.from_angle(heading) * SPACING


## Rebuilds her skin, body and skull in one, in the head's own space: from
## the tail along the rope (smoothed, a wave running down it, leaving the
## head along its line) to the neck, then on through the skull. Her sections
## grow flatter from side to side towards the tail; a ribbon fin runs down
## her back and belly to a leaf of a tail; the pores of her lateral line run
## down each flank and onto her head.
func _rebuild_body() -> void:
	if model == null:
		return
	var face := _face()
	var neck := pos + face * NECK_X * SIZE
	# Along the rope from the neck to the tail, in samples.
	var rope := PackedVector2Array()
	for i in SEGMENTS - 1:
		var p0 := segments[maxi(i - 1, 0)] if i > 0 else neck * 2.0 - segments[1]
		var p3 := segments[mini(i + 2, SEGMENTS - 1)]
		for sub_step in SUBDIVIDE:
			rope.append(segments[i].cubic_interpolate(segments[i + 1], p0, p3, float(sub_step) / SUBDIVIDE))
	rope.append(segments[SEGMENTS - 1])
	rope[0] = neck
	var n := rope.size()
	var dist := PackedFloat32Array([0.0])
	for i in range(1, n):
		dist.append(dist[i - 1] + rope[i].distance_to(rope[i - 1]))
	var total := maxf(dist[n - 1], 1.0)
	# The wave, sideways in the plane, growing down the body; and near the
	# neck the body is drawn onto the head's line.
	var waved := PackedVector3Array()
	waved.resize(n)
	for i in n:
		var t := dist[i] / total
		var ahead := rope[maxi(i - 1, 0)] - rope[mini(i + 1, n - 1)]
		var across := Vector2(-ahead.y, ahead.x).normalized()
		var amp := _wave_amp * smoothstep(0.0, 0.18, t) * (0.5 + 0.5 * t)
		var p := rope[i] + across * sin(dist[i] * TAU / 9.0 - _wave) * amp
		var w := 1.0 - smoothstep(0.0, 4.5, dist[i])
		p = p.lerp(neck - face * dist[i], w)
		# Back from the play plane wherever she crosses herself.
		var at := float(i) / SUBDIVIDE
		var k := mini(int(at), SEGMENTS - 2)
		waved[i] = Vector3(p.x, p.y, lerpf(_depth[k], _depth[k + 1], at - k))
	# Into the head's space (the model as it stands this frame).
	var to_local := Transform3D(model.basis, model.position).affine_inverse()
	var pts := PackedVector3Array()
	pts.resize(n)
	for i in n:
		pts[i] = to_local * (waved[n - 1 - i] - Vector3(pos.x, pos.y, 0.0))
	pts[n - 1] = Vector3(NECK_X, 0.0, 0.0)
	var scale := SIZE
	# Each section's back carried down from the head's, so it never flips,
	# then turned about her length by how much less (or more) it has rolled
	# over than her head.
	var tangents := PackedVector3Array()
	tangents.resize(n)
	for i in n:
		tangents[i] = (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
	tangents[n - 1] = Vector3.RIGHT
	var backs := PackedVector3Array()
	backs.resize(n)
	var carried := Vector3.UP
	for i in range(n - 1, -1, -1):
		var b := carried - tangents[i] * carried.dot(tangents[i])
		carried = b.normalized() if b.length_squared() > 1e-6 else carried
		var at := float(n - 1 - i) / SUBDIVIDE
		var k := mini(int(at), SEGMENTS - 2)
		var twist := lerpf(_rolls[k], _rolls[k + 1], at - k) - _flip
		backs[i] = carried.rotated(tangents[i], twist) if absf(twist) > 0.001 else carried
	var grid: Array[PackedVector3Array] = []
	var along := PackedFloat32Array()
	var fins: Array[PackedVector3Array] = [PackedVector3Array(), PackedVector3Array(), PackedVector3Array(),
		PackedVector3Array()]
	var head_len: float = HEAD[HEAD.size() - 1][0] - NECK_X
	for i in n:
		var back_by := dist[n - 1 - i] / scale
		var t := back_by * scale / total
		var r := lerpf(NECK_R, 0.2, pow(t, 0.9)) * (1.0 - 0.9 * smoothstep(0.96, 1.0, t))
		var rh := r * lerpf(1.0, 0.62, pow(t, 0.7))
		var side := tangents[i].cross(backs[i])
		var ring := PackedVector3Array()
		for j in SIDES + 1:
			var a := TAU * j / SIDES
			var sc := signf(cos(a)) * pow(absf(cos(a)), 0.85)
			var ss := signf(sin(a)) * pow(absf(sin(a)), 0.85)
			ring.append(pts[i] + backs[i] * sc * r + side * ss * rh)
		grid.append(ring)
		along.append(head_len + back_by)
		# The ribbon fins: low along the back from behind the head, along the
		# belly from half way, both rising to a leaf at the tail.
		var tail := smoothstep(0.85, 1.0, t)
		var dorsal := (0.08 + 0.1 * t + 0.45 * tail) * smoothstep(0.03, 0.08, t)
		var anal := (0.06 + 0.08 * t + 0.4 * tail) * smoothstep(0.4, 0.46, t)
		fins[0].append(pts[i] + backs[i] * r * 0.85)
		fins[1].append(pts[i] + backs[i] * (r + dorsal))
		fins[2].append(pts[i] - backs[i] * r * 0.85)
		fins[3].append(pts[i] - backs[i] * (r + anal))
	for x_ring in HEAD_RINGS:
		var x := lerpf(NECK_X, HEAD[HEAD.size() - 1][0], float(x_ring + 1) / HEAD_RINGS)
		var ring := PackedVector3Array()
		for j in SIDES + 1:
			ring.append(MotherModel.head_point(x, TAU * j / SIDES))
		grid.append(ring)
		along.append(HEAD[HEAD.size() - 1][0] - x)
	_commit_body(grid, along, fins, n)


## Builds the mesh: the skin over [param grid] (its first [param body_rings]
## rings the body's), and the fins along it.
func _commit_body(grid: Array[PackedVector3Array], along: PackedFloat32Array, fins: Array[PackedVector3Array],
		body_rings: int) -> void:
	var rings := grid.size()
	var row := SIDES + 1
	var count := rings * row + body_rings * 8
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	verts.resize(count)
	normals.resize(count)
	colors.resize(count)
	uvs.resize(count)
	uv2s.resize(count)
	var v := 0
	for i in rings:
		var arcs := PackedFloat32Array([0.0])
		for j in SIDES:
			arcs.append(arcs[j] + grid[i][j].distance_to(grid[i][j + 1]))
		for j in SIDES + 1:
			var a := TAU * j / SIDES
			var ahead := grid[mini(i + 1, rings - 1)][j] - grid[maxi(i - 1, 0)][j]
			var round := grid[i][(j + 1) % SIDES] - grid[i][(j - 1 + SIDES) % SIDES]
			verts[v] = grid[i][j]
			normals[v] = round.cross(ahead).normalized()
			colors[v] = Color(0.0, smoothstep(0.1, -0.7, cos(a)), 0.0)
			var from_back := minf(arcs[j], arcs[SIDES] - arcs[j])
			uvs[v] = Vector2(along[i], from_back * 0.55)
			# For the pores of her lateral line: how far round from the
			# flank's midline (the line itself only down the body).
			uv2s[v] = Vector2(along[i], from_back - arcs[SIDES] * 0.25 if i < body_rings - 2 else 99.0)
			v += 1
	# The fins, both faces of each.
	for f in 2:
		var root := fins[f * 2]
		var tip := fins[f * 2 + 1]
		for face in 2:
			for i in body_rings:
				var dir := (tip[i] - root[i]).normalized()
				var ahead := root[mini(i + 1, body_rings - 1)] - root[maxi(i - 1, 0)]
				var nrm := ahead.cross(dir).normalized() * (1.0 if face == 0 else -1.0)
				for e in 2:
					verts[v] = root[i] if e == 0 else tip[i]
					normals[v] = nrm
					colors[v] = Color(0.0, 0.2, 0.02 if e == 0 else 0.9)
					uvs[v] = Vector2(along[i], 0.02 * e)
					uv2s[v] = Vector2(0.0, 99.0)
					v += 1
	if _body_indices.is_empty():
		_body_indices = MotherModel.indices(rings, body_rings)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = _body_indices
	_body_mesh.clear_surfaces()
	_body_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


## The corners of the mouth: skin from the upper lip down to the lower jaw's
## rim, from the hinge forward, stretching as she gapes.
func _rebuild_cheeks() -> void:
	var rot := Basis(Vector3.BACK, -_gape)
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
				var u := 1.1 * t * (1.0 - 0.4 * sin(PI * f) * t)
				var rim := HINGE + rot * MotherModel.jaw_rim(u, sgn)
				var lip := MotherModel.upper_lip(HINGE.x + u + 0.2, sgn)
				var p := lip.lerp(rim, f)
				p.z += sgn * sin(PI * f) * (0.04 + 0.15 * _gape) * sin(PI * 0.5 * t)
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
					for q: int in quad:
						st.add_index(q)
		at += grid.size() * 2
	st.generate_normals()
	_cheek_mesh.clear_surfaces()
	st.commit(_cheek_mesh)


## Shown as a specimen (the codex), which never moves: coiled, listening,
## her jaw a little open.
func reveal() -> void:
	state = State.PROWL
	_lay_coil()
	_separate(0.0)
	_update_visuals(0.0)
	_gape = 0.3
	_gill_open = 0.25
	_listen = 1.0
	_jaw.rotation.z = -_gape
	_body.set_instance_shader_parameter(&"glow_boost", _listen)
	_rebuild_cheeks()
	_rebuild_body()
