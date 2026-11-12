extends Node3D
## Debug helper: the Blind Mother up close in a lit tank, coiled as the codex
## shows her, to judge her model: "view" from an angle ([yaw] [pitch]
## degrees round her head, [distance] metres off); "state" in one of her
## states (prowl, aim, lunge, stuck, dead), held a couple of seconds so her
## jaw and gills settle.
## Usage: xvfb-run godot --path . res://tools/debug/preview_mother_model.tscn --
## <out.png> [yaw] [pitch] [distance] [state] [whole|focus x]

var _mother: BlindMother
var _frames := 0
var _state := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var layout := LevelGenerator.new().generate(BiomeLibrary.get_biome(3), 5, 6)
	var level := Level.new()
	add_child(level)
	level.build(layout, 1)
	level.terrain.visible = false
	level.environment_rig.environment.ambient_light_energy = 1.2
	level.environment_rig.environment.volumetric_fog_enabled = false
	level.environment_rig.environment.fog_enabled = false
	var origin := Vector2(layout.size().x * 0.5, -80.0)
	_mother = BlindMother.new()
	_mother.pos = origin
	level.add_entity(_mother)
	_mother.pos = origin
	_mother.reveal()
	_mother.sync_transform()
	_state = args[4] if args.size() > 4 else ""
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 30, 0)
	key.light_energy = 1.2
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
	var yaw := float(args[1]) if args.size() > 1 else 35.0
	var pitch := float(args[2]) if args.size() > 2 else 12.0
	var distance := float(args[3]) if args.size() > 3 else 14.0
	var whole := args.size() > 5 and args[5] == "whole"
	var head := Vector3(origin.x, origin.y, 0.0) + Vector3(1.6, 0.0, 0.0)
	if whole:
		head = Vector3(origin.x - 6.0, origin.y - 2.0, 0.0)
	elif args.size() > 5 and args[5].is_valid_float():
		head = Vector3(origin.x + float(args[5]), origin.y, 0.0)
	var turn := Basis(Vector3.UP, deg_to_rad(yaw)) * Basis(Vector3.RIGHT, deg_to_rad(-pitch))
	var eye := head + turn * Vector3(0, 0, distance)
	cam.transform = Transform3D(Basis.looking_at(head - eye, Vector3.UP), eye)


func _process(_delta: float) -> void:
	_frames += 1
	if _state != "":
		_mother.state = {"prowl": BlindMother.State.PROWL, "aim": BlindMother.State.AIM,
			"lunge": BlindMother.State.LUNGE, "stuck": BlindMother.State.STUCK,
			"dead": BlindMother.State.DEAD}.get(_state, BlindMother.State.PROWL)
		_mother.set(&"_timer", 0.01 if _state == "aim" else (1.5 if _state == "dead" else 2.0))
		_mother.set(&"_t", _frames / 30.0)
		_mother.call(&"_update_visuals", 1.0 / 30.0)
		_mother.call(&"_rebuild_body")
	if _frames == 60:
		get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
		get_tree().quit()
