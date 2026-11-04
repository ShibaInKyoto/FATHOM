class_name MakoBuild
extends RefCounted
## The Mako, a racing prototype: a long, flattened hull with a fighter canopy
## over a reclined pilot, a tall swept dorsal fin, swept dive planes, lamps
## set like eyes, gill intakes on the flanks and an X-tail round a shrouded
## pump-jet. Its torpedo pods hang on as equipment. Nose +X.

const PAINT_MAP := "res://assets/subs/mako_paint.png"
const NORMAL_MAP := "res://assets/subs/mako_normal.png"
## Fairing stations: x, centre height, height above and below the centre,
## half-width, and how square the upper and lower halves are (2 is round).
const STATIONS: Array = [
	[-2.05, 0.02, 0.11, 0.11, 0.13, 2.0, 2.0],
	[-1.7, 0.03, 0.22, 0.2, 0.26, 2.2, 2.2],
	[-1.0, 0.04, 0.34, 0.29, 0.43, 2.4, 2.6],
	[-0.2, 0.04, 0.4, 0.33, 0.51, 2.5, 2.8],
	[0.6, 0.03, 0.38, 0.32, 0.49, 2.4, 2.7],
	[1.3, 0.0, 0.3, 0.26, 0.39, 2.3, 2.4],
	[1.85, -0.03, 0.18, 0.17, 0.24, 2.1, 2.1],
	[2.2, -0.05, 0.075, 0.075, 0.085, 2.0, 2.0],
]
## The canopy's profile along the hull: (x, radius).
const CANOPY: Array[Vector2] = [Vector2(0.05, 0.0), Vector2(0.25, 0.1), Vector2(0.55, 0.2), Vector2(0.85, 0.235),
	Vector2(1.1, 0.215), Vector2(1.32, 0.14), Vector2(1.45, 0.05), Vector2(1.5, 0.0)]
## The pump-jet's axis.
const JET := Vector3(-2.25, 0.025, 0.0)

static var _hull: HullFairing


## Every Mako has the same shape.
static func fairing() -> HullFairing:
	if _hull == null:
		_hull = HullFairing.new(STATIONS, 80, 72)
	return _hull


static func build(m: SubmarineModel) -> void:
	var hull := m.paint_material(ResourceLoader.exists(PAINT_MAP))
	if ResourceLoader.exists(PAINT_MAP):
		hull.set_shader_parameter(&"paint_map", load(PAINT_MAP))
		hull.set_shader_parameter(&"normal_tex", load(NORMAL_MAP))
	var glass := m.glass_material()
	glass.albedo_color = Color(0.45, 0.6, 0.72, 0.16)
	var mats := {
		"hull": hull, "trim": m.paint_material(false),
		"carbon": m.metal_material(Color(0.045, 0.047, 0.052), 0.3, 0.32, false),
		"ti": m.metal_material(Color(0.5, 0.51, 0.53), 0.85, 0.3, false),
		"steel": m.metal_material(Color(0.78, 0.79, 0.8), 0.95, 0.2, false),
		"rubber": m.metal_material(Color(0.03, 0.03, 0.033), 0.0, 0.85, false),
		"interior": m.metal_material(Color(0.09, 0.095, 0.1), 0.2, 0.7, false),
		"suit": m.metal_material(Color(0.07, 0.07, 0.08), 0.0, 0.7, false),
		"helmet": m.metal_material(Color(0.92, 0.92, 0.9), 0.1, 0.25, false),
		"visor": m.metal_material(Color(0.03, 0.04, 0.05), 0.9, 0.08, false),
		"glass": glass,
		"cockpit": m.cockpit_material,
		"lens": MeshKit.emissive_material(Color(1.0, 0.95, 0.85), 6.0),
		"jet": MeshKit.emissive_material(Color(0.35, 0.75, 1.0), 2.5),
		"strobe": MeshKit.emissive_material(Color.WHITE, 8.0),
		"port": MeshKit.emissive_material(Color(1.0, 0.12, 0.08), 6.0),
		"starboard": MeshKit.emissive_material(Color(0.15, 1.0, 0.35), 6.0),
	}
	if not m.restore(mats):
		_fairing(m, mats)
		_nose(m, mats)
		_canopy(m, mats)
		_fins(m, mats)
		_lamp_arm(m, mats)
		_jet(m, mats)
		m.remember(mats)


## Where equipment goes on the Mako (see SubEquipment).
static func mounts() -> Dictionary:
	var f := fairing()
	var up := Vector3.UP
	var down := Vector3.DOWN
	var out := {}
	out[&"harpoon"] = SubEquipment.frame_at(Vector3(1.75, f.keel_y(1.75, 0.0) + 0.005, 0.0), down)
	out[&"sonar"] = SubEquipment.frame_at(Vector3(-0.35, f.keel_y(-0.35, 0.0) + 0.01, 0.0), down)
	out[&"shock"] = SubEquipment.frame_at(Vector3(0.85, f.keel_y(0.85, 0.0) + 0.01, 0.0), down)
	out[&"flare"] = SubEquipment.frame_at(Vector3(-1.22, f.deck_y(-1.22, 0.0) - 0.005, 0.0), up)
	out[&"decoy"] = SubEquipment.frame_at(Vector3(-1.52, f.deck_y(-1.52, 0.0) - 0.005, 0.0), up)
	var y := -0.14
	var torpedo := SubEquipment.frame_at(Vector3(1.25, y, f.side_z(1.25, y) - 0.02), Vector3(0.0, -0.25, 1.0))
	out[&"torpedo"] = [torpedo, SubEquipment.mirror(torpedo)]
	out[&"drive"] = [f.mount(-1.55, 0.17), f.mount(-1.55, 0.83)]
	out[&"foil"] = [f.mount(0.0, 0.1), f.mount(0.0, 0.9)]
	var deck: Array = []
	for x: float in [0.35, -0.35, -0.85]:
		deck.append_array([f.mount(x, 0.41), f.mount(x, 0.59)])
	out[&"deck"] = deck
	var flank: Array = []
	for x: float in [-1.25, -0.65, 0.0, 0.6]:
		flank.append_array([f.mount(x, 0.14), f.mount(x, 0.86)])
	out[&"flank"] = flank
	var belly: Array = []
	for x: float in [-0.95, -1.35, 0.8]:
		belly.append(SubEquipment.frame_at(Vector3(x, f.keel_y(x, 0.0) + 0.01, 0.0), down))
	out[&"belly"] = belly
	out[&"power"] = SubEquipment.frame_at(Vector3(0.3, f.keel_y(0.3, 0.0) + 0.01, 0.0), down)
	out[&"galvanic"] = Vector3(-1.3, 0.75, 0.075)
	return out


# --- Parts ---------------------------------------------------------------------------

static func _fairing(m: SubmarineModel, mats: Dictionary) -> void:
	var wear := func(u: float, _v: float) -> Color:
		return Color(1.0, 1.0 - 0.5 * smoothstep(0.05, 0.0, u), 1.0)
	m.place(fairing().mesh(wear), mats.hull)


## A sonar dome on the tip, lamps set like eyes either side of the nose.
static func _nose(m: SubmarineModel, mats: Dictionary) -> void:
	m.place(HullMesh.lathe(PackedVector2Array([Vector2(2.12, 0.088), Vector2(2.2, 0.085), Vector2(2.27, 0.068),
		Vector2(2.31, 0.04), Vector2(2.325, 0.012), Vector2(2.327, 0.001)]), 24), mats.carbon, Vector3(0, -0.05, 0))
	m.place(HullMesh.lathe(PackedVector2Array([Vector2(2.11, 0.083), Vector2(2.115, 0.093), Vector2(2.13, 0.093),
		Vector2(2.135, 0.083)]), 24), mats.ti, Vector3(0, -0.05, 0))
	for sgn: float in [1.0, -1.0]:
		var x := 1.66
		var y := 0.05
		var at := Vector3(x, y, sgn * (fairing().side_z(x, y) - 0.03))
		var turn := Vector3(0, -sgn * 24.0, -4.0)
		# A slim housing let into the hull, the lens glowing in it.
		m.place(HullMesh.lathe(PackedVector2Array([Vector2(-0.12, 0.001), Vector2(-0.12, 0.04), Vector2(-0.07, 0.056),
			Vector2(0.025, 0.056), Vector2(0.04, 0.05), Vector2(0.04, 0.04), Vector2(0.04, 0.04),
			Vector2(0.02, 0.04)]), 20), mats.carbon, at, turn)
		m.place(HullMesh.lathe(PackedVector2Array([Vector2(0.016, 0.041), Vector2(0.032, 0.026),
			Vector2(0.035, 0.001)]), 20, 0.0), mats.lens, at, turn)


## The canopy over a dark cockpit: the pilot reclined in a racing helmet,
## glowing instruments ahead, a frame arch and sills.
static func _canopy(m: SubmarineModel, mats: Dictionary) -> void:
	var f := fairing()
	var x0 := CANOPY[0].x
	var x1 := CANOPY[CANOPY.size() - 1].x
	var centre := func(x: float) -> float: return f.deck_y(x, 0.0) - 0.05
	var radius := func(x: float) -> float:
		for k in range(1, CANOPY.size()):
			if x <= CANOPY[k].x:
				var t := (x - CANOPY[k - 1].x) / (CANOPY[k].x - CANOPY[k - 1].x)
				return lerpf(CANOPY[k - 1].y, CANOPY[k].y, t * t * (3.0 - 2.0 * t)) + 0.0005
		return 0.0005
	var shell := func(scale: float, drop: float) -> Callable:
		return func(u: float, v: float) -> Vector3:
			var x := lerpf(x0, x1, u)
			var r: float = radius.call(x) * scale
			var a := v * TAU
			return Vector3(x, centre.call(x) - drop + cos(a) * r * 1.05, sin(a) * r)
	m.place(HullMesh.surface(shell.call(1.0, 0.0), 32, 32, true), mats.glass)
	# The cockpit floor, dark, so the hull doesn't show through the glass.
	m.place(HullMesh.surface(shell.call(0.97, 0.12), 24, 24, true), mats.interior)
	# Frame arch over the middle and sills along both sides.
	var arch := PackedVector3Array()
	var ax := 0.98
	var ar: float = radius.call(ax) + 0.008
	for k in 13:
		var a := lerpf(-PI * 0.5, PI * 0.5, k / 12.0)
		arch.append(Vector3(ax, centre.call(ax) + cos(a) * ar * 1.05, sin(a) * ar))
	m.place(HullMesh.pipe(arch, 0.014, 8), mats.carbon)
	for sgn: float in [1.0, -1.0]:
		var sill := PackedVector3Array()
		for k in 15:
			var x := lerpf(x0 + 0.08, x1 - 0.06, k / 14.0)
			sill.append(Vector3(x, centre.call(x) + 0.004, sgn * (radius.call(x) + 0.006)))
		m.place(HullMesh.pipe(sill, 0.011, 8), mats.carbon)
	# The pilot, reclined, helmet back on the headrest.
	var hy: float = centre.call(0.62)
	m.place(HullMesh.rounded_box(Vector3(0.05, 0.2, 0.2), 0.03), mats.interior, Vector3(0.52, hy + 0.06, 0.0),
		Vector3(0, 0, 40))
	m.place(HullMesh.rounded_box(Vector3(0.34, 0.12, 0.26), 0.05), mats.suit, Vector3(0.74, hy - 0.02, 0.0),
		Vector3(0, 0, 18))
	var head := Vector3(0.6, hy + 0.11, 0.0)
	m.place(HullMesh.lathe(_ball(0.07, 10), 16), mats.helmet, head, Vector3(0, 0, 90))
	m.place(HullMesh.rounded_box(Vector3(0.04, 0.045, 0.11), 0.018), mats.visor, head + Vector3(0.055, 0.0, 0.0),
		Vector3(0, 0, 20))
	# Instruments under the windscreen.
	var dash: float = centre.call(1.12)
	m.place(HullMesh.rounded_box(Vector3(0.14, 0.05, 0.26), 0.02), mats.interior, Vector3(1.12, dash + 0.02, 0.0),
		Vector3(0, 0, 25))
	for z: float in [-0.07, 0.07]:
		m.place(HullMesh.rounded_box(Vector3(0.07, 0.004, 0.1), 0.002, 1), mats.cockpit,
			Vector3(1.1, dash + 0.05, z), Vector3(0, 0, 25))
	m.add_cockpit_light(Vector3(0.9, hy + 0.08, 0.0))
	# Grab handles on the spine behind the canopy.
	for sgn: float in [1.0, -1.0]:
		var gx := -0.05
		var gz := sgn * 0.12
		var gy := f.deck_y(gx, gz)
		m.place(HullMesh.pipe(PackedVector3Array([Vector3(gx - 0.08, gy - 0.01, gz), Vector3(gx - 0.06, gy + 0.03, gz),
			Vector3(gx + 0.06, gy + 0.03, gz), Vector3(gx + 0.08, gy - 0.01, gz)]), 0.008, 6, 0.02), mats.steel)


## The dorsal fin, the swept dive planes and the X-tail, all lit at the tips.
static func _fins(m: SubmarineModel, mats: Dictionary) -> void:
	var f := fairing()
	var fin := HullMesh.wing(Vector2(-0.05, -0.95), Vector2(-0.86, -1.08), 0.52, 0.1, 12, 22, 0.55, 3.0)
	var fin_y := f.deck_y(-0.5, 0.0) - 0.07
	m.place(fin, mats.trim, Vector3(0.0, fin_y, 0.0))
	m.strobe = m.place(HullMesh.lathe(_ball(0.022, 8), 12, 0.0), mats.strobe, Vector3(-0.98, fin_y + 0.505, 0.0))
	m.place(HullMesh.pipe(PackedVector3Array([Vector3(-1.0, fin_y + 0.3, 0.0), Vector3(-1.32, fin_y + 0.36, 0.0)]),
		0.004, 5), mats.carbon)
	# Dive planes: swept back and drooping, like a shark's pectorals.
	var plane := HullMesh.wing(Vector2(1.02, 0.48), Vector2(0.52, 0.36), 0.52, 0.09, 10, 20, 0.8, 1.0)
	for sgn: float in [1.0, -1.0]:
		var droop := deg_to_rad(14.0)
		var basis := Basis(Vector3.RIGHT, sgn * (PI * 0.5 + droop))
		var root_y := -0.13
		var root := Vector3(0.0, root_y, sgn * (f.side_z(0.75, root_y) - 0.05))
		m.place_xform(plane, mats.trim, Transform3D(basis, root))
		var tip := root + basis.y * 0.5 + Vector3(0.44, 0.0, 0.0)
		m.place(HullMesh.lathe(_ball(0.018, 8), 12, 0.0), mats.starboard if sgn > 0.0 else mats.port, tip)
	# X-tail round the pump-jet.
	var tail := HullMesh.wing(Vector2(-1.5, -2.02), Vector2(-1.86, -2.14), 0.44, 0.09, 10, 20, 0.7, 1.0)
	for k in 4:
		var basis := Basis(Vector3.RIGHT, PI * 0.25 + PI * 0.5 * k)
		m.place_xform(tail, mats.trim, Transform3D(basis, Vector3(0.0, JET.y, 0.0) + basis.y * 0.07))


## The main lamp's swing arm: hubs on both flanks of the snout and a yoke,
## painted like the hull, whose two arms reach round the nose and meet at
## the socket the lamp head fits in. It swings the lamp over, ahead of or
## under the nose, wherever the pilot aims.
static func _lamp_arm(m: SubmarineModel, mats: Dictionary) -> void:
	var f := fairing()
	var center := Vector3(1.95, -0.04, 0.0)
	var hub := f.side_z(center.x, center.y) + 0.018
	for sgn: float in [1.0, -1.0]:
		m.place(HullMesh.lathe(PackedVector2Array([Vector2(-0.03, 0.001), Vector2(-0.03, 0.06), Vector2(-0.02, 0.07),
			Vector2(0.01, 0.07), Vector2(0.02, 0.06), Vector2(0.02, 0.001)]), 20), mats.carbon,
			center + Vector3(0, 0, sgn * (hub - 0.012)), Vector3(0, -90 * sgn, 0))
	var reach := 0.43
	var track := m.add_lamp_track(center, PackedFloat32Array([reach]), -110.0, 110.0)
	for sgn: float in [1.0, -1.0]:
		var a := Vector3(0.0, 0.0, sgn * (hub + 0.012))
		var b := Vector3(reach - 0.045, 0.0, sgn * 0.05)
		var d := b - a
		m.place(HullMesh.rounded_box(Vector3(d.length() + 0.04, 0.045, 0.02), 0.009), mats.trim, (a + b) * 0.5,
			Vector3(0, rad_to_deg(atan2(-d.z, d.x)), 0), track)
		m.place(HullMesh.lathe(PackedVector2Array([Vector2(-0.012, 0.001), Vector2(-0.012, 0.04), Vector2(0.012, 0.04),
			Vector2(0.012, 0.001)]), 16), mats.ti, a, Vector3(0, 90, 0), track)
	m.place(HullMesh.rounded_box(Vector3(0.04, 0.05, 0.13), 0.012), mats.carbon, Vector3(reach - 0.03, 0, 0),
		Vector3.ZERO, track)


## The pump-jet: a shroud with a glowing nozzle lip round a hub, stator
## vanes and a many-bladed rotor.
static func _jet(m: SubmarineModel, mats: Dictionary) -> void:
	var y := JET.y
	m.place(HullMesh.lathe(PackedVector2Array([Vector2(-2.56, 0.15), Vector2(-2.42, 0.178), Vector2(-2.2, 0.197),
		Vector2(-2.03, 0.192), Vector2(-1.97, 0.18), Vector2(-1.955, 0.165), Vector2(-1.97, 0.152),
		Vector2(-2.08, 0.148), Vector2(-2.35, 0.143), Vector2(-2.53, 0.132), Vector2(-2.56, 0.138),
		Vector2(-2.56, 0.15)]), 40, 0.6), mats.carbon, Vector3(0, y, 0))
	m.place(HullMesh.lathe(PackedVector2Array([Vector2(-1.99, 0.17), Vector2(-1.975, 0.187), Vector2(-1.955, 0.19),
		Vector2(-1.94, 0.18), Vector2(-1.94, 0.155), Vector2(-1.955, 0.146), Vector2(-1.98, 0.146)]), 40, 0.4), mats.ti,
		Vector3(0, y, 0))
	m.place(HullMesh.lathe(PackedVector2Array([Vector2(-2.36, 0.18), Vector2(-2.35, 0.1885), Vector2(-2.26, 0.193),
		Vector2(-2.25, 0.185)]), 40, 0.0), mats.trim, Vector3(0, y, 0))
	m.place(HullMesh.lathe(PackedVector2Array([Vector2(-2.535, 0.128), Vector2(-2.54, 0.134), Vector2(-2.525, 0.136),
		Vector2(-2.52, 0.13)]), 40, 0.0), mats.jet, Vector3(0, y, 0))
	m.place(HullMesh.lathe(PackedVector2Array([Vector2(-2.52, 0.001), Vector2(-2.5, 0.035), Vector2(-2.42, 0.062),
		Vector2(-2.28, 0.085), Vector2(-2.12, 0.11), Vector2(-2.0, 0.125)]), 24), mats.carbon, Vector3(0, y, 0))
	for k in 7:
		var vane := HullMesh.wing(Vector2(0.04, -0.04), Vector2(0.04, -0.04), 0.06, 0.12, 2, 8)
		var basis := Basis(Vector3.RIGHT, TAU * k / 7.0)
		m.place_xform(vane, mats.carbon, Transform3D(basis, Vector3(-2.1, y, 0.0) + basis.y * 0.105))
	m.propeller.position = JET
	m.place(HullMesh.blades(9, 0.07, 0.142, 0.06, 0.45, 0.15), mats.steel, Vector3.ZERO, Vector3.ZERO, m.propeller)


## A lathe from [param profile] (as for HullMesh.lathe) squashed to an oval:
## [param sy] as tall and [param sz] as wide.
static func _oval_lathe(profile: PackedVector2Array, sy: float, sz: float, sides: int) -> ArrayMesh:
	var lengths := PackedFloat32Array([0.0])
	for k in range(1, profile.size()):
		lengths.append(lengths[k - 1] + profile[k].distance_to(profile[k - 1]))
	var total := lengths[lengths.size() - 1]
	var fn := func(u: float, v: float) -> Vector3:
		var target := u * total
		var k := 0
		while k < profile.size() - 2 and lengths[k + 1] < target:
			k += 1
		var p := profile[k].lerp(profile[k + 1], clampf((target - lengths[k]) / maxf(lengths[k + 1] - lengths[k],
			1e-9), 0.0, 1.0))
		var a := v * TAU
		return Vector3(p.x, cos(a) * p.y * sy, sin(a) * p.y * sz)
	return HullMesh.surface(fn, profile.size() * 4, sides, true)


## A sphere's profile for the lathe.
static func _ball(r: float, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in steps + 1:
		var a := PI * k / steps
		out.append(Vector2(-cos(a) * r, sin(a) * r + 0.0002))
	return out
