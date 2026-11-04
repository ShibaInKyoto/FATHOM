extends SceneTree
## Writes a hull's fairing skin to JSON for tools/art/hull_maps.py, which
## paints the maps that wrap it.
## Usage: godot --headless --path . -s res://tools/art/dump_hull.gd -- <out.json>


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://lantern_hull.json"
	var grid := LanternBuild.fairing_grid(LanternBuild.NU, LanternBuild.NV)
	var points: Array = []
	for p in grid:
		points.append([snappedf(p.x, 0.0001), snappedf(p.y, 0.0001), snappedf(p.z, 0.0001)])
	var data := {"x0": LanternBuild.X0, "x1": LanternBuild.X1, "nu": LanternBuild.NU, "nv": LanternBuild.NV,
		"points": points}
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	quit()
