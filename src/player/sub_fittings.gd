class_name SubFittings
extends SubLaunchers
## The handling and utility fittings of a submarine's kit (see SubEquipment):
## Overdrive's boosters, Silent Screws' dampers on the main propulsor and the
## Hydrodynamic Hull's foils; the Magnet Coil, Deep Pockets' crates, the
## Pressure Compass, the Ink Sac and the Scavenger Protocol's salvage gear.


# --- Handling ------------------------------------------------------------------------

## Aft: Overdrive's booster pods on the drive mounts, their nozzles glowing
## hotter while the sub boosts (a longer pod with cooling rings and an
## afterburner ring at two); Silent Screws on the main propulsor (see
## _screws); a Hydrodynamic Hull's foils (see _foils).
func _drive() -> void:
	var mounts: Variant = _mount(&"drive")
	var boost := mini(_n(&"overdrive"), 2)
	if mounts != null and boost > 0:
		# Lit, not flat: its emission is what the model turns up while boosting.
		var glow := StandardMaterial3D.new()
		glow.albedo_color = Color(0.3, 0.12, 0.05)
		glow.emission_enabled = true
		glow.emission = Color(1.0, 0.5, 0.18)
		glow.emission_energy_multiplier = 0.8
		mats["boost_glow"] = glow
		m.set_boost_glow(glow)
		for mount: Transform3D in mounts:
			_booster(mount, boost)
	_screws()
	_foils()


## One Overdrive booster pod on a pylon.
func _booster(mount: Transform3D, level: int) -> void:
	var length := 0.2 if level == 1 else 0.27
	var r := 0.032 if level == 1 else 0.038
	var h := 0.072
	_put(HullMesh.rounded_box(Vector3(0.09, h - r * 0.5 + 0.02, 0.022), 0.008), "metal", mount,
		_at(Vector3(0.0, (h - r * 0.5) * 0.5 - 0.01, 0)))
	var pod := mount * _at(Vector3(0.02, h, 0))
	var back := -length * 0.5
	_put(HullMesh.lathe(PackedVector2Array([Vector2(back + 0.04, 0.001), Vector2(back + 0.04, r),
		Vector2(length * 0.5 - 0.025, r), Vector2(length * 0.5, r * 0.82), Vector2(length * 0.5, 0.001)]), 20), "paint", pod)
	# The intake at the front, dark behind a steel lip.
	_put(HullMesh.lathe(_torus(r * 0.72, 0.005, 6), 18), "steel", pod, _at(Vector3(length * 0.5 + 0.002, 0, 0)))
	_put(HullMesh.lathe(PackedVector2Array([Vector2(length * 0.5 + 0.001, 0.001), Vector2(length * 0.5 + 0.001, r * 0.7)]),
		16, 0.0), "rubber", pod)
	# The nozzle, its throat glowing.
	_put(HullMesh.lathe(PackedVector2Array([Vector2(back + 0.045, r * 0.96), Vector2(back + 0.01, r * 0.9),
		Vector2(back - 0.03, r * 1.18), Vector2(back - 0.03, r * 1.04), Vector2(back - 0.03, r * 1.04),
		Vector2(back + 0.008, r * 0.62)]), 20), "steel", pod)
	_put(HullMesh.lathe(PackedVector2Array([Vector2(back + 0.01, 0.001), Vector2(back + 0.01, r * 0.66)]), 16, 0.0),
		"boost_glow", pod)
	if level >= 2:
		for k in 5:
			_put(HullMesh.lathe(_torus(r + 0.003, 0.0035, 5), 18), "steel", pod, _at(Vector3(back + 0.07 + k * 0.03, 0, 0)))
		_put(HullMesh.lathe(_torus(r * 1.1, 0.004, 6), 20, 0.0), "boost_glow", pod, _at(Vector3(back - 0.03, 0, 0)))
	_led(mount, Vector3(0.05, h - r * 0.5 - 0.004, 0.012), POWER, 0.007)


## Silent Screws, on the frame's main propulsor (its "screw" mount: the duct's
## centre, half-height and half-width, squareness, half-length, how much it
## narrows at its exit, and whether a skirt fits there): a ribbed rubber
## damping collar round the duct, and at two a skirt of rubber chevrons
## trailing from its exit (or, on a duct already cut so, a second collar).
func _screws() -> void:
	var level := mini(_n(&"silent_screws"), 2)
	var screw: Variant = _mount(&"screw")
	if level == 0 or screw == null:
		return
	var s := screw as Array
	var centre: Vector3 = s[0]
	var half: Vector2 = s[1]
	var n: float = s[2]
	var half_len: float = s[3]
	var exit: float = s[4]
	var skirt: bool = s[5]
	var collars := [centre.x + half_len * 0.35]
	if level >= 2 and not skirt:
		collars.append(centre.x - half_len * 0.3)
	for x: float in collars:
		var rib := PackedVector2Array([Vector2(x - 0.05, 0.98)])
		for k in 5:
			rib.append(Vector2(x - 0.05 + k * 0.025, 1.07 if k % 2 == 0 else 1.095))
		rib.append(Vector2(x + 0.05, 0.98))
		_put(_ring_lathe(rib, centre, half, n), "rubber", Transform3D.IDENTITY)
	if level >= 2 and skirt:
		var lip := centre.x - half_len
		for k in 18:
			var a := TAU * (k + 0.5) / 18.0
			var q := _section(a, n)
			var out := Vector3(0.0, q.x * half.x, q.y * half.y).normalized()
			var base := Vector3(lip + 0.008, centre.y + q.x * half.x * exit, centre.z + q.y * half.y * exit)
			# Wide enough to touch their neighbours: one serrated skirt, its points turned in a little.
			var width := TAU * maxf(half.x, half.y) * exit / 18.0
			_put(_wedge(base, base + Vector3(-0.045, 0, 0) - out * 0.008, width, 0.008, out.cross(Vector3.RIGHT), out),
				"rubber", Transform3D.IDENTITY)
	var top := Vector3(collars[0] + 0.03, centre.y + half.x * 1.1, centre.z)
	_put(HullMesh.lathe(_ball(0.008, 6), 8, 0.0), UTIL.to_html(), Transform3D(Basis(), top))


## The Hydrodynamic Hull: a swept foil either side on the "foil" mounts, a
## steel leading edge and a light at its tip, longer as the card stacks;
## end plates at two, and a second, smaller pair aft at three.
func _foils() -> void:
	var level := mini(_n(&"hydrofoil"), 3)
	var foils: Variant = _mount(&"foil")
	if level == 0 or foils == null:
		return
	var span := 0.14 + 0.05 * level
	var aft: Array = m.mounts.get(&"foil_aft", [])
	for k in (foils as Array).size():
		var mount: Transform3D = foils[k]
		_foil(mount, span, level >= 2, true)
		if level >= 3:
			# The second pair on mounts of their own where the hull curves away aft.
			_foil(aft[k] if k < aft.size() else mount * _at(Vector3(-0.36, 0, 0)), span * 0.6, false, false)


## One foil along the mount's Y: swept and tapered, thick at the root and
## faired into the hull there, a steel leading edge.
func _foil(mount: Transform3D, span: float, plates: bool, lit: bool) -> void:
	_put(HullMesh.wing(Vector2(0.16, -0.14), Vector2(-0.02, -0.12), span, 0.14, 10, 16, 0.75, 1.2), "paint", mount)
	_put(HullMesh.rounded_box(Vector3(0.32, 0.05, 0.05), 0.018), "metal", mount, _at(Vector3(0.01, -0.012, 0)))
	_put(HullMesh.pipe(PackedVector3Array([Vector3(0.158, 0.012, 0.0), Vector3(-0.018, span - 0.004, 0.0)]), 0.005, 6),
		"steel", mount)
	if plates:
		_put(HullMesh.rounded_box(Vector3(0.11, 0.008, 0.07), 0.003, 1), "paint", mount,
			_at(Vector3(-0.07, span + 0.002, 0.0)))
	if lit:
		_led(mount, Vector3(-0.07, span + 0.01, 0.0), UTIL, 0.007)


# --- Utility -------------------------------------------------------------------------

## On the deck: the Magnet Coil, Deep Pockets' crates and the Pressure
## Compass; on the belly the Ink Sac and the Scavenger Protocol's gear.
func _utilities() -> void:
	_magnet()
	for k in mini(_n(&"lucky"), 2):
		var mount: Variant = _take(&"deck")
		if mount != null:
			_crate(mount)
	_compass()
	var salvage := mini(_n(&"scavenger"), 3)
	if salvage > 0:
		var belly: Variant = _take(&"belly")
		if belly != null:
			_scavenger(belly, salvage)
	if _n(&"ink") > 0:
		var belly: Variant = _take(&"belly")
		if belly != null:
			_ink_sac(belly)


## The Magnet Coil: an electromagnet on a plinth, an iron core between steel
## pole caps wound in copper, a glowing field ring over it; bigger at two,
## with a second ring.
func _magnet() -> void:
	var level := mini(_n(&"magnet_coil"), 2)
	if level == 0:
		return
	var mount: Variant = _take(&"deck")
	if mount == null:
		return
	var r := 0.045 + 0.016 * level
	var h := 0.085 + 0.03 * level
	_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.02, 0.001), Vector2(-0.02, r + 0.02), Vector2(0.012, r + 0.018),
		Vector2(0.02, r + 0.008), Vector2(0.022, 0.001)]), 20), "metal", mount, _stand(Vector3.ZERO))
	_put(HullMesh.lathe(PackedVector2Array([Vector2(0.02, 0.001), Vector2(0.02, 0.02), Vector2(h + 0.035, 0.02),
		Vector2(h + 0.035, 0.001)]), 12), "iron", mount, _stand(Vector3.ZERO))
	for y: float in [0.03, h + 0.025]:
		_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.006, 0.001), Vector2(-0.006, r + 0.01), Vector2(0.006, r + 0.01),
			Vector2(0.006, 0.001)]), 20), "steel", mount, _stand(Vector3(0, y, 0)))
	var turns := int((h - 0.03) / 0.015)
	for k in turns:
		_put(HullMesh.lathe(_torus(r, 0.008, 6), 20), "copper", mount, _stand(Vector3(0, 0.045 + k * 0.015, 0)))
	for k in level:
		_put(HullMesh.lathe(_torus(r + 0.02 + k * 0.02, 0.0035, 5), 24, 0.0), UTIL.to_html(), mount,
			_stand(Vector3(0, h + 0.06 + k * 0.03, 0)))
	_put(HullMesh.pipe(PackedVector3Array([Vector3(-r - 0.015, 0.012, 0.0), Vector3(-r - 0.04, 0.012, 0.0),
		Vector3(-r - 0.05, -0.02, 0.0)]), 0.006, 6, 0.015), "rubber", mount)
	_led(mount, Vector3(r + 0.018, 0.012, 0.0), UTIL, 0.008)


## Deep Pockets: a cargo crate strapped down, steel guards on its corners,
## latches and a carrying handle.
func _crate(mount: Transform3D) -> void:
	var size := Vector3(0.2, 0.1, 0.14)
	_put(HullMesh.rounded_box(size, 0.012), "crate", mount, _at(Vector3(0, 0.05, 0)))
	_put(HullMesh.rounded_box(Vector3(0.204, 0.012, 0.144), 0.004, 1), "olive", mount, _at(Vector3(0, 0.076, 0)))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_put(HullMesh.rounded_box(Vector3(0.024, 0.104, 0.024), 0.005, 1), "metal", mount,
				_at(Vector3(sx * 0.09, 0.05, sz * 0.06)))
		_put(HullMesh.rounded_box(Vector3(0.018, 0.022, 0.006), 0.002, 1), "steel", mount,
			_at(Vector3(sx * 0.045, 0.072, 0.072)))
	_put(HullMesh.pipe(PackedVector3Array([Vector3(-0.045, 0.1, 0.0), Vector3(-0.035, 0.122, 0.0),
		Vector3(0.035, 0.122, 0.0), Vector3(0.045, 0.1, 0.0)]), 0.005, 6, 0.01), "steel", mount)
	_put(HullMesh.rounded_box(Vector3(0.022, 0.106, 0.146), 0.004, 1), "rubber", mount, _at(Vector3(0.0, 0.05, 0)))
	_led(mount, Vector3(0.1, 0.035, 0.0), UTIL, 0.008)


## The Pressure Compass: a brass binnacle with a gimballed glass bowl and a lit needle.
func _compass() -> void:
	if _n(&"compass") == 0:
		return
	var mount: Variant = _take(&"deck")
	if mount == null:
		return
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


## The Ink Sac: a glossy black bladder on two brackets in strap bands, a
## nozzle pointing aft with a valve wheel on it.
func _ink_sac(mount: Transform3D) -> void:
	var at := _at(Vector3(0.01, 0.072, 0))
	_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.13, 0.001), Vector2(-0.115, 0.035), Vector2(-0.06, 0.06),
		Vector2(0.03, 0.062), Vector2(0.1, 0.045), Vector2(0.14, 0.02), Vector2(0.15, 0.001)]), 20), "ink", mount, at)
	for x: float in [-0.055, 0.045]:
		_put(HullMesh.lathe(_torus(0.0625, 0.005, 6), 20), "rubber", mount, at * _at(Vector3(x, 0, 0)))
		_put(HullMesh.rounded_box(Vector3(0.024, 0.024, 0.04), 0.005, 1), "metal", mount, _at(Vector3(x + 0.01, 0.006, 0)))
	var nozzle := at * _at(Vector3(-0.125, 0, 0))
	_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.075, 0.001), Vector2(-0.075, 0.012), Vector2(-0.07, 0.016),
		Vector2(-0.02, 0.012), Vector2(0.005, 0.02), Vector2(0.01, 0.001)]), 14), "steel", mount, nozzle)
	_put(HullMesh.lathe(_torus(0.014, 0.0028, 5), 14), "brass", mount, nozzle * _at(Vector3(-0.04, 0.026, 0),
		Vector3(0, 0, 90)))
	_put(HullMesh.pipe(PackedVector3Array([nozzle.origin - Vector3(0, 0, 0), nozzle * Vector3(-0.04, 0.026, 0)]), 0.003,
		4), "brass", Transform3D.IDENTITY)
	_led(mount, Vector3(0.06, 0.012, 0.03), UTIL, 0.008)


## The Scavenger Protocol: a wire salvage basket on brackets with scrap in it;
## at two a suction hose to an intake funnel ahead; at three a claw arm
## folded along its side.
func _scavenger(mount: Transform3D, level: int) -> void:
	var c := Vector3(0.0, 0.085, 0.0)
	var hx := 0.12
	var hy := 0.05
	var hz := 0.07
	for x: float in [-0.08, 0.08]:
		_put(HullMesh.rounded_box(Vector3(0.025, 0.05, 0.05), 0.006), "metal", mount, _at(Vector3(x, 0.02, 0)))
	# The frame's edges, and the mesh across its outer face and sides.
	var corners: Array[Vector3] = []
	for sy: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			corners.append(c + Vector3(0, sy * hy, sz * hz))
	for p: Vector3 in corners:
		_put(HullMesh.pipe(PackedVector3Array([p + Vector3(-hx, 0, 0), p + Vector3(hx, 0, 0)]), 0.004, 5), "steel", mount)
	for x: float in [-hx, hx]:
		var ring := PackedVector3Array([corners[0], corners[1], corners[3], corners[2], corners[0]])
		for k in ring.size():
			ring[k] += Vector3(x, 0, 0)
		_put(HullMesh.pipe(ring, 0.004, 5), "steel", mount)
	for k in 7:
		var x := lerpf(-hx, hx, (k + 0.5) / 7.0)
		_put(HullMesh.pipe(PackedVector3Array([c + Vector3(x, hy, -hz), c + Vector3(x, hy, hz)]), 0.0018, 4), "steel",
			mount)
		for sz: float in [-1.0, 1.0]:
			_put(HullMesh.pipe(PackedVector3Array([c + Vector3(x, -hy, sz * hz), c + Vector3(x, hy, sz * hz)]), 0.0018, 4),
				"steel", mount)
	# Scrap: a gear, a length of pipe and a bent plate.
	_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.006, 0.001), Vector2(-0.006, 0.026), Vector2(0.006, 0.026),
		Vector2(0.006, 0.001)]), 12), "brass", mount, _at(c + Vector3(-0.05, 0.02, 0.01), Vector3(20, 70, 0)))
	_put(HullMesh.bolt_ring(10, 0.026, 0.006), "brass", mount, _at(c + Vector3(-0.05, 0.02, 0.01), Vector3(20, 70, 0)))
	_put(HullMesh.pipe(PackedVector3Array([c + Vector3(0.0, 0.025, -0.04), c + Vector3(0.09, 0.03, 0.03)]), 0.012, 8),
		"iron", mount)
	_put(HullMesh.rounded_box(Vector3(0.08, 0.006, 0.05), 0.003, 1), "copper", mount,
		_at(c + Vector3(0.04, 0.035, -0.01), Vector3(15, 0, -25)))
	if level >= 2:
		var mouth := Vector3(hx + 0.12, c.y + 0.01, 0.0)
		_put(HullMesh.pipe(PackedVector3Array([c + Vector3(hx - 0.02, -hy * 0.4, 0.0), c + Vector3(hx + 0.04, -hy * 0.2, 0.0),
			mouth + Vector3(-0.03, 0, 0)]), 0.011, 8, 0.03), "rubber", mount)
		_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.035, 0.012), Vector2(0.0, 0.016), Vector2(0.03, 0.04),
			Vector2(0.034, 0.04), Vector2(0.034, 0.036), Vector2(0.004, 0.012)]), 16), "steel", mount, _at(mouth))
	if level >= 3:
		var base := c + Vector3(-hx + 0.02, -hy, hz + 0.012)
		var elbow := base + Vector3(0.11, 0.03, 0.01)
		var wrist := elbow + Vector3(0.09, 0.035, 0.0)
		_put(HullMesh.pipe(PackedVector3Array([base, elbow, wrist]), 0.008, 6), "steel", mount)
		for p: Vector3 in [base, elbow]:
			_put(HullMesh.lathe(_ball(0.013, 6), 8), "metal", mount, _at(p))
		for sgn: float in [-1.0, 1.0]:
			_put(HullMesh.pipe(PackedVector3Array([wrist, wrist + Vector3(0.025, sgn * 0.016, 0.0),
				wrist + Vector3(0.045, sgn * 0.006, 0.0)]), 0.004, 5, 0.008), "steel", mount)
	_led(mount, c + Vector3(-hx - 0.006, -hy * 0.5, 0.0), UTIL, 0.008)


# --- Shapes --------------------------------------------------------------------------

## A point round a section of squareness [param n] at angle [param a]: (up, out), each -1..1.
static func _section(a: float, n: float) -> Vector2:
	var cs := cos(a)
	var sn := sin(a)
	return Vector2(signf(sn) * pow(absf(sn), 2.0 / n), signf(cs) * pow(absf(cs), 2.0 / n))


## A ring round the X axis through [param centre]: [param profile] is (x,
## radius as a share of [param half] (height, width)), its section of
## squareness [param n]; outside on the left of travel, as for HullMesh.lathe.
static func _ring_lathe(profile: PackedVector2Array, centre: Vector3, half: Vector2, n: float) -> ArrayMesh:
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
		var q := _section(v * TAU, n)
		return Vector3(p.x, centre.y + q.x * p.y * half.x, centre.z + q.y * p.y * half.y)
	# Which way the faces turn, judged on the longest run of the profile.
	var best := 0
	for k in profile.size() - 1:
		if absf(profile[k + 1].x - profile[k].x) > absf(profile[best + 1].x - profile[best].x):
			best = k
	var u := (lengths[best] + lengths[best + 1]) * 0.5 / total
	var at := fn.call(u, 0.2) as Vector3
	var du := (fn.call(u + 0.005, 0.2) as Vector3) - (fn.call(u - 0.005, 0.2) as Vector3)
	var dv := (fn.call(u, 0.21) as Vector3) - (fn.call(u, 0.19) as Vector3)
	var faces_out := du.cross(dv).dot(at - Vector3(at.x, centre.y, centre.z)) > 0.0
	var wants_out := profile[best + 1].x > profile[best].x
	return HullMesh.surface(fn, profile.size() * 3, 48, faces_out != wants_out)


## A faceted wedge from [param a] to a point at [param b], [param width]
## across along [param across] and [param thick] through along [param out].
static func _wedge(a: Vector3, b: Vector3, width: float, thick: float, across: Vector3, out: Vector3) -> ArrayMesh:
	var fn := func(u: float, v: float) -> Vector3:
		var k := 1.0 - u * 0.97
		var ang := v * TAU
		var cs := cos(ang)
		var sn := sin(ang)
		return a.lerp(b, u) + across * width * 0.5 * k * signf(cs) * cs * cs + out * thick * 0.5 * k * signf(sn) * sn * sn
	var p := fn.call(0.5, 0.25) as Vector3
	var du := (fn.call(0.52, 0.25) as Vector3) - (fn.call(0.48, 0.25) as Vector3)
	var dv := (fn.call(0.5, 0.27) as Vector3) - (fn.call(0.5, 0.23) as Vector3)
	return HullMesh.surface(fn, 4, 8, du.cross(dv).dot(p - a.lerp(b, 0.5)) < 0.0)
