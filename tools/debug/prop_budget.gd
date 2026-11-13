extends Node
## Debug helper: triangles in each prop variant, and for a zone of each
## biome how many props it scatters, their triangles, and the most a single
## dive-camera view draws once patches out of view are culled.
## Usage: godot --headless --path . res://tools/debug/prop_budget.tscn


func _ready() -> void:
	for id: StringName in PropScatter.DEFS:
		var counts := []
		for m: Mesh in PropScatter.variants(id):
			counts.append(_tris(m))
		print("%s: %s" % [id, counts])
	for zone: int in [0, 3, 6, 9, 12]:
		var layout := LevelGenerator.new().generate(BiomeLibrary.biome_for_zone(zone), 77, zone)
		var level := Level.new()
		add_child(level)
		level.layout = layout
		level.field = layout.field
		level.biome = layout.biome
		PropScatter.scatter(level)
		var total := 0
		var instances := 0
		var batches: Array[MultiMeshInstance3D] = []
		for c in level.get_children():
			if c is MultiMeshInstance3D:
				var mm: MultiMesh = c.multimesh
				total += _tris(mm.mesh) * mm.instance_count
				instances += mm.instance_count
				batches.append(c)
		# The worst view: a 52 x 30 window (the dive camera's) slid over the zone.
		var worst := 0
		var worst_calls := 0
		var size := layout.size()
		for x in range(0, int(size.x), 8):
			for y in range(0, int(size.y), 8):
				var view := Rect2(x, -y - 30.0, 52.0, 30.0)
				var seen := 0
				var calls := 0
				for b in batches:
					# Each batch is one patch of PropScatter.CHUNK, named id_variant_x_y.
					var part := String(b.name).rsplit("_", true, 2)
					var patch := Rect2(int(part[1]) * PropScatter.CHUNK, int(part[2]) * PropScatter.CHUNK,
						PropScatter.CHUNK, PropScatter.CHUNK)
					if view.intersects(patch.grow(3.0)):
						seen += _tris(b.multimesh.mesh) * b.multimesh.instance_count
						calls += 1
				if seen > worst:
					worst = seen
					worst_calls = calls
		print("zone %d (%s): %d props in %d batches, %d triangles; worst view %d triangles in %d batches"
			% [zone, layout.biome.id, instances, batches.size(), total, worst, worst_calls])
		level.free()
	get_tree().quit()


func _tris(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		n += (m.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return n
