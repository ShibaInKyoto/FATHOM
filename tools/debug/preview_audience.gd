extends "res://tools/debug/preview_stage.gd"
## Debug helper: hangs back from the audience over Meridian Deep and saves
## screenshots as the Choir's tone shifts and they turn together.
## "film" films eight seconds over two shifts of the tone; "close" watches
## from a camera in front of the crowd instead of the dive camera (the sub
## kept away); "swim" films the sub swimming in under the crowd.
## Usage: xvfb-run godot --path . res://tools/debug/preview_audience.tscn -- <out_dir> [seed] [zoom] [film]

var _audience: StationAudience
var _film := false
var _forced := false
var _cam: Camera3D
var _swim_to := Vector2.INF


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	stage(BiomeLibrary.TOTAL_ZONES - 1, int(args[1]) if args.size() > 1 else 7)
	_audience = find_entity(func(e: Entity) -> bool: return e is StationAudience)
	var station: MeridianStation = find_entity(func(e: Entity) -> bool: return e is MeridianStation)
	# Off to one side of the gallery, low down, looking up at the dome.
	var at := level.field.resolve_circle(station.pos + Vector2(-15.0, 3.0), 1.6)
	place_sub(at, float(args[2]) if args.size() > 2 else 1.4)
	add_hud()
	_audience.set(&"_tone_in", 2.5)
	shot_prefix = "audience"
	shot_times = [2.0, 3.2, 5.5]
	_film = args.has("film")
	if args.has("close"):
		_cam = Camera3D.new()
		_cam.fov = 50.0
		add_child(_cam)
		_cam.current = true
		_cam.position = Vector3(station.pos.x, station.pos.y + 8.5, 24.0)
		_cam.look_at(Vector3(station.pos.x, station.pos.y + 8.0, -2.0))
		sub.pos = station.pos + Vector2(0.0, 60.0)
	if args.has("swim"):
		sub.pos = level.field.resolve_circle(station.pos + Vector2(-20.0, 3.5), 1.6)
		_swim_to = level.field.resolve_circle(station.pos + Vector2(-1.0, 4.0), 1.6)
		camera.snap()
		shot_times = []
		for i in 150:
			shot_times.append(1.0 + i / 15.0)
	if _film:
		shot_times = []
		for i in 120:
			shot_times.append(1.0 + i / 15.0)


func direct(_dt: float) -> void:
	sub.run.hull = sub.stats.max_hull
	if _swim_to != Vector2.INF:
		var to := _swim_to - sub.pos
		sub.aim = Vector2(1.0, 0.1).normalized()
		sub.external_move = to.normalized() * clampf(to.length() * 0.2, 0.0, 0.5) if t > 1.0 else Vector2.ZERO
		if to.length() < 0.4:
			sub.vel *= 0.8
	else:
		sub.vel = Vector2.ZERO
		sub.aim = Vector2(1.0, 0.0)
	if _film and t > 5.5 and not _forced:
		_forced = true
		_audience.set(&"_tone_in", 0.0)
