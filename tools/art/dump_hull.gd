extends SceneTree
## Writes a frame's fairing skin to JSON for tools/art/hull_maps.py, which
## paints the maps that wrap it.
## Usage: godot --headless --path . -s res://tools/art/dump_hull.gd -- <out.json> <frame>


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://hull.json"
	var frame := args[1] if args.size() > 1 else "lantern"
	var hull: HullFairing = LanternBuild.fairing()
	match frame:
		"mako":
			hull = MakoBuild.fairing()
		"bathysphere":
			hull = BathysphereBuild.fairing()
	var points: Array = []
	for p in hull.grid():
		points.append([snappedf(p.x, 0.0001), snappedf(p.y, 0.0001), snappedf(p.z, 0.0001)])
	var data := {"x0": hull.x0, "x1": hull.x1, "nu": hull.nu, "nv": hull.nv, "points": points}
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	quit()
