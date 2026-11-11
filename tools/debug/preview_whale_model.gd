extends Node3D
## Debug helper: the passing sperm whale up close in a lit tank, to judge its
## model and stroke. "sheet" shows it side on, from below and from the
## front; "view" from an angle ([yaw] [pitch] degrees round its head);
## "clip" films it swimming side on for eight seconds (one frame a file,
## <out>_NNN.png), its jaw dropping open once.
## Usage: xvfb-run godot --path . res://tools/debug/preview_whale_model.tscn --
## <out.png> [sheet|view|clip] [yaw] [pitch]

const CLIP_FRAMES := 240

var _mode := "sheet"
var _whales: Array[PassingWhale] = []
var _frames := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_mode = args[1] if args.size() > 1 else "sheet"
	var layout := LevelGenerator.new().generate(BiomeLibrary.get_biome(0), 5, 0)
	var level := Level.new()
	add_child(level)
	level.build(layout, 1)
	level.terrain.visible = false
	level.environment_rig.environment.ambient_light_energy = 1.4
	level.environment_rig.environment.volumetric_fog_enabled = false
	level.environment_rig.environment.fog_enabled = false
	var origin := Vector2(layout.size().x * 0.5, -60.0)
	var rows := 3 if _mode == "sheet" else 1
	for i in rows:
		var w := PassingWhale.new()
		w.backdrop = true
		w.from = origin + Vector2(-400.0, -i * 9.0)
		w.to = origin + Vector2(400.0, -i * 9.0)
		w.pos = origin
		level.add_entity(w)
		w.call(&"_set_off", 1.0)
		w.set(&"_x", origin.x)
		_whales.append(w)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 30, 0)
	key.light_energy = 1.4
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, 200, 0)
	rim.light_energy = 0.6
	rim.light_color = Color(0.6, 0.85, 1.0)
	add_child(rim)
	var cam := Camera3D.new()
	cam.fov = 36.0
	cam.far = 400.0
	add_child(cam)
	cam.current = true
	var centre := Vector3(origin.x, origin.y - (rows - 1) * 4.5, PassingWhale.DEPTH)
	cam.position = centre + Vector3(0.0, 0.0, 30.0 if rows > 1 else 19.0)
	if _mode == "view":
		var yaw := float(args[2]) if args.size() > 2 else 40.0
		var pitch := float(args[3]) if args.size() > 3 else 10.0
		var head := centre + Vector3(4.0, 0.0, 0.0)
		var eye := head + Basis(Vector3.UP, deg_to_rad(yaw)) * Basis(Vector3.RIGHT, deg_to_rad(-pitch)) * Vector3(0, 0, 12)
		cam.transform = Transform3D(Basis.looking_at(head - eye, Vector3.UP), eye)


func _process(_delta: float) -> void:
	var dt := 1.0 / 30.0
	_frames += 1
	for i in _whales.size():
		var w := _whales[i]
		w.set(&"_t", float(w.get(&"_t")) + dt)
		w.set(&"_fade", 1.0)
		var rig: Node3D = w.get(&"_rig")
		rig.position = Vector3(float(w.get(&"_x")), w.from.y, PassingWhale.DEPTH)
		if _mode == "clip" and _frames == 1:
			# The jaw drops open part way through.
			w.set(&"_gape_in", 6.0)
		w.call(&"_pose", dt)
		if _mode == "sheet":
			# Side on, from below, and from the front.
			rig.rotation = [Vector3.ZERO, Vector3(-1.2, 0.0, 0.0), Vector3(0.0, -1.1, 0.0)][i]
	var args := OS.get_cmdline_user_args()
	if _mode == "clip":
		if _frames > 10:
			get_viewport().get_texture().get_image().save_png("%s_%03d.png" % [args[0].get_basename(), _frames - 11])
		if _frames == 10 + CLIP_FRAMES:
			get_tree().quit()
	elif _frames == 30:
		get_viewport().get_texture().get_image().save_png(args[0])
		get_tree().quit()
