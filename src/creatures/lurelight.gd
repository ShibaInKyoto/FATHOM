class_name Lurelight
extends Creature
## Ambush angler. Hangs near a wall with a glowing lure dangling in front of
## a near-invisible body; anything that comes close to the light is engulfed.
## A deep-sea anglerfish: a round, velvet-black body, a huge upturned mouth
## with an underbite and long glassy fangs, tiny eyes, a row of pale sense
## organs down each flank, little fins it sculls with. From its brow a
## flexible rod bends out over the mouth to a glowing bulb trailing
## filaments, which it twitches now and then. It strikes by gaping in an
## instant and lunging; hurt, it curls the lure back over its head and dims it.

enum State { LURE, SNAP, RETURN, HIDE }

const SNAP_RANGE := 6.5
const SNAP_SPEED := 17.0
## Model space: x from the tail to the snout. Stations as in
## [method BodyKit.body]: round and deep, the head as big as the body.
## The head's underside is cut away in front by the mouth: the lower jaw
## makes the bottom of the head there.
const BODY := [[-1.32, 0.05, 0.09, 0.09, 0.06], [-1.05, 0.15, 0.26, 0.22, 0.08], [-0.6, 0.36, 0.6, 0.52, 0.1],
	[-0.1, 0.54, 0.88, 0.74, 0.08], [0.3, 0.62, 0.98, 0.66, 0.06], [0.7, 0.6, 0.92, 0.42, 0.04],
	[1.02, 0.5, 0.76, 0.22, 0.02], [1.26, 0.36, 0.52, 0.12, 0.0], [1.4, 0.18, 0.26, 0.07, -0.01],
	[1.47, 0.02, 0.03, 0.02, -0.02]]
const BODY_LENGTH := 2.79
## The lower jaw's hinge, at the back corner of the mouth, and how long the
## jaw is: it reaches past the snout.
const HINGE := Vector3(0.28, -0.38, 0.0)
const JAW_LEN := 1.42
## The lower jaw (jaw space, x from the hinge forward): deep under the
## throat, its floor sweeping up to a jutting chin past the snout.
const JAW := [[-0.05, 0.42, 0.1, 0.2, -0.02], [0.3, 0.52, 0.1, 0.3, 0.0], [0.7, 0.46, 0.09, 0.3, 0.08],
	[1.05, 0.32, 0.08, 0.22, 0.22], [1.3, 0.16, 0.07, 0.13, 0.36], [JAW_LEN, 0.05, 0.04, 0.05, 0.42]]
## Where the rod leaves the brow, and where its bulb hangs at rest.
const ROD_BASE := Vector3(0.98, 0.84, 0.0)
const ESCA_REST := Vector3(2.15, 0.95, 0.0)

## Pebbled skin, shared by every lurelight.
static var _skin_tex: NoiseTexture2D

var wall_normal := Vector2.UP
var state := State.LURE
var _home := Vector2.ZERO
var _timer := 0.0
var _lit_time := 0.0
var _jaw: MeshInstance3D
var _gape := 0.06
var _lure_light: OmniLight3D
var _rod_mesh := ArrayMesh.new()
var _esca: Node3D
var _cheek_mesh := ArrayMesh.new()
## The bulb's place (model space) and how fast it is moving, and the next
## twitch.
var _tip := ESCA_REST
var _tip_v := Vector3.ZERO
var _twitch_wait := 2.0
## Which way it faces while it waits, holding its lure out, and which way
## it lunges.
var _rest_facing := Vector2.RIGHT
var _snap_dir := Vector2.ZERO
var _t := 0.0


func setup() -> void:
	species = &"lurelight"
	max_hp = 60.0
	radius = 1.3
	mass = 4.0
	contact_damage = 26.0
	salvage_drop = 8
	glow_color = Color(0.5, 1.0, 0.85)
	_turn_speed = 3.0
	body_span = BODY_LENGTH
	flex = 0.35
	flex_pivot = 0.3
	pos += wall_normal * 2.2
	super.setup()
	pos = level.field.resolve_circle(pos, radius)
	_home = pos
	facing = Vector2(-wall_normal.y, wall_normal.x) if level.rng.randf() < 0.5 else Vector2(wall_normal.y, -wall_normal.x)
	facing = (facing + wall_normal * 0.6).normalized()
	_rest_facing = facing
	lock_facing = true


func build_model() -> void:
	var mat := species_material(func(m: ShaderMaterial) -> void:
		m.set_shader_parameter(&"back_color", Color(0.032, 0.026, 0.03))
		m.set_shader_parameter(&"belly_color", Color(0.06, 0.04, 0.045))
		m.set_shader_parameter(&"glow_color", Color(0.4, 1.0, 0.8))
		m.set_shader_parameter(&"glow_strength", 1.6)
		m.set_shader_parameter(&"rim_strength", 0.18)
		m.set_shader_parameter(&"roughness", 0.75)
		m.set_shader_parameter(&"metallic", 0.0)
		m.set_shader_parameter(&"skin_pits", 0.006)
		m.set_shader_parameter(&"skin_tex", _skin())
		m.set_shader_parameter(&"skin_tex_scale", 2.2)
		m.set_shader_parameter(&"skin_tex_depth", 0.01)
		m.set_shader_parameter(&"skin_tex_shade", 0.25)
		m.set_shader_parameter(&"body_length", BODY_LENGTH)
		# A poor swimmer: a lazy beat of the tail end, the big head steady.
		m.set_shader_parameter(&"swim_amp", 0.16)
		m.set_shader_parameter(&"swim_freq", 2.6)
		m.set_shader_parameter(&"swim_wave", 2.0)
		m.set_shader_parameter(&"swim_vertical", 0.0)
		m.set_shader_parameter(&"swim_head", 0.05)
		m.set_shader_parameter(&"swim_still", 0.3)
		m.set_shader_parameter(&"fin_lag", 0.4)
		m.set_shader_parameter(&"bend_pivot", 0.3)
		m.set_shader_parameter(&"anchored", true)
		m.set_shader_parameter(&"flutter_amp", 0.05)
		m.set_shader_parameter(&"flutter_freq", 7.0)
		m.set_shader_parameter(&"flutter_wave", 5.0)
		m.set_shader_parameter(&"fin_color", Color(0.025, 0.02, 0.022, 1.0))
		m.set_shader_parameter(&"tooth_color", Color(0.62, 0.68, 0.7)))
	var parts := [[BodyKit.body(BODY, 48, 24)]]
	# The sense organs: a row of pale bumps down each flank and round the
	# head, and a few on the brow.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for sgn: float in [1.0, -1.0]:
		for i in 9:
			var x := lerpf(0.9, -0.8, i / 8.0) + rng.randf_range(-0.05, 0.05)
			var y := BodyKit.at(BODY, x, 4) + BodyKit.at(BODY, x, 2) * rng.randf_range(0.05, 0.2)
			var bump := BodyKit.enamel(MeshKit.ball(rng.randf_range(0.01, 0.016), 0.0, 6, 4))
			parts.append([bump, Transform3D(Basis(), Vector3(x, y, BodyKit.at(BODY, x, 1) * 0.985 * sgn)), x])
	# Fins: a rounded tail fan, a soft dorsal and anal fin set far back, and
	# small pectorals behind the gill openings.
	var roots := PackedVector2Array()
	var tips := PackedVector2Array()
	for i in 9:
		var f := i / 8.0
		roots.append(Vector2(-1.26, lerpf(0.13, -0.01, f)))
		var a := lerpf(0.75, -0.75, f)
		tips.append(Vector2(-1.26, 0.06) + Vector2(-cos(a), sin(a)) * lerpf(0.5, 0.6, 1.0 - absf(f - 0.5) * 2.0))
	parts.append([BodyKit.ray_fin(roots, tips, 0.12, 0.05, 0.012, 0.012, 0.0, 2, 5)])
	for up: float in [1.0, -1.0]:
		roots = PackedVector2Array()
		tips = PackedVector2Array()
		for i in 5:
			var x := lerpf(-0.55, -0.95, i / 4.0)
			var edge := BodyKit.at(BODY, x, 4) + (BodyKit.at(BODY, x, 2) if up > 0.0 else -BodyKit.at(BODY, x, 3))
			roots.append(Vector2(x, edge - 0.03 * up))
			tips.append(Vector2(x - 0.22, edge + lerpf(0.3, 0.12, i / 4.0) * up))
		parts.append([BodyKit.ray_fin(roots, tips, 0.15, 0.05, 0.01, 0.012, 0.0, 2, 4)])
	var pec := BodyKit.ray_fin(PackedVector2Array([Vector2(0.05, 0.08), Vector2(0.02, 0.04), Vector2(-0.01, 0.0),
		Vector2(-0.04, -0.04), Vector2(-0.07, -0.08)]), PackedVector2Array([Vector2(-0.22, 0.24), Vector2(-0.3, 0.12),
		Vector2(-0.33, 0.0), Vector2(-0.3, -0.12), Vector2(-0.22, -0.2)]), 0.12, 0.05, 0.009, 0.01, 0.0, 2, 4)
	for sgn: float in [1.0, -1.0]:
		parts.append([pec, Transform3D(Basis(Vector3.UP, -0.5 * sgn), Vector3(0.12, -0.1, 0.56 * sgn)), 0.12])
	# Long glassy fangs down the upper jaw, the longest at the front.
	for sgn: float in [1.0, -1.0]:
		for t: Array in BodyKit.teeth_row(_upper_lip(0.6, sgn), _upper_lip(1.36, sgn), 9, 0.3,
				Vector3(0.15, -1.0, -0.35 * sgn), 11 if sgn > 0.0 else 12):
			parts.append([BodyKit.enamel(t[0]), t[1], (t[1] as Transform3D).origin.x])
	add_visual(BodyKit.merged(parts), mat)
	# The lower jaw: a deep scoop reaching past the snout, fangs along its rim
	# leaning in towards the throat.
	var jaw_parts := [[BodyKit.body(JAW, 32, 20)]]
	for sgn: float in [1.0, -1.0]:
		for t: Array in BodyKit.teeth_row(_jaw_rim(0.25, sgn), _jaw_rim(1.3, sgn), 10, 0.38,
				Vector3(-0.25, 1.0, -0.45 * sgn), 13 if sgn > 0.0 else 14):
			jaw_parts.append([BodyKit.enamel(t[0]), t[1], (t[1] as Transform3D).origin.x])
	_jaw = add_visual(BodyKit.merged(jaw_parts), mat, Transform3D(Basis(), HINGE))
	# The mouth's corners, stretching as it gapes, and the dark throat seen
	# when it does.
	var cheeks := MeshInstance3D.new()
	cheeks.mesh = _cheek_mesh
	cheeks.material_override = mat
	cheeks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(cheeks)
	visuals.append(cheeks)
	var throat := MeshInstance3D.new()
	throat.mesh = MeshKit.sphere(1.0, 16, 8)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.03, 0.008, 0.012)
	dark.roughness = 0.9
	dark.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	throat.material_override = dark
	throat.transform = Transform3D(Basis().scaled(Vector3(0.5, 0.24, 0.38)), Vector3(0.8, -0.2, 0.0))
	model.add_child(throat)
	add_eyes(Vector3(1.12, 0.36, 0.42), 0.06, Color(0.5, 0.62, 0.66), 0.0, Eye.FISH)
	# The lure: a flexible rod (rebuilt as it bends) and its bulb.
	var rod := MeshInstance3D.new()
	rod.mesh = _rod_mesh
	rod.material_override = mat
	rod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(rod)
	_esca = Node3D.new()
	model.add_child(_esca)
	var bulb := MeshInstance3D.new()
	bulb.mesh = MeshKit.sphere(0.13, 16, 8)
	bulb.material_override = MeshKit.emissive_material(Color(0.55, 1.0, 0.85), 9.0)
	_esca.add_child(bulb)
	var sheath := MeshInstance3D.new()
	sheath.mesh = MeshKit.sphere(0.2, 16, 8)
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.5, 0.9, 0.8, 0.18)
	glass.roughness = 0.1
	glass.emission_enabled = true
	glass.emission = Color(0.3, 0.8, 0.65)
	glass.emission_energy_multiplier = 0.5
	sheath.material_override = glass
	sheath.transform = Transform3D(Basis().scaled(Vector3(1.0, 1.15, 1.0)), Vector3(0.0, 0.03, 0.0))
	_esca.add_child(sheath)
	# Filaments trailing from the bulb, glowing at their tips.
	var threads := []
	for k in 4:
		var a := TAU * k / 4.0 + 0.4
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		for i in 6:
			var f := i / 5.0
			pts.append(Vector3(cos(a) * 0.08 * (1.0 + f), -0.12 - f * (0.22 + 0.06 * k), sin(a) * 0.08 * (1.0 + f)))
			radii.append(lerpf(0.012, 0.004, f))
		var tube := ArrayMesh.new()
		MeshKit.tube(tube, pts, radii, 4)
		threads.append([tube])
	var filaments := MeshInstance3D.new()
	filaments.mesh = MeshKit.merge(threads)
	filaments.material_override = MeshKit.emissive_material(Color(0.4, 0.95, 0.8), 2.0)
	_esca.add_child(filaments)
	_lure_light = OmniLight3D.new()
	_lure_light.light_color = Color(0.5, 1.0, 0.85)
	_lure_light.omni_range = 7.0
	_lure_light.light_energy = 1.6
	_lure_light.light_volumetric_fog_energy = 1.0
	_lure_light.position = Vector3(0.0, 0.0, 0.5)
	_esca.add_child(_lure_light)
	_pose_lure()
	_rebuild_cheeks()


## Pebbled skin: soft cells, built once.
static func _skin() -> NoiseTexture2D:
	if _skin_tex == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_CELLULAR
		noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
		noise.frequency = 0.03
		noise.seed = 11
		_skin_tex = NoiseTexture2D.new()
		_skin_tex.width = 256
		_skin_tex.height = 256
		_skin_tex.seamless = true
		_skin_tex.generate_mipmaps = true
		_skin_tex.noise = noise
	return _skin_tex


## The upper jaw's edge on side [param sgn] at model x [param x].
static func _upper_lip(x: float, sgn: float) -> Vector3:
	var hw := BodyKit.at(BODY, x, 1)
	return Vector3(x, BodyKit.at(BODY, x, 4) - BodyKit.at(BODY, x, 3) * 0.8, hw * 0.75 * sgn)


## The lower jaw's rim on side [param sgn], [param u] metres along it (jaw
## space).
static func _jaw_rim(u: float, sgn: float) -> Vector3:
	return Vector3(u, BodyKit.at(JAW, u, 4) + BodyKit.at(JAW, u, 2) * 0.8, BodyKit.at(JAW, u, 1) * 0.88 * sgn)


## Where the bulb is (world): the lure the prey swims up to.
func lure_position() -> Vector2:
	if _esca == null:
		return pos + facing * 2.2 + Vector2(0, 0.8)
	var p := _esca.global_position
	return Vector2(p.x, p.y)


func think() -> void:
	if state != State.LURE:
		return
	var sub := level.player
	if sub == null or not sub.alive:
		return
	var lure_d := sub.pos.distance_to(lure_position())
	var body_d := sub.pos.distance_to(pos)
	if sub.illuminates(pos, radius) and body_d < 12.0:
		_lit_time += THINK_INTERVAL
	else:
		_lit_time = maxf(_lit_time - THINK_INTERVAL, 0.0)
	if (lure_d < SNAP_RANGE or body_d < SNAP_RANGE * 0.8 or _lit_time > 1.0) and level.field.line_of_sight(pos, sub.pos):
		alert()
		state = State.SNAP
		_timer = 0.4
		_lit_time = 0.0
		lock_facing = true
		_snap_dir = (sub.pos - pos).normalized()
		Audio.play_at(&"lurelight_snap", pos, 2.0)


func behave(delta: float) -> void:
	_t += delta
	var want := 0.06 + sin(_t * 0.7) * 0.03
	var light := 1.4 + sin(_t * 2.1) * 0.25
	# Where the bulb wants to be: dangling in front of the mouth, bobbing.
	var tip_rest := ESCA_REST + Vector3(sin(_t * 0.9) * 0.06, sin(_t * 1.3) * 0.08, 0.0)
	match state:
		State.LURE:
			# Holds still, sculling, its lure held out the same way.
			seek(_home, 1.0, 1.5, delta)
			lock_facing = true
			facing = facing.slerp(_rest_facing, 1.0 - exp(-1.5 * delta)).normalized()
			# Now and then a twitch: the bulb darts and wobbles back.
			_twitch_wait -= delta
			if _twitch_wait <= 0.0:
				_twitch_wait = 1.2 + fposmod(sin(_t * 7.31) * 43758.5, 2.6)
				var r := fposmod(sin(_t * 3.17) * 12345.6, 1.0)
				_tip_v += Vector3(lerpf(-2.2, 2.6, r), lerpf(1.8, -1.6, fposmod(r * 7.0, 1.0)), 0.0)
		State.SNAP:
			_timer -= delta
			# Whips round to its prey as it lunges.
			if _snap_dir != Vector2.ZERO:
				facing = facing.slerp(_snap_dir, 1.0 - exp(-30.0 * delta)).normalized()
			vel = facing * SNAP_SPEED
			# Gapes in an instant, and snaps shut at the end of the lunge; the
			# lure flicks up out of the way.
			want = 1.0 if _timer > 0.08 else 0.05
			tip_rest = Vector3(1.75, 1.75, 0.0)
			if _timer <= 0.0:
				state = State.RETURN
				_timer = 2.5
				lock_facing = false
		State.RETURN:
			_timer -= delta
			seek(_home, 3.0, 2.0, delta)
			# Swims home facing its way, turning back to wait as it arrives.
			lock_facing = pos.distance_to(_home) < 2.0
			if lock_facing:
				facing = facing.slerp(_rest_facing, 1.0 - exp(-2.5 * delta)).normalized()
			want = 0.12
			if _timer <= 0.0 or pos.distance_to(_home) < 1.0:
				state = State.LURE
		State.HIDE:
			_timer -= delta
			seek(_home, 4.0, 3.0, delta)
			lock_facing = pos.distance_to(_home) < 2.0
			# The lure curled back over its head, dimmed.
			tip_rest = Vector3(0.95, 1.65, 0.0)
			light = 0.2
			want = 0.02
			if _timer <= 0.0:
				state = State.LURE
	# The bulb follows on a spring, so it swings and settles.
	_tip_v += ((tip_rest - _tip) * 60.0 - _tip_v * 7.0) * delta
	_tip += _tip_v * delta
	_lure_light.light_energy = lerpf(_lure_light.light_energy, light, 1.0 - exp(-4.0 * delta))
	var rate := 40.0 if want > _gape else 14.0
	_gape = lerpf(_gape, want, 1.0 - exp(-rate * delta))


func _update_visuals(delta: float) -> void:
	super._update_visuals(delta)
	_jaw.rotation.z = -_gape * 0.8
	_pose_lure()
	_rebuild_cheeks()


## Bends the rod from the brow to where the bulb is: up and forward, then
## arching down to it.
func _pose_lure() -> void:
	var tip := _tip
	var c1 := ROD_BASE + Vector3(0.25, 0.8, 0.0)
	var c2 := tip + Vector3(-0.15, 0.55, 0.0)
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in 17:
		var t := i / 16.0
		var a := 1.0 - t
		pts.append(ROD_BASE * a * a * a + c1 * 3.0 * a * a * t + c2 * 3.0 * a * t * t + tip * t * t * t)
		radii.append(lerpf(0.035, 0.012, t))
	MeshKit.tube(_rod_mesh, pts, radii, 6)
	_esca.position = tip - Vector3(0.0, 0.14, 0.0)


## The corners of the mouth: skin from the upper jaw's edge down to the
## lower jaw's rim, from the hinge forward, stretching into a web as the
## mouth gapes; dark inside.
func _rebuild_cheeks() -> void:
	var rot := Basis(Vector3.BACK, -_gape * 0.8)
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
				var u := 0.55 * t * (1.0 - 0.4 * sin(PI * f) * t)
				var rim := HINGE + rot * _jaw_rim(u, sgn)
				var lip := _upper_lip(HINGE.x + u + 0.12, sgn)
				var p := lip.lerp(rim, f)
				p.z += sgn * sin(PI * f) * (0.02 + 0.08 * _gape) * sin(PI * 0.5 * t)
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


func on_touch_player(sub: Submarine) -> void:
	sub.take_damage(contact_damage if state == State.SNAP else 8.0, pos, self)
	if state == State.SNAP:
		state = State.RETURN
		_timer = 2.5
		lock_facing = false


func on_damaged(_amount: float, _from: Vector2) -> void:
	if hp < max_hp * 0.5 and state != State.SNAP:
		state = State.HIDE
		_timer = 5.0
