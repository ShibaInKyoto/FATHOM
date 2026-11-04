class_name ModuleKit
extends RefCounted
## The modules installed on a dive, made visible on the hull. Each family of
## modules adds hardware that grows with every one fitted: propulsion goes
## from a bare propeller to a ducted one, then side thrusters, then a glowing
## pump-jet; plating bolts on armour plates; capacitors hang battery pods
## under the belly; sonar modules raise a dome and an array; lamp modules a
## second lamp bar; harpoon modules a heavier launcher; torpedo modules tubes
## on the flanks; a magnet coil copper rings; a galvanic hull glowing wires.

## Modules in each family; a family's stage is how many of them are fitted.
const FAMILIES: Dictionary[StringName, Array] = {
	&"drive": [&"hydrofoil", &"overdrive"],
	&"armour": [&"plating", &"nanites"],
	&"power": [&"capacitor", &"bioconverter", &"leech"],
	&"sonar": [&"amplifier", &"quick_ping", &"echo_analyzer", &"compass", &"sonar_stun"],
	&"lamp": [&"long_lamp", &"wide_lens", &"cold_lamp"],
	&"harpoon": [&"serrated", &"twin_reel", &"glass_cannon"],
	&"torpedo": [&"torpedo_rack", &"warhead", &"torpedo_kit"],
	&"coil": [&"magnet_coil", &"scavenger"],
	&"galvanic": [&"shock_hull", &"capacitor_coil"],
}
## Where hardware goes on each frame: the propeller, the hull's half-height
## and half-width, the stretch along it that takes plates, and the nose.
const MOUNTS: Dictionary[StringName, Dictionary] = {
	&"lantern": {"stern": Vector3(-2.3, 0.0, 0.0), "ry": 0.65, "rz": 0.74, "x": Vector2(-1.3, 1.1), "nose": 1.6,
		"top": 0.62},
	&"mako": {"stern": Vector3(-2.5, 0.0, 0.0), "ry": 0.41, "rz": 0.5, "x": Vector2(-1.4, 1.3), "nose": 2.1,
		"top": 0.45},
	&"bathysphere": {"stern": Vector3(-1.72, 0.0, 0.0), "ry": 1.15, "rz": 1.15, "x": Vector2(-0.6, 0.6), "nose": 1.15,
		"top": 1.15},
	&"whisper": {"stern": Vector3(-2.1, 0.0, 0.0), "ry": 0.27, "rz": 0.75, "x": Vector2(-1.2, 1.2), "nose": 1.9,
		"top": 0.3},
}
const GLOW := Color(0.3, 0.9, 1.0)

static var _mats: Dictionary[StringName, Material] = {}


## How many of [param family]'s modules are in [param modules].
static func stage(modules: Array[StringName], family: StringName) -> int:
	var n := 0
	for m in modules:
		if FAMILIES[family].has(m):
			n += 1
	return n


## Adds the hardware for [param modules] to [param model] (built as
## [param frame_id]) under one node, which it returns.
static func fit(model: Node3D, frame_id: StringName, modules: Array[StringName]) -> Node3D:
	var kit := Node3D.new()
	kit.name = "ModuleKit"
	model.add_child(kit)
	if modules.is_empty():
		return kit
	var m: Dictionary = MOUNTS.get(frame_id, MOUNTS[&"lantern"])
	_drive(kit, m, stage(modules, &"drive"))
	_armour(kit, m, stage(modules, &"armour"))
	_power(kit, m, stage(modules, &"power"))
	_sonar(kit, m, stage(modules, &"sonar"))
	_lamp(kit, m, stage(modules, &"lamp"))
	_harpoon(kit, m, stage(modules, &"harpoon"), modules.has(&"glass_cannon"))
	_torpedo(kit, m, stage(modules, &"torpedo"))
	_coil(kit, m, stage(modules, &"coil"))
	_galvanic(kit, m, stage(modules, &"galvanic"))
	return kit


## Ducted prop (1), side thrusters (2), a glowing pump-jet ring (3), glowing
## thrusters (4), a long nozzle (5+).
static func _drive(kit: Node3D, m: Dictionary, s: int) -> void:
	if s <= 0:
		return
	var stern: Vector3 = m.stern
	var rz: float = m.rz
	_ring(kit, 0.42, 0.07, _mat(&"dark"), stern, Vector3(0, 0, 90))
	if s >= 2:
		for z: float in [rz + 0.18, -rz - 0.18]:
			var at := Vector3(stern.x + 0.75, 0.0, z)
			_part(kit, _capsule(0.13, 0.7), _mat(&"steel"), at, Vector3(0, 0, 90))
			_ring(kit, 0.15, 0.04, _mat(&"glow") if s >= 4 else _mat(&"dark"), at - Vector3(0.36, 0, 0),
				Vector3(0, 0, 90))
			_seg(kit, Vector3(stern.x + 0.75, 0.0, z * 0.7), at, 0.04, _mat(&"dark"))
	if s >= 3:
		_ring(kit, 0.33, 0.045, _mat(&"glow"), stern - Vector3(0.12, 0, 0), Vector3(0, 0, 90))
	if s >= 5:
		_part(kit, _cylinder(0.45, 0.38, 0.35, 20), _mat(&"dark"), stern - Vector3(0.28, 0, 0), Vector3(0, 0, 90))


## An armour plate bolted to each flank per module.
static func _armour(kit: Node3D, m: Dictionary, s: int) -> void:
	var span: Vector2 = m.x
	var rz: float = m.rz
	var ry: float = m.ry
	for i in mini(s, 4):
		var x := lerpf(span.x, span.y, (i + 0.5) / 4.0)
		for side: float in [1.0, -1.0]:
			_part(kit, _box(Vector3(absf(span.y - span.x) / 4.5, ry * 1.15, 0.07)), _mat(&"plate"),
				Vector3(x, -ry * 0.05, side * (rz + 0.02)), Vector3.ZERO)
			for bolt: float in [-0.35, 0.35]:
				_part(kit, MeshKit.sphere(0.03, 6, 3), _mat(&"steel"),
					Vector3(x, bolt * ry, side * (rz + 0.06)), Vector3.ZERO)


## Battery pods under the belly, a glowing band round each.
static func _power(kit: Node3D, m: Dictionary, s: int) -> void:
	var span: Vector2 = m.x
	var ry: float = m.ry
	for i in mini(s, 4):
		var x := lerpf(span.x * 0.8, span.y * 0.8, (i + 0.5) / 4.0)
		var at := Vector3(x, -ry - 0.12, 0.0)
		_part(kit, _capsule(0.12, 0.5), _mat(&"steel"), at, Vector3(0, 0, 90))
		_ring(kit, 0.125, 0.025, _mat(&"glow"), at, Vector3(0, 0, 90))


## A sonar dome on the back (1), bigger (2), and an array of rods (3+).
static func _sonar(kit: Node3D, m: Dictionary, s: int) -> void:
	if s <= 0:
		return
	var top: float = m.top
	var span: Vector2 = m.x
	var x := lerpf(span.x, span.y, 0.62)
	var r := 0.16 + 0.05 * mini(s, 2)
	_part(kit, MeshKit.sphere(r, 12, 6), _mat(&"dome"), Vector3(x, top + r * 0.4, 0.0), Vector3.ZERO)
	if s >= 3:
		for k in mini(s - 1, 4):
			var base := Vector3(x - 0.25 - k * 0.14, top, (k % 2 - 0.5) * 0.25)
			_seg(kit, base, base + Vector3(0.0, 0.35 + k * 0.05, 0.0), 0.012, _mat(&"steel"))


## A second lamp bar over the nose, brighter with each lamp module.
static func _lamp(kit: Node3D, m: Dictionary, s: int) -> void:
	if s <= 0:
		return
	var nose: float = m.nose
	var ry: float = m.ry
	var at := Vector3(nose - 0.35, ry * 0.75, 0.0)
	_part(kit, _box(Vector3(0.18, 0.1, 0.35 + 0.12 * s)), _mat(&"dark"), at, Vector3(0, 0, -12))
	_part(kit, _box(Vector3(0.02, 0.06, 0.3 + 0.12 * s)), _mat(&"lamp"), at + Vector3(0.09, -0.01, 0.0),
		Vector3(0, 0, -12))


## A launcher under the nose that grows heavier; a glass cannon glows red.
static func _harpoon(kit: Node3D, m: Dictionary, s: int, glass: bool) -> void:
	if s <= 0:
		return
	var nose: float = m.nose
	var ry: float = m.ry
	var length := 0.45 + 0.15 * mini(s, 3)
	var at := Vector3(nose - 0.4 + length * 0.5, -ry * 0.7, 0.0)
	_part(kit, _cylinder(0.06, 0.08, length, 10), _mat(&"steel"), at, Vector3(0, 0, -90))
	_part(kit, MeshKit.spike(0.05, 0.18, 0.0, 6), _mat(&"red_glow") if glass else _mat(&"steel"),
		at + Vector3(length * 0.5 + 0.08, 0, 0), Vector3(0, 0, -90))


## Torpedo tubes along the flanks, a pair per module.
static func _torpedo(kit: Node3D, m: Dictionary, s: int) -> void:
	var rz: float = m.rz
	var ry: float = m.ry
	var span: Vector2 = m.x
	for i in mini(s, 3):
		var x := lerpf(span.x, span.y, 0.35 + i * 0.18)
		for side: float in [1.0, -1.0]:
			var at := Vector3(x, -ry * 0.45, side * (rz + 0.1))
			_part(kit, _capsule(0.07, 0.55), _mat(&"dark"), at, Vector3(0, 0, 90))
			_part(kit, MeshKit.sphere(0.04, 6, 3), _mat(&"red_glow"), at + Vector3(0.28, 0, 0), Vector3.ZERO)


## Copper coils round the hull.
static func _coil(kit: Node3D, m: Dictionary, s: int) -> void:
	var span: Vector2 = m.x
	var ry: float = m.ry
	var rz: float = m.rz
	for i in mini(s, 3):
		var x := lerpf(span.x, span.y, 0.2 + i * 0.12)
		var ring := _ring(kit, maxf(ry, rz) + 0.04, 0.035, _mat(&"copper"), Vector3(x, 0, 0), Vector3(0, 0, 90))
		ring.scale = Vector3(ry / maxf(ry, rz) + 0.05, 1.0, rz / maxf(ry, rz) + 0.05)


## Glowing wires along the hull.
static func _galvanic(kit: Node3D, m: Dictionary, s: int) -> void:
	if s <= 0:
		return
	var span: Vector2 = m.x
	var ry: float = m.ry
	var rz: float = m.rz
	for k in mini(s * 2, 4):
		var a := PI * 0.25 + k * PI * 0.5
		var off := Vector3(0.0, cos(a) * ry * 1.02, sin(a) * rz * 1.02)
		_seg(kit, Vector3(span.x, 0, 0) + off, Vector3(span.y, 0, 0) + off, 0.018, _mat(&"glow"))


static func _mat(id: StringName) -> Material:
	if not _mats.has(id):
		var mat := StandardMaterial3D.new()
		match id:
			&"dark":
				mat.albedo_color = Color(0.12, 0.13, 0.15)
				mat.metallic = 0.7
				mat.roughness = 0.35
			&"steel":
				mat.albedo_color = Color(0.6, 0.62, 0.65)
				mat.metallic = 0.85
				mat.roughness = 0.28
			&"plate":
				mat.albedo_color = Color(0.32, 0.34, 0.36)
				mat.metallic = 0.7
				mat.roughness = 0.5
			&"copper":
				mat.albedo_color = Color(0.85, 0.48, 0.25)
				mat.metallic = 0.9
				mat.roughness = 0.3
			&"dome":
				mat.albedo_color = Color(0.85, 0.85, 0.8)
				mat.roughness = 0.2
				mat.rim_enabled = true
			&"glow":
				mat = MeshKit.emissive_material(GLOW, 3.0)
			&"red_glow":
				mat = MeshKit.emissive_material(Color(1.0, 0.25, 0.15), 3.0)
			&"lamp":
				mat = MeshKit.emissive_material(Color(1.0, 0.95, 0.8), 4.5)
		_mats[id] = mat
	return _mats[id]


static func _part(kit: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot_deg: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	kit.add_child(mi)
	return mi


static func _ring(kit: Node3D, radius: float, thickness: float, mat: Material, pos: Vector3,
		rot_deg: Vector3) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = radius - thickness
	t.outer_radius = radius + thickness
	t.rings = 20
	t.ring_segments = 6
	return _part(kit, t, mat, pos, rot_deg)


static func _seg(kit: Node3D, a: Vector3, b: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var y := (b - a).normalized()
	var x := y.cross(Vector3.BACK)
	if x.length_squared() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var mi := _part(kit, _cylinder(r, r, a.distance_to(b), 6), mat, (a + b) * 0.5, Vector3.ZERO)
	mi.basis = Basis(x, y, x.cross(y).normalized())
	return mi


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


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
	c.radial_segments = 10
	c.rings = 3
	return c
