extends "res://tools/debug/preview_stage.gd"
## Debug helper: stages the second Sunlit Shelf zone and saves screenshots of
## the sperm whale passing behind the playfield, clicking.
## Usage: xvfb-run godot --path . res://tools/debug/preview_whale_pass.tscn -- <out_dir> [seed] [zoom]

var _whale: PassingWhale


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	stage(PassingWhale.ZONE, int(args[1]) if args.size() > 1 else 17)
	_whale = find_entity(func(e: Entity) -> bool: return e is PassingWhale)
	# Over the middle of its stretch, a little above its line.
	place_sub(_whale.pos + Vector2(0.0, 3.0), float(args[2]) if args.size() > 2 else 0.8)
	add_hud()
	shot_prefix = "whale"
	var to_middle := (_whale.to.x - _whale.from.x) * 0.5 / PassingWhale.SPEED
	shot_times = [to_middle - 4.0, to_middle, to_middle + 3.0]


func direct(_dt: float) -> void:
	# (Watching, not fighting: whatever drifts by does it no harm.)
	sub.run.hull = sub.stats.max_hull
	sub.vel = Vector2.ZERO
	sub.lamp_on = true
	sub.aim = Vector2(0.0, -1.0)
