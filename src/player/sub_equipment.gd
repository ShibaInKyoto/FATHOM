class_name SubEquipment
extends RefCounted
## The kit hung on a submarine, the way gear piles onto a character in a
## roguelite: the lamp head on its track, the harpoon launcher, the frame's
## own tool, and a piece for every module card taken in the run, each with a
## small light in its card's colour. Stacking a card changes its piece again.
## Only module cards change the kit, never hangar upgrades, so it grows over
## a run and looks the same at every start. Pieces go onto the mount points
## the frame provides (SubmarineModel.mounts); each is built in its mount's
## frame, Y out of the hull and X towards the bow.

const HULL := Color(1.0, 0.55, 0.3)
const POWER := Color(1.0, 0.9, 0.3)
const LIGHT := Color(1.0, 1.0, 0.8)
const SONAR := Color(0.3, 0.95, 1.0)
const WEAPON := Color(1.0, 0.35, 0.35)
const UTIL := Color(0.6, 1.0, 0.6)

var m: SubmarineModel
var root: Node3D
## The frame's own tools, before any card.
var tools: Array[StringName]
var modules: Array[StringName]
var mats := {}
## Free mount points left in each row, taken front to back.
var _free := {}


## Fits [param model] with its frame's kit and a piece for each of
## [param cards] (module ids, one per card taken, so stacks repeat).
static func fit(model: SubmarineModel, cards: Array[StringName]) -> void:
	var kit := SubEquipment.new()
	kit.m = model
	kit.root = model.equipment_root()
	kit.tools = SubStats.build(model.frame(), {}, []).tools
	kit.modules = cards
	kit._build()
	model.finish_equipment()


## A frame at [param at] with Y along [param normal] and X towards the bow.
static func frame_at(at: Vector3, normal: Vector3) -> Transform3D:
	var y := normal.normalized()
	var fwd := Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.UP
	var x := (fwd - y * y.dot(fwd)).normalized()
	return Transform3D(Basis(x, y, x.cross(y)), at)


## Mount points for a frame built without its own (rough, from its size).
static func default_mounts(length: float, radius: float) -> Dictionary:
	var h := length * 0.5
	var out := {}
	out[&"harpoon"] = frame_at(Vector3(h * 0.55, -radius * 0.6, radius * 0.75), Vector3(0, -0.4, 1))
	out[&"flare"] = frame_at(Vector3(-h * 0.3, radius * 0.95, 0.0), Vector3.UP)
	out[&"decoy"] = frame_at(Vector3(-h * 0.6, radius * 0.8, 0.0), Vector3.UP)
	out[&"shock"] = frame_at(Vector3(h * 0.6, -radius * 0.95, 0.0), Vector3.DOWN)
	out[&"sonar"] = frame_at(Vector3(h * 0.1, radius, 0.0), Vector3.UP)
	out[&"torpedo"] = _pair(frame_at(Vector3(h * 0.2, -radius * 0.5, radius * 0.85), Vector3(0, -0.3, 1)))
	out[&"drive"] = _pair(frame_at(Vector3(-h * 0.75, 0.0, radius * 0.8), Vector3.BACK))
	out[&"foil"] = _pair(frame_at(Vector3(h * 0.3, -radius * 0.5, radius * 0.8), Vector3(0, -0.5, 1)))
	var deck: Array = []
	for x: float in [0.3, -0.1, -0.5]:
		deck.append_array(_pair(frame_at(Vector3(x * h, radius * 0.85, radius * 0.4), Vector3(0, 1, 0.5))))
	out[&"deck"] = deck
	var flank: Array = []
	for x: float in [-0.5, -0.1, 0.3]:
		flank.append_array(_pair(frame_at(Vector3(x * h, -radius * 0.2, radius * 0.95), Vector3.BACK)))
	out[&"flank"] = flank
	var belly: Array = []
	for x: float in [-0.4, 0.0, 0.4]:
		belly.append(frame_at(Vector3(x * h, -radius, 0.0), Vector3.DOWN))
	out[&"belly"] = belly
	return out


## [param t] and its mirror across the centreline.
static func _pair(t: Transform3D) -> Array:
	return [t, mirror(t)]


static func mirror(t: Transform3D) -> Transform3D:
	var flip := Vector3(1.0, 1.0, -1.0)
	return frame_at(t.origin * flip, t.basis.y * flip)


func _build() -> void:
	_materials()
	for row: StringName in [&"deck", &"flank", &"belly"]:
		_free[row] = (m.mounts.get(row, []) as Array).duplicate()
	_lamp()
	_harpoon()
	_sonar()
	if tools.has(&"flare") or _n(&"flare_kit") > 0:
		_flares()
	if tools.has(&"torpedo") or _n(&"torpedo_kit") > 0:
		_torpedoes()
	if tools.has(&"decoy") or _n(&"decoy_kit") > 0:
		_decoys()
	if tools.has(&"shock"):
		_shock()
	_armour()
	_power()
	_drive()
	_utilities()


func _materials() -> void:
	mats = {
		"paint": m.paint_material(false),
		"metal": m.metal_material(Color(0.085, 0.09, 0.095), 0.6, 0.45, true),
		"steel": m.metal_material(Color(0.78, 0.79, 0.8), 0.95, 0.2, false),
		"brass": m.metal_material(Color(0.76, 0.56, 0.27), 1.0, 0.32, false),
		"copper": m.metal_material(Color(0.86, 0.45, 0.27), 1.0, 0.28, false),
		"rubber": m.metal_material(Color(0.03, 0.03, 0.033), 0.0, 0.85, false),
		"ceramic": m.metal_material(Color(0.9, 0.89, 0.84), 0.0, 0.18, false),
		"iron": m.metal_material(Color(0.2, 0.2, 0.21), 0.75, 0.55, true),
		"olive": m.metal_material(Color(0.2, 0.235, 0.16), 0.25, 0.6, true),
		"safety": m.metal_material(Color(0.95, 0.32, 0.04), 0.1, 0.45, true),
		"canister": m.metal_material(Color(0.98, 0.62, 0.08), 0.15, 0.4, true),
		"warhead": m.metal_material(Color(0.95, 0.72, 0.08), 0.2, 0.4, true),
		"crate": m.metal_material(Color(0.46, 0.4, 0.28), 0.0, 0.8, true),
		"ink": m.metal_material(Color(0.03, 0.025, 0.04), 0.2, 0.08, false),
		"glass": m.glass_material(),
		"lens": MeshKit.emissive_material(Color(1.0, 0.94, 0.78), 6.0),
		"lens_cold": MeshKit.emissive_material(Color(0.75, 0.9, 1.0), 6.0),
		"flare_glow": MeshKit.emissive_material(Color(1.0, 0.3, 0.2), 2.5),
		"bio": MeshKit.emissive_material(Color(0.35, 1.0, 0.45), 2.5),
		"boost": MeshKit.emissive_material(Color(1.0, 0.55, 0.2), 2.5),
		"arc": MeshKit.emissive_material(Color(0.45, 0.85, 1.0), 3.0),
		"beacon": MeshKit.emissive_material(Color(1.0, 0.6, 0.1), 5.0),
		"cockpit_sonar": MeshKit.emissive_material(Color(0.25, 0.9, 0.8), 2.2),
	}
	for c: Color in [HULL, POWER, LIGHT, SONAR, WEAPON, UTIL]:
		mats[c.to_html()] = MeshKit.emissive_material(c, 3.0)


# --- Helpers -------------------------------------------------------------------------

func _n(id: StringName) -> int:
	return modules.count(id)


func _mount(id: StringName) -> Variant:
	return m.mounts.get(id)


## The next free mount in [param row], or null when the row is full.
func _take(row: StringName) -> Variant:
	var free: Array = _free.get(row, [])
	return free.pop_front() if not free.is_empty() else null


## Takes a pair of mounts (near and far side) from [param row].
func _take_pair(row: StringName) -> Array:
	var a: Variant = _take(row)
	var b: Variant = _take(row)
	var out: Array = []
	for t: Variant in [a, b]:
		if t != null:
			out.append(t)
	return out


## Adds [param mesh] at [param local] in [param mount]'s frame.
func _put(mesh: Mesh, mat: String, mount: Transform3D, local := Transform3D.IDENTITY,
		parent: Node3D = null) -> MeshInstance3D:
	return m.place_xform(mesh, mats[mat], mount * local, parent if parent else root)


## A small light in a card's colour.
func _led(mount: Transform3D, at: Vector3, color: Color, size := 0.012, parent: Node3D = null) -> void:
	_put(HullMesh.lathe(_ball(size, 6), 8, 0.0), color.to_html(), mount, Transform3D(Basis(), at), parent)


static func _at(pos: Vector3, rot_deg := Vector3.ZERO) -> Transform3D:
	return Transform3D(Basis.from_euler(rot_deg * PI / 180.0), pos)


## Stands along Y (a lathe built along X), at [param pos].
static func _stand(pos: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3.BACK, PI * 0.5), pos)


# --- The lamp ------------------------------------------------------------------------

## The lamp head, fitted into the socket at the end of the frame's lamp
## track: a fork holding the head on a swivel, its lens facing out along the
## track. Its three cards each change it, and again at their second stack:
## a Halogen Core runs a long focusing barrel out to the lens with a
## white-hot core in it (and a focusing collar at two); a Wide-Angle Lens
## flares a reflector hood round the lens (opening into four barn doors at
## two); a Cold-Light Lamp turns the lens blue-white and rings the body with
## heat-sink fins (and winds a copper coolant coil round it at two).
func _lamp() -> void:
	var socket := m.lamp_tilt
	if socket == null:
		return
	var halogen := mini(_n(&"long_lamp"), 2)
	var wide := mini(_n(&"wide_lens"), 2)
	var cold := mini(_n(&"cold_lamp"), 2)
	var r := 0.075
	var body := r * 1.5
	var head := Node3D.new()
	head.name = "LampHead"
	socket.add_child(head)
	var here := Transform3D.IDENTITY
	# The fork: a block on the carriage and two arms out to the swivel's pins.
	var pin := 0.03 + body * 0.55
	var span := r + 0.03
	_put(HullMesh.rounded_box(Vector3(0.05, span * 2.0 + 0.03, 0.06), 0.012), "metal", here,
		_at(Vector3(0.02, 0, 0)), head)
	for sgn: float in [-1.0, 1.0]:
		_put(HullMesh.rounded_box(Vector3(pin, 0.022, 0.05), 0.008), "metal", here,
			_at(Vector3(0.02 + pin * 0.5, sgn * span, 0)), head)
	var swivel := Node3D.new()
	swivel.position = Vector3(0.03 + pin, 0, 0)
	head.add_child(swivel)
	_put(HullMesh.pipe(PackedVector3Array([Vector3(0, -span - 0.015, 0), Vector3(0, span + 0.015, 0)]), 0.012, 8),
		"steel", here, Transform3D.IDENTITY, swivel)
	var back := -body * 0.55
	var front := body * 0.45
	# The housing: a finned can, open at the front.
	_put(HullMesh.lathe(PackedVector2Array([Vector2(back, 0.001), Vector2(back, r * 0.6), Vector2(back + r * 0.2,
		r * 0.9), Vector2(back + r * 0.5, r), Vector2(front - r * 0.2, r), Vector2(front - r * 0.1, r * 1.08),
		Vector2(front - r * 0.03, r * 1.08), Vector2(front, r * 0.98), Vector2(front, r * 0.85), Vector2(front, r * 0.85),
		Vector2(front - r * 0.15, r * 0.85)]), 24), "metal", here, Transform3D.IDENTITY, swivel)
	for k in 2:
		var x := back + r * (0.45 + 0.28 * k)
		_put(HullMesh.lathe(PackedVector2Array([Vector2(x - 0.005, r * 0.98), Vector2(x - 0.005, r * 1.2),
			Vector2(x + 0.005, r * 1.2), Vector2(x + 0.005, r * 0.98)]), 24), "metal", here, Transform3D.IDENTITY, swivel)
	var lens_at := front
	var lens_r := r * 0.86
	if halogen > 0:
		# A focusing barrel out to the lens, longer at two stacks, the core glowing white down it.
		var reach := r * (0.75 + 0.55 * (halogen - 1))
		var br := r * 0.78
		_put(HullMesh.lathe(PackedVector2Array([Vector2(front - r * 0.15, br), Vector2(front + reach, br),
			Vector2(front + reach + r * 0.06, br * 1.1), Vector2(front + reach + r * 0.12, br * 1.1),
			Vector2(front + reach + r * 0.12, br * 0.86), Vector2(front + reach + r * 0.12, br * 0.86),
			Vector2(front + reach, br * 0.86)]), 24), "steel", here, Transform3D.IDENTITY, swivel)
		_put(HullMesh.lathe(_ball(r * (0.24 + 0.08 * halogen), 8), 12, 0.0), LIGHT.to_html(), here,
			_at(Vector3(front - r * 0.05, 0, 0)), swivel)
		if halogen >= 2:
			_put(HullMesh.lathe(PackedVector2Array([Vector2(front + reach * 0.4, br * 1.02), Vector2(front + reach * 0.4,
				br * 1.12), Vector2(front + reach * 0.5, br * 1.12), Vector2(front + reach * 0.5, br * 1.02)]), 24), "brass",
				here, Transform3D.IDENTITY, swivel)
		lens_at = front + reach + r * 0.1
		lens_r = br * 0.88
	_put(HullMesh.lathe(PackedVector2Array([Vector2(lens_at - r * 0.17, lens_r), Vector2(lens_at - r * 0.09,
		lens_r * 0.7), Vector2(lens_at - r * 0.07, 0.001)]), 24, 0.0), "lens_cold" if cold > 0 else "lens", here,
		Transform3D.IDENTITY, swivel)
	if wide > 0:
		# A reflector hood flaring out round the lens; at two stacks, four barn doors on it.
		var mouth := lens_r * (1.7 + 0.3 * wide)
		var deep := r * (0.5 + 0.15 * wide)
		_put(HullMesh.lathe(PackedVector2Array([Vector2(lens_at - r * 0.12, lens_r * 1.14), Vector2(lens_at + deep,
			mouth), Vector2(lens_at + deep + 0.006, mouth - 0.01), Vector2(lens_at - r * 0.1, lens_r * 1.04)]), 24),
			"steel", here, Transform3D.IDENTITY, swivel)
		if wide >= 2:
			for k in 4:
				var a := TAU * k / 4.0 + PI * 0.25
				var dir := Vector3(0.0, cos(a), sin(a))
				var hinge := Vector3(lens_at + deep, 0, 0) + dir * mouth
				var door := Basis(dir.cross(Vector3.RIGHT).normalized(), deg_to_rad(-35.0))
				var mi := _put(HullMesh.rounded_box(Vector3(r * 0.55, 0.005, mouth * 0.7), 0.002, 1), "steel", here,
					Transform3D.IDENTITY, swivel)
				var flat := Basis(Vector3.RIGHT, a)
				mi.transform = Transform3D(door * flat, hinge + door * flat * Vector3(r * 0.27, 0, 0))
	if cold > 0:
		# Heat-sink fins round the body; at two stacks, a copper coolant coil wound over them.
		for k in 8:
			var a := TAU * k / 8.0
			var out := Vector3(0.0, cos(a), sin(a))
			var mi := _put(HullMesh.rounded_box(Vector3(body * 0.75, r * 0.32, 0.006), 0.002, 1), "steel", here,
				Transform3D.IDENTITY, swivel)
			mi.transform = Transform3D(Basis(Vector3.RIGHT, a), Vector3(back * 0.15, 0, 0) + out * r * 1.12)
		if cold >= 2:
			var coil := PackedVector3Array()
			for k in 49:
				var a := TAU * 3.0 * k / 48.0
				coil.append(Vector3(lerpf(back + r * 0.3, front - r * 0.3, k / 48.0), cos(a) * r * 1.34, sin(a) * r * 1.34))
			_put(HullMesh.pipe(coil, 0.007, 6), "copper", here, Transform3D.IDENTITY, swivel)
	_led(here, Vector3(back + 0.012, 0, r * 0.75), SONAR if cold > 0 else LIGHT, 0.008, swivel)
	var lens := Node3D.new()
	lens.position = Vector3(lens_at, 0, 0)
	swivel.add_child(lens)
	m.merge_under(swivel)
	m.merge_under(head)
	m.set_lamp_head(head, swivel, lens)


## A plain lamp arm for a frame built without its own track: a hub at the
## nose of a hull [param length] long and [param radius] round, and an arm
## swinging out from it.
static func default_track(model: SubmarineModel, length: float, radius: float) -> void:
	var mat := model.metal_material(Color(0.085, 0.09, 0.095), 0.6, 0.45, true)
	var center := Vector3(length * 0.5 + 0.05, 0.0, 0.0)
	model.place(HullMesh.lathe(PackedVector2Array([Vector2(-0.05, 0.001), Vector2(-0.05, 0.07), Vector2(0.05, 0.07),
		Vector2(0.05, 0.001)]), 16), mat, center + Vector3(0, 0, radius * 0.5), Vector3(0, 90, 0))
	var reach := radius * 0.8 + 0.1
	var track := model.add_lamp_track(center, PackedFloat32Array([reach]))
	model.place(HullMesh.pipe(PackedVector3Array([Vector3(0, 0, radius * 0.5), Vector3(reach * 0.6, 0, radius * 0.3),
		Vector3(reach, 0, 0.0)]), 0.025, 8, 0.08), mat, Vector3.ZERO, Vector3.ZERO, track)


# --- The harpoon ---------------------------------------------------------------------

## The harpoon launcher: a pneumatic gun on a pedestal, its loaded spear's
## head at the muzzle, an air tank under the barrel and a reel of cable at
## the breech. Its cards each change it, and again as they stack: Serrated
## Harpoon rakes barbs round the head (a second row at two, a saw-toothed
## muzzle at three); Twin Reel adds a second drum and a cable guide (a winch
## motor and a longer barrel at two); a Galvanic Barb turns the head copper
## behind an insulator, wired to a capacitor (a copper coil round the barrel
## and a lit muzzle at two); Glass Cannon mounts a glass accumulator glowing
## red over the barrel, with red vents along it. The loaded spear is the one
## that flies, so what the harpoon throws matches what it carries.
func _harpoon() -> void:
	var mount: Variant = _mount(&"harpoon")
	if mount == null:
		return
	# The main weapon: drawn a size up so it reads at a glance.
	mount = (mount as Transform3D).scaled_local(Vector3.ONE * 1.35)
	var serrated := mini(_n(&"serrated"), 3)
	var reels := mini(_n(&"twin_reel"), 2)
	var galvanic := mini(_n(&"leech"), 2)
	var glass := _n(&"glass_cannon") > 0
	var h := 0.1
	var muzzle := 0.24 + (0.08 if reels >= 2 else 0.0)
	# Base plate, pedestal and breech.
	_put(HullMesh.rounded_box(Vector3(0.2, 0.025, 0.11), 0.008), "metal", mount, _at(Vector3(-0.02, 0.012, 0)))
	_put(HullMesh.rounded_box(Vector3(0.08, 0.07, 0.07), 0.015), "metal", mount, _at(Vector3(-0.04, 0.055, 0)))
	_put(HullMesh.rounded_box(Vector3(0.09, 0.075, 0.07), 0.018), "metal", mount, _at(Vector3(-0.14, h, 0)))
	# The barrel, open at the muzzle, a ring round its mouth.
	_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.1, 0.026), Vector2(muzzle - 0.03, 0.026),
		Vector2(muzzle - 0.025, 0.035), Vector2(muzzle, 0.035), Vector2(muzzle, 0.018), Vector2(muzzle, 0.018),
		Vector2(muzzle - 0.06, 0.018)]), 18), "metal", mount, _at(Vector3(0, h, 0)))
	# The air tank under it, a brass gauge on its side.
	_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.13, 0.001), Vector2(-0.12, 0.018), Vector2(-0.1, 0.021),
		Vector2(0.1, 0.021), Vector2(0.12, 0.018), Vector2(0.13, 0.001)]), 14), "steel", mount,
		_at(Vector3(0.0, h - 0.048, 0)))
	_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.004, 0.016), Vector2(0.006, 0.016), Vector2(0.006, 0.001)]), 12),
		"brass", mount, _at(Vector3(-0.06, h - 0.048, 0.02), Vector3(0, -90, 0)))
	for x: float in [-0.08, 0.08]:
		_put(HullMesh.rounded_box(Vector3(0.016, 0.07, 0.05), 0.005, 1), "metal", mount, _at(Vector3(x, h - 0.03, 0)))
	# The reel: a drum of cable on the breech's side, a second on the other for Twin Reel.
	var drum_r := 0.046 + (0.012 if reels >= 2 else 0.0)
	for k in 1 + mini(reels, 1):
		var z := 0.075 if k == 0 else -0.075
		var spin := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-0.14, h, z))
		_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.022, 0.001), Vector2(-0.022, drum_r), Vector2(-0.016, drum_r),
			Vector2(-0.016, drum_r * 0.6), Vector2(0.016, drum_r * 0.6), Vector2(0.016, drum_r), Vector2(0.022, drum_r),
			Vector2(0.022, 0.001)]), 20), "metal", mount, spin)
		_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.016, drum_r * 0.6), Vector2(-0.015, drum_r * 0.85),
			Vector2(0.015, drum_r * 0.85), Vector2(0.016, drum_r * 0.6)]), 20), "rubber", mount, spin)
	if reels >= 1:
		# A cable guide over the breech: a sheave on a little arch.
		_put(HullMesh.pipe(PackedVector3Array([Vector3(-0.17, h + 0.035, -0.04), Vector3(-0.15, h + 0.08, 0.0),
			Vector3(-0.17, h + 0.035, 0.04)]), 0.006, 6, 0.03), "steel", mount)
		_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.008, 0.001), Vector2(-0.008, 0.02), Vector2(0.008, 0.02),
			Vector2(0.008, 0.001)]), 12), "steel", mount, Transform3D(Basis(Vector3.UP, PI * 0.5),
			Vector3(-0.15, h + 0.07, 0.0)))
	if reels >= 2:
		# The winch motor behind the drums.
		var motor := _at(Vector3(-0.22, h, 0))
		_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.05, 0.001), Vector2(-0.05, 0.032), Vector2(0.04, 0.032),
			Vector2(0.04, 0.001)]), 16), "steel", mount, motor)
		for k in 4:
			_put(HullMesh.lathe(_torus(0.034, 0.004, 6), 16), "metal", mount, motor * _at(Vector3(-0.035 + k * 0.022, 0, 0)))
	if galvanic >= 1:
		# A lead from the head back along the barrel to a capacitor on the breech.
		_put(HullMesh.pipe(PackedVector3Array([Vector3(muzzle - 0.04, h + 0.03, 0), Vector3(-0.08, h + 0.03, 0),
			Vector3(-0.12, h + 0.045, 0)]), 0.005, 6, 0.02), "copper", mount)
		_put(HullMesh.rounded_box(Vector3(0.05, 0.03, 0.045), 0.008), "olive", mount, _at(Vector3(-0.14, h + 0.052, 0)))
		_led(mount, Vector3(-0.114, h + 0.055, 0.0), POWER, 0.008)
	if galvanic >= 2:
		var coil := PackedVector3Array()
		for k in 41:
			var a := TAU * 4.0 * k / 40.0
			coil.append(Vector3(lerpf(muzzle * 0.35, muzzle - 0.04, k / 40.0), h + cos(a) * 0.032, sin(a) * 0.032))
		_put(HullMesh.pipe(coil, 0.0045, 5), "copper", mount)
		_put(HullMesh.lathe(_torus(0.036, 0.005, 6), 18, 0.0), POWER.to_html(), mount, _at(Vector3(muzzle, h, 0)))
	if serrated >= 3:
		# A saw-toothed crown round the muzzle.
		for k in 8:
			var a := TAU * k / 8.0
			var dir := Vector3(0, cos(a), sin(a))
			_put(HullMesh.pipe(PackedVector3Array([Vector3(muzzle - 0.005, h, 0) + dir * 0.032,
				Vector3(muzzle + 0.025, h, 0) + dir * 0.026]), 0.006, 4), "steel", mount)
	if glass:
		# The glass accumulator, its core glowing, and red vents along the barrel.
		var tube := _at(Vector3(0.02, h + 0.055, 0))
		_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.09, 0.001), Vector2(-0.085, 0.018), Vector2(0.085, 0.018),
			Vector2(0.09, 0.001)]), 14), "glass", mount, tube)
		_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.07, 0.001), Vector2(-0.065, 0.009), Vector2(0.065, 0.009),
			Vector2(0.07, 0.001)]), 10, 0.0), WEAPON.to_html(), mount, tube)
		for x: float in [-0.09, 0.09]:
			_put(HullMesh.rounded_box(Vector3(0.016, 0.04, 0.03), 0.005, 1), "metal", mount, _at(Vector3(x + 0.02,
				h + 0.035, 0)))
		for k in 3:
			for sgn: float in [-1.0, 1.0]:
				_put(HullMesh.rounded_box(Vector3(0.018, 0.006, 0.003), 0.001, 1), WEAPON.to_html(), mount,
					_at(Vector3(0.03 + k * 0.035, h, sgn * 0.0265)))
	_led(mount, Vector3(-0.14, h + 0.04, 0.0) if galvanic == 0 else Vector3(-0.185, h + 0.02, 0.0), WEAPON)
	# The loaded spear: kept apart, so it can be hidden while the harpoon is out.
	var spear := Node3D.new()
	spear.name = "Spear"
	spear.transform = mount * _at(Vector3(muzzle + 0.005, h, 0))
	root.add_child(spear)
	_spear(spear, serrated, galvanic)
	m.merge_under(spear)
	m.set_harpoon_spear(spear)
	m.add_muzzle(&"harpoon", mount * Vector3(muzzle + 0.1, h, 0))


## The spear's head, along +X from [param node]'s origin: a steel point with
## two flukes, raked barbs for Serrated Harpoon (longer and in two rows as it
## stacks), copper behind an insulator collar for a Galvanic Barb.
func _spear(node: Node3D, serrated: int, galvanic: int) -> void:
	var here := Transform3D.IDENTITY
	var metal := "copper" if galvanic > 0 else "steel"
	var length := 0.11 * (1.0 + 0.25 * maxi(serrated - 1, 0))
	_put(HullMesh.pipe(PackedVector3Array([Vector3(-0.06, 0, 0), Vector3(0.02, 0, 0)]), 0.009, 8), "steel", here,
		Transform3D.IDENTITY, node)
	_put(HullMesh.lathe(PackedVector2Array([Vector2(0.0, 0.001), Vector2(0.0, 0.017), Vector2(length * 0.3, 0.02),
		Vector2(length, 0.001)]), 12), metal, here, Transform3D.IDENTITY, node)
	if galvanic > 0:
		_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.018, 0.001), Vector2(-0.018, 0.016), Vector2(-0.002, 0.016),
			Vector2(-0.002, 0.001)]), 12), "ceramic", here, Transform3D.IDENTITY, node)
	for k in 2:
		var sgn := 1.0 if k == 0 else -1.0
		_put(HullMesh.rounded_box(Vector3(0.04, 0.003, 0.02), 0.001, 1), "steel", here,
			_at(Vector3(0.01, 0, sgn * 0.022)), node)
	var rows := mini(serrated, 2)
	for row in rows:
		var x := length * (0.25 + 0.35 * row)
		for k in 3:
			var a := TAU * k / 3.0 + row * PI / 3.0
			var out := Vector3(0, cos(a), sin(a))
			_put(HullMesh.pipe(PackedVector3Array([Vector3(x + 0.02, 0, 0) + out * 0.012,
				Vector3(x - 0.03, 0, 0) + out * 0.055]), 0.007, 5), metal, here, Transform3D.IDENTITY, node)


# --- The tools -----------------------------------------------------------------------

## The flare launcher: a box of tubes angled up and forward, more of them
## with each level and Flare Pouch. Emergency Flares alone give one
## strapped-on tube.
func _flares() -> void:
	var mount: Variant = _mount(&"flare")
	if mount == null:
		return
	var kit_only := not tools.has(&"flare")
	var tubes := clampi((1 if kit_only else 2) + _n(&"flare_pouch"), 1, 5)
	var cols := mini(tubes, 4)
	var rows := ceili(tubes / 4.0)
	var w := 0.05 * cols + 0.03
	var d := 0.05 * rows + 0.04
	_put(HullMesh.rounded_box(Vector3(w, 0.05, d), 0.012), "safety" if kit_only else "metal", mount,
		_at(Vector3(0, 0.025, 0), Vector3(0, 90, 0)))
	var tilt := Basis.from_euler(Vector3(0, 0, deg_to_rad(-55.0)))
	for k in tubes:
		var cx := (k / 4 - (rows - 1) * 0.5) * 0.05
		var cz := (k % 4 - (cols - 1) * 0.5) * 0.05
		var at := Vector3(cx, 0.05, cz)
		var tube := Transform3D(tilt, at)
		_put(HullMesh.lathe(PackedVector2Array([Vector2(0.0, 0.001), Vector2(0.0, 0.021), Vector2(0.09, 0.021),
			Vector2(0.095, 0.017), Vector2(0.095, 0.017), Vector2(0.095, 0.001)]), 12), "metal", mount, tube)
		_put(HullMesh.lathe(PackedVector2Array([Vector2(0.094, 0.015), Vector2(0.1, 0.012), Vector2(0.102, 0.001)]), 10,
			0.0), "flare_glow", mount, tube)
	_led(mount, Vector3(-d * 0.5 - 0.005, 0.03, w * 0.5 - 0.01), LIGHT, 0.009)
	m.add_muzzle(&"flare", mount * Vector3(0.06, 0.12, 0))


## Torpedo pods either side, each with its tubes' mouths in the nose; more
## tubes with each level and Torpedo Rack, warheads showing with a Shaped
## Warhead. A Salvaged Torpedo Tube alone gives one bare tube on straps.
func _torpedoes() -> void:
	var mounts: Variant = _mount(&"torpedo")
	if mounts == null:
		return
	var tubes := clampi(1 + _n(&"torpedo_rack"), 1, 3)
	var kit_only := not tools.has(&"torpedo")
	var warhead := _n(&"warhead") > 0
	var first := true
	for mount: Transform3D in mounts:
		if kit_only and not first:
			break
		var r := 0.055 + 0.02 * (tubes - 1)
		var y := 0.06 + r
		_put(HullMesh.rounded_box(Vector3(0.22, y, 0.04), 0.012), "metal", mount, _at(Vector3(0.0, y * 0.5, 0)))
		if kit_only:
			_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.3, 0.001), Vector2(-0.3, 0.045), Vector2(0.28, 0.045),
				Vector2(0.28, 0.035), Vector2(0.28, 0.035), Vector2(0.24, 0.035)]), 14), "iron", mount,
				_at(Vector3(0, y, 0)))
			for x: float in [-0.15, 0.12]:
				_put(HullMesh.lathe(_torus(0.048, 0.006, 6), 14), "rubber", mount, _at(Vector3(x, y, 0), Vector3(0, 0, 90)))
		else:
			var length := 0.65
			_put(HullMesh.lathe(PackedVector2Array([Vector2(-length * 0.5, 0.001), Vector2(-length * 0.42, r * 0.6),
				Vector2(-length * 0.25, r * 0.95), Vector2(length * 0.3, r), Vector2(length * 0.45, r * 0.92),
				Vector2(length * 0.5, r * 0.8), Vector2(length * 0.5, r * 0.8), Vector2(length * 0.5, 0.001)]), 24),
				"paint", mount, _at(Vector3(0, y, 0)))
			for k in tubes:
				var a := TAU * k / tubes + PI * 0.5
				var off := Vector3(0, cos(a), sin(a)) * (r * 0.42 if tubes > 1 else 0.0)
				var at := Vector3(length * 0.5, y, 0) + off
				_put(HullMesh.lathe(PackedVector2Array([Vector2(0.0, 0.03), Vector2(0.008, 0.03), Vector2(0.01, 0.024),
					Vector2(0.01, 0.024), Vector2(-0.03, 0.024), Vector2(-0.03, 0.001)]), 14), "steel", mount,
					_at(at))
				if warhead:
					_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.02, 0.022), Vector2(0.0, 0.02),
						Vector2(0.02, 0.012), Vector2(0.03, 0.001)]), 12), "warhead", mount, _at(at))
			_led(mount, Vector3(-length * 0.2, y + r * 0.95, 0.0), WEAPON)
		if first:
			m.add_muzzle(&"torpedo", mount * Vector3(0.33, y, 0))
		first = false


## The decoy launcher: a rack of orange canisters with sonar-blue bands, more
## with each level and Decoy Rack. Sonar Decoys alone clamp on a single one.
func _decoys() -> void:
	var mount: Variant = _mount(&"decoy")
	if mount == null:
		return
	var kit_only := not tools.has(&"decoy")
	var count := clampi((1 if kit_only else 2) + _n(&"decoy_rack"), 1, 5)
	var w := 0.06 * count + 0.02
	_put(HullMesh.rounded_box(Vector3(0.1, 0.03, w), 0.01), "metal", mount, _at(Vector3(0, 0.015, 0)))
	var tilt := Basis.from_euler(Vector3(0, 0, deg_to_rad(75.0)))
	for k in count:
		var z := (k - (count - 1) * 0.5) * 0.06
		var can := Transform3D(tilt, Vector3(0.0, 0.03, z))
		_put(HullMesh.lathe(PackedVector2Array([Vector2(0.0, 0.001), Vector2(0.0, 0.024), Vector2(0.11, 0.024),
			Vector2(0.125, 0.016), Vector2(0.13, 0.001)]), 12), "canister", mount, can)
		_put(HullMesh.lathe(PackedVector2Array([Vector2(0.05, 0.024), Vector2(0.05, 0.026), Vector2(0.065, 0.026),
			Vector2(0.065, 0.024)]), 12, 0.0), SONAR.to_html(), mount, can)
		_put(HullMesh.pipe(PackedVector3Array([Vector3(0.13, 0, 0), Vector3(0.18, 0, 0)]), 0.003, 4), "metal", mount,
			can)
	m.add_muzzle(&"decoy", mount * Vector3(0.0, 0.14, 0))


## The shock emitter: copper balls on stacks of ceramic insulators, a disc
## more for each level, copper coils round them with each Arc Coil.
func _shock() -> void:
	var mount: Variant = _mount(&"shock")
	if mount == null:
		return
	var discs := 4
	var coils := _n(&"capacitor_coil")
	_put(HullMesh.rounded_box(Vector3(0.12, 0.03, 0.7), 0.012), "metal", mount, _at(Vector3(0, 0.015, 0)))
	var tilt := Basis.from_euler(Vector3(0, 0, deg_to_rad(55.0)))
	for z: float in [-0.28, 0.28]:
		var at := Transform3D(tilt, Vector3(0, 0.03, z))
		var profile := PackedVector2Array([Vector2(0.0, 0.001), Vector2(0.0, 0.035)])
		for k in discs:
			var x := 0.035 + k * 0.045
			profile.append_array(PackedVector2Array([Vector2(x - 0.008, 0.035), Vector2(x, 0.065),
				Vector2(x + 0.012, 0.065), Vector2(x + 0.02, 0.035)]))
		var top := 0.035 + discs * 0.045
		profile.append_array(PackedVector2Array([Vector2(top, 0.035), Vector2(top + 0.01, 0.001)]))
		_put(HullMesh.lathe(profile, 18), "ceramic", mount, at)
		_put(HullMesh.pipe(PackedVector3Array([Vector3(top, 0, 0), Vector3(top + 0.1, 0, 0)]), 0.012, 8), "copper",
			mount, at)
		_put(HullMesh.lathe(_ball(0.05, 10), 14), "copper", mount, at * _at(Vector3(top + 0.14, 0, 0)))
		for k in mini(coils, 2) * 3:
			_put(HullMesh.lathe(_torus(0.075, 0.008, 8), 18), "copper", mount, at * _at(Vector3(0.06 + k * 0.03, 0, 0)))
		if coils > 0:
			_put(HullMesh.lathe(_ball(0.022, 8), 10, 0.0), "arc", mount, at * _at(Vector3(top + 0.14, 0, 0)))
	_led(mount, Vector3(0.03, 0.035, 0.0), WEAPON)


## The sonar head: a rubber transducer dome on a pedestal. Its cards each
## change it, and again as they stack: a Pulse Amplifier lifts the dome on a
## ribbed amplifier stage (rings a reflector round it at two, reaches
## hydrophone booms out either side at three); Quick Ping sets pinger cans by
## its foot (and a capacitor rack behind it at two); the Echo Analyzer puts a
## processor with a glowing sweep display and a whip antenna behind it; a
## Concussive Ping mounts a dish with a red-tipped emitter ahead of it. The
## Pressure Compass sits on the deck (see _utilities).
func _sonar() -> void:
	var mount: Variant = _mount(&"sonar")
	if mount == null:
		return
	var amp := mini(_n(&"amplifier"), 3)
	var quick := mini(_n(&"quick_ping"), 2)
	var r := 0.085
	_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.01, 0.075), Vector2(0.02, 0.075), Vector2(0.03, 0.068),
		Vector2(0.035, 0.06), Vector2(0.035, 0.001)]), 24), "metal", mount, _stand(Vector3.ZERO))
	var top := 0.035
	if amp >= 1:
		# The amplifier stage: a ribbed drum with a glowing band.
		_put(HullMesh.lathe(PackedVector2Array([Vector2(0.0, 0.001), Vector2(0.0, r * 0.95), Vector2(0.055, r * 0.95),
			Vector2(0.055, 0.001)]), 24), "steel", mount, _stand(Vector3(0, top, 0)))
		for k in 3:
			_put(HullMesh.lathe(_torus(r * 0.97, 0.006, 6), 24), "metal", mount, _stand(Vector3(0, top + 0.01 + k * 0.017, 0)))
		_put(HullMesh.lathe(PackedVector2Array([Vector2(0.0, r * 0.955), Vector2(0.0, r * 0.97), Vector2(0.006, r * 0.97),
			Vector2(0.006, r * 0.955)]), 24, 0.0), SONAR.to_html(), mount, _stand(Vector3(0, top + 0.044, 0)))
		top += 0.055
	_put(HullMesh.lathe(_torus(r * 1.02, 0.009, 8), 24), "metal", mount, _stand(Vector3(0, top + 0.004, 0)))
	_put(HullMesh.lathe(_cap(r, 10), 24), "rubber", mount, _stand(Vector3(0, top, 0)))
	_led(mount, Vector3(r * 0.7, top + 0.012, 0.0), SONAR, 0.008)
	if amp >= 2:
		# A reflector ring flaring round the dome's foot.
		_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.004, r * 1.06), Vector2(0.03, r * 1.75), Vector2(0.034, r * 1.73),
			Vector2(0.002, r * 1.05)]), 28), "steel", mount, _stand(Vector3(0, top - 0.01, 0)))
	if amp >= 3:
		# Hydrophone booms out to either side, a little dome at each tip.
		for sgn: float in [-1.0, 1.0]:
			var tip := Vector3(0.0, top + 0.02, sgn * (r + 0.2))
			_put(HullMesh.pipe(PackedVector3Array([Vector3(0, top - 0.02, sgn * r * 0.8), tip]), 0.009, 8), "metal", mount)
			_put(HullMesh.lathe(_cap(0.035, 8), 14), "rubber", mount, _stand(tip))
			_put(HullMesh.lathe(_torus(0.036, 0.005, 6), 14), "metal", mount, _stand(tip + Vector3(0, 0.002, 0)))
			_led(mount, tip + Vector3(0.0, 0.04, 0.0), SONAR, 0.007)
	if quick >= 1:
		# Pinger cans at the foot, either side.
		for sgn: float in [-1.0, 1.0]:
			var at := Vector3(0.0, 0.0, sgn * (r + 0.075))
			_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.01, 0.026), Vector2(0.05, 0.026), Vector2(0.055, 0.02),
				Vector2(0.055, 0.001)]), 14), "metal", mount, _stand(at))
			_put(HullMesh.lathe(_cap(0.02, 6), 10), "rubber", mount, _stand(at + Vector3(0, 0.055, 0)))
			_led(mount, at + Vector3(0.027, 0.03, 0.0), SONAR, 0.007)
	if quick >= 2:
		# A capacitor rack behind, strapped together.
		for k in 3:
			var at := Vector3(-r - 0.06, 0.0, (k - 1) * 0.04)
			_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.01, 0.018), Vector2(0.075, 0.018), Vector2(0.078, 0.012),
				Vector2(0.078, 0.001)]), 12), "olive", mount, _stand(at))
			_led(mount, at + Vector3(0, 0.082, 0), SONAR, 0.006)
		_put(HullMesh.rounded_box(Vector3(0.05, 0.012, 0.13), 0.004, 1), "metal", mount,
			_at(Vector3(-r - 0.06, 0.045, 0)))
	if _n(&"echo_analyzer") > 0:
		# A processor behind the dome, a glowing sweep on each face and a whip antenna.
		var at := Vector3(-r - 0.07, 0.05, 0.0) if quick < 2 else Vector3(-r - 0.07, 0.12, 0.0)
		_put(HullMesh.rounded_box(Vector3(0.09, 0.08, 0.1), 0.014), "metal", mount, _at(at))
		for sgn: float in [-1.0, 1.0]:
			_put(HullMesh.rounded_box(Vector3(0.06, 0.05, 0.004), 0.004, 1), "cockpit_sonar", mount,
				_at(at + Vector3(0.0, 0.004, sgn * 0.051)))
		_put(HullMesh.pipe(PackedVector3Array([at + Vector3(-0.03, 0.04, 0), at + Vector3(-0.06, 0.22, 0)]), 0.004, 5),
			"metal", mount)
	if _n(&"sonar_stun") > 0:
		# A concussion dish ahead of the dome, its emitter tipped red.
		var arm := Vector3(r + 0.03, 0.03, 0.0)
		var dish := _at(Vector3(r + 0.1, top * 0.5 + 0.04, 0.0), Vector3(0, 0, 12))
		_put(HullMesh.pipe(PackedVector3Array([Vector3(r * 0.4, 0.02, 0), arm, Vector3(r + 0.08, top * 0.5 + 0.04, 0)]),
			0.01, 6, 0.02), "metal", mount)
		_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.012, 0.001), Vector2(-0.006, 0.02), Vector2(0.02, 0.065),
			Vector2(0.026, 0.07), Vector2(0.03, 0.068), Vector2(0.008, 0.024), Vector2(0.0, 0.001)]), 24), "metal", mount, dish)
		_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.01, 0.001), Vector2(-0.01, 0.009), Vector2(0.04, 0.006),
			Vector2(0.045, 0.001)]), 10), "steel", mount, dish)
		_led(mount, (dish * Vector3(0.046, 0, 0)), WEAPON, 0.009)


# --- Module cards --------------------------------------------------------------------

## Bolted armour plates along the flanks, a pair for each Reinforced Plating
## card; Repair Nanites dock little pods on the deck.
func _armour() -> void:
	for k in _n(&"plating"):
		for mount: Transform3D in _take_pair(&"flank"):
			_put(HullMesh.rounded_box(Vector3(0.32, 0.02, 0.22), 0.008), "metal", mount, _at(Vector3(0, 0.008, 0)))
			_put(HullMesh.rounded_box(Vector3(0.3, 0.022, 0.2), 0.01), "paint", mount, _at(Vector3(0, 0.016, 0)))
			for c: Vector2 in [Vector2(0.12, 0.075), Vector2(-0.12, 0.075), Vector2(0.12, -0.075), Vector2(-0.12, -0.075)]:
				_put(HullMesh.bolt_head(0.01), "steel", mount, _at(Vector3(c.x, 0.027, c.y), Vector3(0, 0, 90)))
			_led(mount, Vector3(0.0, 0.029, 0.0), HULL, 0.008)
	for k in _n(&"nanites"):
		var mount: Variant = _take(&"deck")
		if mount == null:
			break
		_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.01, 0.06), Vector2(0.02, 0.06), Vector2(0.025, 0.05),
			Vector2(0.025, 0.001)]), 16), "metal", mount, _stand(Vector3.ZERO))
		_put(HullMesh.lathe(_cap(0.05, 8), 16), "glass", mount, _stand(Vector3(0, 0.025, 0)))
		_put(HullMesh.lathe(_ball(0.025, 8), 12, 0.0), HULL.to_html(), mount, _at(Vector3(0, 0.045, 0)))


## Under the belly: a capacitor for each Capacitor Bank, a glowing tank for the Bio-Converter, an ink bladder for
## the Ink Sac, a scoop for the Scavenger Protocol.
func _power() -> void:
	for k in _n(&"capacitor"):
		var mount: Variant = _take(&"belly")
		if mount == null:
			break
		for z: float in [-0.045, 0.045]:
			var at := _at(Vector3(0, 0.05, z))
			_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.12, 0.001), Vector2(-0.12, 0.035), Vector2(0.12, 0.035),
				Vector2(0.12, 0.001)]), 14), "metal", mount, at)
			_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.03, 0.035), Vector2(-0.03, 0.037), Vector2(0.03, 0.037),
				Vector2(0.03, 0.035)]), 14, 0.0), POWER.to_html(), mount, at)
	if _n(&"bioconverter") > 0:
		var mount: Variant = _take(&"belly")
		if mount != null:
			var at := _at(Vector3(0, 0.06, 0))
			_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.13, 0.001), Vector2(-0.12, 0.045), Vector2(0.12, 0.045),
				Vector2(0.13, 0.001)]), 16), "glass", mount, at)
			_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.11, 0.001), Vector2(-0.1, 0.035), Vector2(0.1, 0.035),
				Vector2(0.11, 0.001)]), 12, 0.0), "bio", mount, at)
			for x: float in [-0.13, 0.13]:
				_put(HullMesh.lathe(_torus(0.047, 0.008, 6), 14), "metal", mount, at * _at(Vector3(x, 0, 0)))
	if _n(&"ink") > 0:
		var mount: Variant = _take(&"belly")
		if mount != null:
			_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.12, 0.001), Vector2(-0.09, 0.05), Vector2(0.02, 0.065),
				Vector2(0.1, 0.04), Vector2(0.14, 0.012), Vector2(0.16, 0.012), Vector2(0.16, 0.001)]), 16), "ink", mount,
				_at(Vector3(0, 0.065, 0)))
			_led(mount, Vector3(0.0, 0.13, 0.0), UTIL, 0.008)
	if _n(&"scavenger") > 0:
		var mount: Variant = _take(&"belly")
		if mount != null:
			for z: float in [-0.07, 0.0, 0.07]:
				_put(HullMesh.pipe(PackedVector3Array([Vector3(-0.08, 0.0, z), Vector3(-0.06, 0.09, z), Vector3(0.1, 0.11, z),
					Vector3(0.14, 0.06, z)]), 0.006, 5, 0.03), "steel", mount)
			_put(HullMesh.pipe(PackedVector3Array([Vector3(0.14, 0.06, -0.08), Vector3(0.14, 0.06, 0.08)]), 0.008, 5),
				"steel", mount)
			_led(mount, Vector3(-0.07, 0.02, 0.0), UTIL, 0.009)


## Aft: glowing boosters for Overdrive, rubber baffles for Silent Screws;
## foils along the flanks for a Hydrodynamic Hull.
func _drive() -> void:
	var mounts: Variant = _mount(&"drive")
	var boost := _n(&"overdrive")
	var quiet := _n(&"silent_screws")
	if mounts != null and (boost > 0 or quiet > 0):
		for mount: Transform3D in mounts:
			var y := 0.08
			_put(HullMesh.rounded_box(Vector3(0.12, y, 0.03), 0.01), "metal", mount, _at(Vector3(0, y * 0.5, 0)))
			if quiet > 0:
				_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.12, 0.001), Vector2(-0.08, 0.05), Vector2(0.08, 0.05),
					Vector2(0.12, 0.001)]), 14), "rubber", mount, _at(Vector3(0, y, 0)))
			if boost > 0:
				var at := _at(Vector3(-0.1, y + (0.06 if quiet > 0 else 0.0), 0))
				_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.05, 0.035), Vector2(-0.03, 0.04), Vector2(0.06, 0.035),
					Vector2(0.06, 0.001)]), 14), "metal", mount, at)
				_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.051, 0.028), Vector2(-0.051, 0.001)]), 14, 0.0),
					"boost", mount, at)
			_led(mount, Vector3(0.0, y + 0.06, 0.0), POWER if boost > 0 else UTIL, 0.008)
	var foils: Variant = _mount(&"foil")
	if foils != null and _n(&"hydrofoil") > 0:
		var span := 0.16 + 0.06 * _n(&"hydrofoil")
		for mount: Transform3D in foils:
			_put(HullMesh.wing(Vector2(0.18, -0.12), Vector2(0.02, -0.14), span, 0.1, 8, 16, 0.8), "paint", mount)
			_led(mount, Vector3(-0.06, span - 0.01, 0.0), UTIL, 0.008)


## On the deck: a magnet coil for a Magnet Coil, cargo crates for Deep
## Pockets, the Pressure Compass, and along the flanks the Galvanic Hull's
## live strips.
func _utilities() -> void:
	var coil := 2 * _n(&"magnet_coil")
	if coil > 0:
		var mount: Variant = _take(&"deck")
		if mount != null:
			var r := 0.05 + 0.012 * coil
			_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.01, r * 0.7), Vector2(0.02, r * 0.7),
				Vector2(0.02, 0.001)]), 18), "metal", mount, _stand(Vector3.ZERO))
			for k in 3 + coil:
				_put(HullMesh.lathe(_torus(r, 0.009, 6), 20), "copper", mount, _stand(Vector3(0, 0.03 + k * 0.017, 0)))
			_put(HullMesh.lathe(PackedVector2Array([Vector2(0.0, 0.025), Vector2(0.05 + (3 + coil) * 0.017, 0.025),
				Vector2(0.05 + (3 + coil) * 0.017, 0.001)]), 12), "metal", mount, _stand(Vector3(0, 0.0, 0)))
			_led(mount, Vector3(0, 0.06 + (3 + coil) * 0.017, 0), UTIL, 0.01)
	for k in _n(&"lucky"):
		var mount: Variant = _take(&"deck")
		if mount == null:
			break
		_put(HullMesh.rounded_box(Vector3(0.2, 0.1, 0.14), 0.012), "crate", mount, _at(Vector3(0, 0.05, 0)))
		for x: float in [-0.06, 0.06]:
			_put(HullMesh.rounded_box(Vector3(0.018, 0.104, 0.144), 0.004, 1), "rubber", mount, _at(Vector3(x, 0.05, 0)))
		_led(mount, Vector3(0.101, 0.07, 0.0), UTIL, 0.008)
	if _n(&"compass") > 0:
		# The Pressure Compass: a brass binnacle with a gimballed glass bowl and a lit needle.
		var mount: Variant = _take(&"deck")
		if mount != null:
			_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.01, 0.045), Vector2(0.02, 0.04), Vector2(0.05, 0.028),
				Vector2(0.06, 0.03), Vector2(0.065, 0.001)]), 18), "brass", mount, _stand(Vector3.ZERO))
			var bowl := Vector3(0, 0.12, 0)
			_put(HullMesh.lathe(_torus(0.066, 0.006, 6), 22), "brass", mount, _at(bowl, Vector3(90, 0, 0)))
			_put(HullMesh.lathe(_torus(0.058, 0.005, 6), 22), "brass", mount, _at(bowl, Vector3(0, 0, 90)))
			for sgn: float in [-1.0, 1.0]:
				_put(HullMesh.pipe(PackedVector3Array([Vector3(0, 0.06, sgn * 0.066), bowl + Vector3(0, 0, sgn * 0.066)]),
					0.006, 6), "brass", mount)
			_put(HullMesh.lathe(_ball(0.048, 10), 14), "glass", mount, _at(bowl))
			_put(HullMesh.rounded_box(Vector3(0.07, 0.004, 0.008), 0.002, 1), SONAR.to_html(), mount,
				_at(bowl, Vector3(0, 30, 0)))
			_led(mount, bowl + Vector3(0.03, 0.0, 0.0), WEAPON, 0.006)
	if _n(&"shock_hull") > 0:
		for mount: Transform3D in m.mounts.get(&"flank", []):
			_put(HullMesh.pipe(PackedVector3Array([Vector3(-0.2, 0.008, 0), Vector3(0.2, 0.008, 0)]), 0.006, 6), "arc",
				mount)
			for x: float in [-0.2, 0.2]:
				_put(HullMesh.lathe(_cap(0.016, 5), 8), "ceramic", mount, _stand(Vector3(x, 0.0, 0)))


# --- Profiles ------------------------------------------------------------------------

static func _ball(r: float, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in steps + 1:
		var a := PI * k / steps
		out.append(Vector2(-cos(a) * r, sin(a) * r + 0.0002))
	return out


static func _cap(r: float, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in steps + 1:
		var a := PI * 0.5 * k / steps
		out.append(Vector2(sin(a) * r, cos(a) * r + 0.0002))
	return out


static func _torus(r: float, tube: float, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in steps + 1:
		var a := TAU * k / steps
		out.append(Vector2(sin(a) * tube, r + cos(a) * tube))
	return out
