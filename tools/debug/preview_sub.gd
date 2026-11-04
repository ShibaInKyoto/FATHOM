extends Node3D
## Debug helper: one submarine frame close up under studio light, from a
## three-quarter angle, side on and from above, with its equipment fitted.
## Usage: xvfb-run godot --path . res://tools/debug/preview_sub.tscn -- <out.png> <frame> [skin id|-]
## [modules,...|-|full] [view|-] [aim degrees|-] [flash|boost]
## Views: close, side, far, rear, top, bow, dome, port, upper (one view, filling the frame), or
## at:<muzzle>[:<pitch>,<yaw>[:<x>,<y>,<z>]] for a close look at one piece of equipment, the camera
## that far from its muzzle (at:flare, at:torpedo:0,-90:-0.3,0,1.2); pt:<x>,<y>,<z>[...] the same
## round a point in the model's own space.
## "full" fits every module card once (two of each card that stacks), "max" every card stacked to its
## limit. The aim turns the lamp
## that many degrees round from the screen's right; "flash" shows the shock emitter firing,
## "boost" the Overdrive boosters hot, "beam" the lamp lit with its beam leaving the glass.

var _frames := 0
var _aims: Array = []
var _beams: Array = []
## With at:lamp the camera follows the lens once the lamp has swung to its aim.
var _cam: Camera3D
var _lamp_off := Vector3.ZERO
var _lamp_model: SubmarineModel


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var frame := StringName(args[1]) if args.size() > 1 else &"lantern"
	var skin := SubSkins.find(args[2]) if args.size() > 2 and args[2] != "-" else null
	var modules: Array[StringName] = []
	var full := args.size() > 3 and (args[3] == "full" or args[3] == "max")
	if full:
		for def in Catalog.modules():
			for k in (def.max_stacks if args[3] == "max" else mini(def.max_stacks, 2)):
				modules.append(def.id)
	elif args.size() > 3 and args[3] != "-" and args[3] != "":
		for m in args[3].split(","):
			modules.append(StringName(m))
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.13, 0.17)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.65, 0.75)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 35, 0)
	key.light_energy = 1.4
	key.shadow_enabled = true
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 200, 0)
	rim.light_energy = 0.8
	rim.light_color = Color(0.6, 0.85, 1.0)
	add_child(rim)
	# Three views in a row: three-quarter, side, top; or one of them close up.
	var views := [Vector3(-12, -32, 0), Vector3(0, 0, 0), Vector3(80, 0, 0)]
	var single := {"close": Vector3(-14, -35, 0), "side": Vector3.ZERO, "top": Vector3(80, 0, 0),
		"rear": Vector3(-10, 140, 0), "far": Vector3(0, 180, 0), "bow": Vector3(-6, -62, 0),
		"stern": Vector3(-12, 145, 0), "under": Vector3(-60, -20, 0), "dome": Vector3(-5, -55, 0),
		"port": Vector3(-4, -80, 0), "upper": Vector3(-30, -40, 0), "lamp": Vector3(-8, -50, 0),
		"harpoon": Vector3(-10, -30, 0), "sonar": Vector3(35, -30, 0), "compass": Vector3(30, 25, 0),
		"keel": Vector3(-40, -25, 0)}
	var one: String = args[4] if args.size() > 4 else ""
	if single.has(one):
		views = [single[one]]
	var focus := one.substr(3).get_slice(":", 0) if one.begins_with("at:") or one.begins_with("pt:") else ""
	if focus != "":
		var turn := one.get_slice(":", 2).split_floats(",") if one.count(":") > 1 else PackedFloat64Array([30, -40])
		views = [Vector3(turn[0], turn[1], 0)]
	var last: SubmarineModel = null
	for i in views.size():
		var m := SubmarineModel.new()
		add_child(m)
		m.build(frame, skin)
		m.fit_equipment(modules)
		m.position = Vector3((i - (views.size() - 1) * 0.5) * 6.2, 0.0, 0.0)
		m.rotation_degrees = views[i]
		last = m
		if args.size() > 6 and args[6] == "flash":
			m.flash_shock()
			m.animate(0.0, 0.0)
		elif args.size() > 6 and args[6] == "boost":
			m.animate(2.0, 1.6)
		elif args.size() > 6 and args[6] == "beam":
			_beams.append(m)
		if args.size() > 5 and args[5] != "-":
			var a := deg_to_rad(float(args[5]))
			_aims.append([m, Vector3(cos(a), sin(a), 0.0)])
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.3, 11.5 if views.size() > 1 else 5.6)
	if one == "dome":
		cam.position = Vector3(0.9, 0.15, 3.0)
	elif one == "port":
		cam.position = Vector3(0.2, 0.1, 3.4)
	elif one == "upper":
		cam.position = Vector3(0.3, 0.9, 2.6)
	elif one == "lamp":
		cam.position = Vector3(1.45, 0.15, 2.35)
	elif one == "harpoon":
		cam.position = Vector3(0.5, -0.32, 2.25)
	elif one == "sonar":
		cam.position = Vector3(0.33, 0.72, 1.85)
	elif one == "keel":
		cam.position = Vector3(0.0, -0.2, 3.4)
	elif one == "compass":
		cam.position = Vector3(0.96, 0.42, 1.15)
	if focus != "":
		var target: Variant = last.lamp_origin() if focus == "lamp" else last.muzzle(StringName(focus))
		if one.begins_with("pt:"):
			var p := focus.split_floats(",")
			target = last.global_transform * Vector3(p[0], p[1], p[2])
		var off := Vector3(-0.1, -0.07, 1.0)
		if one.count(":") > 2:
			var o := one.get_slice(":", 3).split_floats(",")
			off = Vector3(o[0], o[1], o[2])
		if target != null:
			cam.position = (target as Vector3) + off
		if focus == "lamp":
			_lamp_off = off
			_lamp_model = last
	cam.fov = 42
	add_child(cam)
	_cam = cam


func _process(_d: float) -> void:
	_frames += 1
	for pair: Array in _aims:
		(pair[0] as SubmarineModel).aim_lamp(pair[1], 1.0)
	if _frames == 3:
		for m: SubmarineModel in _beams:
			_add_beam(m)
		if _lamp_model:
			_cam.position = _lamp_model.lamp_origin() + _lamp_off
	if _frames == 12:
		var args := OS.get_cmdline_user_args()
		get_viewport().get_texture().get_image().save_png(args[0] if args.size() > 0 else "user://sub.png")
		get_tree().quit()


## The lamp's light and beam as the dive draws them, out of [param m]'s lens.
func _add_beam(m: SubmarineModel) -> void:
	var length := 9.0
	var glass := m.lamp_lens_radius
	var spot := SpotLight3D.new()
	spot.spot_range = 12.0
	spot.spot_angle = 32.0
	spot.light_energy = 6.0
	add_child(spot)
	var dir := m.lamp_direction()
	spot.global_transform = Transform3D(Basis.looking_at(dir, Vector3.BACK if absf(dir.z) < 0.9 else Vector3.UP),
		m.lamp_origin())
	var cone := CylinderMesh.new()
	cone.top_radius = glass
	cone.bottom_radius = glass + tan(deg_to_rad(32.0 * 0.8)) * length
	cone.height = length
	cone.radial_segments = 20
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://src/fx/shaders/lamp_beam.gdshader")
	mat.set_shader_parameter(&"noise_tex", TerrainRenderer.detail_noise())
	mat.set_shader_parameter(&"beam_length", length)
	mat.set_shader_parameter(&"glass_radius", glass)
	var beam := MeshInstance3D.new()
	beam.mesh = cone
	beam.material_override = mat
	beam.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, -length * 0.5))
	spot.add_child(beam)
