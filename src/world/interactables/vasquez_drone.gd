class_name VasquezDrone
extends Entity
## The work drone T. Vasquez took out to cut a path to the escape lock, the
## night the Choir sang his tunnel shut (log_09). It lies in the last Hadal
## Trench zone, sealed into a wall behind the playfield: smooth rock has
## flowed over its tail and cockpit like wax, and only the nose and the cutter
## arm still reach out. One work lamp still flickers out over the tunnel, its
## status lamp blinks and its transponder chirps.
## Coming alongside plays its flight recorder (a log outside the Meridian
## set) and drains what charge is left in its cells into the sub.

## The zone it was lost in: the last one above the hadal floor.
const ZONE := BiomeLibrary.TOTAL_ZONES - 2
## How far behind the play plane the drone sits.
const DEPTH := -2.0
const SCALE := 1.4
const SURVEY_RANGE := 7.0
const SURVEY_RESEARCH := 8
const CELL_CHARGE := 30.0
const BLINK_PERIOD := 1.6
const CHIRP_PERIOD := 6.0
## The transponder only chirps while the sub is this close.
const HEARING := 55.0
const LOG_ID := &"log_drone"
const FOAM := Color(0.8, 0.56, 0.12)
const FRAME := Color(0.2, 0.21, 0.22)
const STEEL := Color(0.5, 0.5, 0.48)
const GLASS := Color(0.03, 0.04, 0.05)
const LAMP := Color(1.0, 0.18, 0.1)
const WORK_LIGHT := Color(1.0, 0.86, 0.6)

## Where the wall surface is, on the gameplay plane, and which way it faces.
var wall := Vector2.ZERO
var normal := Vector2.RIGHT
var surveyed := false
var _t := 0.0
var _chirp_at := 1.0
var _lamp_mat: StandardMaterial3D
var _light: OmniLight3D
var _mat: ShaderMaterial
var _work: SpotLight3D
var _beam_mat: ShaderMaterial
var _work_energy := 1.0


## Picks a stretch of wall with open water in front, away from the zone's
## entrance, exit and [param avoid], and seals the drone into it; returns it,
## or null if the zone has no such wall.
static func place(level: Level, rng: RandomNumberGenerator, avoid: PackedVector2Array) -> VasquezDrone:
	var layout := level.layout
	var anchors := layout.anchors.duplicate()
	for i in range(anchors.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp: LevelLayout.Anchor = anchors[i]
		anchors[i] = anchors[j]
		anchors[j] = tmp
	for a: LevelLayout.Anchor in anchors:
		if absf(a.normal.x) < 0.75 or a.pos.distance_to(layout.start) < 30.0 or a.pos.distance_to(layout.exit) < 20.0:
			continue
		var water := a.pos + a.normal * 3.0
		if not layout.is_reachable(water) or level.field.sample(a.pos + a.normal * 2.0) < 1.0:
			continue
		if not _clear_of(water, avoid, 12.0):
			continue
		var drone := VasquezDrone.new()
		drone.wall = a.pos
		drone.normal = a.normal
		drone.pos = a.pos + a.normal * 1.8
		level.add_entity(drone)
		return drone
	return null


static func _clear_of(p: Vector2, points: PackedVector2Array, dist: float) -> bool:
	for q in points:
		if q.distance_squared_to(p) < dist * dist:
			return false
	return true


func setup() -> void:
	radius = 0.0
	active_radius = 90.0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(wall)
	var facing := 1.0 if normal.x >= 0.0 else -1.0
	# Local +X points out of the wall; for walls that face left the meshes
	# are mirrored so the arm and markings stay on the near side.
	var rig := Node3D.new()
	rig.top_level = true
	add_child(rig)
	var base := wall + normal * PropScatter.surface_offset(DEPTH)
	rig.position = Vector3(base.x, base.y, DEPTH)
	rig.rotation.z = facing * (atan2(normal.y, absf(normal.x)) + rng.randf_range(-0.12, 0.22))
	rig.scale = Vector3.ONE * SCALE
	var model := Node3D.new()
	model.rotation.x = rng.randf_range(-0.15, 0.1)
	rig.add_child(model)
	var hull := MeshInstance3D.new()
	hull.mesh = _facing(_build_drone(), facing)
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://src/fx/shaders/station.gdshader")
	_mat.set_shader_parameter(&"sediment_tint", level.biome.sediment_tint)
	_mat.set_shader_parameter(&"seams", 0.0)
	_mat.set_shader_parameter(&"metal", 0.25)
	_mat.set_shader_parameter(&"window_color", WORK_LIGHT)
	hull.material_override = _mat
	model.add_child(hull)
	# The rock that grew over it, mapped like the cave walls.
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _facing(_build_rock(rng), facing)
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D.IDENTITY)
	mm.set_instance_custom_data(0, Color(0.0, 0.45, 0.95, 0.0))
	var rock := MultiMeshInstance3D.new()
	rock.multimesh = mm
	rock.material_override = PropScatter.rock_material(level.biome)
	model.add_child(rock)
	var lamp := MeshInstance3D.new()
	lamp.mesh = MeshKit.sphere(0.07, 8, 4)
	_lamp_mat = MeshKit.emissive_material(LAMP, 6.0)
	lamp.material_override = _lamp_mat
	lamp.position = Vector3(facing * 0.95, 0.72, 0.42)
	model.add_child(lamp)
	var plate := Label3D.new()
	plate.text = "MD-02"
	plate.font = UiTheme.TITLE_FONT_FILE
	plate.font_size = 48
	plate.outline_size = 0
	plate.pixel_size = 0.006
	plate.modulate = Color(0.1, 0.08, 0.05, 0.85)
	plate.shaded = true
	plate.position = Vector3(facing * 0.55, 0.42, 0.59)
	model.add_child(plate)
	_light = OmniLight3D.new()
	_light.light_color = LAMP
	_light.omni_range = 6.0
	_light.light_energy = 0.0
	_light.position = Vector3(facing * 1.0, 0.9, 1.2)
	rig.add_child(_light)
	# The near work lamp, still running on the last of the cells.
	_work = SpotLight3D.new()
	_work.light_color = WORK_LIGHT
	_work.spot_range = 13.0
	_work.spot_angle = 24.0
	_work.spot_attenuation = 0.8
	_work.light_volumetric_fog_energy = 2.5
	_work.position = Vector3(facing * 1.4, 0.22, 0.42)
	_work.rotation = Vector3(0.0, -facing * PI * 0.5, 0.0)
	_work.rotate_object_local(Vector3.RIGHT, -0.12)
	rig.add_child(_work)
	# Its cone in the water, drawn like the sub's lamp beam.
	var length := 8.0
	var cone := CylinderMesh.new()
	cone.top_radius = 0.1
	cone.bottom_radius = tan(deg_to_rad(_work.spot_angle * 0.8)) * length
	cone.height = length
	cone.radial_segments = 16
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	var beam := MeshInstance3D.new()
	beam.mesh = cone
	_beam_mat = ShaderMaterial.new()
	_beam_mat.shader = preload("res://src/fx/shaders/lamp_beam.gdshader")
	_beam_mat.set_shader_parameter(&"noise_tex", TerrainRenderer.detail_noise())
	_beam_mat.set_shader_parameter(&"beam_color", Color(WORK_LIGHT, 1.0))
	_beam_mat.set_shader_parameter(&"beam_length", length)
	_beam_mat.set_shader_parameter(&"glass_radius", cone.top_radius)
	beam.material_override = _beam_mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.0, -length * 0.5))
	_work.add_child(beam)


func tick(delta: float) -> void:
	_t += delta
	var sub := level.player
	if surveyed:
		# Once the recorder has played and the cells are drained, the lamps go out.
		_lamp_mat.emission_energy_multiplier = move_toward(_lamp_mat.emission_energy_multiplier, 0.0, delta * 2.0)
		_light.light_energy = move_toward(_light.light_energy, 0.0, delta * 0.5)
		_work_energy = move_toward(_work_energy, 0.0, delta * 0.35)
		_set_work_light(_work_energy * (0.8 + 0.2 * sin(_t * 31.0)))
		return
	# The work lamp gutters, and every few seconds nearly dies.
	var flicker := 0.85 + 0.15 * sin(_t * 23.0) * sin(_t * 7.3)
	if fmod(_t, 5.3) < 0.3 or fmod(_t, 8.9) < 0.12:
		flicker = 0.12
	_set_work_light(flicker)
	var lit := fmod(_t, BLINK_PERIOD) < 0.2
	_lamp_mat.emission_energy_multiplier = 6.0 if lit else 0.25
	_light.light_energy = 1.4 if lit else 0.0
	if _t >= _chirp_at:
		_chirp_at = _t + CHIRP_PERIOD
		if sub and sub.pos.distance_to(pos) < HEARING:
			Audio.play_at(&"beacon_ping", pos, -12.0, 0.02, 1.45)
	if sub and sub.alive and sub.pos.distance_to(pos) < SURVEY_RANGE:
		survey(sub)


## Plays the flight recorder and drains the drone's cells into [param sub].
func survey(sub: Submarine) -> void:
	if surveyed:
		return
	surveyed = true
	Wonders.witness("drone")
	_lamp_mat.emission_energy_multiplier = 6.0
	_light.light_energy = 1.4
	var charge := minf(CELL_CHARGE, maxf(sub.stats.max_battery - sub.run.battery, 0.0))
	sub.run.battery += charge
	sub.run.research += SURVEY_RESEARCH
	sub.show_gain(SURVEY_RESEARCH, " research", UiTheme.ACCENT)
	Events.banner.emit("MD-02", "Vasquez's drone. The rock has grown over its cockpit.")
	if charge >= 1.0:
		Events.toast.emit("Drained the drone's cells: +%d battery, +%d research" % [roundi(charge), SURVEY_RESEARCH],
			UiTheme.ACCENT)
	else:
		Events.toast.emit("Drone survey: +%d research" % SURVEY_RESEARCH, UiTheme.ACCENT)
	if not Game.meta.logs_found.has(String(LOG_ID)):
		Game.meta.logs_found.append(String(LOG_ID))
	Audio.play(&"log_found", -2.0)
	Events.log_found.emit(LOG_ID)


func _set_work_light(k: float) -> void:
	_work.light_energy = 2.2 * k
	_beam_mat.set_shader_parameter(&"intensity", 0.04 * k)
	_mat.set_shader_parameter(&"failing_energy", 3.0 * k)


## [param mesh] as is for [param facing] +1, or mirrored left to right for -1
## (positions and normals flipped, triangles rewound so they still face out;
## a negative node scale would turn the double-sided shading inside out).
static func _facing(mesh: ArrayMesh, facing: float) -> ArrayMesh:
	if facing > 0.0:
		return mesh
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in verts.size():
			verts[i].x = -verts[i].x
		for i in normals.size():
			normals[i].x = -normals[i].x
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TANGENT] = null
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		if indices is PackedInt32Array and not (indices as PackedInt32Array).is_empty():
			var idx: PackedInt32Array = indices
			for i in range(0, idx.size() - 2, 3):
				var tmp := idx[i + 1]
				idx[i + 1] = idx[i + 2]
				idx[i + 2] = tmp
			arrays[Mesh.ARRAY_INDEX] = idx
		else:
			for key in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV]:
				arrays[key] = _rewound(arrays[key])
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


## Copy of a per-vertex array with the 2nd and 3rd vertex of each triangle swapped.
static func _rewound(values: Variant) -> Variant:
	if values == null:
		return null
	var out: Variant = values.duplicate()
	for i in range(0, out.size() - 2, 3):
		out[i + 1] = values[i + 2]
		out[i + 2] = values[i + 1]
	return out


## Uniformly coloured copy of [param mesh] at [param xf], for the station
## shader, as a part for [method MeshKit.merge]; [param window] marks a lit
## lens (0.5 = the failing work lamp).
static func _part(mesh: Mesh, xf: Transform3D, color: Color, window := 0.0) -> Array:
	var c := Color(color, window)
	return [MeshKit.painted(MeshKit.transformed(mesh, xf), func(_v: Vector3) -> Color: return c)]


## Cylinder of radius [param r] from [param a] to [param b].
static func _rod(a: Vector3, b: Vector3, r: float, color: Color) -> Array:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = a.distance_to(b)
	m.radial_segments = 8
	m.rings = 1
	var y := (b - a).normalized()
	var x := y.cross(Vector3.BACK)
	if x.length_squared() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	return _part(m, Transform3D(Basis(x, y, x.cross(y).normalized()), (a + b) * 0.5), color)


## A small work submersible, nose along +X: buoyancy block on top, an open
## frame with the pilot's sphere at the front, dead lamps, thruster ducts and
## a manipulator arm ending in a rock saw.
static func _build_drone() -> ArrayMesh:
	var parts: Array = []
	var c := 0.15
	var foam := BoxMesh.new()
	foam.size = Vector3(2.1, 0.5, 1.15)
	parts.append(_part(foam, Transform3D(Basis(), Vector3(c, 0.42, 0.0)), FOAM))
	var sphere := MeshKit.sphere(0.45, 16, 8)
	parts.append(_part(sphere, Transform3D(Basis(), Vector3(c + 0.75, -0.08, 0.0)), GLASS))
	var bezel := TorusMesh.new()
	bezel.inner_radius = 0.4
	bezel.outer_radius = 0.5
	bezel.rings = 18
	bezel.ring_segments = 6
	parts.append(_part(bezel, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(c + 0.92, -0.08, 0.0)), FRAME))
	# Open frame: corner posts, bottom rails and skids.
	for sx: float in [-0.85, 0.85]:
		for sz: float in [-0.52, 0.52]:
			parts.append(_rod(Vector3(c + sx, -0.55, sz), Vector3(c + sx, 0.2, sz), 0.05, FRAME))
	for sz: float in [-0.52, 0.52]:
		parts.append(_rod(Vector3(c - 0.95, -0.55, sz), Vector3(c + 1.05, -0.55, sz), 0.05, FRAME))
		parts.append(_rod(Vector3(c - 0.7, -0.72, sz), Vector3(c + 0.9, -0.72, sz), 0.06, STEEL))
		parts.append(_rod(Vector3(c + 0.9, -0.72, sz), Vector3(c + 1.12, -0.55, sz), 0.06, STEEL))
	# Lamp cans either side of the sphere; the near one still gutters.
	var can := CylinderMesh.new()
	can.top_radius = 0.1
	can.bottom_radius = 0.12
	can.height = 0.24
	can.radial_segments = 10
	var lens := MeshKit.sphere(0.09, 8, 4)
	for sz: float in [-0.42, 0.42]:
		parts.append(_part(can, Transform3D(Basis(Vector3.BACK, -PI * 0.5), Vector3(c + 1.08, 0.22, sz)), STEEL))
		parts.append(_part(lens, Transform3D(Basis().scaled(Vector3(0.4, 1.0, 1.0)), Vector3(c + 1.2, 0.22, sz)),
			GLASS, 0.5 if sz > 0.0 else 0.0))
	# Vertical thruster ducts through the buoyancy block.
	var duct := TorusMesh.new()
	duct.inner_radius = 0.16
	duct.outer_radius = 0.24
	duct.rings = 14
	duct.ring_segments = 6
	for sx: float in [-0.5, 0.45]:
		parts.append(_part(duct, Transform3D(Basis(), Vector3(c + sx, 0.68, 0.0)), FRAME))
	# Manipulator arm, reaching out from under the sphere, and its rock saw.
	var shoulder := Vector3(c + 0.85, -0.42, 0.45)
	var elbow := Vector3(c + 1.55, -0.08, 0.62)
	var wrist := Vector3(c + 2.1, -0.5, 0.66)
	var joint := MeshKit.sphere(0.1, 8, 4)
	parts.append(_rod(shoulder, elbow, 0.07, STEEL))
	parts.append(_rod(elbow, wrist, 0.06, STEEL))
	for p in [shoulder, elbow, wrist]:
		parts.append(_part(joint, Transform3D(Basis(), p), FRAME))
	var hub := wrist + Vector3(0.14, -0.06, 0.08)
	var blade := CylinderMesh.new()
	blade.top_radius = 0.34
	blade.bottom_radius = 0.34
	blade.height = 0.035
	blade.radial_segments = 20
	blade.rings = 1
	parts.append(_part(blade, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), hub), STEEL))
	var tooth := BoxMesh.new()
	tooth.size = Vector3(0.07, 0.07, 0.04)
	for k in 14:
		var a := TAU * k / 14.0
		var at := hub + Vector3(cos(a), sin(a), 0.0) * 0.36
		parts.append(_part(tooth, Transform3D(Basis(Vector3.BACK, a + 0.6), at), FRAME))
	parts.append(_part(joint, Transform3D(Basis().scaled(Vector3(0.8, 0.8, 1.4)), hub), FRAME))
	return MeshKit.merge(parts)


## The rock that flowed over the drone: a mass where it meets the wall, the
## tail and cockpit swallowed, and a tongue creeping forward over the top.
static func _build_rock(rng: RandomNumberGenerator) -> ArrayMesh:
	var blob := MeshKit.ball(1.0, 0.0, 16, 10)
	var parts: Array = []
	for i in 6:
		var r := rng.randf_range(1.1, 1.5)
		parts.append([blob, Transform3D(Basis().scaled(Vector3(r, r * 1.1, r)),
			Vector3(rng.randf_range(-2.1, -1.4), rng.randf_range(-1.2, 1.4), rng.randf_range(-1.0, 0.3)))])
	for i in 9:
		var r := rng.randf_range(0.45, 0.85)
		parts.append([blob, Transform3D(Basis().scaled(Vector3(r, r * 0.9, r)),
			Vector3(rng.randf_range(-1.2, -0.2), rng.randf_range(-0.7, 1.0), rng.randf_range(-0.6, 0.55)))])
	for k in 3:
		parts.append([blob, Transform3D(Basis().scaled(Vector3(0.75 - k * 0.15, 0.3 - k * 0.05, 0.7 - k * 0.1)),
			Vector3(-0.15 + k * 0.38, 0.75 - k * 0.04, rng.randf_range(-0.2, 0.2)))])
	var grain := FastNoiseLite.new()
	grain.frequency = 0.7
	return MeshKit.painted(MeshKit.merge(parts), func(v: Vector3) -> Color:
		var g := 0.85 + grain.get_noise_3dv(v) * 0.15
		return Color(g, g, g, 0.0))
