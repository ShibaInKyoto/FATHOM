extends Node3D
## Debug helper: MD-02's model alone in an even light, from the side the
## game shows, three quarters front and behind, and from above.
## Usage: xvfb-run godot --path . res://tools/debug/preview_drone_model.tscn -- <out_dir>


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
	env.environment.glow_enabled = true
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 25, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)
	var drone := MeshInstance3D.new()
	drone.mesh = DroneModel.build()
	var mat := ShaderMaterial.new()
	mat.shader = VasquezDrone.DRONE_SHADER
	mat.set_shader_parameter(&"status", 1.0)
	drone.material_override = mat
	add_child(drone)
	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.current = true
	var views := [[Vector3(0.4, 0.3, 7.5), Vector3(0.4, 0.0, 0)], [Vector3(4.5, 1.8, 4.5), Vector3(0.6, 0.0, 0)],
		[Vector3(-4.0, 2.0, 4.0), Vector3(0.2, 0.0, 0)], [Vector3(0.4, 7.0, 1.0), Vector3(0.4, 0.0, 0)],
		[Vector3(3.3, -0.2, 2.6), Vector3(1.7, -0.3, 0.6)]]
	for i in views.size():
		cam.position = views[i][0]
		cam.look_at(views[i][1])
		for _f in 3:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("model_%d.png" % i))
	get_tree().quit()
