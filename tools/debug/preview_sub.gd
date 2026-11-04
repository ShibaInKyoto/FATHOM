extends Node3D
## Debug helper: one submarine frame close up under studio light, from a
## three-quarter angle, side on and from above, with optional modules fitted.
## Usage: xvfb-run godot --path . res://tools/debug/preview_sub.tscn -- <out.png> <frame> [skin id] [modules,...]

var _frames := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var frame := StringName(args[1]) if args.size() > 1 else &"lantern"
	var skin := SubSkins.find(args[2]) if args.size() > 2 and args[2] != "-" else null
	var modules: Array[StringName] = []
	if args.size() > 3:
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
	# Three views in a row: three-quarter, side, top.
	var views := [Vector3(-12, -32, 0), Vector3(0, 0, 0), Vector3(80, 0, 0)]
	for i in views.size():
		var m := SubmarineModel.new()
		add_child(m)
		m.build(frame, skin)
		if not modules.is_empty():
			ModuleKit.fit(m, frame, modules)
		m.position = Vector3((i - 1) * 6.2, 0.0, 0.0)
		m.rotation_degrees = views[i]
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.3, 11.5)
	cam.fov = 42
	add_child(cam)


func _process(_d: float) -> void:
	_frames += 1
	if _frames == 12:
		var args := OS.get_cmdline_user_args()
		get_viewport().get_texture().get_image().save_png(args[0] if args.size() > 0 else "user://sub.png")
		get_tree().quit()
