extends Node3D
## Debug helper: the stalactite variants alone in an even light, side on,
## from below, and tipped over to see the top of their plugs (as they show
## when they fall), all three sections together.
## Usage: xvfb-run godot --path . res://tools/debug/preview_stalactite_model.tscn -- <out_dir>


func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.04, 0.06, 0.09)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.45, 0.5, 0.6)
	env.environment.ambient_light_energy = 0.6
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 25, 0)
	sun.light_energy = 1.4
	add_child(sun)
	var mat := ShaderMaterial.new()
	mat.shader = Stalactite.SHADER
	mat.set_shader_parameter(&"rock_albedo", TerrainRenderer.ROCK_ALBEDO)
	mat.set_shader_parameter(&"rock_tint", Color(0.42, 0.45, 0.55))
	mat.set_shader_parameter(&"calcite", Color(0.7, 0.7, 0.72))
	var holders: Array[Node3D] = []
	for v in StalactiteModel.VARIANTS:
		var holder := Node3D.new()
		holder.position = Vector3((v - 1) * 3.0, 0.0, 0.0)
		add_child(holder)
		holders.append(holder)
		for mesh in StalactiteModel.sections(v):
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = mat
			holder.add_child(mi)
	var cam := Camera3D.new()
	cam.fov = 45.0
	add_child(cam)
	cam.current = true
	# Side on, from below, then tipped over (seen from above).
	var shots := [[Vector3(0, 0.2, 9.0), Vector3(0, 0.0, 0), 0.0], [Vector3(0, -6.0, 5.0), Vector3(0, -0.5, 0), 0.0],
		[Vector3(0, 6.0, 6.5), Vector3(0, 0.0, 0), 1.9], [Vector3(1.5, 2.0, 4.0), Vector3(0, 1.4, 0), 0.0]]
	for i in shots.size():
		for h in holders:
			h.rotation.x = shots[i][2]
		cam.position = shots[i][0]
		cam.look_at(shots[i][1])
		for _f in 3:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("model_%d.png" % i))
	get_tree().quit()
