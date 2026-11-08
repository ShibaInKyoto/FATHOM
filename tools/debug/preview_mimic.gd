extends "res://tools/debug/preview_stage.gd"
## Debug helper: a salvage cache and a Mimic side by side beside the sub,
## through the dive camera with the HUD: asleep (they should look alike),
## then the Mimic wakes, lunges and gives chase.
## Usage: xvfb-run godot --path . res://tools/debug/preview_mimic.tscn -- <out_dir> [zoom] [film]
## "film" saves every frame for twelve seconds instead: the sub runs from it
## and it gives chase, then gives up and settles back into a crate.

var _mimic: Mimic


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	stage(4, 4040, &"lantern", true)
	var at := level.layout.random_open_point(level.rng, 7.0)
	var cache := SalvageCache.new()
	cache.pos = at + Vector2(-2.2, 0.0)
	level.add_entity(cache)
	_mimic = Mimic.new()
	_mimic.pos = at + Vector2(2.2, 0.0)
	level.add_entity(_mimic)
	place_sub(at + Vector2(-9.0, 1.5), float(args[1]) if args.size() > 1 else 0.4)
	add_hud()
	shot_prefix = "mimic"
	shot_times = [0.9, 1.3, 1.55, 2.3, 3.2]
	if args.size() > 2 and args[2] == "film":
		shot_times.clear()
		for i in 330:
			shot_times.append(0.7 + i / 30.0)


func direct(_dt: float) -> void:
	sub.lamp_on = true
	sub.aim = (_mimic.pos - sub.pos).normalized()
	# (Filmed, not fought: the sub shrugs off its bites.)
	sub.run.hull = sub.stats.max_hull
	# Backs off as it comes, so it has to chase; then gets clear away, so it
	# gives up and settles.
	sub.external_move = Vector2(-1.0, 0.15) if t > 1.4 and t < 7.0 else Vector2.ZERO
	if t >= 7.5 and _mimic.state == Mimic.State.CHASE:
		_mimic.set(&"_timer", 0.0)
	if t >= 7.5 and t < 7.5 + STEP * 1.5:
		# Just out of its reach, both still in shot.
		sub.pos = _mimic.pos + Vector2(-6.5, 1.5)
	if t >= 1.0 and _mimic.state == Mimic.State.DORMANT:
		_mimic.call(&"_wake")
