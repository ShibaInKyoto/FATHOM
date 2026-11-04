class_name BathysphereBuild
extends RefCounted
## The old Bathysphere: a cast pressure sphere grown into a working sub. Its
## halves are bolted at a heavy flange; an observer in a leather cap looks
## out through a thick quartz port under two smaller ones. A dogged hatch and
## a lifting bail on top, floodlights on arms, two big battery boxes and a
## drop-ballast hopper in a cradle on skids, and a caged propeller on an
## outrigger behind. Its shock emitter and sonar hang on as equipment. The
## port faces +X.

const PAINT_MAP := "res://assets/subs/bathysphere_paint.png"
const NORMAL_MAP := "res://assets/subs/bathysphere_normal.png"
## The sphere's radius.
const R := 1.0
const WARM := Color(1.0, 0.68, 0.36)
## How far round the lamp rail runs, up over the top and down under the sphere.
const RAIL_HIGH := 70.0
const RAIL_LOW := -45.0
## Which way the upper port on the near side looks (the far one mirrors it).
const UPPER_PORT := Vector3(0.6198, 0.5499, 0.5599)

static var _hull: HullFairing


## Where equipment goes on the Bathysphere (see SubEquipment): on the sphere,
## each mount facing straight out of it.
static func mounts() -> Dictionary:
	var on := func(d: Vector3) -> Transform3D:
		var n := d.normalized()
		return SubEquipment.frame_at(n * R, n)
	var pair := func(d: Vector3) -> Array:
		var t: Transform3D = on.call(d)
		return [t, SubEquipment.mirror(t)]
	var out := {}
	out[&"sonar"] = on.call(Vector3(-0.8, 0.55, 0.0))
	out[&"harpoon"] = on.call(Vector3(0.5, 0.15, 0.85))
	out[&"flare"] = on.call(Vector3(-0.45, 0.4, 0.8))
	out[&"decoy"] = on.call(Vector3(-0.45, 0.4, -0.8))
	out[&"shock"] = SubEquipment.frame_at(Vector3(1.02, -1.14, 0.0), Vector3.UP)
	out[&"torpedo"] = pair.call(Vector3(0.3, -0.45, 0.84))
	out[&"drive"] = pair.call(Vector3(-0.6, -0.1, 0.79))
	out[&"foil"] = pair.call(Vector3(0.15, -0.72, 0.68))
	var deck: Array = []
	for d: Vector3 in [Vector3(0.3, 0.84, 0.45), Vector3(-0.3, 0.84, 0.45), Vector3(0.0, 0.72, 0.69)]:
		deck.append_array(pair.call(d))
	out[&"deck"] = deck
	var flank: Array = []
	for d: Vector3 in [Vector3(-0.42, -0.32, 0.85), Vector3(-0.72, -0.2, 0.66), Vector3(-0.15, -0.62, 0.77),
			Vector3(-0.3, 0.42, 0.86)]:
		flank.append_array(pair.call(d))
	out[&"flank"] = flank
	out[&"belly"] = [on.call(Vector3(-0.5, -0.87, 0.0)), on.call(Vector3(0.42, -0.9, 0.0)),
		on.call(Vector3(-0.78, -0.62, 0.0))]
	return out


## The sphere, lofted end to end along X (its poles hide under the main
## port and the stern plate).
static func fairing() -> HullFairing:
	if _hull == null:
		var rows: Array = []
		for k in 13:
			var phi := deg_to_rad(lerpf(163.0, 17.0, k / 12.0))
			var r := sin(phi) * R
			rows.append([cos(phi) * R, 0.0, r, r, r, 2.0, 2.0])
		_hull = HullFairing.new(rows, 64, 96)
	return _hull


static func build(m: SubmarineModel) -> void:
	var hull := m.paint_material(ResourceLoader.exists(PAINT_MAP))
	if ResourceLoader.exists(PAINT_MAP):
		hull.set_shader_parameter(&"paint_map", load(PAINT_MAP))
		hull.set_shader_parameter(&"normal_tex", load(NORMAL_MAP))
	hull.set_shader_parameter(&"coat", 0.25)
	# Holes in the skin under the two upper ports, so they look into the cabin too.
	var holes: Array[Vector4] = []
	for sgn: float in [1.0, -1.0]:
		var d := UPPER_PORT * Vector3(1.0, 1.0, sgn)
		holes.append(Vector4(d.x * R, d.y * R, d.z * R, 0.122))
	hull.set_shader_parameter(&"holes", holes)
	hull.set_shader_parameter(&"hole_count", holes.size())
	hull.set_shader_parameter(&"roughness", 0.5)
	var quartz := m.glass_material()
	quartz.albedo_color = Color(0.7, 0.88, 0.8, 0.12)
	m.cockpit_material.albedo_color = Color(0.25, 0.17, 0.08)
	m.cockpit_material.emission = WARM
	var mats := {
		"hull": hull, "trim": m.paint_material(false),
		"iron": m.metal_material(Color(0.13, 0.13, 0.14), 0.75, 0.55, true),
		"frame": m.metal_material(Color(0.1, 0.105, 0.11), 0.5, 0.55, true),
		"brass": m.metal_material(Color(0.76, 0.56, 0.27), 1.0, 0.32, false),
		"copper": m.metal_material(Color(0.86, 0.45, 0.27), 1.0, 0.28, false),
		"ceramic": m.metal_material(Color(0.9, 0.89, 0.84), 0.0, 0.18, false),
		"rubber": m.metal_material(Color(0.03, 0.03, 0.033), 0.0, 0.85, false),
		"battery": m.metal_material(Color(0.2, 0.235, 0.16), 0.25, 0.6, true),
		"warning": m.metal_material(Color(0.95, 0.7, 0.08), 0.1, 0.5, true),
		"interior": m.metal_material(Color(0.13, 0.115, 0.1), 0.2, 0.75, false),
		"jacket": m.metal_material(Color(0.19, 0.12, 0.07), 0.0, 0.65, false),
		"cap": m.metal_material(Color(0.16, 0.1, 0.06), 0.0, 0.5, false),
		"skin": m.metal_material(Color(0.62, 0.46, 0.36), 0.0, 0.6, false),
		"quartz": quartz,
		"cockpit": m.cockpit_material,
		"lens": MeshKit.emissive_material(Color(1.0, 0.9, 0.7), 5.0),
		"strobe": MeshKit.emissive_material(Color.WHITE, 8.0),
		"port": MeshKit.emissive_material(Color(1.0, 0.12, 0.08), 6.0),
		"starboard": MeshKit.emissive_material(Color(0.15, 1.0, 0.35), 6.0),
	}
	if not m.restore(mats):
		_sphere(m, mats)
		_ports(m, mats)
		_lamp_rail(m, mats)
		_top(m, mats)
		_lamps(m, mats)
		_cradle(m, mats)
		_power(m, mats)
		_thruster(m, mats)
		m.remember(mats)


# --- Parts ---------------------------------------------------------------------------

## The cast sphere, its dark inside, the bolted flange and the stern plate.
static func _sphere(m: SubmarineModel, mats: Dictionary) -> void:
	var wear := func(u: float, _v: float) -> Color:
		return Color(1.0, 1.0 - 0.5 * (smoothstep(0.06, 0.0, u) + smoothstep(0.94, 1.0, u)), 1.0)
	m.place(fairing().mesh(wear), mats.hull)
	# Seen from inside through the ports: a dark wall.
	m.place(HullMesh.lathe(_ball_inward(R * 0.95, 16), 32), mats.interior)
	m.place(HullMesh.lathe(PackedVector2Array([Vector2(-0.075, 0.97), Vector2(-0.075, 1.035), Vector2(-0.065, 1.05),
		Vector2(0.065, 1.05), Vector2(0.075, 1.035), Vector2(0.075, 0.97)]), 64), mats.iron)
	m.place(HullMesh.bolt_ring(36, 1.015, 0.016), mats.brass, Vector3(0.075, 0.0, 0.0))
	m.place(HullMesh.bolt_ring(36, 1.015, 0.016, 0.5), mats.brass, Vector3(-0.075, 0.0, 0.0), Vector3(0, 180, 0))
	m.place(HullMesh.lathe(PackedVector2Array([Vector2(-1.08, 0.001), Vector2(-1.08, 0.2), Vector2(-1.065, 0.25),
		Vector2(-1.03, 0.29), Vector2(-0.88, 0.47)]), 32), mats.iron)
	m.place(HullMesh.bolt_ring(10, 0.22, 0.014), mats.brass, Vector3(-1.08, 0.0, 0.0), Vector3(0, 180, 0))


## The main quartz port in its boss, two smaller ports above it, and the
## observer inside with his dials.
static func _ports(m: SubmarineModel, mats: Dictionary) -> void:
	m.place(HullMesh.lathe(PackedVector2Array([Vector2(0.86, 0.5), Vector2(0.96, 0.44), Vector2(1.08, 0.415),
		Vector2(1.115, 0.405), Vector2(1.13, 0.39), Vector2(1.13, 0.39), Vector2(1.13, 0.335), Vector2(1.13, 0.335),
		Vector2(0.88, 0.335)]), 40), mats.iron)
	m.place(HullMesh.lathe(PackedVector2Array([Vector2(1.1, 0.336), Vector2(1.112, 0.3), Vector2(1.124, 0.16),
		Vector2(1.127, 0.001)]), 40, 0.0), mats.quartz)
	m.place(HullMesh.bolt_ring(12, 0.362, 0.013), mats.brass, Vector3(1.13, 0.0, 0.0))
	for sgn: float in [1.0, -1.0]:
		var d := UPPER_PORT * Vector3(1.0, 1.0, sgn)
		var basis := Basis(Quaternion(Vector3.RIGHT, d))
		m.place_xform(HullMesh.lathe(PackedVector2Array([Vector2(0.9, 0.21), Vector2(1.0, 0.195), Vector2(1.07, 0.185),
			Vector2(1.085, 0.165), Vector2(1.085, 0.165), Vector2(1.085, 0.125), Vector2(1.085, 0.125),
			Vector2(0.92, 0.125)]), 28), mats.iron, Transform3D(basis, Vector3.ZERO))
		m.place_xform(HullMesh.lathe(PackedVector2Array([Vector2(1.065, 0.126), Vector2(1.074, 0.08),
			Vector2(1.077, 0.001)]), 28, 0.0), mats.quartz, Transform3D(basis, Vector3.ZERO))
		m.place_xform(HullMesh.bolt_ring(8, 0.145, 0.011), mats.brass, Transform3D(basis, basis.x * 1.085))
	# The observer, hunched at the port: leather cap and jacket, headset on.
	m.place(HullMesh.rounded_box(Vector3(0.26, 0.34, 0.4), 0.11), mats.jacket, Vector3(0.5, -0.3, 0.0), Vector3(0, 0, -25))
	for sgn: float in [-1.0, 1.0]:
		m.place(HullMesh.pipe(PackedVector3Array([Vector3(0.52, -0.2, sgn * 0.19), Vector3(0.66, -0.36, sgn * 0.22),
			Vector3(0.8, -0.3, sgn * 0.14)]), 0.045, 8, 0.05), mats.jacket)
		m.place(HullMesh.lathe(_ball(0.035, 6), 8), mats.skin, Vector3(0.82, -0.29, sgn * 0.13))
	var head := Vector3(0.7, -0.04, 0.0)
	m.place(HullMesh.lathe(_ball(0.085, 10), 14), mats.skin, head, Vector3(0, 0, 90))
	m.place(HullMesh.lathe(_cap(0.095, 8), 14), mats.cap, head + Vector3(-0.012, 0.024, 0.0), Vector3(0, 0, 100))
	# The cap's peak, and goggles pushed up on it.
	m.place(HullMesh.rounded_box(Vector3(0.06, 0.012, 0.12), 0.005, 1), mats.cap, head + Vector3(0.075, 0.05, 0.0),
		Vector3(0, 0, -12))
	for sgn: float in [-1.0, 1.0]:
		m.place(HullMesh.lathe(PackedVector2Array([Vector2(-0.012, 0.022), Vector2(0.012, 0.022), Vector2(0.014, 0.017),
			Vector2(0.014, 0.017), Vector2(0.014, 0.001)]), 12), mats.brass, head + Vector3(0.06, 0.075, sgn * 0.032),
			Vector3(0, 0, 50))
	m.place(HullMesh.pipe(PackedVector3Array([head + Vector3(-0.01, -0.02, 0.095), head + Vector3(-0.01, 0.1, 0.0),
		head + Vector3(-0.01, -0.02, -0.095)]), 0.008, 6, 0.07), mats.iron)
	for sgn: float in [-1.0, 1.0]:
		m.place(HullMesh.lathe(_ball(0.03, 6), 10), mats.iron, head + Vector3(-0.01, -0.02, sgn * 0.09))
	# Brass dials either side of the port, lit warm.
	for yz: Vector2 in [Vector2(0.2, 0.3), Vector2(0.2, -0.3), Vector2(-0.06, 0.36), Vector2(-0.06, -0.36)]:
		var at := Vector3(0.84, yz.x, yz.y)
		m.place(HullMesh.lathe(PackedVector2Array([Vector2(-0.01, 0.045), Vector2(0.01, 0.045), Vector2(0.012, 0.04),
			Vector2(0.012, 0.04), Vector2(0.012, 0.001)]), 14), mats.brass, at)
		m.place(HullMesh.lathe(PackedVector2Array([Vector2(0.013, 0.035), Vector2(0.014, 0.001)]), 14, 0.0),
			mats.cockpit, at)
	m.add_cockpit_light(Vector3(0.75, 0.25, 0.0), WARM)


## The dogged hatch with its handwheel, the lifting bail and shackle, a
## sonar transducer on the forehead, the strobe and whip on the bail.
static func _top(m: SubmarineModel, mats: Dictionary) -> void:
	var up := Vector3(0, 0, 90)
	m.place(HullMesh.lathe(PackedVector2Array([Vector2(0.9, 0.36), Vector2(0.98, 0.34), Vector2(1.07, 0.335),
		Vector2(1.08, 0.32), Vector2(1.08, 0.32), Vector2(1.08, 0.29)]), 36), mats.iron, Vector3.ZERO, up)
	m.place(HullMesh.lathe(PackedVector2Array([Vector2(1.07, 0.3), Vector2(1.1, 0.29), Vector2(1.13, 0.24),
		Vector2(1.155, 0.13), Vector2(1.162, 0.001)]), 36), mats.trim, Vector3.ZERO, up)
	for k in 8:
		var a := TAU * (k + 0.5) / 8.0
		var mi := m.place(HullMesh.rounded_box(Vector3(0.09, 0.05, 0.045), 0.012), mats.iron,
			Vector3(cos(a) * 0.31, 1.095, sin(a) * 0.31))
		mi.rotation.y = -a
	m.place(HullMesh.rounded_box(Vector3(0.1, 0.07, 0.18), 0.02), mats.iron, Vector3(-0.32, 1.1, 0.0))
	m.place(HullMesh.lathe(_torus(0.12, 0.011, 10), 28), mats.brass, Vector3(0.0, 1.2, 0.0), up)
	for a: float in [0.0, PI / 3.0, PI * 2.0 / 3.0]:
		m.place(HullMesh.pipe(PackedVector3Array([Vector3(-cos(a) * 0.12, 1.2, -sin(a) * 0.12),
			Vector3(cos(a) * 0.12, 1.2, sin(a) * 0.12)]), 0.007, 6), mats.brass)
	m.place(HullMesh.pipe(PackedVector3Array([Vector3(0.0, 1.16, 0.0), Vector3(0.0, 1.2, 0.0)]), 0.02, 8), mats.brass)
	# The bail: a heavy arch across the sphere, a shackle at its crown.
	m.place(HullMesh.pipe(PackedVector3Array([Vector3(0.0, 0.82, -0.56), Vector3(0.0, 1.32, -0.44),
		Vector3(0.0, 1.32, 0.44), Vector3(0.0, 0.82, 0.56)]), 0.036, 12, 0.16), mats.iron)
	for z: float in [-0.56, 0.56]:
		var mi := m.place(HullMesh.rounded_box(Vector3(0.16, 0.06, 0.16), 0.02), mats.iron, Vector3(0.0, 0.83, z))
		mi.rotation.x = signf(z) * 0.6
	m.place(HullMesh.lathe(_torus(0.07, 0.016, 10), 20), mats.iron, Vector3(0.0, 1.43, 0.0), Vector3(0, 90, 0))
	m.strobe = m.place(HullMesh.lathe(_ball(0.025, 8), 12, 0.0), mats.strobe, Vector3(0.0, 1.39, -0.3))
	m.place(HullMesh.pipe(PackedVector3Array([Vector3(0.0, 1.34, -0.3), Vector3(0.0, 1.37, -0.3)]), 0.012, 6),
		mats.iron)
	m.place(HullMesh.pipe(PackedVector3Array([Vector3(0.0, 1.35, 0.25), Vector3(-0.1, 1.8, 0.2)]), 0.005, 5), mats.iron)


## The main lamp's rail: a toothed iron arc hugging the sphere from high over
## the top to well under it, stepping out round the main port, on standoffs
## from the sphere; an iron carriage with a brass pinion walks the lamp along
## it to wherever the observer aims.
static func _lamp_rail(m: SubmarineModel, mats: Dictionary) -> void:
	var lo := RAIL_LOW
	var hi := RAIL_HIGH
	var steps := 48
	var reach := PackedFloat32Array()
	for k in steps + 1:
		reach.append(_rail_radius(lerpf(lo, hi, float(k) / steps)) + 0.06)
	for z: float in [-0.03, 0.03]:
		var rail := PackedVector3Array()
		for k in steps + 1:
			var a := deg_to_rad(lerpf(lo - 4.0, hi + 4.0, float(k) / steps))
			rail.append(Vector3(cos(a), sin(a), 0.0) * _rail_radius(rad_to_deg(a)) + Vector3(0, 0, z))
		m.place(HullMesh.pipe(rail, 0.012, 8), mats.iron)
	# Teeth round the outside of the rail, for the carriage's pinion.
	for k in 61:
		var deg := lerpf(lo, hi, k / 60.0)
		var a := deg_to_rad(deg)
		m.place(HullMesh.rounded_box(Vector3(0.016, 0.014, 0.05), 0.004, 1), mats.brass,
			Vector3(cos(a), sin(a), 0.0) * (_rail_radius(deg) + 0.014), Vector3(0, 0, deg))
	# Standoffs from the sphere to the rail, a foot bolted down under each.
	for deg: float in [hi + 3.0, 42.0, lo - 3.0]:
		var a := deg_to_rad(deg)
		var out := Vector3(cos(a), sin(a), 0.0)
		m.place(HullMesh.pipe(PackedVector3Array([out * (R - 0.02), out * (_rail_radius(deg) - 0.008)]), 0.02, 8),
			mats.iron)
		m.place(HullMesh.rounded_box(Vector3(0.1, 0.03, 0.1), 0.01), mats.iron, out * (R + 0.005),
			Vector3(0, 0, deg - 90.0))
	m.add_lamp_track(Vector3.ZERO, reach, lo, hi, 1.5)
	var shoe := m.lamp_socket
	m.place(HullMesh.rounded_box(Vector3(0.06, 0.12, 0.11), 0.015), mats.iron, Vector3(-0.04, 0, 0), Vector3.ZERO, shoe)
	m.place(HullMesh.lathe(PackedVector2Array([Vector2(-0.015, 0.001), Vector2(-0.015, 0.03), Vector2(0.015, 0.03),
		Vector2(0.015, 0.001)]), 12), mats.brass, Vector3(-0.044, 0.0, 0.068), Vector3(0, 90, 0), shoe)


## The rail's distance from the sphere's centre at [param deg] round from
## straight ahead: just off the sphere, stepping out to pass in front of
## the main port.
static func _rail_radius(deg: float) -> float:
	return R * 1.1 + 0.17 * smoothstep(32.0, 18.0, absf(deg))


## Floodlights on arms either side of the port, with the running lights.
static func _lamps(m: SubmarineModel, mats: Dictionary) -> void:
	for sgn: float in [1.0, -1.0]:
		var lamp := Vector3(0.72, -0.28, sgn * 0.86)
		m.place(HullMesh.pipe(PackedVector3Array([Vector3(0.0, -0.28, sgn * 1.03), Vector3(0.35, -0.28, sgn * 1.0),
			lamp + Vector3(-0.2, 0.0, 0.0)]), 0.025, 8, 0.12), mats.iron)
		var r := 0.1
		m.place(HullMesh.lathe(PackedVector2Array([Vector2(-0.22, 0.001), Vector2(-0.22, 0.06), Vector2(-0.18, 0.09),
			Vector2(-0.1, r), Vector2(0.03, r), Vector2(0.045, r * 1.08), Vector2(0.06, r * 1.08),
			Vector2(0.065, r * 0.98), Vector2(0.065, r * 0.85), Vector2(0.065, r * 0.85), Vector2(0.04, r * 0.85)]), 28),
			mats.brass, lamp)
		for k in 3:
			var x := -0.17 + 0.05 * k
			m.place(HullMesh.lathe(PackedVector2Array([Vector2(x - 0.006, r * 0.95), Vector2(x - 0.006, r * 1.15),
				Vector2(x + 0.006, r * 1.15), Vector2(x + 0.006, r * 0.95)]), 28), mats.iron, lamp)
		m.place(HullMesh.lathe(PackedVector2Array([Vector2(0.045, r * 0.86), Vector2(0.06, r * 0.6),
			Vector2(0.063, 0.001)]), 28, 0.0), mats.lens, lamp)
		m.place(HullMesh.lathe(_ball(0.02, 8), 12, 0.0), mats.starboard if sgn > 0.0 else mats.port,
			lamp + Vector3(-0.05, r + 0.02, 0.0))


## The cradle round the lower sphere, its legs and skids, and the shock
## electrodes on their insulators at the front.
static func _cradle(m: SubmarineModel, mats: Dictionary) -> void:
	var ring_y := -0.62
	var ring_r := sqrt(R * R - ring_y * ring_y) + 0.02
	m.place(HullMesh.lathe(_torus(ring_r, 0.035, 10), 48), mats.frame, Vector3(0.0, ring_y, 0.0), Vector3(0, 0, 90))
	var skid_y := -1.3
	for sgn: float in [1.0, -1.0]:
		m.place(HullMesh.pipe(PackedVector3Array([Vector3(-1.05, skid_y, sgn * 0.72), Vector3(0.88, skid_y, sgn * 0.72),
			Vector3(1.16, skid_y + 0.22, sgn * 0.72)]), 0.042, 10, 0.18), mats.frame)
		for x: float in [-0.75, 0.0, 0.7]:
			m.place(HullMesh.rounded_box(Vector3(0.24, 0.03, 0.11), 0.012), mats.rubber,
				Vector3(x, skid_y - 0.045, sgn * 0.72))
		for xs: float in [1.0, -1.0]:
			var a := Vector3(xs * ring_r * 0.7071, ring_y, sgn * ring_r * 0.7071)
			var b := Vector3(xs * 0.72, skid_y, sgn * 0.72)
			m.place(HullMesh.pipe(PackedVector3Array([a, b]), 0.034, 10), mats.frame)
			m.place(HullMesh.rounded_box(Vector3(0.12, 0.05, 0.12), 0.015), mats.frame, b + Vector3(0, 0.03, 0))
		m.place(HullMesh.rounded_box(Vector3(0.1, 0.04, 0.03), 0.01), mats.brass, Vector3(-0.4, skid_y, sgn * 0.77))
	for x: float in [-0.72, 0.6]:
		m.place(HullMesh.pipe(PackedVector3Array([Vector3(x, skid_y + 0.02, -0.72), Vector3(x, skid_y + 0.02, 0.72)]),
			0.03, 8), mats.frame)
	# A crossbar at the front, for the shock emitter if one is fitted.
	var bar_x := 1.02
	var bar_y := skid_y + 0.13
	m.place(HullMesh.pipe(PackedVector3Array([Vector3(bar_x, bar_y, -0.72), Vector3(bar_x, bar_y, 0.72)]), 0.03, 8),
		mats.frame)


## The batteries in their boxes, the drop-ballast hopper and the cables.
static func _power(m: SubmarineModel, mats: Dictionary) -> void:
	for sgn: float in [1.0, -1.0]:
		var at := Vector3(-0.05, -1.09, sgn * 0.37)
		m.place(HullMesh.rounded_box(Vector3(1.15, 0.29, 0.31), 0.035), mats.battery, at)
		m.place(HullMesh.rounded_box(Vector3(1.17, 0.03, 0.33), 0.012), mats.battery, at + Vector3(0, 0.1, 0))
		for x: float in [-0.38, 0.0, 0.38]:
			m.place(HullMesh.rounded_box(Vector3(0.05, 0.305, 0.325), 0.01), mats.iron, at + Vector3(x, 0.0, 0.0))
		m.place(HullMesh.rounded_box(Vector3(0.008, 0.08, 0.1), 0.004, 1), mats.warning,
			at + Vector3(0.578, 0.03, 0.0))
		for k in 2:
			var gland := at + Vector3(0.58, -0.06 + 0.07 * k, sgn * -0.08)
			m.place(HullMesh.lathe(PackedVector2Array([Vector2(0.0, 0.025), Vector2(0.04, 0.025), Vector2(0.045, 0.018),
				Vector2(0.045, 0.001)]), 12), mats.brass, gland)
		# A cable from the box up into the sphere, one to the floodlight.
		m.place(HullMesh.pipe(PackedVector3Array([at + Vector3(0.62, -0.06, sgn * -0.08),
			at + Vector3(0.78, 0.02, sgn * -0.04), Vector3(0.62, -0.72, sgn * 0.3)]), 0.018, 8, 0.12), mats.rubber)
		m.place(HullMesh.pipe(PackedVector3Array([Vector3(0.3, -0.92, sgn * 0.42), Vector3(0.38, -0.7, sgn * 0.85),
			Vector3(0.5, -0.4, sgn * 0.86), Vector3(0.52, -0.3, sgn * 0.86)]), 0.015, 8, 0.12), mats.rubber)
	# Drop ballast: a hopper of steel shot under the sphere, an iron gate below.
	m.place(HullMesh.lathe(PackedVector2Array([Vector2(-0.01, 0.001), Vector2(-0.01, 0.17), Vector2(0.0, 0.18),
		Vector2(0.17, 0.07), Vector2(0.24, 0.05), Vector2(0.24, 0.05), Vector2(0.24, 0.001)]), 20), mats.iron,
		Vector3(0.0, -0.93, 0.0), Vector3(0, 0, -90))


## The thruster: a motor on struts from the stern plate, a wide-bladed
## propeller in a ring with a wire guard behind.
static func _thruster(m: SubmarineModel, mats: Dictionary) -> void:
	for y: float in [0.12, -0.12]:
		m.place(HullMesh.pipe(PackedVector3Array([Vector3(-1.06, y, 0.0), Vector3(-1.38, y * 0.6, 0.0)]), 0.03, 8),
			mats.iron)
	m.place(HullMesh.lathe(PackedVector2Array([Vector2(-1.62, 0.001), Vector2(-1.6, 0.08), Vector2(-1.55, 0.12),
		Vector2(-1.38, 0.13), Vector2(-1.33, 0.11), Vector2(-1.32, 0.001)]), 24), mats.trim)
	m.place(HullMesh.lathe(PackedVector2Array([Vector2(-1.45, 0.125), Vector2(-1.45, 0.137), Vector2(-1.41, 0.137),
		Vector2(-1.41, 0.125)]), 24, 0.0), mats.brass)
	var at := Vector3(-1.68, 0.0, 0.0)
	m.place(_duct(0.34, 0.31, 0.14), mats.iron, at)
	# The guard: a ring behind on rods.
	m.place(HullMesh.lathe(_torus(0.32, 0.012, 8), 40), mats.iron, at + Vector3(-0.2, 0.0, 0.0))
	for k in 8:
		var a := TAU * k / 8.0
		var off := Vector3(0.0, cos(a), sin(a)) * 0.325
		m.place(HullMesh.pipe(PackedVector3Array([at + off + Vector3(-0.05, 0, 0), at + off + Vector3(-0.2, 0, 0)]), 0.008,
			5), mats.iron)
	for k in 4:
		var a := TAU * k / 4.0 + PI / 4.0
		var off := Vector3(0.0, cos(a), sin(a))
		m.place(HullMesh.pipe(PackedVector3Array([at + Vector3(-0.2, 0, 0), at + Vector3(-0.2, 0, 0) + off * 0.31]),
			0.006, 5), mats.iron)
	m.propeller.position = at
	m.place(HullMesh.blades(3, 0.06, 0.29, 0.2, 0.7, 0.35), mats.brass, Vector3.ZERO, Vector3.ZERO, m.propeller)
	m.place(HullMesh.lathe(PackedVector2Array([Vector2(-0.12, 0.001), Vector2(-0.1, 0.035), Vector2(-0.05, 0.06),
		Vector2(0.05, 0.065), Vector2(0.06, 0.001)]), 16), mats.brass, Vector3.ZERO, Vector3.ZERO, m.propeller)


## A thruster ring round the X axis: outer radius [param outer], inner
## [param inner], [param length] long, centred on 0.
static func _duct(outer: float, inner: float, length: float) -> ArrayMesh:
	var h := length * 0.5
	var t := outer - inner
	return HullMesh.lathe(PackedVector2Array([
		Vector2(-h, inner + t * 0.5), Vector2(-h * 0.6, outer), Vector2(h * 0.6, outer), Vector2(h, inner + t * 0.5),
		Vector2(h * 0.6, inner), Vector2(-h * 0.6, inner), Vector2(-h, inner + t * 0.5)]), 40, 0.8)


## A sphere's profile for the lathe.
static func _ball(r: float, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in steps + 1:
		var a := PI * k / steps
		out.append(Vector2(-cos(a) * r, sin(a) * r + 0.0002))
	return out


## A sphere's profile traced the other way, so it faces inward.
static func _ball_inward(r: float, steps: int) -> PackedVector2Array:
	var out := _ball(r, steps)
	out.reverse()
	return out


## A dome cap's profile (the top part of a sphere of radius [param r]).
static func _cap(r: float, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in steps + 1:
		var a := PI * 0.5 * k / steps
		out.append(Vector2(-r * 0.15 + sin(a) * r * 0.9, cos(a) * r + 0.0002))
	return out


## A small torus's profile (tube [param tube] round a ring of [param r]).
static func _torus(r: float, tube: float, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in steps + 1:
		var a := TAU * k / steps
		out.append(Vector2(sin(a) * tube, r + cos(a) * tube))
	return out
