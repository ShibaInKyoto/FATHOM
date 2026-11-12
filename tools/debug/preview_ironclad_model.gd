extends Node3D
## Debug helper: the Ironclad up close in a lit tank, standing on a floor
## as it would on its lair's, to judge its model: seen from an angle ([yaw]
## [pitch] degrees round its middle, [distance] metres off) in one of its
## states (dormant, crawl, rear, slam, scalded, spit, dead), held a couple
## of seconds so its pose settles. "walk" instead films it walking on the
## spot for two seconds, every frame, as <out>_N.png ("rear", "scalded",
## "spit", "dead", "turn" after "walk" film that); a number there instead
## looks at that point along it (metres, + towards the head).
## Usage: xvfb-run godot --path . res://tools/debug/preview_ironclad_model.tscn --
## <out.png> [yaw] [pitch] [distance] [state] [walk [rear|scalded|spit|dead|turn] | focus]

const FPS := 30.0

var _boss: Ironclad
var _frames := 0
var _state := ""
var _film := ""
var _out := ""
var _turned := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0]
	var layout := LevelGenerator.new().generate(BiomeLibrary.get_biome(4), 5, 7)
	var level := Level.new()
	add_child(level)
	level.build(layout, 1)
	level.terrain.visible = false
	level.environment_rig.environment.ambient_light_energy = 1.0
	level.environment_rig.environment.volumetric_fog_enabled = false
	level.environment_rig.environment.fog_enabled = false
	var origin := Vector2(layout.size().x * 0.5, -80.0)
	_boss = Ironclad.new()
	_boss.pos = origin
	level.add_entity(_boss)
	# Posed here, not run by the level.
	level.entities.erase(_boss)
	_boss.pos = origin
	_boss.sync_transform()
	_state = args[4] if args.size() > 4 else "crawl"
	_film = args[6] if args.size() > 6 else ("walk" if args.size() > 5 and args[5] == "walk" else "")
	# The floor it stands on.
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30.0, 14.0)
	floor_mesh.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.16, 0.13, 0.12)
	floor_mat.roughness = 0.9
	floor_mesh.material_override = floor_mat
	floor_mesh.position = Vector3(origin.x, origin.y - Ironclad.RIDE, 0.0)
	add_child(floor_mesh)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 25, 0)
	key.light_energy = 1.3
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 200, 0)
	rim.light_energy = 0.7
	rim.light_color = Color(1.0, 0.6, 0.35)
	add_child(rim)
	var cam := Camera3D.new()
	cam.fov = 36.0
	cam.far = 400.0
	add_child(cam)
	cam.current = true
	var yaw := float(args[1]) if args.size() > 1 else 30.0
	var pitch := float(args[2]) if args.size() > 2 else 15.0
	var distance := float(args[3]) if args.size() > 3 else 16.0
	var at := Vector3(origin.x, origin.y - 0.6, 0.0)
	if args.size() > 5 and args[5].is_valid_float():
		at.x += float(args[5]) * _boss.heading
	var turn := Basis(Vector3.UP, deg_to_rad(yaw)) * Basis(Vector3.RIGHT, deg_to_rad(-pitch))
	var eye := at + turn * Vector3(0, 0, distance)
	cam.transform = Transform3D(Basis.looking_at(at - eye, Vector3.UP), eye)


func _process(_delta: float) -> void:
	_frames += 1
	var t := _frames / FPS
	var state := _state
	if _film == "walk":
		state = "crawl"
	elif _film != "" and _film != "turn":
		# Walking a second, then into the mood.
		state = "crawl" if t < 0.8 else _film
	_boss.state = {"dormant": Ironclad.State.DORMANT, "crawl": Ironclad.State.CRAWL, "rear": Ironclad.State.REAR,
		"slam": Ironclad.State.SLAM, "scalded": Ironclad.State.SCALDED, "spit": Ironclad.State.SPIT,
		"dead": Ironclad.State.DEAD}.get(state, Ironclad.State.CRAWL)
	_boss.exposed = 2.0 if state == "scalded" else 0.0
	_boss.set(&"_timer", 2.5 if state == "dead" else 1.0)
	_boss.set(&"_t", t)
	_boss.set(&"_slam_dir", Vector2(1.0, 0.2).normalized())
	var walking := state == "crawl" and (_film != "" or _state == "crawl")
	_boss.vel = Vector2(3.5 * _boss.heading, 0.0) if walking else Vector2.ZERO
	if _film == "turn" and t > 0.8 and not _turned:
		_turned = true
		_boss.heading = -_boss.heading
		_boss.facing = Vector2(-_boss.facing.x, _boss.facing.y)
	if state == "rear":
		_boss.facing = Vector2(1.0, 0.8).normalized()
	_boss.call(&"_update_visuals", 1.0 / FPS)
	if _film != "":
		if _frames > 2:
			get_viewport().get_texture().get_image().save_png("%s_%d.png" % [_out, _frames - 3])
		if _frames >= 3 + int(FPS * 3.0):
			get_tree().quit()
	elif _frames == 75:
		get_viewport().get_texture().get_image().save_png(_out)
		get_tree().quit()
