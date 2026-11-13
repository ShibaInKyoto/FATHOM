extends Node3D
## Debug helper: the giant clam alone in an even light, to judge its model:
## shut from the side and from above, half open, wide open, and its mantle
## and pearl close to; "film" films it gaping open slowly and snapping shut
## (a frame every fifteenth of a second, run with --fixed-fps 30).
## Usage: xvfb-run godot --path . --fixed-fps 30 res://tools/debug/preview_clam_model.tscn -- <out_dir> [film]

const GAPE := 0.62

var _out := "user://"
var _film := false
var _frame := 0
var _hinge: Node3D
var _root: Node3D
var _mantle_mat: ShaderMaterial
var _pearl_mat: ShaderMaterial
var _cam: Camera3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://"
	_film = args.size() > 1 and args[1] == "film"
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.03, 0.06, 0.1)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.4, 0.48, 0.6)
	env.environment.ambient_light_energy = 0.6
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment.glow_enabled = true
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	floor_mesh.mesh = plane
	var silt := StandardMaterial3D.new()
	silt.albedo_color = Color(0.3, 0.29, 0.27)
	floor_mesh.material_override = silt
	floor_mesh.position.y = -0.62 * GiantClam.SIZE
	add_child(floor_mesh)
	_root = Node3D.new()
	_root.scale = Vector3.ONE * GiantClam.SIZE
	add_child(_root)
	var shell_mat := ShaderMaterial.new()
	shell_mat.shader = GiantClam.SHELL_SHADER
	var bottom := MeshInstance3D.new()
	bottom.mesh = ClamModel.valve(false, 3)
	bottom.material_override = shell_mat
	_root.add_child(bottom)
	_hinge = Node3D.new()
	_hinge.position = ClamModel.HINGE
	_root.add_child(_hinge)
	var top := MeshInstance3D.new()
	top.mesh = ClamModel.valve(true, 4)
	top.material_override = shell_mat
	top.position = -ClamModel.HINGE
	_hinge.add_child(top)
	_mantle_mat = ShaderMaterial.new()
	_mantle_mat.shader = GiantClam.MANTLE_SHADER
	_mantle_mat.set_shader_parameter(&"hinge", ClamModel.HINGE)
	var mantle := MeshInstance3D.new()
	mantle.mesh = ClamModel.mantle()
	mantle.material_override = _mantle_mat
	mantle.extra_cull_margin = 2.0
	_root.add_child(mantle)
	var pearl := MeshInstance3D.new()
	pearl.mesh = ClamModel.pearl()
	_pearl_mat = ShaderMaterial.new()
	_pearl_mat.shader = GiantClam.PEARL_SHADER
	pearl.material_override = _pearl_mat
	pearl.position = Vector3(0.35, 0.16, 0.3)
	_root.add_child(pearl)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	add_child(_cam)
	_cam.current = true
	if not _film:
		_stills()


func _set_open(openness: float) -> void:
	_hinge.rotation.z = GAPE * openness
	_mantle_mat.set_shader_parameter(&"gape", GAPE * openness)
	var swell := smoothstep(0.15, 1.0, openness)
	_mantle_mat.set_shader_parameter(&"open", swell)
	_mantle_mat.set_shader_parameter(&"glow", 0.9 * swell)
	_pearl_mat.set_shader_parameter(&"glow", 0.25 + 3.0 * openness)


func _stills() -> void:
	var shots := [[0.0, Vector3(0, 1.6, 7.5), Vector3(0, 0.1, 0)], [0.0, Vector3(0.5, 7.5, 2.0), Vector3(0, 0, 0)],
		[0.5, Vector3(2.5, 2.0, 6.5), Vector3(0, 0.3, 0)], [1.0, Vector3(4.0, 2.4, 5.5), Vector3(0, 0.4, 0)],
		[1.0, Vector3(2.2, 1.8, 2.8), Vector3(0.5, 0.3, 0.2)], [1.0, Vector3(0, 1.0, 7.5), Vector3(0, 0.3, 0)]]
	for i in shots.size():
		_set_open(shots[i][0])
		_cam.position = shots[i][1]
		_cam.look_at(shots[i][2])
		for _f in 3:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_out.path_join("clam_%d.png" % i))
	get_tree().quit()


func _process(_delta: float) -> void:
	if not _film:
		return
	_frame += 1
	# Shut a moment, gape open over the next few seconds, hold, then snap.
	var t := _frame / 30.0
	var o := smoothstep(0.8, 2.2, t) * (1.0 - smoothstep(5.0, 5.18, t))
	_set_open(o)
	_cam.position = Vector3(3.2, 2.3, 6.0)
	_cam.look_at(Vector3(0, 0.3, 0))
	if _frame % 2 == 0:
		get_viewport().get_texture().get_image().save_png(_out.path_join("f_%03d.png" % (_frame / 2)))
	if t > 6.5:
		get_tree().quit()
