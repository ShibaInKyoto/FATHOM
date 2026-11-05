extends Node3D
## Debug helper: one species in a lit tank, for reviewing its model and how it
## swims. "sheet" shows it side on, three-quarter and from above; "swim" shows
## four of it mid-stroke: swimming straight (two moments of the stroke), and
## turning up and turning down, so the spine's bend shows.
## "game" shows one at the distance and lens of the dive camera; "stroke"
## shows four moments of one swim stroke from above. "clip" films one side on
## and one from above for four seconds (cruising, a burst, cruising again)
## and saves every frame as <out>_NNN.png; "gameclip" films the "game" view
## the same way (a school is startled half way through).
## Usage: xvfb-run godot --path . res://tools/debug/preview_creature.tscn -- <out.png> <species>
## [sheet|swim|game|gameclip|stroke|clip|wall|wallclip|wallgame] [biome index] [backdrop]
## "wall", "wallclip" and "wallgame" set a wall dweller on a real floor of
## the cave, rock and all: close, filmed (it strikes part way through), or
## at the game camera's distance.
## "backdrop" hangs a lit rock-grey wall behind them, to judge see-through
## flesh.

const TURN := 1.6
const SPEED := 4.0
const CLIP_FRAMES := 120

var _frames := 0
var _level: Level
var _crits: Array[Creature] = []
var _turns: Array[float] = []
var _mode := "sheet"
var _school: Creature
var _dweller: Creature
var _filming := false


## One fish of a school, posed and swum like any creature so it can be seen
## up close ("shoal" in any mode but "game", which shows a whole school).
class SchoolFish:
	extends Creature

	func setup() -> void:
		species = &"shoal"
		glow_color = level.biome.glow_color
		body_span = Shoal.BODY_LENGTH
		radius = 0.2
		flex = 1.0
		super.setup()

	func build_model() -> void:
		var glow := glow_color
		add_visual(Shoal.fish_mesh(), species_material(func(m: ShaderMaterial) -> void:
			Shoal.configure_material(m, glow)))


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var id := StringName(args[1]) if args.size() > 1 else &"stalker"
	_mode = args[2] if args.size() > 2 else "sheet"
	_filming = _mode == "clip" or _mode == "gameclip" or _mode == "wallclip"
	if _mode == "gameclip":
		_mode = "game"
	var biome := int(args[3]) if args.size() > 3 else 2
	var backdrop := args.size() > 4 and args[4] == "backdrop"
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
	if _mode.begins_with("wall"):
		_wall_scene(script, layout)
		return
	if id == &"shoal" and _mode != "game":
		script = SchoolFish
	if script == null:
		script = {&"mimic": Mimic, &"mother": BlindMother, &"lamplighter": Lamplighter,
			&"ironclad": Ironclad}.get(id, Stalker)
	var count := 3 if _mode == "sheet" else (1 if _mode == "game" else (2 if _mode == "clip" else 4))
	var span := 0.0
	if id == &"shoal" and _mode == "game":
		_school = script.new()
		_school.pos = origin
		_level.add_entity(_school)
		count = 0
	for i in count:
		var c: Creature = script.new()
		c.pos = origin
		# A burrower shown side on, reaching out to the right.
		c.set(&"wall_normal", Vector2.RIGHT if c is Gulper else Vector2.UP)
		_level.add_entity(c)
		c.lock_facing = true
		span = maxf(c.body_span, maxf(c.reach * 2.0, c.radius * 2.0))
		_crits.append(c)
	# Lay them out in a row, and turn each to its view.
	var gap := span * 1.35 + minf(1.0, span * 0.4)
	for i in count:
		var c := _crits[i]
		c.pos = origin + Vector2((i - (count - 1) * 0.5) * gap, 0.0)
		if _mode == "sheet" or _mode == "game" or _mode == "stroke" or _mode == "clip":
			_turns.append(0.0)
			if _mode == "stroke":
				c.set(&"_swim_clock", i / 4.0 * TAU / maxf(float(c.visuals[0].material_override.get_shader_parameter(
					&"swim_freq")), 0.1) if not c.visuals.is_empty() else 0.0)
		else:
			_turns.append([0.0, 0.0, TURN, -TURN][i])
			# Start a quarter of the way into a turn, so it heads right at the shot.
			c.facing = Vector2.RIGHT.rotated(-_turns[i] * 0.4)
			c._last_heading = c.facing.angle()
			c.set(&"_swim_clock", i * 0.37)
		c.sync_transform()
		if c.has_method(&"_rebuild_body"):
			# Laid out in the world where it started: lay it out again here.
			c.call(&"_rebuild_body")
	if _mode == "sheet":
		_view(_crits[1], 1)
		_view(_crits[2], 2)
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
	if not _crits.is_empty() and _crits[0].upright:
		# A drifter hangs below its bell: frame the whole of it.
		cam.position.y -= span * 0.3
		cam.position.z *= 0.8
	if _mode == "game":
		cam.fov = 42.0
		cam.position = Vector3(origin.x, origin.y, DiveCamera.BASE_DISTANCE)
		_level.environment_rig.environment.ambient_light_energy = 0.8
	add_child(cam)
	cam.current = true
	if backdrop:
		var wall := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(width * 3.0, width * 3.0)
		wall.mesh = quad
		var rock := StandardMaterial3D.new()
		rock.albedo_color = Color(0.32, 0.36, 0.38)
		rock.roughness = 0.9
		wall.material_override = rock
		wall.position = Vector3(origin.x, origin.y, -span * 0.6)
		add_child(wall)


func _process(_delta: float) -> void:
	var dt := 1.0 / 30.0
	_frames += 1
	if _dweller:
		if _mode == "wallclip" and _frames == 50 and _dweller is Gulper:
			# Strike out across the cave.
			var g := _dweller as Gulper
			g.state = Gulper.State.WINDUP
			g.set(&"_timer", Gulper.WINDUP_TIME)
			g.set(&"_strike_to", g.pos + (g.wall_normal + Vector2(0.5, 0.0)).normalized() * 7.0)
		_dweller.tick(dt)
		_dweller.sync_transform()
	if _school:
		if _frames == 55:
			(_school as Shoal).scare(_school.pos + Vector2(-4.0, -1.0))
		_school.behave(dt)
		_school._update_visuals(dt)
		var cam := get_viewport().get_camera_3d()
		cam.position = Vector3(_school.pos.x, _school.pos.y, cam.position.z)
	for i in _crits.size():
		var c := _crits[i]
		if _mode == "swim":
			c.facing = c.facing.rotated(_turns[i] * dt)
		c.vel = c.facing * (0.4 if c.upright else SPEED)
		if _mode == "clip":
			# Cruise, burst away, cruise again.
			var t := _frames * dt
			c.vel = c.facing * (SPEED * 3.0 if t > 1.6 and t < 2.4 else SPEED)
			if c.upright:
				# Drifters drift.
				c.vel = c.facing * (1.2 if t > 1.6 and t < 2.4 else 0.4)
		if c.get(&"_pulse_t") != null:
			# A pulsing swimmer's beat runs in its behaviour, which this skips.
			c.set(&"_pulse_t", float(c.get(&"_pulse_t")) + dt)
		var clock: float = c.get(&"_swim_clock")
		c._update_visuals(dt)
		if _mode == "sheet" and i > 0:
			_view(c, i)
		if _mode == "stroke":
			c.set(&"_swim_clock", clock)
			c.set(&"_swim_power", 1.0)
			c._update_visuals(0.0)
			_view(c, 3)
		if _mode == "clip" and i == 1:
			_view(c, 2 if c.upright else 3)
	if _filming:
		if _frames > 10:
			var args := OS.get_cmdline_user_args()
			get_viewport().get_texture().get_image().save_png("%s_%03d.png" % [args[0].get_basename(), _frames - 11])
		if _frames == 10 + CLIP_FRAMES:
			get_tree().quit()
		return
	if _frames == 24:
		var args := OS.get_cmdline_user_args()
		get_viewport().get_texture().get_image().save_png(args[0] if args.size() > 0 else "user://creature.png")
		get_tree().quit()


## Turns [param c] to a view: 1 three-quarter, 2 from above (a drifter that
## hangs upright, from below, into its bell), 3 straight down.
func _view(c: Creature, view: int) -> void:
	if c.upright:
		c.model.basis = Basis(Vector3.RIGHT, [0.0, 0.5, -0.7, 1.2][view]) * Basis(Vector3.BACK, PI * 0.5)
	else:
		c.model.rotation_degrees = [Vector3.ZERO, Vector3(0, -35, 0), Vector3(80, 0, 0), Vector3(90, 0, 0)][view]


## A wall dweller on the open floor of a cave nearest its middle, the rock
## shown, seen close or from the dive camera.
func _wall_scene(script: Script, layout: LevelLayout) -> void:
	_level.terrain.visible = true
	_level.environment_rig.environment.ambient_light_energy = 1.0
	var mid := layout.size() * 0.5
	var best: LevelLayout.Anchor = null
	for a in layout.anchors:
		if a.normal.y < 0.8 or _level.field.sample(a.pos + a.normal * 6.0) < 4.0:
			continue
		if best == null or a.pos.distance_to(mid) < best.pos.distance_to(mid):
			best = a
	_dweller = script.new()
	_dweller.pos = best.pos + best.normal * 0.6
	_dweller.set(&"wall_normal", best.normal)
	_level.add_entity(_dweller)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 30, 0)
	key.light_energy = 1.2
	add_child(key)
	var cam := Camera3D.new()
	cam.fov = 42.0
	cam.far = 400
	var lift: float = {"wall": 0.9, "wallclip": 3.5}.get(_mode, 4.0)
	var distance: float = {"wall": 8.0, "wallclip": 13.0}.get(_mode, DiveCamera.BASE_DISTANCE)
	var look := best.pos + best.normal * lift
	cam.position = Vector3(look.x, look.y, distance)
	add_child(cam)
	cam.current = true
	# The sub's lamp, off to one side.
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(look.x - 3.0, look.y + 1.5, 3.0)
	lamp.light_energy = 3.0
	lamp.omni_range = 16.0
	add_child(lamp)
