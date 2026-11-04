class_name SubLaunchers
extends SubEquipmentBase
## The launchers of a submarine's kit (see SubEquipment): flares, torpedoes,
## decoys and the shock emitter, each changing with the cards that feed it.

# --- The tools -----------------------------------------------------------------------

## The flares. A launcher (on a sub that has one): tubes in a clamped pack on
## a yoke, angled up and forward, a flare's red cap in each mouth. Flare Pouch
## straps canvas pouches of spare cartridges behind it (a third tube with the
## second, and with the third a belt of cartridges feeding the breech and a
## fourth tube). Emergency Flares alone give an orange distress canister on a
## saddle, more strapped alongside as Flare Pouch stacks; on a sub that already
## has a launcher, a spare canister lashed beside it.
func _flares() -> void:
	var mount: Variant = _mount(&"flare")
	if mount == null or not (tools.has(&"flare") or _n(&"flare_kit") > 0):
		return
	var pouch := mini(_n(&"flare_pouch"), 3)
	if tools.has(&"flare"):
		var width := _flare_launcher(mount, pouch)
		if _n(&"flare_kit") > 0:
			_flare_canister(mount, Vector3(-0.01, 0.024, width * 0.5 + 0.05), 0.0, false)
	else:
		var count := 1 + maxi(pouch - 1, 0)
		for k in count:
			_flare_canister(mount, Vector3(0.0, 0.058, (k - (count - 1) * 0.5) * 0.056), 24.0, k == 0)
		_led(mount, Vector3(0.062, 0.05, (count - 1) * 0.028 + 0.022), LIGHT, 0.008)
	for k in mini(pouch, 2):
		_flare_pouch(mount, Vector3(-0.135, -0.006, 0.034 if k == 0 else -0.034))
	if pouch >= 3:
		_flare_belt(mount)


## The launcher proper; returns its width.
func _flare_launcher(mount: Transform3D, pouch: int) -> float:
	var tubes := 2 + maxi(pouch - 1, 0)
	var pitch := 0.05
	var pack_w := (tubes - 1) * pitch + 0.05
	# Base plate bolted down, two cheeks and the pivot pin through them.
	_put(HullMesh.rounded_box(Vector3(0.17, 0.05, pack_w + 0.06), 0.006), "metal", mount, _at(Vector3(0, -0.007, 0)))
	for x: float in [-0.07, 0.07]:
		for sgn: float in [-1.0, 1.0]:
			_put(HullMesh.bolt_head(0.008), "steel", mount, _at(Vector3(x, 0.018, sgn * (pack_w * 0.5 + 0.018)),
				Vector3(0, 0, 90)))
	var pivot := Vector3(-0.005, 0.092, 0.0)
	for sgn: float in [-1.0, 1.0]:
		var z := sgn * (pack_w * 0.5 + 0.009)
		_put(HullMesh.rounded_box(Vector3(0.065, 0.085, 0.012), 0.005), "metal", mount, _at(Vector3(pivot.x, 0.058, z)))
		_put(HullMesh.lathe(PackedVector2Array([Vector2(0.0, 0.001), Vector2(0.0, 0.016), Vector2(0.008, 0.014),
			Vector2(0.01, 0.001)]), 12), "steel", mount, Transform3D(Basis(Vector3.UP, -sgn * PI * 0.5),
			pivot + Vector3(0, 0, z + sgn * 0.006)))
	# The elevation quadrant on the near cheek.
	var arc := PackedVector3Array()
	for k in 9:
		var a := deg_to_rad(lerpf(-150.0, -60.0, k / 8.0))
		arc.append(pivot + Vector3(cos(a) * 0.05, sin(a) * 0.05, pack_w * 0.5 + 0.017))
	_put(HullMesh.pipe(arc, 0.004, 5), "brass", mount)
	# The pack: tubes side by side, pitched up 40 degrees.
	var pack := mount * Transform3D(Basis(Vector3.BACK, deg_to_rad(40.0)), pivot)
	for k in tubes:
		var at := _at(Vector3(0, 0, (k - (tubes - 1) * 0.5) * pitch))
		_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.058, 0.001), Vector2(-0.058, 0.019), Vector2(-0.054, 0.021),
			Vector2(0.118, 0.021), Vector2(0.118, 0.024), Vector2(0.134, 0.024), Vector2(0.134, 0.017),
			Vector2(0.134, 0.017), Vector2(0.1, 0.017)]), 16), "metal", pack, at)
		_put(HullMesh.lathe(PackedVector2Array([Vector2(0.1, 0.001), Vector2(0.1, 0.0165), Vector2(0.114, 0.0162),
			Vector2(0.122, 0.011), Vector2(0.125, 0.001)]), 14, 0.0), "flare_glow", pack, at)
	for x: float in [-0.028, 0.078]:
		_put(HullMesh.rounded_box(Vector3(0.022, 0.05, pack_w + 0.006), 0.007), "paint", pack, _at(Vector3(x, 0, 0)))
	_put(HullMesh.rounded_box(Vector3(0.016, 0.048, pack_w), 0.006), "metal", pack, _at(Vector3(-0.064, 0, 0)))
	# The firing lead from the breech down into the base.
	_put(HullMesh.pipe(PackedVector3Array([pivot + Basis(Vector3.BACK, deg_to_rad(40.0)) * Vector3(-0.07, 0.0, 0.0),
		Vector3(-0.075, 0.03, 0.0), Vector3(-0.075, 0.012, 0.0)]), 0.006, 6, 0.012), "rubber", mount)
	_led(mount, Vector3(pivot.x + 0.02, 0.03, pack_w * 0.5 + 0.017), LIGHT, 0.008)
	m.add_muzzle(&"flare", pack * Vector3(0.15, 0, 0))
	return pack_w + 0.06


## An orange distress canister along +X from [param at], pitched up by
## [param pitch] degrees on a saddle with hose clamps, a pull ring at the back.
func _flare_canister(mount: Transform3D, at: Vector3, pitch: float, muzzle: bool) -> void:
	var tilt := Basis(Vector3.BACK, deg_to_rad(pitch))
	var can := mount * Transform3D(tilt, at)
	_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.1, 0.001), Vector2(-0.1, 0.018), Vector2(-0.095, 0.021),
		Vector2(0.09, 0.021), Vector2(0.094, 0.018), Vector2(0.094, 0.001)]), 16), "safety", can)
	_put(HullMesh.lathe(PackedVector2Array([Vector2(0.03, 0.0208), Vector2(0.03, 0.0222), Vector2(0.056, 0.0222),
		Vector2(0.056, 0.0208)]), 16, 0.0), "ceramic", can)
	_put(HullMesh.lathe(PackedVector2Array([Vector2(0.092, 0.001), Vector2(0.092, 0.0175), Vector2(0.106, 0.0175),
		Vector2(0.112, 0.011), Vector2(0.114, 0.001)]), 14, 0.0), "flare_glow", can)
	for x: float in [-0.055, 0.05]:
		_put(HullMesh.lathe(_torus(0.0215, 0.0035, 6), 16), "steel", can, _at(Vector3(x, 0, 0)))
	# The pull ring on a short cord.
	_put(HullMesh.pipe(PackedVector3Array([Vector3(-0.1, 0, 0), Vector3(-0.118, 0, 0)]), 0.0025, 4), "rubber", can)
	_put(HullMesh.lathe(_torus(0.011, 0.0025, 5), 12), "steel", can, _at(Vector3(-0.129, 0, 0), Vector3(0, 90, 0)))
	# The saddle: a block under the front clamp, the back end resting on the hull.
	var front := at + tilt * Vector3(0.05, -0.021, 0)
	var foot := maxf(front.y, 0.012)
	_put(HullMesh.rounded_box(Vector3(0.03, foot + 0.046, 0.036), 0.005), "metal", mount,
		_at(Vector3(front.x, foot * 0.5 - 0.02, at.z)))
	var back := at + tilt * Vector3(-0.055, -0.021, 0)
	_put(HullMesh.rounded_box(Vector3(0.026, maxf(back.y, 0.0) + 0.046, 0.036), 0.005), "metal", mount,
		_at(Vector3(back.x, maxf(back.y, 0.0) * 0.5 - 0.02, at.z)))
	if muzzle:
		m.add_muzzle(&"flare", can * Vector3(0.13, 0, 0))


## A canvas pouch of spare cartridges, brass heads up, its flap thrown back.
func _flare_pouch(mount: Transform3D, at: Vector3) -> void:
	_put(HullMesh.rounded_box(Vector3(0.06, 0.1, 0.056), 0.017), "canvas", mount, _at(at + Vector3(0, 0.03, 0)))
	_put(HullMesh.rounded_box(Vector3(0.008, 0.045, 0.054), 0.004), "canvas", mount,
		_at(at + Vector3(-0.036, 0.066, 0), Vector3(0, 0, -18)))
	_put(HullMesh.rounded_box(Vector3(0.064, 0.012, 0.06), 0.005), "rubber", mount, _at(at + Vector3(0, 0.036, 0)))
	_put(HullMesh.rounded_box(Vector3(0.006, 0.016, 0.014), 0.002, 1), "steel", mount,
		_at(at + Vector3(0.033, 0.036, 0)))
	for k in 3:
		var z := (k - 1) * 0.017
		_flare_shell(mount, Transform3D(Basis(Vector3.BACK, PI * 0.5).rotated(Vector3.BACK, (k - 1) * -0.08),
			at + Vector3((1 - k) * 0.004, 0.05, z)))


## One flare cartridge along +X from [param t]: a red hull and a brass head.
func _flare_shell(mount: Transform3D, t: Transform3D) -> void:
	_put(HullMesh.lathe(PackedVector2Array([Vector2(0.0, 0.001), Vector2(0.0, 0.0105), Vector2(0.044, 0.0105),
		Vector2(0.044, 0.001)]), 12), "flare_red", mount, t)
	_put(HullMesh.lathe(PackedVector2Array([Vector2(0.043, 0.0108), Vector2(0.054, 0.0108), Vector2(0.055, 0.0125),
		Vector2(0.058, 0.0125), Vector2(0.058, 0.001)]), 12), "brass", mount, t)


## Flare Pouch three times: a belt of cartridges out of the near pouch, over
## and down into a feed box on the launcher's breech.
func _flare_belt(mount: Transform3D) -> void:
	var z := 0.034
	var p0 := Vector3(-0.135, 0.11, z)
	var p1 := Vector3(-0.115, 0.165, z)
	var p2 := Vector3(-0.07, 0.1, z)
	_put(HullMesh.rounded_box(Vector3(0.034, 0.042, 0.06), 0.006), "metal", mount, _at(p2 + Vector3(0, -0.028, 0)))
	var pts := PackedVector3Array()
	for k in 8:
		var t := k / 7.0
		var p := p0.lerp(p1, t).lerp(p1.lerp(p2, t), t)
		var d := (p1 - p0).lerp(p2 - p1, t).normalized()
		pts.append(p)
		# Each round across the belt, its brass head to the near side.
		var across := Basis(Vector3.UP, -PI * 0.5)
		_flare_shell(mount, Transform3D(Basis(Vector3.BACK, atan2(d.y, d.x)) * across, p + Vector3(0, 0, -0.03)))
	for dz: float in [-0.024, 0.016]:
		var link := PackedVector3Array()
		for p: Vector3 in pts:
			link.append(p + Vector3(0, 0, dz))
		_put(HullMesh.pipe(link, 0.003, 4), "steel", mount)


## The torpedoes. On a sub with a torpedo bay, a pod either side: a nacelle
## in the sub's paint on a pylon, the tubes' mouths in a steel bezel at its
## nose, fins at its tail. Torpedo Rack gives each pod a second and third tube
## (the nacelle swelling to take them) and at three a spare torpedo clamped
## under it. Shaped Warhead shows yellow warheads in the mouths, and at two
## standoff probes ahead of them. A Salvaged Torpedo Tube alone gives a rusty
## iron tube strapped to the near side, a handwheel on its breech (bundled
## with more as Torpedo Rack stacks); on a sub with pods already, one strapped
## on top of the near pod.
func _torpedoes() -> void:
	var mounts: Variant = _mount(&"torpedo")
	if mounts == null or (mounts as Array).is_empty() or not (tools.has(&"torpedo") or _n(&"torpedo_kit") > 0):
		return
	var rack := mini(_n(&"torpedo_rack"), 3)
	var warhead := mini(_n(&"warhead"), 2)
	var tubes := 1 + mini(rack, 2)
	if not tools.has(&"torpedo"):
		_salvaged_tubes(mounts[0], tubes, warhead, Vector3(0, 0.075, 0))
		return
	var first := true
	for mount: Transform3D in mounts:
		var muzzle := _torpedo_pod(mount, tubes, warhead, rack >= 3, first and _n(&"torpedo_kit") > 0)
		if first:
			m.add_muzzle(&"torpedo", mount * muzzle)
		first = false


## One pod; returns its muzzle in the mount's frame.
func _torpedo_pod(mount: Transform3D, tubes: int, warhead: int, spare: bool, salvaged: bool) -> Vector3:
	var r: float = [0.048, 0.06, 0.07][tubes - 1]
	var gap := 0.045
	var pod := mount * _at(Vector3(0, gap + r, 0))
	var down := _down(mount)
	# The pylon, a little into the hull.
	_put(HullMesh.rounded_box(Vector3(0.24, gap + r * 0.6 + 0.02, 0.024), 0.008), "metal", mount,
		_at(Vector3(-0.03, (gap + r * 0.6) * 0.5 - 0.01, 0)))
	# The nacelle, its tail capped in metal.
	_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.28, 0.001), Vector2(-0.28, r * 0.5), Vector2(-0.22, r * 0.86),
		Vector2(-0.14, r * 0.99), Vector2(0.24, r), Vector2(0.255, r * 0.985), Vector2(0.255, 0.001)]), 24), "paint", pod)
	_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.33, 0.001), Vector2(-0.325, r * 0.2), Vector2(-0.3, r * 0.42),
		Vector2(-0.279, r * 0.5), Vector2(-0.279, 0.001)]), 18), "metal", pod)
	# The bezel and the dark face of the nose.
	_put(HullMesh.lathe(PackedVector2Array([Vector2(0.244, r * 1.012), Vector2(0.268, r * 1.012),
		Vector2(0.276, r * 0.96), Vector2(0.276, r * 0.88), Vector2(0.276, r * 0.88), Vector2(0.262, r * 0.88)]), 24),
		"steel", pod)
	_put(HullMesh.lathe(PackedVector2Array([Vector2(0.25, r * 0.89), Vector2(0.266, r * 0.89), Vector2(0.266, 0.001)]),
		24, 0.0), "metal", pod)
	var rt: float = [0.024, 0.019, 0.017][tubes - 1]
	for k in tubes:
		var o := Vector3.ZERO
		if tubes == 2:
			o = Vector3(0, 0, (k - 0.5) * 0.054)
		elif tubes == 3:
			var a := TAU * k / 3.0 + PI * 0.5
			o = Vector3(0, cos(a), sin(a)) * 0.034
		_torpedo_mouth(pod * _at(Vector3(0.266, 0, 0) + o), rt, warhead)
	# Fins at the tail, crosswise.
	for k in 4:
		var turn := Basis(Vector3.RIGHT, PI * 0.25 + PI * 0.5 * k)
		_put(HullMesh.rounded_box(Vector3(0.07, 0.04, 0.004), 0.0015, 1), "paint", pod,
			Transform3D(turn, turn * Vector3(-0.25, r * 0.6 + 0.02, 0)))
	_led(pod, Vector3(-0.17, r * 0.97, 0.0), WEAPON, 0.009)
	if spare:
		# A reload clamped under the pod.
		var at := Vector3(-0.04, 0, down * (r + 0.027))
		_torpedo_round(pod * _at(at), warhead)
		for x: float in [-0.1, 0.05]:
			_put(HullMesh.rounded_box(Vector3(0.018, 0.022, 0.016), 0.004, 1), "metal", pod,
				_at(Vector3(x, 0, down * (r + 0.004))))
			_put(HullMesh.lathe(_torus(0.0215, 0.003, 5), 14), "steel", pod, _at(at + Vector3(x - at.x, 0, 0)))
	if salvaged:
		_salvaged_tubes(mount, 1, warhead, Vector3(-0.02, gap + r, -down * (r + 0.033)))
	return Vector3(0.3, gap + r, 0)


## A tube's mouth at [param t] (facing +X): a steel rim round a dark bore and
## the torpedo's nose showing in it.
func _torpedo_mouth(t: Transform3D, rt: float, warhead: int) -> void:
	_put(HullMesh.lathe(_torus(rt, 0.0035, 6), 16), "steel", t, _at(Vector3(0.002, 0, 0)))
	_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.004, rt), Vector2(0.001, rt), Vector2(0.001, 0.001)]), 16, 0.0),
		"rubber", t)
	_torpedo_nose(t, rt * 0.85, warhead)


## A torpedo's nose along +X from [param t]: blunt steel, a yellow warhead
## with a black band, and with two Shaped Warheads a standoff probe.
func _torpedo_nose(t: Transform3D, r: float, warhead: int) -> void:
	if warhead == 0:
		_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.01, r), Vector2(0.002, r), Vector2(0.012, r * 0.7),
			Vector2(0.018, 0.001)]), 14), "steel", t)
		return
	_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.01, r), Vector2(0.006, r), Vector2(0.024, r * 0.72),
		Vector2(0.038, r * 0.3), Vector2(0.041, 0.001)]), 14), "warhead", t)
	_put(HullMesh.lathe(PackedVector2Array([Vector2(0.002, r * 1.02), Vector2(0.009, r * 1.02), Vector2(0.009, r * 0.9)]),
		14, 0.0), "rubber", t)
	if warhead >= 2:
		_put(HullMesh.pipe(PackedVector3Array([Vector3(0.036, 0, 0), Vector3(0.09, 0, 0)]), 0.0035, 6), "steel", t)
		_put(HullMesh.lathe(PackedVector2Array([Vector2(0.086, 0.001), Vector2(0.086, 0.008), Vector2(0.093, 0.008),
			Vector2(0.096, 0.001)]), 12), "copper", t)


## A whole torpedo along +X from [param t]: olive body, nose by warhead,
## fins and a little screw at its tail.
func _torpedo_round(t: Transform3D, warhead: int) -> void:
	var r := 0.02
	_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.15, 0.001), Vector2(-0.15, r * 0.45), Vector2(-0.12, r * 0.95),
		Vector2(0.1, r), Vector2(0.11, r), Vector2(0.11, 0.001)]), 16), "olive", t)
	_torpedo_nose(t * _at(Vector3(0.11, 0, 0)), r, warhead)
	for k in 4:
		var turn := Basis(Vector3.RIGHT, PI * 0.5 * k)
		_put(HullMesh.rounded_box(Vector3(0.03, 0.016, 0.003), 0.001, 1), "olive", t,
			Transform3D(turn, turn * Vector3(-0.135, r * 0.6 + 0.008, 0)))
	_put(HullMesh.blades(3, 0.004, 0.017, 0.012), "brass", t, _at(Vector3(-0.158, 0, 0)))


## Salvaged tubes: rusty iron with a handwheel on the breech, bundled with
## rubber straps, on a saddle; [param at] is the first tube's centre.
func _salvaged_tubes(mount: Transform3D, count: int, warhead: int, at: Vector3) -> void:
	var down := _down(mount)
	var rt := 0.03
	var centres: Array[Vector3] = []
	for k in count:
		var o := Vector3.ZERO
		if k == 1:
			o = Vector3(0, 0, -down * 0.064)
		elif k == 2:
			o = Vector3(0, 0.055, -down * 0.032)
		centres.append(at + o)
	for c: Vector3 in centres:
		var t := mount * _at(c)
		_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.25, 0.001), Vector2(-0.25, rt * 0.9), Vector2(-0.24, rt),
			Vector2(0.22, rt), Vector2(0.22, rt * 1.18), Vector2(0.25, rt * 1.18), Vector2(0.25, rt * 0.82),
			Vector2(0.25, rt * 0.82), Vector2(0.2, rt * 0.82)]), 18), "iron", t)
		_put(HullMesh.lathe(PackedVector2Array([Vector2(0.12, rt * 0.99), Vector2(0.12, rt * 1.04), Vector2(0.15, rt * 1.04),
			Vector2(0.15, rt * 0.99)]), 18, 0.0), "safety", t)
		_put(HullMesh.lathe(PackedVector2Array([Vector2(0.2, rt * 0.82), Vector2(0.2, 0.001)]), 16, 0.0), "rubber", t)
		_torpedo_nose(t * _at(Vector3(0.2, 0, 0)), rt * 0.75, warhead)
		# The breech's handwheel: a brass rim on four spokes.
		var wheel := t * _at(Vector3(-0.265, 0, 0))
		_put(HullMesh.lathe(_torus(0.026, 0.004, 6), 16), "brass", wheel)
		_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.006, 0.001), Vector2(-0.006, 0.008), Vector2(0.015, 0.008),
			Vector2(0.015, 0.001)]), 10), "brass", wheel)
		for k in 4:
			var a := PI * 0.5 * k + PI * 0.25
			_put(HullMesh.pipe(PackedVector3Array([Vector3(0, cos(a), sin(a)) * 0.006, Vector3(0, cos(a), sin(a)) * 0.024]),
				0.0025, 4), "brass", wheel)
	for x: float in [-0.13, 0.07]:
		for c: Vector3 in centres:
			_put(HullMesh.lathe(_torus(rt + 0.003, 0.005, 6), 16), "rubber", mount, _at(c + Vector3(x, 0, 0)))
		# A saddle from the hull up to the bundle.
		var low: Vector3 = centres[0]
		_put(HullMesh.rounded_box(Vector3(0.03, low.y - rt + 0.04, 0.05), 0.006), "metal", mount,
			_at(Vector3(x, (low.y - rt) * 0.5 - 0.02, low.z)))
	if not tools.has(&"torpedo"):
		_led(mount, Vector3(-0.2, at.y + rt * 0.9, at.z), WEAPON, 0.009)
		m.add_muzzle(&"torpedo", mount * (at + Vector3(0.3, 0, 0)))


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


## The shock emitter: a tower on an insulated housing, a glowing orb held in
## a copper ring at its top that flares as the pulse fires. Arc Coil winds
## the tower into a copper coil and swells the ring; at two, electrodes on
## outriggers either side arc to the orb, and a row of capacitor jars stands
## on the plinth behind.
func _shock() -> void:
	var mount: Variant = _mount(&"shock")
	if mount == null:
		return
	mount = (mount as Transform3D).scaled_local(Vector3.ONE * 1.45)
	var coil := mini(_n(&"capacitor_coil"), 2)
	# Lit, not flat: its emission is what flash_shock() drives.
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.12, 0.3, 0.42)
	glow.roughness = 0.15
	glow.emission_enabled = true
	glow.emission = Color(0.45, 0.85, 1.0)
	glow.emission_energy_multiplier = 1.6
	mats["shock_glow"] = glow
	m.set_shock_glow(glow)
	# The plinth clamped to the frame, bolted at its corners, and the housing on it.
	var plinth := Vector3(0.16, 0.03, 0.18) + (Vector3(0.1, 0, 0.08) if coil >= 2 else Vector3.ZERO)
	_put(HullMesh.rounded_box(plinth, 0.008), "metal", mount, _at(Vector3(-0.02 if coil >= 2 else 0.0, 0.012, 0)))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var x := (-0.02 if coil >= 2 else 0.0) + sx * (plinth.x * 0.5 - 0.016)
			_put(HullMesh.bolt_head(0.007), "steel", mount, _at(Vector3(x, 0.027, sz * (plinth.z * 0.5 - 0.016)),
				Vector3(0, 0, 90)))
	_put(HullMesh.rounded_box(Vector3(0.11, 0.07, 0.11), 0.014), "paint", mount, _at(Vector3(0, 0.06, 0)))
	_put(HullMesh.rounded_box(Vector3(0.116, 0.012, 0.116), 0.004), "metal", mount, _at(Vector3(0, 0.098, 0)))
	_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.003, 0.014), Vector2(0.004, 0.014), Vector2(0.004, 0.001)]), 14),
		"brass", mount, _at(Vector3(0.054, 0.06, -0.022)))
	_led(mount, Vector3(0.058, 0.062, 0.026), WEAPON, 0.009)
	# The tower: a ceramic insulator, or with an Arc Coil a former wound in copper.
	if coil == 0:
		var profile := PackedVector2Array([Vector2(0.1, 0.001), Vector2(0.1, 0.024)])
		for k in 4:
			var h := 0.128 + k * 0.036
			profile.append_array(PackedVector2Array([Vector2(h - 0.01, 0.024), Vector2(h - 0.004, 0.046),
				Vector2(h + 0.004, 0.046), Vector2(h + 0.009, 0.024)]))
		profile.append_array(PackedVector2Array([Vector2(0.266, 0.022), Vector2(0.272, 0.001)]))
		_put(HullMesh.lathe(profile, 20), "ceramic", mount, _stand(Vector3.ZERO))
	else:
		_put(HullMesh.lathe(PackedVector2Array([Vector2(0.1, 0.001), Vector2(0.1, 0.03), Vector2(0.108, 0.05),
			Vector2(0.117, 0.05), Vector2(0.125, 0.027), Vector2(0.245, 0.027), Vector2(0.253, 0.05), Vector2(0.262, 0.05),
			Vector2(0.27, 0.03), Vector2(0.274, 0.001)]), 20), "ceramic", mount, _stand(Vector3.ZERO))
		var helix := PackedVector3Array()
		for k in 121:
			var t := k / 120.0
			var a := t * TAU * 11.0
			helix.append(Vector3(cos(a) * 0.03, 0.132 + t * 0.108, sin(a) * 0.03))
		_put(HullMesh.pipe(helix, 0.0034, 5), "copper", mount)
	# The orb in its ring on a copper neck.
	var top := 0.31 if coil == 0 else 0.325
	var ring_r := 0.055 if coil == 0 else 0.07
	var tube := 0.017 if coil == 0 else 0.021
	var orb := ring_r - tube + 0.009
	_put(HullMesh.pipe(PackedVector3Array([Vector3(0, 0.26, 0), Vector3(0, top, 0)]), 0.009, 8), "copper", mount)
	_put(HullMesh.lathe(_torus(ring_r, tube, 10), 28), "copper", mount, _stand(Vector3(0, top, 0)))
	_put(HullMesh.lathe(_ball(orb, 12), 18, 0.0), "shock_glow", mount, _at(Vector3(0, top, 0)))
	if coil >= 2:
		for sgn: float in [-1.0, 1.0]:
			var tip := Vector3(0.0, 0.235, sgn * 0.16)
			_put(HullMesh.pipe(PackedVector3Array([Vector3(0.0, 0.025, sgn * 0.105), Vector3(0.0, 0.12, sgn * 0.16), tip]),
				0.006, 6, 0.03), "steel", mount)
			_put(HullMesh.lathe(PackedVector2Array([Vector2(-0.016, 0.001), Vector2(-0.016, 0.01), Vector2(-0.01, 0.022),
				Vector2(-0.004, 0.022), Vector2(0.0, 0.01), Vector2(0.006, 0.022), Vector2(0.012, 0.022), Vector2(0.016, 0.01),
				Vector2(0.016, 0.001)]), 14), "ceramic", mount, _stand(Vector3(0.0, 0.17, sgn * 0.16)))
			_put(HullMesh.lathe(_ball(0.022, 10), 14), "copper", mount, _at(tip + Vector3(0, 0.014, 0)))
			# A forked arc from the electrode to the orb.
			var from := tip + Vector3(0, 0.02, -sgn * 0.02)
			var to := Vector3(0, top, sgn * orb * 0.9)
			var jag := [0.0, 0.014, -0.011, 0.016, -0.009, 0.007, 0.0]
			var arc := PackedVector3Array()
			for k in jag.size():
				var t := float(k) / (jag.size() - 1)
				arc.append(from.lerp(to, t) + Vector3(jag[k], jag[(k + 2) % jag.size()] * 0.6, 0))
			_put(HullMesh.pipe(arc, 0.0028, 4), "shock_glow", mount)
		# Capacitor jars behind: glass, copper-lined, brass knobs.
		for z: float in [-0.06, 0.0, 0.06]:
			var at := Vector3(-0.1, 0.027, z)
			_put(HullMesh.lathe(PackedVector2Array([Vector2(0.0, 0.001), Vector2(0.0, 0.018), Vector2(0.056, 0.018),
				Vector2(0.062, 0.012), Vector2(0.062, 0.001)]), 14), "glass", mount, _stand(at))
			_put(HullMesh.lathe(PackedVector2Array([Vector2(0.0, 0.0185), Vector2(0.032, 0.0185), Vector2(0.032, 0.001)]),
				14, 0.0), "copper", mount, _stand(at))
			_put(HullMesh.pipe(PackedVector3Array([at + Vector3(0, 0.05, 0), at + Vector3(0, 0.085, 0)]), 0.003, 5), "brass",
				mount)
			_put(HullMesh.lathe(_ball(0.008, 8), 10), "brass", mount, _at(at + Vector3(0, 0.088, 0)))
	m.add_muzzle(&"shock", mount * Vector3(0, top, 0))
