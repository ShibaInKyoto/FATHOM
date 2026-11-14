class_name VasquezDrone
extends Entity
## The work drone T. Vasquez took out to cut a path to the escape lock, the
## night the Choir sang his tunnel shut (log_09). It lies in the last Hadal
## Trench zone, sealed into a wall behind the playfield (see [DroneModel]):
## the rock has flowed over its tail and cockpit like wax, a smooth sheet
## poured from the wall and shaped over it, and only the nose and the saw arm
## still reach out. One work lamp still flickers out over the tunnel, its
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
const LAMP := Color(1.0, 0.18, 0.1)
const WORK_LIGHT := Color(1.0, 0.86, 0.6)
const DRONE_SHADER := preload("res://src/fx/shaders/drone.gdshader")
const FLOWSTONE_SHADER := preload("res://src/fx/shaders/flowstone.gdshader")
## How far back along the drone (in its own metres from its middle) the
## rock has flowed.
const SWALLOWED_TO := 0.6
## The grid the flowstone is shaped on, in metres.
const FLOW_CELL := 0.06

## Where the wall surface is, on the gameplay plane, and which way it faces.
var wall := Vector2.ZERO
var normal := Vector2.RIGHT
var surveyed := false
var _t := 0.0
var _chirp_at := 1.0
var _status := 0.0
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
		# No boulders or growth over it.
		level.clearings.append(Rect2(drone.pos - Vector2(4.5, 4.5), Vector2(9.0, 9.0)))
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
	# Its far side sunk into the slope of the wall.
	rig.position = Vector3(base.x, base.y, TerrainRelief.height(level.field, base) - 0.1)
	rig.rotation.z = facing * (atan2(normal.y, absf(normal.x)) + rng.randf_range(-0.12, 0.22))
	rig.scale = Vector3.ONE * SCALE
	var model := Node3D.new()
	model.rotation.x = rng.randf_range(-0.15, 0.1)
	rig.add_child(model)
	var drone_mesh := _facing(DroneModel.build(), facing)
	var hull := MeshInstance3D.new()
	hull.mesh = drone_mesh
	_mat = ShaderMaterial.new()
	_mat.shader = DRONE_SHADER
	_mat.set_shader_parameter(&"sediment_tint", level.biome.sediment_tint)
	_mat.set_shader_parameter(&"work_light", WORK_LIGHT)
	_mat.set_shader_parameter(&"status_light", LAMP)
	hull.material_override = _mat
	model.add_child(hull)
	model.add_child(_stencil(facing))
	# The rock poured over it, shaped round it in world space.
	var model_xf := Transform3D(Basis.from_euler(rig.rotation) * Basis.from_scale(rig.scale), rig.position) \
		* Transform3D(Basis.from_euler(model.rotation), Vector3.ZERO)
	var flow := MeshInstance3D.new()
	flow.mesh = _flowstone(drone_mesh, model_xf, facing)
	var rock := ShaderMaterial.new()
	rock.shader = FLOWSTONE_SHADER
	rock.set_shader_parameter(&"rock_albedo", TerrainRenderer.ROCK_ALBEDO)
	rock.set_shader_parameter(&"rock_rough", TerrainRenderer.ROCK_ROUGH)
	rock.set_shader_parameter(&"rock_tint", level.biome.rock_tint)
	rock.set_shader_parameter(&"rock_tint_deep", level.biome.rock_tint_deep)
	rock.set_shader_parameter(&"sediment_tint", level.biome.sediment_tint)
	flow.material_override = rock
	flow.top_level = true
	add_child(flow)
	var status := DroneModel.STATUS_LAMP
	_light = OmniLight3D.new()
	_light.light_color = LAMP
	_light.omni_range = 6.0
	_light.light_energy = 0.0
	_light.position = Vector3(facing * status.x, status.y + 0.15, status.z + 0.5)
	model.add_child(_light)
	# The near work lamp, still running on the last of the cells.
	var lamp := DroneModel.NEAR_LAMP
	_work = SpotLight3D.new()
	_work.light_color = WORK_LIGHT
	_work.spot_range = 13.0
	_work.spot_angle = 24.0
	_work.spot_attenuation = 0.8
	_work.light_volumetric_fog_energy = 2.5
	_work.position = Vector3(facing * (lamp.x + 0.02), lamp.y, lamp.z)
	_work.rotation = Vector3(0.0, -facing * PI * 0.5, 0.0)
	_work.rotate_object_local(Vector3.RIGHT, -0.12)
	model.add_child(_work)
	# Its cone in the water, drawn like the sub's lamp beam.
	var length := 8.0
	var cone := CylinderMesh.new()
	cone.top_radius = 0.08
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


## "MD-02" and "MERIDIAN DEEP" stencilled on the near side of the float's
## nose, laid flush on it.
func _stencil(facing: float) -> Node3D:
	var marks := Node3D.new()
	var at := DroneModel.FLOAT_AT
	var face := at.z + DroneModel.FLOAT_HALF.z + 0.004
	for line: Array in [["MD-02", 64, 0.0021, at.y + 0.02], ["MERIDIAN DEEP", 40, 0.00115, at.y - 0.1]]:
		var text := Label3D.new()
		text.text = line[0]
		text.font = UiTheme.TITLE_FONT_FILE
		text.font_size = line[1]
		text.outline_size = 0
		text.pixel_size = line[2]
		text.modulate = Color(0.07, 0.055, 0.04, 0.9)
		text.shaded = true
		text.double_sided = false
		text.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
		text.position = Vector3(facing * 0.93, line[3], face)
		marks.add_child(text)
	return marks


## The rock that flowed over the drone (whose mesh, in world space, is
## [param drone] moved by [param xf]): a sheet shaped on a grid over it,
## rising out of the wall's own surface and over the drone's rear and
## cockpit with a smoothly rounded, dripping lip where it stopped, sinking
## back under the wall's surface everywhere else.
func _flowstone(drone: ArrayMesh, xf: Transform3D, facing: float) -> ArrayMesh:
	var arrays := drone.surface_get_arrays(0)
	var src: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var pts := PackedVector3Array()
	pts.resize(src.size())
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in src.size():
		pts[i] = xf * src[i]
		lo = lo.min(Vector2(pts[i].x, pts[i].y))
		hi = hi.max(Vector2(pts[i].x, pts[i].y))
	lo -= Vector2.ONE * 1.4
	hi += Vector2.ONE * 1.4
	var cell := FLOW_CELL
	var nx := int((hi.x - lo.x) / cell) + 1
	var ny := int((hi.y - lo.y) / cell) + 1
	# The drone's height towards the camera over each cell.
	var top := PackedFloat32Array()
	top.resize(nx * ny)
	top.fill(-INF)
	for t in range(0, idx.size(), 3):
		var a := pts[idx[t]]
		var b := pts[idx[t + 1]]
		var c := pts[idx[t + 2]]
		# Each corner marks its own cell (for triangles smaller than a cell)...
		for v: Vector3 in [a, b, c]:
			var kx := clampi(roundi((v.x - lo.x) / cell), 0, nx - 1)
			var ky := clampi(roundi((v.y - lo.y) / cell), 0, ny - 1)
			top[ky * nx + kx] = maxf(top[ky * nx + kx], v.z)
		# ...and every cell centre the triangle covers takes its height there.
		var x0 := maxi(ceili((minf(a.x, minf(b.x, c.x)) - lo.x) / cell), 0)
		var x1 := mini(floori((maxf(a.x, maxf(b.x, c.x)) - lo.x) / cell), nx - 1)
		var y0 := maxi(ceili((minf(a.y, minf(b.y, c.y)) - lo.y) / cell), 0)
		var y1 := mini(floori((maxf(a.y, maxf(b.y, c.y)) - lo.y) / cell), ny - 1)
		var den := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
		if absf(den) < 1e-9:
			continue
		for iy in range(y0, y1 + 1):
			for ix in range(x0, x1 + 1):
				var px := lo.x + ix * cell
				var py := lo.y + iy * cell
				var wa := ((b.y - c.y) * (px - c.x) + (c.x - b.x) * (py - c.y)) / den
				var wb := ((c.y - a.y) * (px - c.x) + (a.x - c.x) * (py - c.y)) / den
				var wc := 1.0 - wa - wb
				if wa < -0.001 or wb < -0.001 or wc < -0.001:
					continue
				var k := iy * nx + ix
				top[k] = maxf(top[k], a.z * wa + b.z * wb + c.z * wc)
	# The wall's surface, and the drone's way out of it.
	var origin := Vector2(xf.origin.x, xf.origin.y)
	var scale := xf.basis.x.length()
	var nose3 := (xf.basis * Vector3(facing, 0.0, 0.0)).normalized()
	var up3 := (xf.basis * Vector3(0.0, 1.0, 0.0)).normalized()
	var nose := Vector2(nose3.x, nose3.y).normalized()
	var up := Vector2(up3.x, up3.y).normalized()
	var ground := PackedFloat32Array()
	var excess := PackedFloat32Array()
	var reach := PackedFloat32Array()
	ground.resize(nx * ny)
	excess.resize(nx * ny)
	reach.resize(nx * ny)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(wall) + 5
	var drip_phase := rng.randf() * TAU
	for iy in ny:
		for ix in nx:
			var k := iy * nx + ix
			var p := lo + Vector2(ix, iy) * cell
			ground[k] = TerrainRelief.height(level.field, p)
			# How far the drone stands out of the wall here, with the rock's
			# own thickness over it.
			excess[k] = maxf(top[k] + 0.07 - ground[k], 0.0)
			# How far it has flowed here: up to its lip, which runs forward in
			# tongues and drips (in the drone's own metres).
			var lx := (p - origin).dot(nose) / scale
			var ly := (p - origin).dot(up) / scale
			var lip := SWALLOWED_TO + 0.1 * sin(ly * 7.0 + drip_phase) + 0.05 * sin(ly * 17.0 + drip_phase * 2.0) \
				+ 0.38 * exp(-pow((ly - 0.62) / 0.1, 2.0)) + 0.22 * exp(-pow((ly + 0.25) / 0.07, 2.0)) \
				+ 0.16 * exp(-pow((ly - 0.2) / 0.05, 2.0))
			var edge := minf(minf(ix, nx - 1 - ix), minf(iy, ny - 1 - iy)) * cell
			reach[k] = (1.0 - smoothstep(lip - 0.12, lip + 0.12, lx)) * smoothstep(0.0, 0.9, edge)
	# Rounded as wax sets: a mound over the drone, widened and blurred so it
	# runs down into the wall all round, never below what it covers; it
	# follows the wall's own surface everywhere else.
	var mound := _blur(_widen(excess, nx, ny, 3), nx, ny, 4.5)
	var z := PackedFloat32Array()
	var wax := PackedFloat32Array()
	z.resize(nx * ny)
	wax.resize(nx * ny)
	for k in nx * ny:
		var r := reach[k]
		# Where it stopped, it set in a rounded bead.
		var bead := 0.06 * sin(clampf(r, 0.0, 1.0) * PI) * smoothstep(0.02, 0.1, excess[k])
		var h := ground[k] + maxf(mound[k], excess[k] - 0.02) + bead
		var w := r * smoothstep(0.015, 0.12, mound[k])
		z[k] = lerpf(ground[k] - 0.1, h, w)
		wax[k] = w
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var index := PackedInt32Array()
	var slot := PackedInt32Array()
	slot.resize(nx * ny)
	slot.fill(-1)
	for iy in ny:
		for ix in nx:
			var k := iy * nx + ix
			var zx := z[iy * nx + mini(ix + 1, nx - 1)] - z[iy * nx + maxi(ix - 1, 0)]
			var zy := z[mini(iy + 1, ny - 1) * nx + ix] - z[maxi(iy - 1, 0) * nx + ix]
			slot[k] = verts.size()
			var p := lo + Vector2(ix, iy) * cell
			verts.append(Vector3(p.x, p.y, z[k]))
			normals.append(Vector3(-zx / (2.0 * cell), -zy / (2.0 * cell), 1.0).normalized())
			colors.append(Color(wax[k], 0.0, 0.0))
	for iy in ny - 1:
		for ix in nx - 1:
			var a := iy * nx + ix
			# Only where it shows above the wall.
			if wax[a] + wax[a + 1] + wax[a + nx] + wax[a + nx + 1] < 0.002:
				continue
			# Clockwise as seen from +Z (Godot's front face; the grid's y runs up).
			index.append_array([slot[a], slot[a + nx], slot[a + 1], slot[a + 1], slot[a + nx], slot[a + nx + 1]])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_COLOR] = colors
	out[Mesh.ARRAY_INDEX] = index
	var mesh := ArrayMesh.new()
	if not index.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return mesh


## [param values] (an [param nx] by [param ny] grid) with each cell raised
## to the highest within [param r] cells.
static func _widen(values: PackedFloat32Array, nx: int, ny: int, r: int) -> PackedFloat32Array:
	var out := values.duplicate()
	for iy in ny:
		for ix in nx:
			var m := values[iy * nx + ix]
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var x := clampi(ix + dx, 0, nx - 1)
					var y := clampi(iy + dy, 0, ny - 1)
					m = maxf(m, values[y * nx + x])
			out[iy * nx + ix] = m
	return out


## [param values] blurred, [param sigma] cells across.
static func _blur(values: PackedFloat32Array, nx: int, ny: int, sigma: float) -> PackedFloat32Array:
	var r := int(ceil(sigma * 2.0))
	var weights := PackedFloat32Array()
	var total := 0.0
	for d in range(-r, r + 1):
		var w := exp(-float(d * d) / (2.0 * sigma * sigma))
		weights.append(w)
		total += w
	var pass1 := PackedFloat32Array()
	pass1.resize(nx * ny)
	for iy in ny:
		for ix in nx:
			var sum := 0.0
			for d in range(-r, r + 1):
				sum += values[iy * nx + clampi(ix + d, 0, nx - 1)] * weights[d + r]
			pass1[iy * nx + ix] = sum / total
	var out := PackedFloat32Array()
	out.resize(nx * ny)
	for iy in ny:
		for ix in nx:
			var sum := 0.0
			for d in range(-r, r + 1):
				sum += pass1[clampi(iy + d, 0, ny - 1) * nx + ix] * weights[d + r]
			out[iy * nx + ix] = sum / total
	return out


func tick(delta: float) -> void:
	_t += delta
	var sub := level.player
	if surveyed:
		# Once the recorder has played and the cells are drained, the lamps go out.
		_status = move_toward(_status, 0.0, delta * 2.0)
		_mat.set_shader_parameter(&"status", _status)
		_mat.set_shader_parameter(&"console", _work_energy)
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
	_status = 1.0 if lit else 0.0
	_mat.set_shader_parameter(&"status", _status)
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
	_status = 1.0
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
	_mat.set_shader_parameter(&"work", k)


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
