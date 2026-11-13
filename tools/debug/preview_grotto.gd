extends "res://tools/debug/preview_stage.gd"
## Debug helper: stages the first Midnight Caverns zone and saves screenshots
## of its glow-worm grotto lit in the quiet, going dark around a loud noise,
## and lighting up again.
## "close" (after the zoom) shoots it from a camera up by the ceiling instead,
## and "film" films eight seconds there, a frame every fifteenth of a second.
## Usage: xvfb-run godot --path . res://tools/debug/preview_grotto.tscn -- <out_dir> [seed] [zoom] [close|film]

var _grotto: GlowwormGrotto
var _noisy := false
var _close: Camera3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var run_seed := int(args[1]) if args.size() > 1 else 17
	for k in 8:
		stage(4, run_seed + k)
		_grotto = find_entity(func(e: Entity) -> bool: return e is GlowwormGrotto)
		if _grotto:
			break
		level.free()
	var at := level.field.resolve_circle(_grotto.room.center + Vector2(0.0, _grotto.room.radius.y * 0.15), 1.6)
	place_sub(at, float(args[2]) if args.size() > 2 else 1.5)
	add_hud()
	shot_prefix = "grotto"
	shot_times = [2.0, 3.8, 5.5, 14.0]
	var mode := args[3] if args.size() > 3 else ""
	if mode == "close" or mode == "film":
		# Up by the ceiling, looking along it.
		var c := _grotto.room.center
		var top := c.y
		for w in _grotto.worm_pos:
			if absf(w.x - c.x) < 3.0:
				top = maxf(top, w.y)
		_close = Camera3D.new()
		_close.fov = 50.0
		add_child(_close)
		_close.position = Vector3(c.x - 2.0, top - 3.2, 9.0)
		_close.look_at(Vector3(c.x + 1.0, top - 1.2, -1.0))
		_close.current = true
		if mode == "film":
			shot_times = []
			for i in 120:
				shot_times.append(1.5 + i / 15.0)


func direct(_dt: float) -> void:
	sub.run.hull = sub.stats.max_hull
	sub.lamp_on = false
	# Hold station, so the camera keeps the grotto in shot.
	sub.vel = Vector2.ZERO
	if t > 2.3 and not _noisy:
		_noisy = true
		level.emit_noise(sub.pos, 26.0, sub)
