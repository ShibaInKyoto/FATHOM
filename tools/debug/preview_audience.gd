extends "res://tools/debug/preview_stage.gd"
## Debug helper: hangs back from the audience over Meridian Deep and saves
## screenshots as the Choir's tone shifts and they turn together.
## "film" films eight seconds over two shifts of the tone.
## Usage: xvfb-run godot --path . res://tools/debug/preview_audience.tscn -- <out_dir> [seed] [zoom] [film]

var _audience: StationAudience
var _film := false
var _forced := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	stage(BiomeLibrary.TOTAL_ZONES - 1, int(args[1]) if args.size() > 1 else 7)
	_audience = find_entity(func(e: Entity) -> bool: return e is StationAudience)
	var centre := Vector2.ZERO
	for m in _audience.members:
		centre += m.pos / _audience.members.size()
	# Below the crowd, clear of every member.
	var at := centre + Vector2(0.0, -3.0)
	for k in 24:
		var p := centre + Vector2(0.0, -2.5) + Vector2.from_angle(TAU * k / 24.0) * 3.0
		var clear := level.field.sample(p) > 2.0
		for m in _audience.members:
			clear = clear and m.pos.distance_to(p) > 5.0
		if clear:
			at = p
			break
	place_sub(at, float(args[2]) if args.size() > 2 else 1.25)
	add_hud()
	_audience.set(&"_tone_in", 2.5)
	shot_prefix = "audience"
	shot_times = [2.0, 3.2, 5.5]
	_film = args.has("film")
	if _film:
		shot_times = []
		for i in 120:
			shot_times.append(1.0 + i / 15.0)


func direct(_dt: float) -> void:
	sub.run.hull = sub.stats.max_hull
	sub.vel = Vector2.ZERO
	sub.aim = Vector2(1.0, 0.0)
	if _film and t > 5.5 and not _forced:
		_forced = true
		_audience.set(&"_tone_in", 0.0)
