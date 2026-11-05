extends Node3D
## Debug helper: one species in a lit tank, for reviewing its model and how it
## swims. "sheet" shows it side on, three-quarter and from above; "swim" shows
## four of it mid-stroke: swimming straight (two moments of the stroke), and
## turning up and turning down, so the spine's bend shows.
## "game" shows one at the distance and lens of the dive camera.
## Usage: xvfb-run godot --path . res://tools/debug/preview_creature.tscn -- <out.png> <species> [sheet|swim|game]
## [biome index]

const TURN := 1.6
const SPEED := 4.0

var _frames := 0
var _level: Level
var _crits: Array[Creature] = []
var _turns: Array[float] = []
var _mode := "sheet"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var id := StringName(args[1]) if args.size() > 1 else &"stalker"
	_mode = args[2] if args.size() > 2 else "sheet"
	var biome := int(args[3]) if args.size() > 3 else 2
	var layout := LevelGenerator.new().generate(BiomeLibrary.get_biome(biome), 5, biome * 2)
	_level = Level.new()
	add_child(_level)
	_level.build(layout, 1)
	_level.terrain.visible = false
	_level.environment_rig.environment.ambient_light_energy = 1.6
	_level.environment_rig.environment.volumetric_fog_enabled = false
	_level.environment_rig.environment.fog_enabled = false
	var origin := Vector2(layout.size().x * 0.5, -60)
	var script: Script = LevelPopulator.SPECIES.get(id, null)
	if script == null:
		script = {&"mimic": Mimic, &"mother": BlindMother, &"lamplighter": Lamplighter,
			&"ironclad": Ironclad}.get(id, Stalker)
	var count := 3 if _mode == "sheet" else (1 if _mode == "game" else 4)
	var span := 0.0
	for i in count:
		var c: Creature = script.new()
		c.pos = origin
		c.set(&"wall_normal", Vector2.UP)
		_level.add_entity(c)
		c.lock_facing = true
		span = maxf(c.body_span, maxf(c.reach * 2.0, c.radius * 2.0))
		_crits.append(c)
	# Lay them out in a row, and turn each to its view.
	var gap := span * 1.35 + 1.0
	for i in count:
		var c := _crits[i]
		c.pos = origin + Vector2((i - (count - 1) * 0.5) * gap, 0.0)
		if _mode == "sheet" or _mode == "game":
			_turns.append(0.0)
		else:
			_turns.append([0.0, 0.0, TURN, -TURN][i])
			# Start a quarter of the way into a turn, so it heads right at the shot.
			c.facing = Vector2.RIGHT.rotated(-_turns[i] * 0.4)
			c._last_heading = c.facing.angle()
			c.set(&"_swim_clock", i * 0.37)
		c.sync_transform()
	if _mode == "sheet":
		_crits[1].model.rotation_degrees = Vector3(0, -35, 0)
		_crits[2].model.rotation_degrees = Vector3(80, 0, 0)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 30, 0)
	key.light_energy = 1.5
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, 200, 0)
	rim.light_energy = 0.7
	rim.light_color = Color(0.6, 0.85, 1.0)
	add_child(rim)
	var cam := Camera3D.new()
	cam.fov = 36
	cam.far = 400
	var width := gap * count
	var aspect := get_viewport().get_visible_rect().size.aspect()
	var half_h := atan(tan(deg_to_rad(cam.fov * 0.5)) * aspect)
	cam.position = Vector3(origin.x, origin.y, width * 0.5 / tan(half_h) + span * 0.3)
	if _mode == "game":
		cam.fov = 42.0
		cam.position = Vector3(origin.x, origin.y, DiveCamera.BASE_DISTANCE)
		_level.environment_rig.environment.ambient_light_energy = 0.8
	add_child(cam)
	cam.current = true


func _process(_delta: float) -> void:
	var dt := 1.0 / 30.0
	_frames += 1
	for i in _crits.size():
		var c := _crits[i]
		if _mode == "swim":
			c.facing = c.facing.rotated(_turns[i] * dt)
		c.vel = c.facing * SPEED
		c._update_visuals(dt)
		if _mode == "sheet" and i > 0:
			c.model.rotation_degrees = [Vector3(0, -35, 0), Vector3(80, 0, 0)][i - 1]
	if _frames == 24:
		var args := OS.get_cmdline_user_args()
		get_viewport().get_texture().get_image().save_png(args[0] if args.size() > 0 else "user://creature.png")
		get_tree().quit()
