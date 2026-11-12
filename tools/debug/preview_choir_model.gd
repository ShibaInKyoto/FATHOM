extends Node3D
## Debug helper: the Choir's body in the dark, to judge its model: its heart
## with a few tentacles trailing from it, and one of its voice organs beside
## it, singing every three seconds. [view] picks what to look at ("heart",
## "organ", "throat" with its petals open); "film" after it saves every
## frame for four seconds as <out>_N.png.
## Usage: xvfb-run godot --path . res://tools/debug/preview_choir_model.tscn --
## <out.png> [heart|organ|throat] [yaw] [pitch] [distance] [film]

const FPS := 30.0
const ORGAN_AT := Vector3(15.0, -4.0, 0.0)

var _heart: Node3D
var _parts: Array[GeometryInstance3D] = []
var _petals: Array[Node3D] = []
var _pipes: Array[Node3D] = []
var _tentacles: Array[ArrayMesh] = []
var _frames := 0
var _view := "heart"
var _film := false
var _out := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0]
	_view = args[1] if args.size() > 1 else "heart"
	_film = args.has("film")
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.01, 0.015, 0.03)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.2, 0.25, 0.35)
	env.environment.ambient_light_energy = 0.6
	env.environment.glow_enabled = true
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	_heart = ChoirModel.build_heart()
	add_child(_heart)
	for p: GeometryInstance3D in _heart.get_meta(&"parts"):
		_parts.append(p)
	for pv: Node3D in _heart.get_meta(&"petals"):
		_petals.append(pv)
		_parts.append(pv.get_child(0) as GeometryInstance3D)
	for i in 5:
		var mesh := ArrayMesh.new()
		_tentacles.append(mesh)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = ChoirModel.flesh_material()
		add_child(mi)
		_parts.append(mi)
	var organ := Node3D.new()
	organ.position = ORGAN_AT
	# Singing back towards the heart, as one does across its arena.
	organ.basis = Basis(Vector3.UP, PI)
	add_child(organ)
	var body := MeshInstance3D.new()
	body.mesh = ChoirModel.organ_body()
	body.material_override = ChoirModel.flesh_material()
	organ.add_child(body)
	_parts.append(body)
	for pipe: Vector3 in ChoirModel.PIPES:
		var pivot := Node3D.new()
		pivot.position = Vector3(0.9, 0.0, 0.0)
		pivot.basis = Basis(Vector3.RIGHT, pipe.y) * Basis(Vector3.BACK, pipe.x)
		var mi := MeshInstance3D.new()
		mi.mesh = ChoirModel.organ_pipe(pipe.z)
		mi.material_override = ChoirModel.flesh_material()
		pivot.add_child(mi)
		organ.add_child(pivot)
		_pipes.append(pivot)
		_parts.append(mi)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.35, 0.85)
	light.omni_range = 40.0
	light.light_energy = 1.2
	light.position = Vector3(0.0, 0.0, 8.0)
	add_child(light)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, 30, 0)
	key.light_energy = 0.35
	key.light_color = Color(0.6, 0.75, 1.0)
	add_child(key)
	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.far = 500.0
	add_child(cam)
	cam.current = true
	var at := Vector3(0.0, 0.0, 0.0)
	var distance := 34.0
	if _view == "organ":
		at = ORGAN_AT + Vector3(-1.0, 0.0, 0.0)
		distance = 12.0
	elif _view == "throat":
		at = ChoirModel.throat_centre()
		distance = 10.0
	var yaw := float(args[2]) if args.size() > 2 else 0.0
	var pitch := float(args[3]) if args.size() > 3 else 5.0
	distance = float(args[4]) if args.size() > 4 else distance
	var turn := Basis(Vector3.UP, deg_to_rad(yaw)) * Basis(Vector3.RIGHT, deg_to_rad(-pitch))
	var eye := at + turn * Vector3(0, 0, distance)
	cam.transform = Transform3D(Basis.looking_at(at - eye, Vector3.UP), eye)


func _process(_delta: float) -> void:
	_frames += 1
	var t := _frames / FPS
	var song := fmod(t + 2.0, 3.0)
	for p in _parts:
		p.set_instance_shader_parameter(&"song", song)
	var open := 1.0 if _view == "throat" else 0.0
	for i in _petals.size():
		var a := TAU * i / _petals.size()
		_petals[i].basis = Basis(Vector3.BACK, a + PI) * Basis(Vector3.UP, -open * 1.1)
	for i in _tentacles.size():
		var a := PI + PI * (i + 0.5) / 5.0
		var dir := Vector3(cos(a), sin(a), 0.0)
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		for k in 14:
			var u := k / 13.0
			var side := Vector3(-dir.y, dir.x, 0.0) * sin(t * 0.7 + i * 1.3 + u * 4.0) * 3.0 * u
			pts.append(dir * (4.5 + u * 28.0) + side + Vector3(0.0, 0.0, -2.0 * u))
			radii.append(lerpf(0.95, 0.08, u))
		var fine := ChoirModel.curve(pts, 48)
		var fine_r := PackedFloat32Array()
		for k in fine.size():
			fine_r.append(lerpf(0.95, 0.08, float(k) / (fine.size() - 1)))
		ChoirModel.tentacle_into(_tentacles[i], fine, fine_r, 4.5, t + i * 0.7)
	if _film:
		if _frames > 2:
			get_viewport().get_texture().get_image().save_png("%s_%d.png" % [_out, _frames - 3])
		if _frames >= 3 + int(FPS * 4.0):
			get_tree().quit()
	elif _frames == 20:
		get_viewport().get_texture().get_image().save_png(_out)
		get_tree().quit()
