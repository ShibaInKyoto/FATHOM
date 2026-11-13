extends "res://tools/debug/preview_stage.gd"
## Debug helper: the whale fall up close, to judge its model: side on, the
## skull, a three-quarter view from above and in front, then as the game
## shows it, the sub's lamp on it throughout. "lit" adds a soft work light
## so the shapes show in the dark of the reef.
## "tank" instead lays the bones alone on a flat floor in an even light, and
## shoots them side on, the skull close, from above and from three quarters.
## Usage: xvfb-run godot --path . --fixed-fps 20 res://tools/debug/preview_whale_fall.tscn --
##        <out_dir> [zone] [seed] [lit|film]
##        ... -- <out_dir> tank
## "film" (in place of "lit") films eight seconds close over the bones.

var _fall: WhaleFall
var _cam: Camera3D
var _views: Array = []
var _film := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 1 and args[1] == "tank":
		_tank()
		return
	var zone := int(args[1]) if args.size() > 1 else 3
	stage(zone, int(args[2]) if args.size() > 2 else 603, &"lantern", true)
	level.event = &"whalefall"
	LevelPopulator.populate(level, run)
	_fall = find_entity(func(e: Entity) -> bool: return e is WhaleFall)
	var head := _fall.spine[_fall.spine.size() - 1]
	var tail := _fall.spine[0]
	var mid := (head + tail) * 0.5
	place_sub(level.field.resolve_circle(mid + Vector2(-_fall.heading * 3.0, 5.0), 1.6), 1.0)
	sub.lamp_on = true
	add_child(PostFx.new())
	if args.size() > 3 and args[3] == "lit":
		var fill := DirectionalLight3D.new()
		fill.light_energy = 0.6
		fill.rotation_degrees = Vector3(-40, 20, 0)
		add_child(fill)
	var depth := WhaleFall.DEPTH
	var length := head.distance_to(tail)
	var m3 := Vector3(mid.x, mid.y, depth)
	var h3 := Vector3(head.x, head.y, depth)
	_views = [
		[m3 + Vector3(0, 2.5, length * 0.95), m3 + Vector3(0, 0.8, 0)],
		[h3 + Vector3(-_fall.heading * 1.0, 3.0, 7.5), h3 + Vector3(-_fall.heading * 2.2, 0.8, 0)],
		[m3 + Vector3(_fall.heading * length * 0.55, 7.0, 9.0), m3 + Vector3(0, 0.3, 0)],
	]
	_cam = Camera3D.new()
	_cam.fov = 42.0
	_cam.far = 200.0
	add_child(_cam)
	shot_prefix = "fall"
	shot_times = [1.0, 1.6, 2.2, 2.8]
	_film = args.size() > 3 and args[3] == "film"
	if _film:
		# Eight seconds close over the bones, a frame every fifteenth.
		_views = [[m3 + Vector3(-_fall.heading * 2.0, 3.2, 8.5), m3 + Vector3(-_fall.heading * 2.0, 0.6, 0)]]
		shot_times = []
		for i in 120:
			shot_times.append(1.0 + i / 15.0)


## The bones alone on a flat floor, filmed from four sides.
func _tank() -> void:
	_out = OS.get_cmdline_user_args()[0]
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.05, 0.08, 0.12)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.45, 0.5, 0.6)
	env.environment.ambient_light_energy = 0.7
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)
	var line := PackedVector3Array()
	for i in 15:
		line.append(Vector3(-8.0 + i * 1.15, 0.0, 0.0))
	var flat := func(_x: float, _z: float) -> float: return 0.0
	var built := WhaleFallModel.build(line, flat, 11)
	var bones := MeshInstance3D.new()
	bones.mesh = built.mesh
	var mat := ShaderMaterial.new()
	mat.shader = WhaleFall.BONE_SHADER
	bones.material_override = mat
	add_child(bones)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 20)
	floor_mesh.mesh = plane
	var silt := StandardMaterial3D.new()
	silt.albedo_color = Color(0.32, 0.3, 0.27)
	floor_mesh.material_override = silt
	add_child(floor_mesh)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	add_child(_cam)
	_cam.current = true
	var views := [[Vector3(0, 4, 22), Vector3(0, 0.8, 0)], [Vector3(4.5, 3.5, 7.5), Vector3(6.5, 0.9, 0)],
		[Vector3(0, 24, 4), Vector3(0, 0, 0)], [Vector3(14, 7, 12), Vector3(0, 0.5, 0)]]
	for i in views.size():
		_cam.position = views[i][0]
		_cam.look_at(views[i][1])
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_out.path_join("tank_%d.png" % i))
	get_tree().quit()


func direct(_dt: float) -> void:
	sub.aim = (Vector2(_fall.pos.x, _fall.pos.y) - sub.pos).normalized()
	var i := mini(shots_taken(), _views.size() - 1) if _film else shots_taken()
	if i < _views.size():
		_cam.current = true
		_cam.position = _views[i][0]
		_cam.look_at(_views[i][1])
	else:
		camera.current = true
