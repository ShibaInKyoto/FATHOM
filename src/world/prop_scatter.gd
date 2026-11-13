class_name PropScatter
extends RefCounted
## Decorates a zone with instanced props placed on reachable wall anchors.
## Each prop type becomes one MultiMeshInstance3D (one draw call).

## Everything grows a little thicker than its definition says.
const LUSH := 1.35
## Side of the square patches props are batched in (see [method scatter]).
const CHUNK := 32.0
const SHADER := preload("res://src/fx/shaders/prop.gdshader")
const NET_SHADER := preload("res://src/fx/shaders/prop_net.gdshader")
const ROCK_SHADER := preload("res://src/fx/shaders/rock_prop.gdshader")

## placement: floor / ceiling / wall / any. density: chance per anchor.
## Optional yaw: max spin (radians) around the up axis; default is any.
## sway: how far the current bends its top; flutter: how far its fronds or
## tentacles stir; retract: whether it shuts when the sub comes close; wake:
## how far (m) the hull bends its top aside in passing (both kept by
## [PropLife]); glass: light through it from behind.
const DEFS: Dictionary[StringName, Dictionary] = {
	&"kelp": {"placement": "floor", "density": 0.22, "scale": Vector2(0.6, 1.4), "z": Vector2(-4.5, 1.5),
		"sway": 0.4, "flutter": 0.04, "wake": 1.5, "glass": 0.45, "rough": 0.55},
	&"rock": {"placement": "any", "density": 0.18, "scale": Vector2(0.5, 2.0), "z": Vector2(-3.0, 1.0),
		"rough": 0.9},
	&"coral": {"placement": "floor", "density": 0.2, "scale": Vector2(0.8, 1.6), "z": Vector2(-3.5, 0.0),
		"rough": 0.65},
	&"anemone": {"placement": "wall", "density": 0.12, "scale": Vector2(0.6, 1.3), "z": Vector2(-3.0, 0.0),
		"flutter": 0.025, "retract": 1.0, "glass": 0.3, "rough": 0.4},
	&"fan": {"placement": "wall", "density": 0.12, "scale": Vector2(0.8, 1.6), "z": Vector2(-4.0, -1.0),
		"sway": 0.05, "glass": 0.5, "rough": 0.6, "yaw": 0.6},
	&"crystal": {"placement": "any", "density": 0.1, "scale": Vector2(0.5, 1.5), "z": Vector2(-3.5, 0.5),
		"rough": 0.15},
	&"mushroom": {"placement": "floor", "density": 0.16, "scale": Vector2(1.0, 2.2), "z": Vector2(-3.0, 0.0),
		"glass": 0.25, "rough": 0.5},
	&"spine": {"placement": "floor", "density": 0.025, "scale": Vector2(0.8, 1.4), "z": Vector2(-4.0, -1.0),
		"rough": 0.55},
	&"tubeworm": {"placement": "floor", "density": 0.2, "scale": Vector2(0.6, 1.3), "z": Vector2(-3.0, 0.0),
		"flutter": 0.012, "retract": 1.0, "rough": 0.45},
	&"chimney": {"placement": "floor", "density": 0.05, "scale": Vector2(0.7, 1.4), "z": Vector2(-4.0, -1.5),
		"rough": 0.9},
}

static var _meshes: Dictionary[StringName, Array] = {}
static var _materials: Dictionary[StringName, ShaderMaterial] = {}


static func scatter(level: Level) -> void:
	var layout := level.layout
	var biome := level.biome
	var rng := RandomNumberGenerator.new()
	rng.seed = layout.zone_seed ^ 0x9e3779b9
	for id in biome.props:
		if not DEFS.has(id):
			continue
		var def: Dictionary = DEFS[id]
		var density: float = def.density * biome.props[id] * LUSH * (Settings.quality + 2) / 4.0
		var meshes := variants(id)
		var xforms: Array[Transform3D] = []
		var customs: Array[Color] = []
		var picks: Array[int] = []
		for a in layout.anchors:
			if rng.randf() > density or not _placement_ok(def.placement, a.normal):
				continue
			if a.pos.distance_to(layout.start) < 6.0:
				continue
			var z := rng.randf_range(def.z.x, def.z.y)
			var base := a.pos + a.normal * surface_offset(z)
			var up := a.normal
			if def.placement == "floor":
				# Floor growth stands up towards the surface (+y), half following the slope.
				up = (a.normal + Vector2(0.0, 1.2)).normalized()
			var max_yaw: float = def.get("yaw", PI)
			var basis := Basis(Vector3.BACK, up.angle() - PI * 0.5) * Basis(Vector3.UP, rng.randf_range(-max_yaw, max_yaw))
			basis = basis.scaled(Vector3.ONE * rng.randf_range(def.scale.x, def.scale.y))
			xforms.append(Transform3D(basis, Vector3(base.x, base.y, z)))
			if id == &"rock" and z > -2.0:
				level.boulders.append(a.pos)
			# (w is left for PropLife's state: shut or leaning.)
			customs.append(Color(rng.randf(), rng.randf(), rng.randf_range(0.75, 1.15), 0.0))
			picks.append(rng.randi() % meshes.size())
		if xforms.is_empty():
			continue
		# One MultiMesh (one draw call) per variant in each patch of the zone,
		# so only the patches in view are drawn.
		var groups := {}
		for i in picks.size():
			var o := xforms[i].origin
			var key := Vector3i(picks[i], floori(o.x / CHUNK), floori(o.y / CHUNK))
			if not groups.has(key):
				groups[key] = []
			groups[key].append(i)
		for key: Vector3i in groups:
			var v := key.x
			var mine: Array = groups[key]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = meshes[v]
			mm.instance_count = mine.size()
			for k in mine.size():
				mm.set_instance_transform(k, xforms[mine[k]])
				mm.set_instance_custom_data(k, customs[mine[k]])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "%s_%d_%d_%d" % [id, v, key.y, key.z]
			mmi.multimesh = mm
			# Room for the current to sway it past its resting bounds.
			mmi.extra_cull_margin = 1.5
			mmi.material_override = _material(id, biome)
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if id == &"rock" or id == &"kelp" \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			level.add_child(mmi)
			if def.get("retract", 0.0) > 0.0 or def.get("wake", 0.0) > 0.0:
				_add_life(level, def, mm, mine, xforms, customs, meshes[v].get_aabb().end.y)
		if id == &"chimney":
			_add_vent_plumes(level, xforms)


## Hands the props of [param mm] (indices [param mine] into [param xforms]
## and [param customs]) to the level's [PropLife].
static func _add_life(level: Level, def: Dictionary, mm: MultiMesh, mine: Array, xforms: Array[Transform3D],
		customs: Array[Color], height: float) -> void:
	if level.prop_life == null:
		level.prop_life = PropLife.new()
	var picked_xf := []
	var picked_custom := []
	for i: int in mine:
		picked_xf.append(xforms[i])
		picked_custom.append(customs[i])
	var kind := PropLife.Kind.SHY if def.get("retract", 0.0) > 0.0 else PropLife.Kind.LEAN
	level.prop_life.add(mm, kind, picked_xf, picked_custom, height)


static func _placement_ok(placement: String, n: Vector2) -> bool:
	match placement:
		"floor":
			return n.y > 0.45
		"ceiling":
			return n.y < -0.45
		"wall":
			return absf(n.y) < 0.75
	return true


## Distance along the wall normal at which the terrain relief sits at depth z
## (inverse of the relief profile in terrain.gdshader).
static func surface_offset(z: float) -> float:
	if z < 0.0:
		return 2.4 * atanh(clampf(-z / TerrainRenderer.BACK_DEPTH, 0.0, 0.95))
	return -2.0 * atanh(clampf(z / TerrainRenderer.ROCK_HEIGHT, 0.0, 0.95))


static func _add_vent_plumes(level: Level, xforms: Array[Transform3D]) -> void:
	for xf in xforms:
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 12.0
		pm.initial_velocity_min = 1.5
		pm.initial_velocity_max = 3.0
		pm.gravity = Vector3(0, 0.8, 0)
		pm.scale_min = 1.5
		pm.scale_max = 4.0
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = 1.5
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(0.9, 0.45, 0.15, 0.5), Color(0.15, 0.12, 0.12, 0.35), Color(0.05, 0.05,
				0.05, 0.0)])
		g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		var ramp := GradientTexture1D.new()
		ramp.gradient = g
		pm.color_ramp = ramp
		var p := GPUParticles3D.new()
		p.amount = 24
		p.lifetime = 4.0
		p.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2(0.8, 0.8)
		q.material = Fx.particle_material(Fx.soft_texture(), false)
		p.draw_pass_1 = q
		p.visibility_aabb = AABB(Vector3(-6, -1, -6), Vector3(12, 20, 12))
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		level.add_child(p)
		p.global_transform = Transform3D(Basis(), xf * Vector3(0, 5.0, 0))
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.45, 0.15)
		light.omni_range = 8.0
		light.light_energy = 1.5
		level.add_child(light)
		light.global_position = xf * Vector3(0, 5.2, 0) + Vector3(0, 0, 1.5)


static func _material(id: StringName, biome: BiomeDef) -> ShaderMaterial:
	var key := StringName("%s/%s" % [id, biome.id])
	if _materials.has(key):
		return _materials[key]
	if id == &"rock":
		_materials[key] = rock_material(biome)
		return _materials[key]
	var def: Dictionary = DEFS[id]
	var m := ShaderMaterial.new()
	m.shader = NET_SHADER if id == &"fan" else SHADER
	m.set_shader_parameter(&"sway", def.get("sway", 0.0))
	m.set_shader_parameter(&"flutter", def.get("flutter", 0.0))
	m.set_shader_parameter(&"retract", def.get("retract", 0.0))
	m.set_shader_parameter(&"wake", def.get("wake", 0.0))
	m.set_shader_parameter(&"translucency", def.get("glass", 0.0))
	m.set_shader_parameter(&"roughness", def.rough)
	m.set_shader_parameter(&"glow_color", biome.glow_color)
	var glow := 0.0
	var tint_a := Color(1, 1, 1)
	var tint_b := Color(1, 1, 1)
	match id:
		&"kelp":
			tint_a = Color(1.0, 1.0, 0.92)
			tint_b = Color(0.85, 0.95, 0.75)
		&"coral":
			tint_a = Color(1.0, 0.45, 0.5)
			tint_b = Color(1.0, 0.7, 0.35)
			glow = 1.6 if biome.id == &"reef" else 0.4
		&"anemone":
			tint_a = Color(1.0, 0.5, 0.8)
			tint_b = Color(0.6, 0.6, 1.0)
			glow = 2.4
		&"fan":
			tint_a = Color(0.9, 0.3, 0.55)
			tint_b = Color(0.6, 0.35, 0.95)
			glow = 1.2
		&"crystal":
			tint_a = biome.glow_color.lerp(Color.WHITE, 0.3)
			tint_b = biome.glow_color
			glow = 3.0
			m.set_shader_parameter(&"metallic", 0.3)
			m.set_shader_parameter(&"facet", 1.0)
			m.set_shader_parameter(&"bump", 0.0)
		&"mushroom":
			tint_a = Color(0.7, 0.75, 0.8)
			tint_b = Color(0.6, 0.65, 0.9)
			glow = 2.5
		&"spine":
			tint_a = Color(0.85, 0.82, 0.72)
			tint_b = Color(0.7, 0.68, 0.62)
		&"tubeworm":
			tint_a = Color(1, 1, 1)
			tint_b = Color(0.9, 0.85, 0.8)
			glow = 1.4
			m.set_shader_parameter(&"glow_color", Color(1.0, 0.25, 0.2))
		&"chimney":
			tint_a = Color(1.0, 0.95, 0.9)
			tint_b = Color(0.8, 0.75, 0.72)
			glow = 3.0
			m.set_shader_parameter(&"glow_color", Color(1.0, 0.45, 0.1))
	m.set_shader_parameter(&"tint_a", tint_a)
	m.set_shader_parameter(&"tint_b", tint_b)
	m.set_shader_parameter(&"glow_strength", glow)
	m.set_shader_parameter(&"glow_pulse", 0.3 if glow > 0.0 else 0.0)
	_materials[key] = m
	return m


# --- Meshes ------------------------------------------------------------------

## The meshes for [param id], a few variants of it (see [PropModels]).
static func variants(id: StringName) -> Array:
	if not _meshes.has(id):
		_meshes[id] = PropModels.variants(id)
	return _meshes[id]


## Loose rock that matches the cave walls of [param biome].
static func rock_material(biome: BiomeDef) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ROCK_SHADER
	m.set_shader_parameter(&"rock_albedo", TerrainRenderer.ROCK_ALBEDO)
	m.set_shader_parameter(&"rock_rough", TerrainRenderer.ROCK_ROUGH)
	m.set_shader_parameter(&"tint_a", biome.rock_tint)
	m.set_shader_parameter(&"tint_b", biome.rock_tint_deep)
	m.set_shader_parameter(&"sediment_tint", biome.sediment_tint)
	return m
