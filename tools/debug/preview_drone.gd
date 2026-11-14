extends "res://tools/debug/preview_stage.gd"
## Debug helper: stages the last Hadal Trench zone and saves screenshots of
## the sub coming alongside Vasquez's drone in its wall.
## "close" shoots it from cameras a few metres off instead; "film" films nine
## seconds of the sub coming alongside; "dark" keeps the sub's lamp off.
## Usage: xvfb-run godot --path . res://tools/debug/preview_drone.tscn -- <out_dir> [seed] [zoom] [close|film] [dark]

var _drone: VasquezDrone
var _cam: Camera3D
var _views: Array = []
var _dark := false
var _film := false
var _stop := Vector2.ZERO


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	stage(VasquezDrone.ZONE, int(args[1]) if args.size() > 1 else 99, &"lantern", true)
	LevelPopulator.populate(level, run)
	_drone = find_entity(func(e: Entity) -> bool: return e is VasquezDrone)
	place_sub(_drone.pos + _drone.normal * 8.0 + Vector2(0.0, 5.5), float(args[2]) if args.size() > 2 else 1.0)
	add_hud()
	shot_prefix = "drone"
	shot_times = [1.5, 7.0]
	_dark = args.has("dark")
	_film = args.has("film")
	if _film:
		# From well off, up alongside, and stop there.
		_stop = level.field.resolve_circle(_drone.pos + _drone.normal * 5.5 + Vector2(0.0, 1.0), 1.6)
		sub.pos = level.field.resolve_circle(_drone.pos + _drone.normal * 18.0 + Vector2(0.0, 2.0), 1.6)
		camera.snap()
		shot_times = []
		for i in 135:
			shot_times.append(0.5 + i / 15.0)
	if args.has("close"):
		var d := Vector3(_drone.pos.x, _drone.pos.y, VasquezDrone.DEPTH)
		var n := Vector3(_drone.normal.x, _drone.normal.y, 0.0)
		_views = [[d + n * 1.0 + Vector3(0, 0.5, 9.0), d + n * 0.8], [d + n * 4.5 + Vector3(0, 1.5, 6.0), d + n * 0.8],
			[d - n * 1.0 + Vector3(0, 2.5, 6.5), d + n * 0.5], [d + n * 2.6 + Vector3(0, -0.6, 3.8), d + n * 2.2]]
		var fill := DirectionalLight3D.new()
		fill.light_energy = 1.4 if OS.has_environment("DRONE_DEBUG") else 0.5
		fill.rotation_degrees = Vector3(-35, 20, 0)
		add_child(fill)
		_cam = Camera3D.new()
		_cam.fov = 42.0
		add_child(_cam)
		_cam.current = true
		shot_times = [1.0, 1.4, 1.8, 2.2]
		# Keep the sub out of shot, and out of the survey's reach.
		sub.pos = _drone.pos + _drone.normal * 14.0


func direct(_dt: float) -> void:
	if _dark:
		sub.lamp_on = false
	if _cam:
		var i := mini(shots_taken(), _views.size() - 1)
		_cam.position = _views[i][0]
		_cam.look_at(_views[i][1])
		sub.vel = Vector2.ZERO
		return
	sub.aim = (_drone.pos - sub.pos).normalized()
	if _film:
		var to := _stop - sub.pos
		sub.external_move = to.normalized() * clampf(to.length() * 0.25, 0.0, 0.6) if t > 1.0 else Vector2.ZERO
		if to.length() < 0.4:
			sub.vel *= 0.8
		return
	if t > 3.0 and t < 4.5:
		sub.external_move = (_drone.pos - sub.pos).normalized() * 0.5
