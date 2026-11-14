extends "res://tools/debug/preview_stage.gd"
## Debug helper: flies the sub up to the Meridian Deep station in the final
## zone and saves screenshots before and after its beacon pings.
## "close" shoots it from cameras a few metres off instead; "film" films ten
## seconds of the sub arriving; "dark" keeps the sub's lamp off.
## Usage: xvfb-run godot --path . res://tools/debug/preview_station.tscn -- <out_dir> [seed] [zoom] [close|film] [dark]

var _station: MeridianStation
var _cam: Camera3D
var _views: Array = []
var _dark := false
var _film := false
var _stop := Vector2.ZERO


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	stage(BiomeLibrary.TOTAL_ZONES - 1, int(args[1]) if args.size() > 1 else 7)
	_station = find_entity(func(e: Entity) -> bool: return e is MeridianStation)
	place_sub(_station.pos + Vector2(-7.0, 5.0), float(args[2]) if args.size() > 2 else 1.15)
	add_hud()
	shot_prefix = "station"
	shot_times = [2.6, 4.0]
	_dark = args.has("dark")
	_film = args.has("film")
	if _film:
		# From well off to the left, along the floor and up to the hub.
		var want := _station.pos + Vector2(-24.0, 4.0)
		sub.pos = level.field.resolve_circle(want, 1.6)
		if sub.pos.distance_to(want) > 3.0:
			sub.pos = level.field.resolve_circle(_station.pos + Vector2(-26.0, 6.0), 1.6)
		_stop = level.field.resolve_circle(_station.pos + Vector2(-3.0, 3.6), 1.6)
		camera.snap()
		shot_times = []
		for i in 150:
			shot_times.append(0.5 + i / 15.0)
	if args.has("close"):
		var c := Vector3(_station.pos.x, _station.pos.y + PropScatter.surface_offset(MeridianStation.DEPTH) - 0.3,
			MeridianStation.DEPTH)
		var k := MeridianStation.SCALE
		_views = [[c + Vector3(0, 4.0, 24.0) * k, c + Vector3(0, 3.6, 0) * k],
			[c + Vector3(-9.5, 3.2, 6.5) * k, c + Vector3(-6.0, 2.6, 0) * k],
			[c + Vector3(13.5, 4.0, 7.0) * k, c + Vector3(10.0, 2.0, 0) * k],
			[c + Vector3(1.5, 4.0, 5.2) * k, c + Vector3(0, 3.3, 0) * k],
			[c + Vector3(-3.5, 10.5, 8.0) * k, c + Vector3(-1.0, 6.0, 0) * k],
			[c + Vector3(-5.0, 1.4, 6.0) * k, c + Vector3(-5.5, 1.0, 0) * k],
			[c + Vector3(3.5, 9.6, 5.0) * k, c + Vector3(0.6, 8.4, 0) * k]]
		var fill := DirectionalLight3D.new()
		fill.light_energy = 0.5
		fill.rotation_degrees = Vector3(-35, 20, 0)
		add_child(fill)
		_cam = Camera3D.new()
		_cam.fov = 42.0
		add_child(_cam)
		_cam.current = true
		shot_times = [1.0, 1.4, 1.8, 2.2, 2.6, 3.0, 3.4]
		# Keep the sub out of shot, and out of the greeting's reach.
		sub.pos = _station.pos + Vector2(0.0, 40.0)


func direct(_dt: float) -> void:
	sub.run.hull = sub.stats.max_hull
	if _dark:
		sub.lamp_on = false
	if _cam:
		var i := mini(shots_taken(), _views.size() - 1)
		_cam.position = _views[i][0]
		_cam.look_at(_views[i][1])
		sub.vel = Vector2.ZERO
		return
	if _film:
		var to := _stop - sub.pos
		sub.aim = Vector2(1.0, -0.2).normalized()
		sub.external_move = to.normalized() * clampf(to.length() * 0.2, 0.0, 0.55) if t > 1.0 else Vector2.ZERO
		if to.length() < 0.4:
			sub.vel *= 0.8
		return
	sub.aim = Vector2(1.0, -0.25).normalized()
	sub.external_move = Vector2(0.25, 0.0)
