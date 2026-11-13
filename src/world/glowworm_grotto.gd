class_name GlowwormGrotto
extends Entity
## A chamber in the Midnight Caverns whose ceiling is strung with glow-worms:
## a sky of small cold lights in the pitch dark, each worm letting down a
## few silk snares beaded with sticky droplets that shine like strings of
## pearls in its light, swaying slowly in the current. They dim at sound.
## Every noise darkens the worms within its reach, the dark spreading
## out from it like a ripple, and they only light again after a few quiet
## seconds. Drift through slowly and the grotto lights your way without the
## lamp; race through and it goes black around you.

## Fraction of a noise's radius within which worms go dark.
const REACH := 0.6
## How fast the dark spreads from a noise, in metres per second.
const RIPPLE_SPEED := 9.0
## How long a worm stays dark after the last noise reached it.
const DARK_TIME := 4.0
const RELIGHT_RATE := 0.3
## (Each worm's light pulls back up its snares from the tips as it dims, and
## runs back down them from the worm as it relights.)
const DIM_RATE := 2.0
## Spacing of worms along the ceiling.
const SPACING := 0.3
const LIGHTS := 4
const GLOW := Color(0.35, 1.0, 0.8)
## How many snares each worm lets down, and how long the longest are.
const SNARES := Vector2i(3, 6)
const SNARE_LENGTH := 2.6
## Droplets strung along a snare, one every this far.
const BEAD_EVERY := 0.17
const SHADER := preload("res://src/fx/shaders/glowworm.gdshader")

## Shown once per session, the first time the sub enters one.
static var _explained := false

## The chamber it fills.
var room: LevelLayout.Chamber
var worm_pos: Array[Vector3] = []
var lit := PackedFloat32Array()
var _dark_from := PackedFloat32Array()
var _dark_until := PackedFloat32Array()
var _lights: Array[OmniLight3D] = []
## Each worm's brightness, one texel per worm, read by everything it lights.
var _lit_image: Image
var _lit_texture: ImageTexture


## Fills a roomy chamber along the main path with glow-worms; returns the
## grotto, or null if the zone has no chamber with ceiling enough.
static func place(level: Level, rng: RandomNumberGenerator) -> GlowwormGrotto:
	var layout := level.layout
	var rooms := layout.chambers_of_kind(&"main")
	for i in range(rooms.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp: LevelLayout.Chamber = rooms[i]
		rooms[i] = rooms[j]
		rooms[j] = tmp
	for room in rooms:
		if room.center.distance_to(layout.start) < 25.0 or room.center.distance_to(layout.exit) < 30.0:
			continue
		if LevelPopulator.in_guarded_room(level, room.center):
			continue
		var grotto := GlowwormGrotto.new()
		grotto.room = room
		grotto.pos = room.center
		if grotto._find_worms(level.field, rng) < 40:
			grotto.free()
			continue
		level.add_entity(grotto)
		return grotto
	return null


## The ceiling straight above [param p] (in open water), or INF if there is
## none within [param max_rise].
static func ceiling_above(field: TerrainField, p: Vector2, max_rise: float) -> float:
	if field.sample(p) <= 0.5:
		return INF
	var q := p
	while q.y - p.y < max_rise:
		if field.sample(q) < 0.05:
			return q.y
		q.y += 0.25
	return INF


## Strings worms along the chamber ceiling; returns how many.
func _find_worms(field: TerrainField, rng: RandomNumberGenerator) -> int:
	worm_pos.clear()
	var x := room.center.x - room.radius.x * 0.9
	while x < room.center.x + room.radius.x * 0.9:
		var top := ceiling_above(field, Vector2(x, room.center.y), room.radius.y + 6.0)
		if top != INF:
			for _k in 3:
				var z := rng.randf_range(-2.5, 0.8)
				# The relief sits lower towards the back of the cave.
				var y := top - PropScatter.surface_offset(z) - 0.05
				worm_pos.append(Vector3(x + rng.randf_range(-0.2, 0.2), y, z))
		x += SPACING
	return worm_pos.size()


func setup() -> void:
	radius = 0.0
	active_radius = 1.0e6
	var n := worm_pos.size()
	lit.resize(n)
	lit.fill(1.0)
	_dark_from.resize(n)
	_dark_from.fill(-1.0)
	_dark_until.resize(n)
	_dark_until.fill(-1.0)
	_lit_image = Image.create(n, 1, false, Image.FORMAT_R8)
	_lit_image.fill(Color.WHITE)
	_lit_texture = ImageTexture.create_from_image(_lit_image)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(room.center)
	var worms := _multimesh(QuadMesh.new(), n)
	var snares: Array[Transform3D] = []
	var snare_custom: Array[Color] = []
	var beads: Array[Transform3D] = []
	var bead_custom: Array[Color] = []
	for i in n:
		var top := worm_pos[i]
		var phase := rng.randf() * TAU
		worms.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * rng.randf_range(0.24, 0.34)),
			top - Vector3(0.0, 0.04, 0.0)))
		worms.set_instance_custom_data(i, Color(i, phase, 0.0, 0.0))
		for _k in rng.randi_range(SNARES.x, SNARES.y):
			# Mostly short, a few long: the long ones catch the eye.
			var length := lerpf(0.3, SNARE_LENGTH, pow(rng.randf(), 1.8))
			var at := top + Vector3(rng.randf_range(-0.14, 0.14), -0.02, rng.randf_range(-0.1, 0.1))
			var sway := phase + rng.randf_range(-0.4, 0.4)
			snares.append(Transform3D(Basis.from_scale(Vector3(1.0, length, 1.0)), at))
			snare_custom.append(Color(i, sway, length, 0.0))
			var count := int(length / BEAD_EVERY) + 1
			for b in count:
				var d := length * (b + 0.6) / count + rng.randf_range(-0.03, 0.03)
				# The last droplet on a line hangs heaviest.
				var size := rng.randf_range(0.045, 0.07) * (1.6 if b == count - 1 else 1.0)
				beads.append(Transform3D(Basis.from_scale(Vector3.ONE * size), at - Vector3(0.0, d, 0.0)))
				bead_custom.append(Color(i, sway, d, length))
	var thread_mesh := CylinderMesh.new()
	thread_mesh.top_radius = 0.006
	thread_mesh.bottom_radius = 0.006
	thread_mesh.height = 1.0
	thread_mesh.radial_segments = 3
	thread_mesh.rings = 1
	var threads := _multimesh(MeshKit.transformed(thread_mesh, Transform3D(Basis(), Vector3(0.0, -0.5, 0.0))),
		snares.size())
	for k in snares.size():
		threads.set_instance_transform(k, snares[k])
		threads.set_instance_custom_data(k, snare_custom[k])
	var drops := _multimesh(QuadMesh.new(), beads.size())
	for k in beads.size():
		drops.set_instance_transform(k, beads[k])
		drops.set_instance_custom_data(k, bead_custom[k])
	var rig := Node3D.new()
	rig.top_level = true
	add_child(rig)
	for part: Array in [[worms, 0, 3.0], [threads, 1, 0.5], [drops, 2, 2.2]]:
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter(&"glow_color", GLOW)
		mat.set_shader_parameter(&"kind", part[1])
		mat.set_shader_parameter(&"energy", part[2])
		mat.set_shader_parameter(&"lit_texture", _lit_texture)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = part[0]
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# They sway past their resting bounds.
		mmi.extra_cull_margin = 0.6
		rig.add_child(mmi)
	# A few real lights so the grotto actually lights the water.
	for k in LIGHTS:
		var light := OmniLight3D.new()
		light.light_color = GLOW
		light.omni_range = room.radius.x * 1.1
		var at := worm_pos[int((k + 0.5) / LIGHTS * n)]
		light.position = Vector3(at.x, at.y - 3.5, 1.5)
		rig.add_child(light)
		_lights.append(light)
	_upload()
	Events.noise_emitted.connect(_on_noise)


func _exit_tree() -> void:
	if Events.noise_emitted.is_connected(_on_noise):
		Events.noise_emitted.disconnect(_on_noise)


static func _multimesh(mesh: Mesh, count: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = count
	return mm


## Sound reaching the worms: the dark spreads out from where it was made.
func _on_noise(p: Vector2, noise_radius: float, _source: Node) -> void:
	var reach := noise_radius * REACH
	if p.distance_to(room.center) > room.radius.x + reach + 2.0:
		return
	var now := level.time
	for i in worm_pos.size():
		var d := p.distance_to(Vector2(worm_pos[i].x, worm_pos[i].y))
		if d > reach:
			continue
		var arrives := now + d / RIPPLE_SPEED
		if _dark_until[i] < now:
			_dark_from[i] = arrives
		else:
			_dark_from[i] = minf(_dark_from[i], arrives)
		_dark_until[i] = maxf(_dark_until[i], arrives + DARK_TIME)


func tick(delta: float) -> void:
	var now := level.time
	var changed := false
	for i in lit.size():
		var dark := now >= _dark_from[i] and now < _dark_until[i]
		var was := lit[i]
		lit[i] = move_toward(lit[i], 0.0 if dark else 1.0, delta * (DIM_RATE if dark else RELIGHT_RATE))
		changed = changed or lit[i] != was
	if changed:
		_upload()
	var sub := level.player
	if sub and sub.alive and _inside(sub.pos):
		Wonders.witness("grotto")
	if not _explained and sub and sub.alive and _inside(sub.pos):
		_explained = true
		Events.toast.emit("A glow-worm grotto. They go dark at any sound - drift through quietly " +
			"and they will light your way.", UiTheme.ACCENT)


## Whether [param p] is in the grotto's chamber.
func _inside(p: Vector2) -> bool:
	var d := (p - room.center) / room.radius
	return d.length() < 1.0


## How lit the grotto is overall, 0..1.
func brightness() -> float:
	var total := 0.0
	for v in lit:
		total += v
	return total / maxf(lit.size(), 1)


func _upload() -> void:
	var n := lit.size()
	for i in n:
		_lit_image.set_pixel(i, 0, Color(lit[i], 0.0, 0.0))
	_lit_texture.update(_lit_image)
	# Each light follows the worms around it.
	for k in _lights.size():
		var a := int(float(k) / _lights.size() * n)
		var b := int(float(k + 1) / _lights.size() * n)
		var total := 0.0
		for i in range(a, b):
			total += lit[i]
		_lights[k].light_energy = 2.0 * total / maxf(b - a, 1)
