class_name SubEquipment
extends SubFittings
## The kit hung on a submarine, the way gear piles onto a character in a
## roguelite: the lamp head on its track, the harpoon launcher, the frame's
## own tool, and a piece for every module card taken in the run, each with a
## small light in its card's colour. Stacking a card changes its piece again.
## Only module cards change the kit, never hangar upgrades, so it grows over
## a run and looks the same at every start. Pieces go onto the mount points
## the frame provides (SubmarineModel.mounts); each is built in its mount's
## frame, Y out of the hull and X towards the bow.

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
	out[&"decoy"] = frame_at(Vector3(-h * 0.72, radius * 0.75, radius * 0.45), Vector3(0, 1, 0.6))
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
	out[&"power"] = frame_at(Vector3(-h * 0.1, -radius, 0.0), Vector3.DOWN)
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
	# Deck pieces fill the near side (towards the camera) before the far.
	var near: Array = []
	var far: Array = []
	for t: Transform3D in _free[&"deck"]:
		(near if t.origin.z > -0.001 else far).append(t)
	_free[&"deck"] = near + far
	_lamp()
	_harpoon()
	_sonar()
	_flares()
	_torpedoes()
	_decoys()
	if tools.has(&"shock") or _n(&"shock_kit") > 0:
		_shock()
	_armour()
	_power()
	_drive()
	_utilities()


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
	m.set_lamp_head(head, swivel, lens, lens_r)


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


# --- The sonar -----------------------------------------------------------------------

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

## Reinforced Plating: a pair of armour plates for each card, low on the
## flanks, the first midships and the rest spreading fore and aft. On a hull
## with a skin they are curved to it, chamfered and bolted; otherwise flat.
## Repair Nanites put a canister of glowing nanite fluid on the deck, a hose
## into the hull, and at two a little repair crawler perched beside it. The
## Galvanic Hull sets a row of electrode studs along each flank (see _galvanic).
func _armour() -> void:
	var plates := mini(_n(&"plating"), 4)
	if plates > 0:
		var flank: Array = m.mounts.get(&"flank", [])
		var mid := 0.0
		for t: Transform3D in flank:
			mid += t.origin.x / flank.size()
		var pairs: Array = []
		for k in flank.size() / 2:
			pairs.append([flank[k * 2], flank[k * 2 + 1]])
		pairs.sort_custom(func(a: Array, b: Array) -> bool:
			return absf((a[0] as Transform3D).origin.x - mid) < absf((b[0] as Transform3D).origin.x - mid))
		for k in mini(plates, pairs.size()):
			for mount: Transform3D in pairs[k]:
				_fitted_once("plate/%s/%s" % [mount.origin, k == 0], _plate.bind(mount, k == 0))
	var galvanic := mini(_n(&"shock_hull"), 2)
	if galvanic > 0:
		_fitted_once("galvanic/%d" % galvanic, _galvanic)
	_nanites()


## One armour plate over [param mount], with a light on the first pair.
func _plate(mount: Transform3D, lit: bool) -> void:
	var f := m.hull_skin
	if f == null:
		_put(HullMesh.rounded_box(Vector3(0.34, 0.03, 0.2), 0.008), "armor", mount, _at(Vector3(0, 0.01, 0)))
		for c: Vector2 in [Vector2(0.14, 0.075), Vector2(-0.14, 0.075), Vector2(0.14, -0.075), Vector2(-0.14, -0.075)]:
			_put(HullMesh.bolt_head(0.01), "steel", mount, _at(Vector3(c.x, 0.025, c.y), Vector3(0, 0, 90)))
		if lit:
			_led(mount, Vector3(0.15, 0.027, 0.0), HULL, 0.008)
		return
	var uv := _skin_uv(mount.origin)
	var hx := 0.19
	var hv := 0.085 / _arc_rate(uv)
	var lift := 0.016
	var bevel := Vector2(0.012, 0.012 / _arc_rate(uv))
	var face := func(u: float, w: float) -> Vector3:
		return f.on_skin(uv.x + lerpf(-hx + bevel.x, hx - bevel.x, u), uv.y + lerpf(-hv + bevel.y, hv - bevel.y, w),
			lift)
	_put(HullMesh.surface(face, 10, 6), "armor", Transform3D.IDENTITY)
	# The chamfer round its edge, from the skin up to the face.
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var centre := f.on_skin(uv.x, uv.y, 0.0)
	for k in 4:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		var edge := func(u: float, t: float) -> Vector3:
			var c := a.lerp(b, u)
			var low := f.on_skin(uv.x + c.x * hx, uv.y + c.y * hv, 0.0)
			var high := f.on_skin(uv.x + c.x * (hx - bevel.x), uv.y + c.y * (hv - bevel.y), lift)
			return low.lerp(high, t)
		var n := (edge.call(0.55, 0.5) - edge.call(0.45, 0.5) as Vector3).cross(edge.call(0.5, 0.6) - edge.call(0.5, 0.4))
		var out: Vector3 = (edge.call(0.5, 0.0) as Vector3) - centre
		_put(HullMesh.surface(edge, 10 if k % 2 == 0 else 6, 1, n.dot(out) < 0.0), "armor", Transform3D.IDENTITY)
	# Bolts round the face.
	for c: Vector2 in [Vector2(-0.8, -0.62), Vector2(0.0, -0.62), Vector2(0.8, -0.62), Vector2(-0.8, 0.62),
			Vector2(0.0, 0.62), Vector2(0.8, 0.62)]:
		var x := uv.x + c.x * hx
		var v := uv.y + c.y * hv
		var nrm := f.normal_at(x, v)
		_put(HullMesh.bolt_head(0.009), "steel", Transform3D(Basis(Quaternion(Vector3.RIGHT, nrm)),
			f.on_skin(x, v, lift - 0.001)))
	if lit:
		var x := uv.x + 0.9 * hx
		_put(HullMesh.lathe(_ball(0.008, 6), 8, 0.0), HULL.to_html(), Transform3D(Basis(),
			f.on_skin(x, uv.y, lift + 0.002)))


## Where [param at] lies on the hull's skin: its x and how far round (v).
func _skin_uv(at: Vector3) -> Vector2:
	var f := m.hull_skin
	var best := 0.0
	var dist := INF
	for k in 96:
		var v := k / 96.0
		var d := f.on_skin(at.x, v, 0.0).distance_squared_to(at)
		if d < dist:
			dist = d
			best = v
	var step := 1.0 / 96.0
	for k in 12:
		step *= 0.5
		for v: float in [best - step, best + step]:
			var d := f.on_skin(at.x, v, 0.0).distance_squared_to(at)
			if d < dist:
				dist = d
				best = v
	return Vector2(at.x, best)


## How far along the skin one unit of v goes at [param uv].
func _arc_rate(uv: Vector2) -> float:
	var f := m.hull_skin
	return maxf(f.on_skin(uv.x, uv.y + 0.01, 0.0).distance_to(f.on_skin(uv.x, uv.y - 0.01, 0.0)) / 0.02, 0.05)


## The Galvanic Hull: ceramic studs with live copper tips in a row along each
## flank (the frame's "galvanic" line: from x, to x, how far round), and at
## two arcs leaping between them. Without a line, live strips on the flanks.
func _galvanic() -> void:
	var level := mini(_n(&"shock_hull"), 2)
	if level == 0:
		return
	var line: Variant = m.mounts.get(&"galvanic")
	if line == null or m.hull_skin == null:
		for mount: Transform3D in m.mounts.get(&"flank", []):
			_put(HullMesh.pipe(PackedVector3Array([Vector3(-0.2, 0.012, 0), Vector3(0.2, 0.012, 0)]), 0.006, 6), "arc",
				mount)
			for x: float in [-0.2, 0.2]:
				_put(HullMesh.lathe(_cap(0.016, 5), 8), "ceramic", mount, _stand(Vector3(x, 0.0, 0)))
		return
	var f := m.hull_skin
	var l := line as Vector3
	var count := maxi(roundi((l.y - l.x) / 0.19), 2) + 1
	for v: float in [l.z, 1.0 - l.z]:
		var tips := PackedVector3Array()
		for k in count:
			var x := lerpf(l.x, l.y, float(k) / (count - 1))
			var nrm := f.normal_at(x, v)
			var t := Transform3D(Basis(Quaternion(Vector3.RIGHT, nrm)), f.on_skin(x, v, -0.004))
			_put(HullMesh.lathe(PackedVector2Array([Vector2(0.0, 0.001), Vector2(0.0, 0.014), Vector2(0.008, 0.014),
				Vector2(0.012, 0.01), Vector2(0.016, 0.014), Vector2(0.02, 0.014), Vector2(0.024, 0.008),
				Vector2(0.026, 0.001)]), 10), "ceramic", t)
			_put(HullMesh.lathe(PackedVector2Array([Vector2(0.024, 0.001), Vector2(0.024, 0.006), Vector2(0.03, 0.006),
				Vector2(0.032, 0.001)]), 8), "copper", t)
			_put(HullMesh.lathe(_ball(0.0055, 6), 8, 0.0), "arc", t * _at(Vector3(0.036, 0, 0)))
			tips.append(t * Vector3(0.036, 0, 0))
		if level >= 2:
			var jag := [0.0, 0.011, -0.008, 0.013, -0.01, 0.006, 0.0]
			for k in count - 1:
				var arc := PackedVector3Array()
				var nrm := f.normal_at(lerpf(l.x, l.y, (k + 0.5) / (count - 1)), v)
				var side := nrm.cross(Vector3.RIGHT).normalized()
				for j in jag.size():
					var s := float(j) / (jag.size() - 1)
					arc.append(tips[k].lerp(tips[k + 1], s) + side * jag[(j + k) % jag.size()] + nrm * 0.008 * sin(s * PI))
				_put(HullMesh.pipe(arc, 0.0022, 4), "arc", Transform3D.IDENTITY)
		var lead := f.on_skin(l.y, v, 0.03)
		_put(HullMesh.lathe(_ball(0.008, 6), 8, 0.0), WEAPON.to_html(), Transform3D(Basis(), lead + Vector3(0.03, 0, 0)))


## Repair Nanites: a canister of glowing nanite fluid on the deck, a hose
## into the hull, and with two cards a repair crawler perched beside it.
func _nanites() -> void:
	var level := mini(_n(&"nanites"), 2)
	if level == 0:
		return
	var mount: Variant = _take(&"deck")
	if mount == null:
		return
	_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.01, 0.001), Vector2(-0.01, 0.046), Vector2(0.018, 0.046),
		Vector2(0.024, 0.04), Vector2(0.024, 0.001)]), 18), "metal", mount, _stand(Vector3.ZERO))
	_put(HullMesh.lathe(PackedVector2Array([Vector2(0.02, 0.001), Vector2(0.02, 0.036), Vector2(0.13, 0.036),
		Vector2(0.13, 0.001)]), 18), "glass", mount, _stand(Vector3.ZERO))
	_put(HullMesh.lathe(PackedVector2Array([Vector2(0.024, 0.001), Vector2(0.024, 0.03), Vector2(0.104, 0.03),
		Vector2(0.11, 0.024), Vector2(0.112, 0.001)]), 14, 0.0), "nanite", mount, _stand(Vector3.ZERO))
	for y: float in [0.02, 0.13]:
		_put(HullMesh.lathe(_torus(0.037, 0.005, 6), 18), "brass", mount, _stand(Vector3(0, y, 0)))
	_put(HullMesh.lathe(PackedVector2Array([Vector2(0.13, 0.001), Vector2(0.13, 0.03), Vector2(0.145, 0.024),
		Vector2(0.15, 0.01), Vector2(0.152, 0.001)]), 16), "brass", mount, _stand(Vector3.ZERO))
	for k in 3:
		var a := TAU * k / 3.0
		_put(HullMesh.pipe(PackedVector3Array([Vector3(cos(a) * 0.037, 0.02, sin(a) * 0.037),
			Vector3(cos(a) * 0.037, 0.13, sin(a) * 0.037)]), 0.003, 4), "brass", mount)
	# The feed hose down into the hull.
	_put(HullMesh.pipe(PackedVector3Array([Vector3(-0.045, 0.03, 0.0), Vector3(-0.08, 0.03, 0.0),
		Vector3(-0.09, -0.02, 0.0)]), 0.007, 6, 0.02), "rubber", mount)
	_led(mount, Vector3(0.042, 0.03, 0.0), HULL, 0.008)
	if level >= 2:
		_crawler(mount * _at(Vector3(0.1, 0.0, 0.02), Vector3(0, -30, 0)))


## A little repair crawler at [param t]: a domed body on four jointed legs,
## a glowing eye and a welding arm.
func _crawler(t: Transform3D) -> void:
	var body := t * _at(Vector3(0, 0.032, 0))
	_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.026, 0.001), Vector2(-0.024, 0.012), Vector2(-0.012, 0.022),
		Vector2(0.012, 0.022), Vector2(0.024, 0.012), Vector2(0.026, 0.001)]), 14), "steel", body,
		Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3.ZERO))
	_put(HullMesh.rounded_box(Vector3(0.05, 0.012, 0.04), 0.005), "safety", body, _at(Vector3(0, -0.002, 0)))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var hip := Vector3(sx * 0.015, -0.002, sz * 0.016)
			var knee := Vector3(sx * 0.032, 0.012, sz * 0.034)
			var foot := Vector3(sx * 0.04, -0.03, sz * 0.042)
			_put(HullMesh.pipe(PackedVector3Array([hip, knee, foot]), 0.0028, 4), "metal", body)
	_put(HullMesh.lathe(_ball(0.006, 6), 8, 0.0), HULL.to_html(), body, _at(Vector3(0.026, 0.002, 0)))
	_put(HullMesh.pipe(PackedVector3Array([Vector3(0.02, 0.006, -0.012), Vector3(0.036, 0.014, -0.014),
		Vector3(0.05, -0.008, -0.014)]), 0.0022, 4), "steel", body)
	_put(HullMesh.lathe(_ball(0.003, 4), 6, 0.0), "arc", body, _at(Vector3(0.051, -0.011, -0.014)))


# --- Power cards ---------------------------------------------------------------------

## The Capacitor Bank: one battery pack at the frame's "power" mount, longer
## with each card, a charge light lit for each; the Bio-Converter on the deck
## (see _bioreactor).
func _power() -> void:
	var cells := mini(_n(&"capacitor"), 4)
	var mount: Variant = _mount(&"power")
	if cells > 0 and mount == null:
		mount = _take(&"belly")
	if cells > 0 and mount != null:
		_battery_pack(mount, cells)
	_bioreactor()


## The battery pack: an olive housing with a yellow band, finned on its face,
## brass terminals and a fat cable at its back end, and a row of charge
## lights, one for each of its [param cells] (Capacitor Bank cards).
func _battery_pack(mount: Transform3D, cells: int) -> void:
	var length := 0.13 + 0.065 * (cells - 1)
	var y := 0.032
	_put(HullMesh.rounded_box(Vector3(length, 0.06, 0.11), 0.012), "olive", mount, _at(Vector3(0, y, 0)))
	_put(HullMesh.rounded_box(Vector3(0.03, 0.062, 0.112), 0.006, 1), "warhead", mount,
		_at(Vector3(length * 0.5 - 0.03, y, 0)))
	# Cooling fins across its face.
	for k in cells * 3:
		var x := -length * 0.5 + 0.02 + k * ((length - 0.075) / maxf(cells * 3 - 1, 1))
		_put(HullMesh.rounded_box(Vector3(0.006, 0.01, 0.086), 0.002, 1), "metal", mount, _at(Vector3(x, y + 0.033, 0)))
	# Straps round it to the mount.
	for x: float in [-length * 0.5 + 0.012, length * 0.5 - 0.06]:
		_put(HullMesh.rounded_box(Vector3(0.014, 0.068, 0.118), 0.004, 1), "metal", mount, _at(Vector3(x, y - 0.002, 0)))
	# Terminals and the cable at the back.
	for z: float in [-0.03, 0.03]:
		_put(HullMesh.lathe(PackedVector2Array([Vector2(0.0, 0.001), Vector2(0.0, 0.009), Vector2(0.014, 0.009),
			Vector2(0.016, 0.006), Vector2(0.016, 0.001)]), 10), "brass", mount,
			Transform3D(Basis(Vector3.UP, PI), Vector3(-length * 0.5, y + 0.01, z)))
	_put(HullMesh.pipe(PackedVector3Array([Vector3(-length * 0.5 - 0.014, y + 0.01, 0.03),
		Vector3(-length * 0.5 - 0.04, y + 0.01, 0.03), Vector3(-length * 0.5 - 0.05, -0.02, 0.03)]), 0.008, 6, 0.02),
		"rubber", mount)
	# Charge lights along the edge facing out, one per card.
	for k in cells:
		_led(mount, Vector3(-length * 0.5 + 0.03 + k * 0.03, y + 0.012, 0.057), POWER, 0.0065)


## The Bio-Converter: a bioreactor on the deck, a vessel of glowing green
## culture with bubbles in it between brass caps; with two cards a second,
## smaller vessel joined to it and an intake funnel on top.
func _bioreactor() -> void:
	var level := mini(_n(&"bioconverter"), 2)
	if level == 0:
		return
	var mount: Variant = _take(&"deck")
	if mount == null:
		return
	for k in level:
		var at := Vector3(0.0 if k == 0 else -0.075, 0.0, 0.0 if k == 0 else 0.02)
		var h := 0.15 if k == 0 else 0.1
		var r := 0.034 if k == 0 else 0.024
		_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.01, 0.001), Vector2(-0.01, r + 0.008), Vector2(0.02, r + 0.008),
			Vector2(0.02, 0.001)]), 16), "metal", mount, _stand(at))
		_put(HullMesh.lathe(PackedVector2Array([Vector2(0.02, 0.001), Vector2(0.02, r), Vector2(0.03, r * 1.15),
			Vector2(h - 0.01, r * 1.15), Vector2(h, r), Vector2(h, 0.001)]), 18), "glass", mount, _stand(at))
		_put(HullMesh.lathe(PackedVector2Array([Vector2(0.022, 0.001), Vector2(0.022, r * 0.95), Vector2(h - 0.025, r),
			Vector2(h - 0.02, 0.001)]), 14, 0.0), "bio", mount, _stand(at))
		_put(HullMesh.lathe(PackedVector2Array([Vector2(h - 0.004, 0.001), Vector2(h - 0.004, r + 0.006),
			Vector2(h + 0.012, r + 0.004), Vector2(h + 0.018, 0.001)]), 16), "brass", mount, _stand(at))
		for j in 4:
			var b := at + Vector3(cos(j * 2.1 + k) * r * 1.02, 0.045 + j * (h - 0.07) / 3.0, sin(j * 2.1 + k) * r * 1.02)
			_put(HullMesh.lathe(_ball(0.006 - j * 0.0008, 6), 8, 0.0), "bubble", mount, _at(b))
	if level >= 2:
		_put(HullMesh.pipe(PackedVector3Array([Vector3(-0.075, 0.07, 0.02), Vector3(-0.04, 0.07, 0.01),
			Vector3(-0.025, 0.07, 0.0)]), 0.006, 6), "brass", mount)
		_put(HullMesh.lathe(PackedVector2Array([Vector2(0.0, 0.008), Vector2(0.03, 0.008), Vector2(0.06, 0.03),
			Vector2(0.064, 0.03), Vector2(0.064, 0.026), Vector2(0.034, 0.005)]), 16), "brass", mount,
			_stand(Vector3(0, 0.168, 0)))
	_led(mount, Vector3(0.044, 0.025, 0.0), POWER, 0.008)
