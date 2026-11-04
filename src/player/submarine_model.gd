class_name SubmarineModel
extends Node3D
## Procedurally assembled submarine. Each hangar frame has its own silhouette:
## the Lantern research sub, the Mako racer, the armored Bathysphere and the
## Whisper stealth drone. The nose points along local +X.

const SURFACE := preload("res://src/player/sub_surface.gdshader")
## Frames rebuilt in full detail, with painted maps and wear.
const DETAILED: Array[StringName] = [&"lantern", &"mako", &"bathysphere"]

static var _plating: ImageTexture
## Finished models kept by frame after their first build: [slot, mesh,
## transform, strobe?] for each part, [transform, parts, main?] for each
## propeller and where the cockpit light sits. Later builds only repaint.
static var _kept: Dictionary[StringName, Dictionary] = {}
var propeller: Node3D
var strobe: MeshInstance3D
var cockpit_material: StandardMaterial3D
var hull_material: ShaderMaterial

var _dark: StandardMaterial3D
var _steel: StandardMaterial3D
var _skin: SubSkins.Livery
var _frame := &""
## Every painted material, so darkening and the glow's pulse reach them all.
var _paints: Array[ShaderMaterial] = []
## Props besides the main one, each turning on its own axis.
var _props: Array[Node3D] = []
var _cockpit_light: OmniLight3D
var _prop_speed := 0.0
var _prop_angle := 0.0
var _strobe_t := 0.0
## Glowing seams that breathe (a "pulse" finish), or false.
var _pulse := false


## Builds the frame's model in [param skin] (its factory paint if null).
func build(frame_id: StringName, skin: SubSkins.Livery = null) -> void:
	_frame = frame_id
	_skin = skin if skin else SubSkins.factory(frame_id)
	_make_materials()
	propeller = Node3D.new()
	add_child(propeller)
	match frame_id:
		&"mako":
			MakoBuild.build(self)
		&"bathysphere":
			BathysphereBuild.build(self)
		&"whisper":
			_build_whisper()
		_:
			LanternBuild.build(self)
	_merge_static()


func animate(delta: float, thrust: float) -> void:
	_prop_speed = lerpf(_prop_speed, 4.0 + thrust * 30.0, 1.0 - exp(-4.0 * delta))
	propeller.rotate_object_local(Vector3.RIGHT, _prop_speed * delta)
	for p in _props:
		p.rotate_object_local(Vector3.RIGHT, _prop_speed * 0.8 * delta)
	_strobe_t += delta
	if strobe:
		strobe.visible = fmod(_strobe_t, 1.6) < 0.08
	if _pulse:
		var energy := 0.4 + 1.8 * pow(0.5 + 0.5 * sin(_strobe_t * 1.8), 2.0)
		for mat in _paints:
			mat.set_shader_parameter(&"glow_energy", energy)


func set_cockpit_glow(energy: float) -> void:
	cockpit_material.emission_energy_multiplier = energy
	if _cockpit_light:
		_cockpit_light.light_energy = 0.45 * energy


## Darkens the livery, glow and all, and dims the lamps (for a wreck).
func darken_hull(amount: float) -> void:
	for mat in _paints:
		mat.set_shader_parameter(&"darken", amount)
	_pulse = false
	var dimmed := {}
	for child in get_children():
		var mi := child as MeshInstance3D
		var mat := mi.material_override as StandardMaterial3D if mi else null
		if mat and mat.emission_enabled and mat != cockpit_material and not dimmed.has(mat):
			dimmed[mat] = true
			mat.emission_energy_multiplier *= 1.0 - amount


# --- Building blocks (used by the frame builders) ---------------------------------

## A material in the livery. With [param maps] it takes the frame's
## paint-shop maps (seams, grime, lettering) on its UVs; the first such
## material becomes [member hull_material].
func paint_material(maps: bool) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SURFACE
	var plain := _skin.pattern == &"plates" and _skin.finish == &""
	var detailed := DETAILED.has(_frame)
	mat.set_shader_parameter(&"metallic", 0.12)
	mat.set_shader_parameter(&"roughness", 0.4)
	mat.set_shader_parameter(&"coat", 0.6)
	mat.set_shader_parameter(&"vertex_wear", detailed)
	mat.set_shader_parameter(&"use_maps", maps)
	if plain or (detailed and _skin.pattern == &"plates"):
		mat.set_shader_parameter(&"paint", _skin.color)
		if not detailed:
			# The older frames wear their plating as a pattern.
			mat.set_shader_parameter(&"use_pattern", true)
			mat.set_shader_parameter(&"pattern_tex", _plating_texture())
	else:
		mat.set_shader_parameter(&"paint", Color.WHITE)
		mat.set_shader_parameter(&"use_pattern", true)
		mat.set_shader_parameter(&"pattern_tex", SubSkins.textures(_skin)[0])
	if not plain:
		var tex := SubSkins.textures(_skin)
		match _skin.finish:
			&"chrome":
				# Mostly mirror, but with nothing down here to mirror it keeps
				# some of its color, and its edges catch the light.
				mat.set_shader_parameter(&"metallic", 0.75)
				mat.set_shader_parameter(&"roughness", 0.16)
				mat.set_shader_parameter(&"rim", 0.7)
				mat.set_shader_parameter(&"coat", 0.0)
			&"glow", &"pulse":
				mat.set_shader_parameter(&"glow_tex", tex[1])
				mat.set_shader_parameter(&"glow_energy", 1.6)
				_pulse = _skin.finish == &"pulse"
			&"sheen":
				mat.set_shader_parameter(&"roughness", 0.25)
				mat.next_pass = SubSkins.sheen()
	_paints.append(mat)
	if maps and hull_material == null:
		hull_material = mat
	return mat


## Bare or painted metal, rubber or plastic. With [param worn], edges wear
## through to bare steel where the mesh marks them.
func metal_material(color: Color, metallic: float, roughness: float, worn: bool) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SURFACE
	mat.set_shader_parameter(&"paint", color)
	mat.set_shader_parameter(&"metallic", metallic)
	mat.set_shader_parameter(&"roughness", roughness)
	mat.set_shader_parameter(&"rim", 0.15)
	mat.set_shader_parameter(&"vertex_wear", worn)
	return mat


## Clear acrylic: barely tinted, glossy, brighter at grazing angles.
func glass_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.7, 0.88, 0.95, 0.07)
	mat.metallic = 0.0
	mat.roughness = 0.03
	mat.metallic_specular = 0.9
	mat.rim_enabled = true
	mat.rim = 0.45
	mat.rim_tint = 0.3
	return mat


## Adds [param mesh] at [param pos], turned by [param rot_deg] (degrees), to
## the model or to [param parent].
func place(mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot_deg := Vector3.ZERO,
		parent: Node3D = null) -> MeshInstance3D:
	var mi := _part(mesh, mat, pos, rot_deg)
	if parent:
		remove_child(mi)
		parent.add_child(mi)
	return mi


func place_xform(mesh: Mesh, mat: Material, xform: Transform3D, parent: Node3D = null) -> MeshInstance3D:
	var mi := place(mesh, mat, Vector3.ZERO, Vector3.ZERO, parent)
	mi.transform = xform
	return mi


## Rebuilds this frame from its kept parts in [param mats] (slot name to
## material). False if none are kept yet.
func restore(mats: Dictionary) -> bool:
	if not _kept.has(_frame):
		return false
	var kept: Dictionary = _kept[_frame]
	for p: Array in kept.parts:
		var mi := place_xform(p[1], mats[p[0]], p[2])
		if p[3]:
			strobe = mi
	for p: Array in kept.props:
		var pivot: Node3D = propeller if p[2] else add_prop(Vector3.ZERO, Vector3.ZERO)
		pivot.transform = p[0]
		for part: Array in p[1]:
			place_xform(part[1], mats[part[0]], part[2], pivot)
	if kept.light != null:
		add_cockpit_light(kept.light, kept.light_color)
	return true


## Merges the freshly built parts and keeps them, by the slot names in
## [param mats], for the next build of this frame.
func remember(mats: Dictionary) -> void:
	_merge_static()
	var slot_of := {}
	for k: String in mats:
		slot_of[mats[k]] = k
	var parts: Array = []
	for child in get_children():
		var mi := child as MeshInstance3D
		if mi:
			parts.append([slot_of[mi.material_override], mi.mesh, mi.transform, mi == strobe])
	var props: Array = []
	var pivots: Array[Node3D] = [propeller]
	pivots.append_array(_props)
	for pivot in pivots:
		var blades: Array = []
		for c in pivot.get_children():
			var mi := c as MeshInstance3D
			blades.append([slot_of[mi.material_override], mi.mesh, mi.transform])
		props.append([pivot.transform, blades, pivot == propeller])
	_kept[_frame] = {"parts": parts, "props": props,
		"light": _cockpit_light.position if _cockpit_light else null,
		"light_color": _cockpit_light.light_color if _cockpit_light else Color.WHITE}


## A second propeller hub at [param at], turning about its own X axis (set by
## [param rot_deg]); put its blades under it.
func add_prop(at: Vector3, rot_deg: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = at
	pivot.rotation_degrees = rot_deg
	add_child(pivot)
	_props.append(pivot)
	return pivot


## A soft light inside the cockpit that follows its glow.
func add_cockpit_light(at: Vector3, color := Color(0.55, 0.85, 1.0)) -> void:
	_cockpit_light = OmniLight3D.new()
	_cockpit_light.position = at
	_cockpit_light.light_color = color
	_cockpit_light.omni_range = 0.9
	_cockpit_light.light_energy = 0.45 * cockpit_material.emission_energy_multiplier
	_cockpit_light.shadow_enabled = false
	add_child(_cockpit_light)


# --- Materials ---------------------------------------------------------------------

func _make_materials() -> void:
	if not DETAILED.has(_frame):
		hull_material = paint_material(false)
	_dark = StandardMaterial3D.new()
	_dark.albedo_color = Color(0.12, 0.13, 0.15)
	_dark.metallic = 0.7
	_dark.roughness = 0.35

	_steel = StandardMaterial3D.new()
	_steel.albedo_color = Color(0.55, 0.58, 0.6)
	_steel.metallic = 0.85
	_steel.roughness = 0.28

	cockpit_material = StandardMaterial3D.new()
	cockpit_material.albedo_color = Color(0.05, 0.2, 0.28)
	cockpit_material.metallic = 0.2
	cockpit_material.roughness = 0.05
	cockpit_material.emission_enabled = true
	cockpit_material.emission = Color(0.2, 0.85, 1.0)
	cockpit_material.emission_energy_multiplier = 0.9
	cockpit_material.rim_enabled = true
	cockpit_material.rim = 0.6


## Riveted hull plating, generated once: light panels with dark seams.
static func _plating_texture() -> ImageTexture:
	if _plating == null:
		var size := 256
		var img := Image.create(size, size, true, Image.FORMAT_RGB8)
		img.fill(Color(1, 1, 1))
		for y in size:
			for x in size:
				var row := int(y / 64.0)
				var seam_y := y % 64 < 2
				var seam_x := (x + row * 37) % 96 < 2
				var c := 1.0
				if seam_y or seam_x:
					c = 0.55
				else:
					var rx := (x + row * 37) % 96
					var ry := y % 64
					if (rx == 8 or rx == 88) and ry % 12 == 6:
						c = 0.7
					c *= 0.94 + 0.06 * sin(float(x) * 0.05 + float(y) * 0.11)
				img.set_pixel(x, y, Color(c, c, c))
		img.generate_mipmaps()
		_plating = ImageTexture.create_from_image(img)
	return _plating


# --- Frames ------------------------------------------------------------------------

func _build_whisper() -> void:
	# A flattened, faceted stealth drone: smoked glass and a glowing sensor
	# strip instead of a canopy, seams of light, a faceted dorsal blade and a
	# hexagonal pump-jet.
	var hull := MeshKit.lathe(PackedVector2Array([
			Vector2(0.0, 0.25), Vector2(0.2, 0.55), Vector2(0.6, 0.6), Vector2(0.9, 0.35), Vector2(1.0, 0.05)]),
		3.8, 6, 10, 0.45, 1.25)
	_part(hull, hull_material, Vector3(0, 0, 0), Vector3.ZERO)
	var seam := MeshKit.emissive_material(Color(0.6, 0.4, 1.0), 3.0)
	_part(_box(Vector3(3.0, 0.03, 1.35)), seam, Vector3(-0.1, 0.0, 0.0), Vector3.ZERO)
	var glass := MeshKit.lathe(PackedVector2Array([Vector2(0, 0.02), Vector2(0.45, 0.22), Vector2(1, 0.02)]), 1.2, 6,
			6, 0.5, 1.0)
	_part(glass, _dark, Vector3(0.95, 0.2, 0), Vector3.ZERO)
	_part(_box(Vector3(0.5, 0.03, 0.08)), cockpit_material, Vector3(1.2, 0.27, 0), Vector3(0, 0, -8))
	var blade := MeshKit.fin(PackedVector2Array([Vector2(0.35, 0), Vector2(-0.55, 0), Vector2(-0.75, 0.5),
		Vector2(-0.45, 0.42)]), 0.05)
	_part(blade, hull_material, Vector3(-0.85, 0.24, 0), Vector3.ZERO)
	var vane := MeshKit.fin(PackedVector2Array([Vector2(0.2, 0), Vector2(-0.5, 0), Vector2(-0.7, 0.55), Vector2(-0.3,
			0.5)]), 0.04)
	_part(vane, hull_material, Vector3(-1.2, 0.05, 0.6), Vector3(80, 0, 0))
	_part(vane, hull_material, Vector3(-1.2, 0.05, -0.6), Vector3(-80, 0, 0))
	_part(_cylinder(0.32, 0.36, 0.5, 6), _dark, Vector3(-1.95, 0, 0), Vector3(0, 0, -90))
	var shroud := _ring(0.36, 0.05, _dark, Vector3(-2.2, 0, 0), Vector3(0, 0, 90))
	(shroud.mesh as TorusMesh).rings = 6
	_add_propeller(Vector3(-2.1, 0, 0), 6, 0.26)
	strobe = _part(MeshKit.sphere(0.04), MeshKit.emissive_material(Color(0.6, 0.4, 1.0), 4.0), Vector3(-1.45, 0.72, 0),
			Vector3.ZERO)
	_part(_cylinder(0.1, 0.14, 0.25, 8), _dark, Vector3(1.4, -0.22, 0.0), Vector3(0, 0, -90))


# --- Helpers ---------------------------------------------------------------------

## Bakes the static parts sharing a material into one mesh each (a frame is
## built from dozens of primitives); the propeller and strobe stay separate
## because they animate.
func _merge_static() -> void:
	var groups: Dictionary[Material, Array] = {}
	for child in get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi == strobe:
			continue
		if not groups.has(mi.material_override):
			groups[mi.material_override] = []
		groups[mi.material_override].append(mi)
	for mat: Material in groups:
		var parts: Array = groups[mat]
		if parts.size() < 2:
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for mi: MeshInstance3D in parts:
			for surface in mi.mesh.get_surface_count():
				st.append_from(mi.mesh, surface, mi.transform)
			remove_child(mi)
			mi.queue_free()
		var merged := MeshInstance3D.new()
		merged.mesh = st.commit()
		merged.material_override = mat
		merged.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(merged)


## A cylinder strut from [param a] to [param b].
func _seg(a: Vector3, b: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var y := (b - a).normalized()
	var x := y.cross(Vector3.BACK)
	if x.length_squared() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var mi := _part(_cylinder(r, r, a.distance_to(b), 8), mat, (a + b) * 0.5, Vector3.ZERO)
	mi.basis = Basis(x, y, x.cross(y).normalized())
	return mi


## A ring (bezel, duct, collar) of [param radius] around its local Y axis.
func _ring(radius: float, thickness: float, mat: Material, pos: Vector3, rot_deg: Vector3) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = radius - thickness
	t.outer_radius = radius + thickness
	t.rings = 24
	t.ring_segments = 8
	return _part(t, mat, pos, rot_deg)


func _add_propeller(at: Vector3, blades: int, length: float) -> void:
	propeller.position = at
	for i in blades:
		var blade := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, length, 0.12)
		blade.mesh = bm
		blade.material_override = _steel
		blade.rotation = Vector3(TAU * i / blades, 0, 0)
		blade.position = Vector3(0, length * 0.47, 0).rotated(Vector3.RIGHT, TAU * i / blades)
		blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		propeller.add_child(blade)


## Red port and green starboard navigation lights.
func _running_lights(port: Vector3, starboard: Vector3) -> void:
	_part(MeshKit.sphere(0.05), MeshKit.emissive_material(Color(1.0, 0.1, 0.1), 5.0), port, Vector3.ZERO)
	_part(MeshKit.sphere(0.05), MeshKit.emissive_material(Color(0.1, 1.0, 0.3), 5.0), starboard, Vector3.ZERO)


func _part(mesh: Mesh, mat: Material, pos: Vector3, rot_deg: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	# The lamp sits inside the hull silhouette; hull shadows would black it out.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


static func _cylinder(top: float, bottom: float, height: float, segments: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = segments
	c.rings = 1
	return c


static func _capsule(radius: float, height: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = height
	c.radial_segments = 16
	c.rings = 4
	return c


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b
