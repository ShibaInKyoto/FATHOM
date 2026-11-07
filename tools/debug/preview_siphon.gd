extends "res://tools/debug/preview_stage.gd"
## Debug helper: a Lantern Chain drifting past the sub, seen through the dive
## camera with the HUD and post-processing, as in play; it stings the sub
## part way through.
## Usage: xvfb-run godot --path . res://tools/debug/preview_siphon.tscn -- <out_dir> [zone]

var _chain: Siphonophore


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	stage(int(args[1]) if args.size() > 1 else 1, 4040, &"lantern", true)
	var at := level.layout.random_open_point(level.rng, 6.0)
	_chain = Siphonophore.new()
	_chain.pos = at
	level.add_entity(_chain)
	# Some way along already, its chain trailing out behind it.
	for i in 300:
		_chain.tick(1.0 / 30.0)
	place_sub(_chain.segments[8] + Vector2(1.0, -7.0), 0.85)
	add_hud()
	shot_prefix = "siphon"
	shot_times = [1.0, 2.2, 2.6, 3.4]


func direct(_dt: float) -> void:
	sub.lamp_on = true
	sub.aim = (_chain.segments[6] - sub.pos).normalized()
	# Rises into the chain.
	sub.external_move = Vector2(0.0, 0.6) if t > 1.2 and t < 2.2 else Vector2.ZERO
