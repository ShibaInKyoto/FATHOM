class_name LanternBuild
extends RefCounted
## The Lantern, the deep research submersible every pilot starts in: a
## painted fairing over a titanium crew sphere that looks out through an
## acrylic bow dome, a lamp bar over the dome and a searchlight on the deck,
## a sample basket and a folded manipulator under the bow, battery pods and a
## skid frame below, and a ducted main thruster in a cruciform tail with two
## lateral thrusters and a vertical one let into the deck. Nose along +X.

const PAINT_MAP := "res://assets/subs/lantern_paint.png"
const NORMAL_MAP := "res://assets/subs/lantern_normal.png"
## Fairing stations: x, centre height, height above and below the centre,
## half-width, and how square the upper and lower halves are (2 is round).
const STATIONS: Array = [
	[-2.0, 0.1, 0.16, 0.16, 0.17, 2.0, 2.0],
	[-1.8, 0.13, 0.33, 0.3, 0.34, 2.2, 2.3],
	[-1.4, 0.19, 0.47, 0.45, 0.5, 2.5, 2.8],
	[-0.8, 0.23, 0.51, 0.53, 0.6, 2.7, 3.2],
	[0.0, 0.24, 0.51, 0.54, 0.62, 2.7, 3.2],
	[0.55, 0.23, 0.49, 0.53, 0.61, 2.6, 3.0],
	[0.9, 0.18, 0.45, 0.5, 0.58, 2.3, 2.5],
	[1.1, 0.13, 0.42, 0.46, 0.54, 2.0, 2.0],
]
## The bow dome and its collar are centred on this height.
const BOW_Y := 0.06
## The main thruster's axis.
const STERN := Vector3(-2.2, 0.1, 0.0)
## Status lights on the cockpit wall.
const LEDS: Array[Color] = [Color(1.0, 0.25, 0.1), Color(0.2, 1.0, 0.4), Color(1.0, 0.7, 0.1), Color(0.2, 0.8, 1.0)]

static var _hull: HullFairing


## Every Lantern has the same shape.
static func fairing() -> HullFairing:
	if _hull == null:
		_hull = HullFairing.new(STATIONS)
	return _hull


static func build(m: SubmarineModel) -> void:
	var hull := m.paint_material(ResourceLoader.exists(PAINT_MAP))
	if ResourceLoader.exists(PAINT_MAP):
		hull.set_shader_parameter(&"paint_map", load(PAINT_MAP))
		hull.set_shader_parameter(&"normal_tex", load(NORMAL_MAP))
	var trim := m.paint_material(false)
	var mats := {
		"hull": hull, "trim": trim,
		"frame": m.metal_material(Color(0.075, 0.08, 0.085), 0.35, 0.5, true),
		"ti": m.metal_material(Color(0.5, 0.51, 0.53), 0.85, 0.3, false),
		"steel": m.metal_material(Color(0.78, 0.79, 0.8), 0.95, 0.2, false),
		"rubber": m.metal_material(Color(0.03, 0.03, 0.033), 0.0, 0.85, false),
		"safety": m.metal_material(Color(0.95, 0.32, 0.04), 0.1, 0.45, true),
		"interior": m.metal_material(Color(0.11, 0.12, 0.13), 0.2, 0.7, false),
		"suit": m.metal_material(Color(0.16, 0.22, 0.32), 0.0, 0.8, false),
		"skin": m.metal_material(Color(0.62, 0.46, 0.36), 0.0, 0.6, false),
		"lens": MeshKit.emissive_material(Color(1.0, 0.94, 0.78), 5.0),
		"glass": m.glass_material(),
		"cockpit": m.cockpit_material,
		"strobe": MeshKit.emissive_material(Color.WHITE, 8.0),
		"port": MeshKit.emissive_material(Color(1.0, 0.12, 0.08), 6.0),
		"starboard": MeshKit.emissive_material(Color(0.15, 1.0, 0.35), 6.0),
		"stern_light": MeshKit.emissive_material(Color(1.0, 0.95, 0.85), 5.0),
	}
	for i in LEDS.size():
		mats["led%d" % i] = MeshKit.emissive_material(LEDS[i], 3.0)
	if not m.restore(mats):
		_build_parts(m, mats)
		m.remember(mats)


static func _build_parts(m: SubmarineModel, mats: Dictionary) -> void:
	_fairing(m, mats)
	_conduits(m, mats)
	_bow(m, mats)
	_lamps(m, mats)
	_deck(m, mats)
	_underside(m, mats)
	_arm(m, mats)
	_stern(m, mats)


## Where equipment goes on the Lantern (see SubEquipment).
static func mounts() -> Dictionary:
	var f := fairing()
	var up := Vector3.UP
	var out := {}
	out[&"lamp"] = SubEquipment.frame_at(Vector3(1.2, BOW_Y + 0.692, 0.0), up)
	out[&"sonar"] = SubEquipment.frame_at(Vector3(0.62, f.deck_y(0.62, 0.0) - 0.01, 0.0), up)
	out[&"harpoon"] = SubEquipment.frame_at(Vector3(0.86, -0.36, 0.52), Vector3(0.0, -0.2, 1.0))
	out[&"flare"] = SubEquipment.frame_at(Vector3(-0.74, f.deck_y(-0.74, 0.0) - 0.01, 0.0), up)
	out[&"decoy"] = f.mount(-1.28, 0.38)
	out[&"shock"] = SubEquipment.frame_at(Vector3(1.52, -0.59, 0.0), up)
	var torpedo := SubEquipment.frame_at(Vector3(-0.25, -0.36, 0.53), Vector3(0.0, -0.3, 1.0))
	out[&"torpedo"] = [torpedo, SubEquipment.mirror(torpedo)]
	out[&"drive"] = [f.mount(-1.62, 0.12), f.mount(-1.62, 0.88)]
	out[&"foil"] = [f.mount(0.55, 0.08), f.mount(0.55, 0.92)]
	var deck: Array = []
	for p: Vector2 in [Vector2(0.85, 0.43), Vector2(-0.3, 0.41), Vector2(-0.95, 0.36)]:
		deck.append_array([f.mount(p.x, p.y), f.mount(p.x, 1.0 - p.y)])
	out[&"deck"] = deck
	var flank: Array = []
	for x: float in [-1.2, -0.6, 0.0, 0.6]:
		flank.append_array([f.mount(x, 0.12), f.mount(x, 0.88)])
	out[&"flank"] = flank
	var belly: Array = []
	for x: float in [-0.85, -0.3, 0.25]:
		belly.append(SubEquipment.frame_at(Vector3(x, -0.6, 0.0), Vector3.DOWN))
	out[&"belly"] = belly
	return out


# --- Parts ---------------------------------------------------------------------------

static func _fairing(m: SubmarineModel, mats: Dictionary) -> void:
	# A little grime where the fairing meets the duct and the collar.
	var wear := func(u: float, _v: float) -> Color:
		return Color(1.0, 1.0 - 0.6 * (smoothstep(0.04, 0.0, u) + smoothstep(0.96, 1.0, u)), 1.0)
	m.place(fairing().mesh(wear), mats.hull)


## Cable runs along both sides of the fairing, clamped down every so often.
static func _conduits(m: SubmarineModel, mats: Dictionary) -> void:
	for v: float in [0.17, 0.83]:
		var pts := PackedVector3Array()
		var x := -1.45
		while x <= 0.86:
			pts.append(fairing().on_skin(x, v, 0.018))
			x += 0.1
		m.place(HullMesh.pipe(pts, 0.012, 8), mats.rubber)
		m.place(HullMesh.pipe(_offset(pts, Vector3(0, 0.03, 0)), 0.008, 6), mats.steel)
		x = -1.4
		while x <= 0.85:
			var at := fairing().on_skin(x, v, 0.016)
			var nrm := (fairing().on_skin(x, v, 0.05) - at).normalized()
			var mi := m.place(HullMesh.rounded_box(Vector3(0.03, 0.075, 0.03), 0.01), mats.frame, at + Vector3(0, 0.012, 0))
			mi.basis = Basis.looking_at(nrm, Vector3.UP)
			x += 0.35


static func _offset(pts: PackedVector3Array, by: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in pts:
		out.append(p + by)
	return out


## The crew sphere's titanium collar, the bolted acrylic dome in it, and the
## cockpit seen through the dome: a pilot, a seat and a console of screens.
static func _bow(m: SubmarineModel, mats: Dictionary) -> void:
	var at := Vector3(0.0, BOW_Y, 0.0)
	m.place(HullMesh.lathe(PackedVector2Array([
		Vector2(0.9, 0.48), Vector2(0.98, 0.555), Vector2(1.01, 0.575), Vector2(1.04, 0.58), Vector2(1.21, 0.58),
		Vector2(1.24, 0.572), Vector2(1.26, 0.55), Vector2(1.265, 0.52), Vector2(1.265, 0.52), Vector2(1.265, 0.49),
		Vector2(1.265, 0.49), Vector2(1.3, 0.49), Vector2(1.31, 0.48), Vector2(1.31, 0.455)]), 48), mats.ti, at)
	# A rubber gasket where the collar meets the fairing.
	m.place(HullMesh.lathe(PackedVector2Array([Vector2(0.995, 0.56), Vector2(1.0, 0.586), Vector2(1.012, 0.59),
		Vector2(1.024, 0.586), Vector2(1.03, 0.56)]), 48), mats.rubber, at)
	m.place(HullMesh.bolt_ring(20, 0.505, 0.012), mats.steel, at + Vector3(1.265, 0.0, 0.0))
	# The dome: one smooth sheet, slightly proud of a sphere.
	var dome := PackedVector2Array()
	for k in 17:
		var a := PI * 0.5 * k / 16.0
		dome.append(Vector2(1.3 + 0.5 * sin(a), 0.47 * cos(a) + 0.0005))
	m.place(HullMesh.lathe(dome, 48, 0.0), mats.glass, at)
	# Inside: the sphere's dark wall and its rim, a console and a pilot.
	m.place(HullMesh.lathe(PackedVector2Array([Vector2(1.3, 0.47), Vector2(1.0, 0.47), Vector2(0.9, 0.36),
		Vector2(0.86, 0.001)]), 32), mats.interior, at)
	var console := HullMesh.rounded_box(Vector3(0.16, 0.07, 0.62), 0.02)
	m.place(console, mats.interior, at + Vector3(1.3, -0.2, 0.0), Vector3(0, 0, 35))
	for z: float in [-0.19, 0.0, 0.19]:
		var screen := HullMesh.rounded_box(Vector3(0.11, 0.006, 0.15), 0.003, 1)
		m.place(screen, mats.cockpit, at + Vector3(1.29, -0.16, z), Vector3(0, 0, 35))
	m.place(HullMesh.rounded_box(Vector3(0.07, 0.46, 0.4), 0.03), mats.interior, at + Vector3(0.95, -0.02, 0.0),
		Vector3(0, 0, -8))
	m.place(HullMesh.rounded_box(Vector3(0.2, 0.3, 0.32), 0.09), mats.suit, at + Vector3(1.04, -0.08, 0.0),
		Vector3(0, 0, -10))
	# Arms out to the console.
	for side: float in [-1.0, 1.0]:
		var shoulder := at + Vector3(1.04, 0.03, side * 0.14)
		var elbow := at + Vector3(1.12, -0.12, side * 0.18)
		var hand := at + Vector3(1.25, -0.12, side * 0.13)
		m.place(HullMesh.pipe(PackedVector3Array([shoulder, elbow, hand]), 0.035, 8, 0.05), mats.suit)
		m.place(HullMesh.lathe(_ball(0.03, 6), 8), mats.skin, hand + Vector3(0.02, 0.0, 0.0))
	m.place(HullMesh.lathe(_ball(0.075, 10), 14), mats.skin, at + Vector3(1.07, 0.15, 0.0), Vector3(0, 0, 90))
	m.place(HullMesh.lathe(_cap(0.08, 8), 14), mats.suit, at + Vector3(1.065, 0.165, 0.0), Vector3(0, 0, 90))
	m.place(HullMesh.rounded_box(Vector3(0.03, 0.026, 0.12), 0.012, 1), mats.interior, at + Vector3(1.135, 0.16, 0.0))
	m.place(HullMesh.pipe(PackedVector3Array([at + Vector3(1.06, 0.13, 0.085), at + Vector3(1.06, 0.24, 0.0),
		at + Vector3(1.06, 0.13, -0.085)]), 0.008, 6, 0.06), mats.interior)
	for side: float in [-1.0, 1.0]:
		m.place(HullMesh.rounded_box(Vector3(0.05, 0.06, 0.025), 0.01), mats.interior,
			at + Vector3(1.06, 0.14, side * 0.085))
	# Status lights on the sphere wall.
	for i in LEDS.size():
		var a := 0.9 + i * 0.18
		m.place(HullMesh.lathe(_ball(0.008, 4), 6, 0.0), mats["led%d" % i],
			at + Vector3(1.12, sin(a) * 0.44, cos(a) * 0.44))
	m.add_cockpit_light(at + Vector3(1.2, 0.05, 0.0))


## A lamp bar over the dome and the searchlight on its yoke on the deck.
static func _lamps(m: SubmarineModel, mats: Dictionary) -> void:
	# A ring of lamps arched over the dome on a tube frame.
	var ring_r := 0.67
	var arc := PackedVector3Array()
	for k in 13:
		var a := deg_to_rad(lerpf(-62.0, 62.0, k / 12.0))
		arc.append(Vector3(1.2, BOW_Y + cos(a) * ring_r, sin(a) * ring_r))
	m.place(HullMesh.pipe(arc, 0.022, 10), mats.frame)
	for a_deg: float in [-62.0, 0.0, 62.0]:
		var a := deg_to_rad(a_deg)
		var out := Vector3(0.0, cos(a), sin(a))
		m.place(HullMesh.pipe(PackedVector3Array([Vector3(1.12, BOW_Y, 0.0) + out * 0.575,
			Vector3(1.2, BOW_Y, 0.0) + out * ring_r]), 0.016, 8), mats.frame)
	for a_deg: float in [-44.0, -22.0, 0.0, 22.0, 44.0]:
		var a := deg_to_rad(a_deg)
		var at := Vector3(1.22, BOW_Y + cos(a) * (ring_r + 0.005), sin(a) * (ring_r + 0.005))
		_lamp_head(m, mats, at, 0.042, Vector3(-a_deg * 0.3, 0, -10))


## A lamp housing facing +X (before [param rot_deg]); a big one gets cooling fins.
static func _lamp_head(m: SubmarineModel, mats: Dictionary, at: Vector3, r: float, rot_deg: Vector3,
		big := false) -> void:
	var back := -r * (2.2 if big else 1.2)
	m.place(HullMesh.lathe(PackedVector2Array([Vector2(back, 0.001), Vector2(back, r * 0.6), Vector2(back + r * 0.2,
		r * 0.9), Vector2(back + r * 0.5, r), Vector2(r * 0.25, r), Vector2(r * 0.35, r * 1.08), Vector2(r * 0.42, r * 1.08),
		Vector2(r * 0.45, r * 0.98), Vector2(r * 0.45, r * 0.85), Vector2(r * 0.45, r * 0.85),
		Vector2(r * 0.3, r * 0.85)]), 24), mats.frame, at, rot_deg)
	m.place(HullMesh.lathe(PackedVector2Array([Vector2(r * 0.28, r * 0.86), Vector2(r * 0.36, r * 0.6),
		Vector2(r * 0.38, 0.001)]), 24, 0.0), mats.lens, at, rot_deg)
	if big:
		for k in 5:
			var x := back + r * (0.45 + 0.28 * k)
			m.place(HullMesh.lathe(PackedVector2Array([Vector2(x - 0.006, r * 0.98), Vector2(x - 0.006, r * 1.18),
				Vector2(x + 0.006, r * 1.18), Vector2(x + 0.006, r * 0.98)]), 24), mats.frame, at, rot_deg)


## The sail with its hatch, the mast, the lifting bail, grab rails and the
## vertical thruster let into the deck.
static func _deck(m: SubmarineModel, mats: Dictionary) -> void:
	var sail_y := fairing().deck_y(-0.15, 0.0)
	m.place(HullMesh.rounded_box(Vector3(0.82, 0.3, 0.5), 0.13, 4), mats.trim, Vector3(-0.17, sail_y + 0.06, 0.0))
	var top := sail_y + 0.21
	# Hatch: a domed lid on a ring, its hinge and handwheel.
	m.place(HullMesh.lathe(PackedVector2Array([Vector2(-0.02, 0.2), Vector2(0.015, 0.2), Vector2(0.025, 0.19),
		Vector2(0.025, 0.17), Vector2(0.025, 0.17), Vector2(0.04, 0.16), Vector2(0.055, 0.1), Vector2(0.06, 0.001)]), 32),
		mats.ti, Vector3(-0.08, top, 0.0), Vector3(0, 0, 90))
	m.place(HullMesh.rounded_box(Vector3(0.1, 0.05, 0.16), 0.015), mats.ti, Vector3(-0.3, top + 0.02, 0.0))
	m.place(HullMesh.lathe(_torus(0.07, 0.008, 10), 24), mats.steel, Vector3(-0.08, top + 0.085, 0.0),
		Vector3(0, 0, 90))
	for a: float in [0.0, PI * 0.5]:
		m.place(HullMesh.pipe(PackedVector3Array([Vector3(-0.08 - cos(a) * 0.07, top + 0.085, -sin(a) * 0.07),
			Vector3(-0.08 + cos(a) * 0.07, top + 0.085, sin(a) * 0.07)]), 0.005, 6), mats.steel)
	# Mast: strobe, whip antenna and a GPS puck.
	var foot := Vector3(-0.45, top - 0.02, 0.0)
	var head := Vector3(-0.52, top + 0.48, 0.0)
	m.place(HullMesh.pipe(PackedVector3Array([foot, head]), 0.022, 10), mats.frame)
	m.place(HullMesh.lathe(PackedVector2Array([Vector2(-0.02, 0.04), Vector2(0.0, 0.04), Vector2(0.0, 0.04),
		Vector2(0.0, 0.03), Vector2(0.06, 0.03), Vector2(0.075, 0.015), Vector2(0.08, 0.001)]), 16), mats.frame, head,
		Vector3(0, 0, 90))
	m.strobe = m.place(HullMesh.lathe(_ball(0.028, 8), 12, 0.0), mats.strobe,
		head + Vector3(0, 0.06, 0))
	m.place(HullMesh.pipe(PackedVector3Array([head + Vector3(0.0, 0.02, 0.0), head + Vector3(-0.08, 0.42, 0.0)]),
		0.005, 6), mats.frame)
	m.place(HullMesh.pipe(PackedVector3Array([foot.lerp(head, 0.6), foot.lerp(head, 0.6) + Vector3(0.1, 0, 0)]),
		0.008, 6), mats.frame)
	m.place(HullMesh.lathe(PackedVector2Array([Vector2(-0.01, 0.035), Vector2(0.01, 0.035), Vector2(0.02, 0.025),
		Vector2(0.025, 0.001)]), 16), mats.trim, foot.lerp(head, 0.6) + Vector3(0.12, 0.0, 0.0), Vector3(0, 0, 90))
	# Lifting bail across the deck ahead of the sail.
	var bx := 0.32
	var by := fairing().deck_y(bx, 0.36)
	m.place(HullMesh.pipe(PackedVector3Array([Vector3(bx, by - 0.02, 0.36), Vector3(bx, by + 0.3, 0.3),
		Vector3(bx, by + 0.3, -0.3), Vector3(bx, by - 0.02, -0.36)]), 0.026, 12, 0.12), mats.safety)
	for z: float in [0.34, -0.34]:
		m.place(HullMesh.rounded_box(Vector3(0.12, 0.05, 0.1), 0.015), mats.frame, Vector3(bx, by, z))
	# Grab rails on stanchions along both sides of the deck.
	for z: float in [0.38, -0.38]:
		var rail := PackedVector3Array()
		var posts: Array[float] = [-1.35, -1.0, -0.65]
		for x in posts:
			var y := fairing().deck_y(x, z)
			m.place(HullMesh.pipe(PackedVector3Array([Vector3(x, y - 0.02, z), Vector3(x, y + 0.09, z)]), 0.012, 8),
				mats.steel)
			rail.append(Vector3(x, y + 0.09, z))
		m.place(HullMesh.pipe(PackedVector3Array([rail[0], rail[1], rail[2]]), 0.014, 8, 0.05), mats.steel)
	# The vertical thruster: a grille over a duct in the deck.
	var vt := Vector3(-1.08, fairing().deck_y(-1.08, 0.0) - 0.035, 0.0)
	m.place(_duct(0.19, 0.155, 0.1), mats.frame, vt, Vector3(0, 0, 90))
	for k in 5:
		var z := -0.12 + 0.06 * k
		var half := sqrt(maxf(0.155 * 0.155 - z * z, 0.0))
		m.place(HullMesh.rounded_box(Vector3(half * 2.0, 0.012, 0.012), 0.005, 1), mats.steel,
			vt + Vector3(0, 0.03, z))
	var vprop := m.add_prop(vt, Vector3(0, 0, 90))
	m.place(HullMesh.blades(4, 0.04, 0.14, 0.07, 0.6), mats.steel, Vector3.ZERO, Vector3.ZERO, vprop)


## Battery pods, the frame and skids, and the sample basket at the bow.
static func _underside(m: SubmarineModel, mats: Dictionary) -> void:
	var pod := PackedVector2Array()
	for k in 7:
		var a := PI * 0.5 * (1.0 - k / 6.0)
		pod.append(Vector2(-1.15 - sin(a) * 0.16, cos(a) * 0.16 + 0.0005))
	for k in 7:
		var a := PI * 0.5 * k / 6.0
		pod.append(Vector2(0.72 + sin(a) * 0.16, cos(a) * 0.16 + 0.0005))
	var pod_mesh := HullMesh.lathe(pod, 28, 0.4)
	for z: float in [0.29, -0.29]:
		var at := Vector3(0.0, -0.45, z)
		m.place(pod_mesh, mats.frame, at)
		for x: float in [-0.75, -0.1, 0.45]:
			m.place(HullMesh.lathe(PackedVector2Array([Vector2(x - 0.03, 0.16), Vector2(x - 0.025, 0.168),
				Vector2(x + 0.025, 0.168), Vector2(x + 0.03, 0.16)]), 28), mats.steel, at)
		m.place(HullMesh.bolt_ring(8, 0.09, 0.01), mats.steel, at + Vector3(0.86, 0.0, 0.0))
	# Frame: longerons under the fairing, posts down to the skids.
	for z: float in [0.5, -0.5]:
		m.place(HullMesh.rounded_box(Vector3(2.55, 0.055, 0.055), 0.012), mats.frame, Vector3(-0.3, -0.32, z))
		for x: float in [-1.3, -0.3, 0.7]:
			m.place(HullMesh.rounded_box(Vector3(0.07, 0.6, 0.065), 0.014), mats.frame, Vector3(x, -0.63, z))
			# A bracket up into the fairing.
			m.place(HullMesh.rounded_box(Vector3(0.09, 0.2, 0.04), 0.012), mats.frame, Vector3(x, -0.24, z * 0.94))
		for pair: Array in [[-1.3, -0.3], [-0.3, 0.7]]:
			m.place(HullMesh.pipe(PackedVector3Array([Vector3(pair[0], -0.36, z), Vector3(pair[1], -0.9, z)]), 0.014,
				8), mats.frame)
		# Skid with an upturned toe, on rubber shoes.
		m.place(HullMesh.rounded_box(Vector3(2.7, 0.06, 0.09), 0.02), mats.frame, Vector3(-0.25, -0.95, z))
		var toe := Vector3(1.22, -0.86, z)
		m.place(HullMesh.rounded_box(Vector3(0.3, 0.06, 0.09), 0.02), mats.frame, toe, Vector3(0, 0, 36))
		for x: float in [-1.35, -0.3, 0.75]:
			m.place(HullMesh.rounded_box(Vector3(0.22, 0.035, 0.1), 0.012), mats.rubber, Vector3(x, -0.995, z))
		m.place(HullMesh.rounded_box(Vector3(0.08, 0.04, 0.03), 0.01), mats.ti, Vector3(-0.8, -0.95, z * 1.12))
	# Cross members.
	for x: float in [-1.3, 0.7]:
		m.place(HullMesh.rounded_box(Vector3(0.05, 0.05, 1.0), 0.012), mats.frame, Vector3(x, -0.92, 0.0))
	# Sample basket: a frame of bars over a mesh floor, out front on the skids.
	var b0 := Vector3(0.98, -0.8, -0.4)
	var b1 := Vector3(1.6, -0.6, 0.4)
	var bar := 0.011
	for y: float in [b0.y, b1.y]:
		for z: float in [b0.z, b1.z]:
			m.place(HullMesh.pipe(PackedVector3Array([Vector3(b0.x, y, z), Vector3(b1.x, y, z)]), bar, 6), mats.frame)
		for x: float in [b0.x, b1.x]:
			m.place(HullMesh.pipe(PackedVector3Array([Vector3(x, y, b0.z), Vector3(x, y, b1.z)]), bar, 6), mats.frame)
	for x: float in [b0.x, b1.x]:
		for z: float in [b0.z, b1.z]:
			m.place(HullMesh.pipe(PackedVector3Array([Vector3(x, b0.y, z), Vector3(x, b1.y, z)]), bar, 6), mats.frame)
	for k in 7:
		var z := lerpf(b0.z, b1.z, (k + 0.5) / 7.0)
		m.place(HullMesh.pipe(PackedVector3Array([Vector3(b0.x, b0.y, z), Vector3(b1.x, b0.y, z)]), 0.005, 4),
			mats.steel)
	for k in 5:
		var x := lerpf(b0.x, b1.x, (k + 0.5) / 5.0)
		for z: float in [b0.z, b1.z]:
			m.place(HullMesh.pipe(PackedVector3Array([Vector3(x, b0.y, z), Vector3(x, b1.y, z)]), 0.005, 4),
				mats.steel)
	# A sample jar and a rock in the basket.
	m.place(HullMesh.lathe(PackedVector2Array([Vector2(0.0, 0.001), Vector2(0.0, 0.045), Vector2(0.11, 0.045),
		Vector2(0.11, 0.045), Vector2(0.11, 0.03), Vector2(0.13, 0.03), Vector2(0.13, 0.001)]), 14), mats.safety,
		Vector3(1.32, -0.79, 0.15), Vector3(0, 0, 90))
	m.place(HullMesh.lathe(_ball(0.06, 8), 9), mats.frame, Vector3(1.45, -0.76, -0.18), Vector3(20, 30, 0))


## The manipulator, folded over the basket on the near side.
static func _arm(m: SubmarineModel, mats: Dictionary) -> void:
	# On the far side: the harpoon has the near one.
	var s := -1.0
	var z := 0.43 * s
	var base := Vector3(0.9, -0.36, z)
	var shoulder := Vector3(0.98, -0.45, z)
	var elbow := Vector3(1.5, -0.33, z)
	var wrist := Vector3(1.35, -0.6, z)
	m.place(HullMesh.lathe(PackedVector2Array([Vector2(-0.06, 0.09), Vector2(0.05, 0.09), Vector2(0.06, 0.08),
		Vector2(0.06, 0.001)]), 20), mats.frame, base, Vector3(0, 0, -90))
	for joint: Vector3 in [shoulder, elbow, wrist]:
		m.place(HullMesh.lathe(PackedVector2Array([Vector2(-0.045, 0.001), Vector2(-0.045, 0.055),
			Vector2(-0.04, 0.062), Vector2(0.04, 0.062), Vector2(0.045, 0.055), Vector2(0.045, 0.001)]), 20),
			mats.ti, joint, Vector3(0, 90, 0))
	_link(m, mats.safety, shoulder, elbow, 0.075, 0.06)
	_link(m, mats.safety, elbow, wrist, 0.06, 0.05)
	# Hydraulic ram along the upper arm: a cylinder and a polished rod.
	var ram0 := shoulder + Vector3(0.05, 0.08, 0.04 * s)
	var ram1 := shoulder.lerp(elbow, 0.75) + Vector3(0.0, 0.06, 0.04 * s)
	var mid := ram0.lerp(ram1, 0.55)
	m.place(HullMesh.pipe(PackedVector3Array([ram0, mid]), 0.022, 10), mats.frame)
	m.place(HullMesh.pipe(PackedVector3Array([mid, ram1]), 0.011, 8), mats.steel)
	# A hose looping from the base along the arm.
	m.place(HullMesh.pipe(PackedVector3Array([base + Vector3(-0.05, 0.02, 0.06 * s),
		shoulder + Vector3(-0.08, 0.1, 0.07 * s), shoulder.lerp(elbow, 0.5) + Vector3(0, 0.08, 0.06 * s),
		elbow + Vector3(0.05, 0.06, 0.05 * s)]), 0.01, 6, 0.08), mats.rubber)
	# The claw: a wrist block and two curled jaws pointing down into the basket.
	var hand := wrist + Vector3(0.02, -0.08, 0.0)
	m.place(HullMesh.rounded_box(Vector3(0.07, 0.08, 0.08), 0.02), mats.ti, hand)
	for side: float in [-1.0, 1.0]:
		var p0 := hand + Vector3(side * 0.03, -0.03, 0.0)
		var p1 := p0 + Vector3(side * 0.04, -0.06, 0.0)
		var p2 := p1 + Vector3(-side * 0.025, -0.05, 0.0)
		m.place(HullMesh.pipe(PackedVector3Array([p0, p1, p2]), 0.012, 8, 0.03), mats.steel)


## A boxy arm link from [param a] to [param b], thicker at [param a].
static func _link(m: SubmarineModel, mat: Material, a: Vector3, b: Vector3, h0: float, h1: float) -> void:
	var d := b - a
	var mesh := HullMesh.rounded_box(Vector3(d.length(), (h0 + h1) * 0.5, 0.05), 0.02)
	m.place(mesh, mat, (a + b) * 0.5, Vector3(0, 0, rad_to_deg(atan2(d.y, d.x))))


## The main thruster in its duct with stator vanes, the cruciform tail with
## running lights, and the lateral thrusters on their pylons.
static func _stern(m: SubmarineModel, mats: Dictionary) -> void:
	# The fairing tapers into a shaft housing that carries the propeller.
	m.place(HullMesh.lathe(PackedVector2Array([Vector2(-2.13, 0.001), Vector2(-2.13, 0.07), Vector2(-2.13, 0.07),
		Vector2(-2.1, 0.1), Vector2(-2.04, 0.14), Vector2(-1.96, 0.16)]), 24), mats.frame, Vector3(0, STERN.y, 0))
	m.place(_duct(0.36, 0.31, 0.42), mats.frame, STERN + Vector3(0.0, 0.0, 0.0))
	# A safety-orange band round the duct's lip.
	m.place(HullMesh.lathe(PackedVector2Array([Vector2(-0.01, 0.35), Vector2(0.0, 0.3635), Vector2(0.1, 0.3655),
		Vector2(0.11, 0.35)]), 48, 0.0), mats.safety, STERN)
	for k in 4:
		var vane := HullMesh.wing(Vector2(0.05, -0.05), Vector2(0.05, -0.05), 0.25, 0.1, 3, 12)
		var basis := Basis(Vector3.RIGHT, TAU * (k + 0.5) / 4.0)
		m.place_xform(vane, mats.frame, Transform3D(basis, STERN + Vector3(0.12, 0.0, 0.0) + basis.y * 0.065))
	m.propeller.position = STERN + Vector3(-0.02, 0.0, 0.0)
	m.place(HullMesh.blades(5, 0.075, 0.3, 0.16, 0.8), mats.steel, Vector3.ZERO, Vector3.ZERO, m.propeller)
	m.place(HullMesh.lathe(PackedVector2Array([Vector2(-0.16, 0.001), Vector2(-0.14, 0.03), Vector2(-0.1, 0.06),
		Vector2(-0.04, 0.078), Vector2(0.06, 0.078), Vector2(0.06, 0.07), Vector2(0.06, 0.001)]), 24), mats.ti,
		Vector3.ZERO, Vector3.ZERO, m.propeller)
	# Tail: a fin up top and stabilisers either side, their tips lit.
	var fin := HullMesh.wing(Vector2(-1.42, -1.98), Vector2(-1.78, -2.06), 0.44, 0.1)
	m.place(fin, mats.trim, Vector3(0.0, fairing().deck_y(-1.7, 0.0) - 0.08, 0.0))
	var stab := HullMesh.wing(Vector2(-1.45, -2.0), Vector2(-1.76, -2.05), 0.5, 0.1)
	for sgn: float in [1.0, -1.0]:
		var basis := Basis(Vector3.RIGHT, sgn * PI * 0.5)
		m.place_xform(stab, mats.trim, Transform3D(basis, Vector3(0.0, 0.12, sgn * 0.22)))
		var tip := Vector3(-1.92, 0.12, sgn * 0.73)
		m.place(HullMesh.lathe(_ball(0.03, 8), 12), mats.frame, tip)
		m.place(HullMesh.lathe(_ball(0.022, 8), 12, 0.0), mats.starboard if sgn > 0.0 else mats.port,
			tip + Vector3(0.0, 0.0, sgn * 0.016))
	var fin_tip := Vector3(-1.98, fairing().deck_y(-1.7, 0.0) + 0.35, 0.0)
	m.place(HullMesh.lathe(_ball(0.022, 8), 12, 0.0), mats.stern_light, fin_tip)
	# Lateral thrusters on pylons either side, their own props turning.
	for sgn: float in [1.0, -1.0]:
		var at := Vector3(-1.2, 0.02, sgn * 0.82)
		m.place(_duct(0.17, 0.145, 0.22), mats.frame, at)
		m.place(HullMesh.lathe(PackedVector2Array([Vector2(-0.04, 0.16), Vector2(-0.035, 0.1715), Vector2(0.04, 0.172),
			Vector2(0.045, 0.16)]), 32, 0.0), mats.safety, at)
		var basis := Basis(Vector3.RIGHT, sgn * PI * 0.5)
		var pylon := HullMesh.wing(Vector2(-1.08, -1.32), Vector2(-1.1, -1.3), 0.18, 0.16, 4, 16)
		m.place_xform(pylon, mats.trim, Transform3D(basis, Vector3(0.0, 0.02, sgn * 0.5)))
		m.place(HullMesh.lathe(PackedVector2Array([Vector2(-0.12, 0.001), Vector2(-0.1, 0.03), Vector2(-0.06, 0.045),
			Vector2(0.08, 0.045), Vector2(0.1, 0.03), Vector2(0.11, 0.001)]), 16), mats.frame, at)
		for k in 3:
			var vane := HullMesh.wing(Vector2(0.03, -0.03), Vector2(0.03, -0.03), 0.1, 0.12, 2, 8)
			var vb := Basis(Vector3.RIGHT, TAU * k / 3.0 + 0.5)
			m.place_xform(vane, mats.frame, Transform3D(vb, at + Vector3(0.07, 0.0, 0.0) + vb.y * 0.04))
		var prop := m.add_prop(at + Vector3(-0.03, 0.0, 0.0), Vector3.ZERO)
		m.place(HullMesh.blades(4, 0.04, 0.14, 0.08, 0.5), mats.steel, Vector3.ZERO, Vector3.ZERO, prop)


## A thruster duct round the X axis: an airfoil ring of outer radius
## [param outer] and inner [param inner], [param length] long, centred on 0.
static func _duct(outer: float, inner: float, length: float) -> ArrayMesh:
	var h := length * 0.5
	var t := outer - inner
	return HullMesh.lathe(PackedVector2Array([
		Vector2(-h, inner + t * 0.55), Vector2(-h * 0.4, outer - t * 0.08), Vector2(h * 0.55, outer),
		Vector2(h * 0.85, outer - t * 0.1), Vector2(h, outer - t * 0.45), Vector2(h * 0.96, inner + t * 0.15),
		Vector2(h * 0.8, inner), Vector2(-h * 0.6, inner + t * 0.02), Vector2(-h, inner + t * 0.3),
		Vector2(-h, inner + t * 0.55)]), 48, 0.8)


## A sphere's profile for the lathe.
static func _ball(r: float, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in steps + 1:
		var a := PI * k / steps
		out.append(Vector2(-cos(a) * r, sin(a) * r + 0.0002))
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
