class_name WhisperBuild
extends RefCounted
## The Whisper, a stealth survey drone built of flat facets: a wedge of a
## hull with a flat belly, sloping sides that meet in sharp chines and a long
## raked chisel of a bow, all coated in anechoic tiles. A low faceted
## deckhouse carries the pilot behind smoked panes; violet light runs along
## each chine and wraps the bow in a sensor slit. A low canted V-tail, and a
## squared duct with a sawtooth lip round the pump-jet to quiet its wake. The
## lamp rides a single rail arched round the bow. Nose +X.

const PAINT_MAP := "res://assets/subs/whisper_paint.png"
const NORMAL_MAP := "res://assets/subs/whisper_normal.png"
## Hull stations, joined by straight runs: x, centre (chine) height, height
## above and below it, half-width, and how square the upper and lower halves
## are (the sloping sides are nearly flat; the belly is broad).
const STATIONS: Array = [
	[-1.8, 0.02, 0.12, 0.14, 0.2, 1.3, 2.4],
	[-1.45, 0.0, 0.24, 0.17, 0.42, 1.15, 2.4],
	[-0.6, -0.02, 0.32, 0.16, 0.6, 1.15, 2.4],
	[0.3, -0.02, 0.32, 0.16, 0.6, 1.15, 2.4],
	[1.05, -0.02, 0.26, 0.15, 0.48, 1.15, 2.4],
	[1.4, -0.02, 0.17, 0.12, 0.34, 1.2, 2.2],
	[1.95, -0.015, 0.012, 0.01, 0.04, 1.6, 2.0],
]
## The deckhouse's stations (body, then the smoked panes over the pilot).
const HOUSE: Array = [
	[0.0, 0.17, 0.05, 0.08, 0.05, 1.2, 2.0],
	[0.14, 0.17, 0.21, 0.08, 0.22, 1.1, 2.0],
	[0.55, 0.17, 0.26, 0.08, 0.26, 1.1, 2.0],
	[0.82, 0.16, 0.23, 0.08, 0.25, 1.1, 2.0],
]
const PANES: Array = [
	[0.82, 0.16, 0.23, 0.08, 0.25, 1.1, 2.0],
	[1.0, 0.14, 0.15, 0.08, 0.21, 1.1, 2.0],
	[1.18, 0.1, 0.03, 0.06, 0.06, 1.2, 2.0],
]
## The pump-jet's axis, and its squared duct's half-height and half-width.
const JET := Vector3(-1.95, 0.02, 0.0)
const DUCT := Vector2(0.15, 0.2)
## Where the lamp's rail is centred, and its radius.
const RAIL_CENTRE := Vector3(1.6, -0.01, 0.0)
const RAIL_R := 0.4
const RAIL_ENDS := 100.0

static var _hull: HullFairing


## Every Whisper has the same shape.
static func fairing() -> HullFairing:
	if _hull == null:
		_hull = HullFairing.new(STATIONS, 96, 72, true)
	return _hull


static func build(m: SubmarineModel) -> void:
	var hull := m.paint_material(ResourceLoader.exists(PAINT_MAP), true)
	if ResourceLoader.exists(PAINT_MAP):
		hull.set_shader_parameter(&"paint_map", load(PAINT_MAP))
		hull.set_shader_parameter(&"normal_tex", load(NORMAL_MAP))
	var trim := m.paint_material(false, true)
	# The fins and deckhouse carry no tile map: darkened to the coating's tone instead.
	trim.set_shader_parameter(&"darken", 0.68)
	var glass := m.glass_material()
	glass.albedo_color = Color(0.09, 0.07, 0.15, 0.62)
	glass.roughness = 0.02
	var mats := {
		"hull": hull, "trim": trim,
		"carbon": m.metal_material(Color(0.04, 0.04, 0.05), 0.25, 0.4, false),
		"ti": m.metal_material(Color(0.36, 0.37, 0.4), 0.8, 0.35, false),
		"steel": m.metal_material(Color(0.7, 0.71, 0.74), 0.95, 0.22, false),
		"interior": m.metal_material(Color(0.06, 0.06, 0.07), 0.2, 0.75, false),
		"suit": m.metal_material(Color(0.05, 0.05, 0.06), 0.0, 0.75, false),
		"helmet": m.metal_material(Color(0.16, 0.16, 0.19), 0.3, 0.35, false),
		"glass": glass,
		"cockpit": m.cockpit_material,
		"visor": MeshKit.emissive_material(Color(0.62, 0.42, 1.0), 1.2),
		"chine": MeshKit.emissive_material(Color(0.6, 0.42, 1.0), 2.6),
		"slit": MeshKit.emissive_material(Color(0.72, 0.5, 1.0), 4.0),
		"jet": MeshKit.emissive_material(Color(0.5, 0.36, 1.0), 2.2),
		"strobe": MeshKit.emissive_material(Color(0.7, 0.5, 1.0), 5.0),
	}
	if not m.restore(mats):
		_fairing(m, mats)
		_lights(m, mats)
		_deckhouse(m, mats)
		_fins(m, mats)
		_lamp_rail(m, mats)
		_jet(m, mats)
		m.remember(mats)


## Where equipment goes on the Whisper (see SubEquipment).
static func mounts() -> Dictionary:
	var f := fairing()
	var up := Vector3.UP
	var down := Vector3.DOWN
	var out := {}
	out[&"harpoon"] = SubEquipment.frame_at(Vector3(1.0, -0.1, f.side_z(1.0, -0.1) - 0.01), Vector3(0.0, -0.3, 1.0))
	out[&"sonar"] = SubEquipment.frame_at(Vector3(0.35, f.keel_y(0.35, 0.0) + 0.01, 0.0), down)
	out[&"shock"] = SubEquipment.frame_at(Vector3(0.95, f.keel_y(0.95, 0.0) + 0.01, 0.0), down)
	# The launchers ride the roof ridge behind the deckhouse.
	out[&"decoy"] = SubEquipment.frame_at(Vector3(-0.27, f.deck_y(-0.27, 0.0) - 0.01, 0.0), up)
	out[&"flare"] = SubEquipment.frame_at(Vector3(-0.78, f.deck_y(-0.78, 0.0) - 0.01, 0.0), up)
	var torpedo := SubEquipment.frame_at(Vector3(0.4, -0.1, f.side_z(0.4, -0.1) - 0.02), Vector3(0.0, -0.3, 1.0))
	out[&"torpedo"] = [torpedo, SubEquipment.mirror(torpedo)]
	out[&"drive"] = [f.mount(-1.5, 0.2), f.mount(-1.5, 0.8)]
	out[&"foil"] = [f.mount(0.1, 0.21), f.mount(0.1, 0.79)]
	var deck: Array = []
	for p: Vector2 in [Vector2(0.55, 0.37), Vector2(-0.35, 0.42), Vector2(-0.95, 0.42)]:
		deck.append_array([f.mount(p.x, p.y), f.mount(p.x, 1.0 - p.y)])
	out[&"deck"] = deck
	# Armour on the lower sides, under the chines.
	var flank: Array = []
	for x: float in [-1.1, -0.5, 0.1, 0.7]:
		flank.append_array([f.mount(x, 0.14), f.mount(x, 0.86)])
	out[&"flank"] = flank
	var belly: Array = []
	for x: float in [-1.15, -0.05, 1.0]:
		belly.append(SubEquipment.frame_at(Vector3(x, f.keel_y(x, 0.0) + 0.01, 0.0), down))
	out[&"belly"] = belly
	out[&"power"] = SubEquipment.frame_at(Vector3(-0.55, f.keel_y(-0.55, 0.0) + 0.01, 0.0), down)
	out[&"galvanic"] = Vector3(-1.35, 1.25, 0.08)
	return out


# --- Parts ---------------------------------------------------------------------------

static func _fairing(m: SubmarineModel, mats: Dictionary) -> void:
	var wear := func(u: float, _v: float) -> Color:
		return Color(1.0, 1.0 - 0.5 * smoothstep(0.05, 0.0, u), 1.0)
	m.place(fairing().mesh(wear), mats.hull)


## A faint light strip along each chine, and the sensor slit that wraps the
## bow, brighter.
static func _lights(m: SubmarineModel, mats: Dictionary) -> void:
	var f := fairing()
	for sgn: float in [1.0, -1.0]:
		var strip := PackedVector3Array()
		for k in 41:
			var x := lerpf(-1.62, 1.45, k / 40.0)
			var s := f.station(x)
			strip.append(Vector3(x, s[1], sgn * (s[4] + 0.002)))
		m.place(HullMesh.pipe(strip, 0.0075, 6), mats.chine)
	var slit := PackedVector3Array()
	for k in 25:
		var a := lerpf(-PI * 0.5, PI * 0.5, k / 24.0)
		var x := lerpf(1.52, 1.93, cos(a))
		var s := f.station(x)
		slit.append(Vector3(x + 0.004 * cos(a), s[1] + 0.003, sin(a) * (s[4] + 0.004)))
	m.place(HullMesh.pipe(slit, 0.009, 6), mats.slit)


## The deckhouse: a low faceted block on the roof, its front a run of smoked
## panes over the pilot, a dark floor beneath them, and a stub mast.
static func _deckhouse(m: SubmarineModel, mats: Dictionary) -> void:
	m.place(HullFairing.new(HOUSE, 24, 32, true).mesh(), mats.trim)
	m.place(HullFairing.new(PANES, 12, 32, true).mesh(), mats.glass)
	# A dark frame where the panes meet the body, over the top from chine to chine.
	var house := HullFairing.new(HOUSE, 24, 32, true)
	var joint := house.station(0.82)
	var frame := PackedVector3Array()
	for k in 17:
		var p := HullFairing.section_point(joint, lerpf(-0.08, PI + 0.08, k / 16.0))
		frame.append(Vector3(0.82, p.y, p.z) + (p - Vector3(0.0, joint[1], 0.0)).normalized() * 0.004)
	m.place(HullMesh.pipe(frame, 0.008, 6), mats.carbon)
	# A small sensor port in each flank of the deckhouse.
	for sgn: float in [1.0, -1.0]:
		var at := Vector3(0.48, 0.25, sgn * house.side_z(0.48, 0.25))
		var turn := Basis(Vector3.UP, -sgn * PI * 0.5) * Basis(Vector3.BACK, deg_to_rad(18.0))
		m.place_xform(HullMesh.lathe(PackedVector2Array([Vector2(-0.01, 0.026), Vector2(0.006, 0.026),
			Vector2(0.006, 0.018), Vector2(0.006, 0.018), Vector2(-0.002, 0.018)]), 16), mats.carbon,
			Transform3D(turn, at))
		m.place_xform(HullMesh.lathe(PackedVector2Array([Vector2(-0.002, 0.018), Vector2(0.002, 0.012),
			Vector2(0.004, 0.001)]), 16, 0.0), mats.visor, Transform3D(turn, at))
	var floor_rows: Array = []
	for row: Array in PANES:
		floor_rows.append([row[0], row[1] - 0.03, row[2] * 0.8, row[3], row[4] * 0.9, row[5], row[6]])
	m.place(HullFairing.new(floor_rows, 12, 24, true).mesh(), mats.interior)
	# The pilot, low in the seat, the helmet's visor glowing faintly.
	var head := Vector3(0.9, 0.28, 0.0)
	m.place(HullMesh.rounded_box(Vector3(0.3, 0.1, 0.22), 0.04), mats.suit, Vector3(0.78, 0.2, 0.0), Vector3(0, 0, 8))
	m.place(HullMesh.lathe(_ball(0.06, 10), 16), mats.helmet, head, Vector3(0, 0, 90))
	m.place(HullMesh.rounded_box(Vector3(0.03, 0.03, 0.09), 0.012), mats.visor, head + Vector3(0.05, 0.005, 0.0),
		Vector3(0, 0, 18))
	for z: float in [-0.06, 0.06]:
		m.place(HullMesh.rounded_box(Vector3(0.05, 0.004, 0.06), 0.002, 1), mats.cockpit, Vector3(1.0, 0.2, z),
			Vector3(0, 0, 30))
	m.add_cockpit_light(Vector3(0.95, 0.3, 0.0), Color(0.62, 0.48, 1.0))
	# The stub mast at the back of the deckhouse, a dim strobe on top.
	var base := Vector3(0.3, 0.38, 0.0)
	m.place(_facet_loft(base, base + Vector3(-0.08, 0.14, 0.0), 0.12, 0.05, 0.022, 0.012, Vector3.RIGHT, Vector3.BACK),
		mats.trim)
	m.strobe = m.place(HullMesh.lathe(_ball(0.015, 8), 12, 0.0), mats.strobe, base + Vector3(-0.085, 0.145, 0.0))
	m.place(HullMesh.pipe(PackedVector3Array([base + Vector3(-0.05, 0.1, 0.0), base + Vector3(-0.3, 0.13, 0.0)]),
		0.0035, 5), mats.carbon)


## The low V-tail, canted out over the stern, coated like the deckhouse.
static func _fins(m: SubmarineModel, mats: Dictionary) -> void:
	var f := fairing()
	for sgn: float in [1.0, -1.0]:
		var cant := Basis(Vector3.RIGHT, -sgn * deg_to_rad(42.0))
		var root := Vector3(-1.3, f.deck_y(-1.3, 0.16) - 0.02, sgn * 0.16)
		var tip := root + cant * Vector3(-0.16, 0.26, 0.0)
		m.place(_facet_loft(root, tip, 0.36, 0.12, 0.026, 0.01, Vector3.RIGHT, cant * Vector3.BACK), mats.trim)


## The lamp's rail: one slim rail arched round the bow from chin to brow on
## a pylon at each end, and a carriage riding it.
static func _lamp_rail(m: SubmarineModel, mats: Dictionary) -> void:
	var f := fairing()
	var rail := PackedVector3Array()
	for k in 33:
		var a := deg_to_rad(lerpf(-RAIL_ENDS, RAIL_ENDS, k / 32.0))
		rail.append(RAIL_CENTRE + Vector3(cos(a) * RAIL_R, sin(a) * RAIL_R, 0.0))
	m.place(_facet_tube(rail, 0.016, 0.011), mats.carbon)
	for sgn: float in [1.0, -1.0]:
		var a := deg_to_rad(RAIL_ENDS) * sgn
		var tip := RAIL_CENTRE + Vector3(cos(a), sin(a), 0.0) * RAIL_R
		var fx := 1.36
		var foot := Vector3(fx, f.deck_y(fx, 0.0) - 0.01 if sgn > 0.0 else f.keel_y(fx, 0.0) + 0.01, 0.0)
		m.place(_facet_loft(foot, tip, 0.05, 0.03, 0.014, 0.01, Vector3.RIGHT, Vector3.BACK, false), mats.carbon)
	m.add_lamp_track(RAIL_CENTRE, PackedFloat32Array([RAIL_R + 0.035]), -RAIL_ENDS, RAIL_ENDS)
	var shoe := m.lamp_socket
	m.place(HullMesh.rounded_box(Vector3(0.04, 0.09, 0.05), 0.012), mats.carbon, Vector3(-0.022, 0, 0), Vector3.ZERO,
		shoe)
	for y: float in [-0.03, 0.03]:
		m.place(HullMesh.lathe(PackedVector2Array([Vector2(-0.01, 0.001), Vector2(-0.01, 0.012), Vector2(0.01, 0.012),
			Vector2(0.01, 0.001)]), 10), mats.ti, Vector3(-0.052, y, 0.0), Vector3(0, 90, 0), shoe)


## The pump-jet in a squared duct, coated outside and bare inside, its
## trailing lip cut into a sawtooth; a faint violet ring, stator vanes and a
## many-bladed rotor within.
static func _jet(m: SubmarineModel, mats: Dictionary) -> void:
	m.place(_squircle_lathe(PackedVector2Array([Vector2(-2.24, 0.93), Vector2(-2.16, 1.0), Vector2(-2.0, 1.03),
		Vector2(-1.86, 1.0), Vector2(-1.8, 0.94)])), mats.trim)
	m.place(_squircle_lathe(PackedVector2Array([Vector2(-1.8, 0.94), Vector2(-1.82, 0.86), Vector2(-1.98, 0.84),
		Vector2(-2.16, 0.85), Vector2(-2.24, 0.88), Vector2(-2.24, 0.93)])), mats.carbon)
	m.place(_squircle_lathe(PackedVector2Array([Vector2(-2.07, 0.835), Vector2(-2.12, 0.835)])), mats.jet)
	for k in 18:
		var a := TAU * (k + 0.5) / 18.0
		var p := _squircle(a) * 0.935
		var out := Vector3(0.0, p.x * DUCT.x, p.y * DUCT.y).normalized()
		var lip := Vector3(-2.238, JET.y + p.x * DUCT.x, p.y * DUCT.y)
		m.place(_facet_loft(lip, lip + Vector3(-0.04, 0, 0) + out * 0.003, 0.026, 0.0, 0.007, 0.002,
			out.cross(Vector3.RIGHT), out), mats.carbon)
	m.place(HullMesh.lathe(PackedVector2Array([Vector2(-2.16, 0.001), Vector2(-2.14, 0.025), Vector2(-2.04, 0.05),
		Vector2(-1.9, 0.07), Vector2(-1.8, 0.075)]), 20), mats.carbon, Vector3(0, JET.y, 0))
	for k in 6:
		var vane := HullMesh.wing(Vector2(0.03, -0.03), Vector2(0.03, -0.03), 0.06, 0.12, 2, 8)
		var basis := Basis(Vector3.RIGHT, TAU * k / 6.0)
		m.place_xform(vane, mats.carbon, Transform3D(basis, Vector3(-1.86, JET.y, 0.0) + basis.y * 0.07))
	m.propeller.position = JET + Vector3(-0.1, 0, 0)
	m.place(HullMesh.blades(11, 0.05, 0.118, 0.045, 0.4, 0.2), mats.ti, Vector3.ZERO, Vector3.ZERO, m.propeller)


## A point round the duct's squared section at angle [param a]: (up, out), each -1..1.
static func _squircle(a: float) -> Vector2:
	var cs := cos(a)
	var sn := sin(a)
	return Vector2(signf(sn) * pow(absf(sn), 2.0 / 3.2), signf(cs) * pow(absf(cs), 2.0 / 3.2))


## A body of revolution like HullMesh.lathe, but round the duct's squared
## section ([param profile] radii scale it).
static func _squircle_lathe(profile: PackedVector2Array) -> ArrayMesh:
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
		var q := _squircle(v * TAU)
		return Vector3(p.x, JET.y + q.x * p.y * DUCT.x, q.y * p.y * DUCT.y)
	# As with HullMesh.lathe, the outside is on the left of travel: a profile
	# running towards +X faces away from the axis, one running back faces in.
	var at := fn.call(0.02, 0.2) as Vector3
	var du := (fn.call(0.03, 0.2) as Vector3) - (fn.call(0.01, 0.2) as Vector3)
	var dv := (fn.call(0.02, 0.21) as Vector3) - (fn.call(0.02, 0.19) as Vector3)
	var faces_out := du.cross(dv).dot(at - Vector3(at.x, JET.y, 0.0)) > 0.0
	var wants_out := profile[1].x > profile[0].x
	return HullMesh.surface(fn, profile.size() * 4, 48, faces_out != wants_out)


## A faceted blade lofted from [param a] to [param b]: each section a diamond
## [param chord] across along [param along] and [param thick] through along
## [param across] (eased from the first value to the second); it closes to an
## edge at [param b] unless [param open].
static func _facet_loft(a: Vector3, b: Vector3, chord_a: float, chord_b: float, thick_a: float, thick_b: float,
		along: Vector3, across: Vector3, close := true) -> ArrayMesh:
	var fn := func(u: float, v: float) -> Vector3:
		var k := 1.0 - (smoothstep(0.86, 1.0, u) * 0.96 if close else 0.0)
		var c := a.lerp(b, u)
		var ch := lerpf(chord_a, chord_b, u) * 0.5 * k
		var th := lerpf(thick_a, thick_b, u) * 0.5 * k
		var ang := v * TAU
		var cs := cos(ang)
		var sn := sin(ang)
		return c + along * ch * signf(cs) * cs * cs + across * th * signf(sn) * sn * sn
	var p := fn.call(0.5, 0.25) as Vector3
	var du := (fn.call(0.52, 0.25) as Vector3) - (fn.call(0.48, 0.25) as Vector3)
	var dv := (fn.call(0.5, 0.27) as Vector3) - (fn.call(0.5, 0.23) as Vector3)
	var flip := du.cross(dv).dot(p - a.lerp(b, 0.5)) < 0.0
	return HullMesh.surface(fn, 10, 8, flip)


## A rail along [param points] with a squarish section, [param w] wide and
## [param h] deep (w across the path in the plane it turns in).
static func _facet_tube(points: PackedVector3Array, w: float, h: float) -> ArrayMesh:
	var fn := func(u: float, v: float) -> Vector3:
		var t := u * (points.size() - 1)
		var k := mini(int(t), points.size() - 2)
		var p := points[k].lerp(points[k + 1], t - k)
		var d := (points[k + 1] - points[k]).normalized()
		var side := Vector3.BACK
		var out := d.cross(side).normalized()
		var ang := v * TAU
		var cs := cos(ang)
		var sn := sin(ang)
		return p + out * h * 0.5 * signf(cs) * pow(absf(cs), 0.6) + side * w * 0.5 * signf(sn) * pow(absf(sn), 0.6)
	var p := fn.call(0.5, 0.25) as Vector3
	var du := (fn.call(0.51, 0.25) as Vector3) - (fn.call(0.49, 0.25) as Vector3)
	var dv := (fn.call(0.5, 0.27) as Vector3) - (fn.call(0.5, 0.23) as Vector3)
	var mid := points[points.size() / 2]
	var flip := du.cross(dv).dot(p - mid) < 0.0
	return HullMesh.surface(fn, points.size() * 2, 8, flip)


## A sphere's profile for the lathe.
static func _ball(r: float, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in steps + 1:
		var a := PI * k / steps
		out.append(Vector2(-cos(a) * r, sin(a) * r + 0.0002))
	return out
