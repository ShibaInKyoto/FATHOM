extends Node3D
## Debug helper: the scattered props (plants, coral, crystals, rock...) up
## close under a biome's own water and light, every variant of each in turn,
## filmed a frame every fifteenth of a second (run with --fixed-fps 30).
## Usage: xvfb-run godot --path . --fixed-fps 30 res://tools/debug/preview_props.tscn -- <out_dir> [zone] [props]
##        [frames] [mode]
## (props: comma-separated ids, default every prop the zone's biome uses;
## frames: how many to film of each variant, default 1; mode: "close"
## (default), "wide" (the whole row at once) or "shy" (the sub's position
## sweeps in to each prop and away again, for the ones that pull in)).

const SPACING := 4.2

var _out := "user://"
var _frames := 0
var _per := 1
var _mode := "close"
var _cam: Camera3D
var _lamp: SpotLight3D
var _items: Array[Array] = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://"
	var zone := int(args[1]) if args.size() > 1 else 0
	var biome := BiomeLibrary.biome_for_zone(zone)
	var ids: Array[StringName] = []
	if args.size() > 2 and args[2] != "" and args[2] != "all":
		for id in args[2].split(","):
			ids.append(StringName(id))
	else:
		for id in biome.props:
			ids.append(id)
	_per = int(args[3]) if args.size() > 3 else 1
	_mode = args[4] if args.size() > 4 else "close"
	var env := LevelEnvironment.new()
	add_child(env)
	env.setup(biome, Vector2(200, 120))
	env.update_depth(0.3)
	for id in ids:
		var meshes := PropScatter.variants(id)
		for v in meshes.size():
			_items.append([id, meshes[v]])
	var x0 := -(_items.size() - 1) * SPACING * 0.5
	for i in _items.size():
		var id: StringName = _items[i][0]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _items[i][1]
		mm.instance_count = 1
		var s := 1.0 if id != &"chimney" and id != &"spine" and id != &"kelp" else 0.55
		var at := Vector3(x0 + i * SPACING, -1.6, 0)
		mm.set_instance_transform(0, Transform3D(Basis(Vector3.UP, 0.4) * Basis.from_scale(Vector3.ONE * s), at))
		mm.set_instance_custom_data(0, Color(0.37 * (i + 1), 0.5, 0.95, 1.0))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = PropScatter.rock_material(biome) if id == &"rock" else PropScatter._material(id, biome)
		add_child(mmi)
		var box: AABB = (_items[i][1] as Mesh).get_aabb()
		_items[i].append(at + box.get_center() * s)
		_items[i].append(box.size * s)
	# A slab of floor for them to stand on.
	var floor := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = Vector3(SPACING * _items.size() + 6.0, 1.0, 8.0)
	floor.mesh = slab
	floor.material_override = PropScatter.rock_material(biome)
	floor.position = Vector3(0, -2.1, -1.0)
	add_child(floor)
	_cam = Camera3D.new()
	_cam.fov = 42.0
	add_child(_cam)
	_cam.current = true
	_lamp = SpotLight3D.new()
	_lamp.light_energy = 14.0
	_lamp.spot_range = 40.0
	_lamp.spot_angle = 35.0
	_lamp.shadow_enabled = true
	_lamp.light_color = Color(1.0, 0.95, 0.85)
	add_child(_lamp)
	add_child(PostFx.new())
	_aim(0)


## Frames the camera (and lamp) on item [param i], or on them all.
func _aim(i: int) -> void:
	var focus := Vector3(0, -0.4, 0)
	var dist := (_items.size() * SPACING) * 0.5 / tan(deg_to_rad(21.0)) / 1.78 + 2.0
	if _mode != "wide":
		focus = _items[i][2]
		var size: Vector3 = _items[i][3]
		dist = maxf(size.y / tan(deg_to_rad(21.0)) * 0.62, size.x / tan(deg_to_rad(21.0)) * 0.42) + size.z * 0.5 + 0.6
	_cam.position = focus + Vector3(0, dist * 0.18, dist)
	_cam.look_at(focus)
	_lamp.position = focus + Vector3(-dist * 0.4, dist * 0.45, dist * 0.7)
	_lamp.look_at(focus)


func _process(_delta: float) -> void:
	_frames += 1
	RenderingServer.global_shader_parameter_set(&"sonar_time", 100.0)
	var n := maxi(_frames - 12, 0) / 2
	var item := mini(n / _per, _items.size() - 1) if _mode != "wide" else 0
	if _mode == "shy":
		# In from twelve metres to the prop, then back out.
		var f := float(n % _per) / maxf(_per - 1, 1)
		var reach := absf(f * 2.0 - 1.0) * 12.0
		var at: Vector3 = _items[item][2]
		RenderingServer.global_shader_parameter_set(&"player_pos", at + Vector3(reach, 0.0, 0.0))
	if _frames < 12:
		return
	_aim(item)
	if (_frames - 12) % 2 == 1:
		get_viewport().get_texture().get_image().save_png(_out.path_join("p_%03d.png" % n))
		var total := _per * (_items.size() if _mode != "wide" else 1)
		if n + 1 >= total:
			get_tree().quit()
