extends "res://tools/debug/preview_stage.gd"
## Debug helper: the sub cruising past a bed of props in a real zone, under
## the dive camera, to see the props sway in the current and the shy ones
## pull in as it passes. Films a frame every fifteenth of a second.
## Usage: xvfb-run godot --path . res://tools/debug/preview_reef.tscn -- <out_dir> [zone] [prop] [seed] [seconds] [zoom]

const FPS := 15.0

var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _length := 8.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var zone := int(args[1]) if args.size() > 1 else 3
	var prop := StringName(args[2]) if args.size() > 2 else &"anemone"
	var run_seed := int(args[3]) if args.size() > 3 else 7
	_length = float(args[4]) if args.size() > 4 else 8.0
	var zoom := float(args[5]) if args.size() > 5 else 1.0
	stage(zone, run_seed, &"lantern", true)
	PropScatter.scatter(level)
	# The prop of that kind with the most of its kind round it and open water above.
	var spots := PackedVector2Array()
	for c in level.get_children():
		if c is MultiMeshInstance3D and String(c.name).begins_with(String(prop) + "_"):
			var mm: MultiMesh = c.multimesh
			for i in mm.instance_count:
				var o := mm.get_instance_transform(i).origin
				if o.z > -2.0:
					spots.append(Vector2(o.x, o.y))
	var best := level.layout.start
	var best_score := -1
	for p in spots:
		var score := 0
		for q in spots:
			if p.distance_to(q) < 8.0:
				score += 1
		if score > best_score and level.field.sample(p + Vector2(0, 4)) > 2.5:
			best_score = score
			best = p
	var above := level.field.resolve_circle(best + Vector2(0, 3.5), 1.6)
	_from = level.field.resolve_circle(above + Vector2(-13, 1), 1.6)
	_to = level.field.resolve_circle(above + Vector2(13, 1), 1.6)
	place_sub(_from, zoom)
	sub.lamp_on = true
	add_child(PostFx.new())
	shot_prefix = "f"
	for i in int(_length * FPS):
		shot_times.append(0.5 + i / FPS)


func direct(_dt: float) -> void:
	sub.run.hull = sub.stats.max_hull
	sub.run.battery = sub.stats.max_battery
	var f := clampf((t - 0.5) / _length, 0.0, 1.0)
	var want := _from.lerp(_to, smoothstep(0.0, 1.0, f))
	var to := want - sub.pos
	sub.external_move = to.limit_length(1.0) if to.length() > 0.3 else Vector2.ZERO
	sub.aim = Vector2.RIGHT.rotated(-0.35)
