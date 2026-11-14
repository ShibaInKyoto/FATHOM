class_name Stalactite
extends Entity
## A loose spike of rock hanging from a cavern ceiling. A very loud noise
## nearby (a ping, a boost, an explosion), a harpoon strike or a bump shakes
## it loose: it trembles for a moment, then falls, skewering whatever is
## below, and shatters with a crack loud enough to bring down its neighbours.

enum State { HANGING, SHAKING, FALLING }

const LENGTH := 3.6
## Only noises at least this loud shake rock loose (cruising never does) ...
const LOUD := 16.0
## ... and only within this fraction of their reach.
const REACH := 0.6
const SHAKE_TIME := 0.9
const GRAVITY := 30.0
const SUB_DAMAGE := 20.0
const CREATURE_DAMAGE := 55.0
const SHATTER_NOISE := 18.0

const SHADER := preload("res://src/fx/shaders/dripstone.gdshader")
## Seconds between drops falling from the tip.
const DROP_EVERY := Vector2(2.5, 5.0)

static var _mesh: Mesh
static var _chunk: Mesh
static var _materials: Dictionary[StringName, ShaderMaterial] = {}
## The first one a pilot sees come loose explains itself, once per session.
static var _explained := false

var state := State.HANGING
var size := 1.0
var _timer := 0.0
var _model: MeshInstance3D
var _drip_mat: StandardMaterial3D
var _drop: MeshInstance3D
var _drop_in := 0.0
var _drop_t := -1.0
var _struck: Array[Node] = []


func setup() -> void:
	radius = 0.9 * size
	active_radius = 90.0
	targetable = true
	if _mesh == null:
		_mesh = _build_mesh()
		_chunk = _chunk_mesh()
	_model = MeshInstance3D.new()
	_model.mesh = _mesh
	_model.material_override = _material(level.biome)
	_model.scale = Vector3.ONE * size
	_model.rotation.y = level.rng.randf() * TAU
	add_child(_model)
	# A bead of mineral water glowing at the tip marks it in the dark, and
	# every few seconds a drop falls from it.
	var drip := MeshInstance3D.new()
	drip.mesh = MeshKit.sphere(0.05)
	_drip_mat = MeshKit.emissive_material(level.biome.glow_color, 2.5)
	drip.material_override = _drip_mat
	drip.position = Vector3(0.0, -LENGTH * 0.5 - 0.05, 0.0)
	drip.scale = Vector3(1.0, 1.3, 1.0)
	_model.add_child(drip)
	_drop = MeshInstance3D.new()
	_drop.mesh = MeshKit.sphere(0.035)
	_drop.material_override = _drip_mat
	_drop.visible = false
	add_child(_drop)
	_drop_in = level.rng.randf_range(0.5, DROP_EVERY.y)


## Upper and lower ends of the spike (it hangs centred on [member pos]).
func base() -> Vector2:
	return pos + Vector2(0.0, LENGTH * 0.5 * size)


func tip() -> Vector2:
	return pos - Vector2(0.0, LENGTH * 0.5 * size)


func tick(delta: float) -> void:
	_drip_drop(delta)
	match state:
		State.HANGING:
			if _heard_loud_noise():
				shake_loose()
			_bump_sub()
		State.SHAKING:
			_timer -= delta
			_model.position = Vector3(randf_range(-1.0, 1.0), randf_range(-0.3, 0.3), 0.0) * 0.07 * size
			_drip_mat.emission_energy_multiplier = randf_range(2.0, 9.0)
			_model.set_instance_shader_parameter(&"drip", randf_range(1.0, 3.0))
			_bump_sub()
			if _timer <= 0.0:
				state = State.FALLING
				_model.position = Vector3.ZERO
		State.FALLING:
			vel.y -= GRAVITY * delta
			pos += vel * delta
			_strike()
			if level.field.sample(tip()) < 0.15:
				_shatter()


## Every few seconds a drop gathers at the tip and falls, glowing, fading
## as it sinks.
func _drip_drop(delta: float) -> void:
	if state == State.FALLING:
		_drop.visible = false
		return
	if _drop_t < 0.0:
		_drop_in -= delta
		if _drop_in <= 0.0:
			_drop_t = 0.0
			_drop_in = level.rng.randf_range(DROP_EVERY.x, DROP_EVERY.y)
		return
	_drop_t += delta
	var fall := 1.6 * _drop_t * _drop_t
	_drop.visible = true
	_drop.position = Vector3(0.0, -LENGTH * 0.5 * size - 0.1 - fall, 0.0)
	_drop.scale = Vector3.ONE * maxf(1.0 - _drop_t / 1.6, 0.05)
	if _drop_t > 1.6 or level.field.sample(pos + Vector2(0.0, _drop.position.y)) < 0.1:
		_drop.visible = false
		_drop_t = -1.0


## Starts the tremble that ends in a fall (no effect once it is already loose).
func shake_loose(time := SHAKE_TIME) -> void:
	if state != State.HANGING:
		return
	state = State.SHAKING
	_timer = time
	Audio.play_at(&"rock_loose", pos, -2.0)
	Fx.ichor(level, base(), level.biome.sediment_tint, 8)
	_explain()


func on_harpoon_hit(_harpoon: Node, _damage: float) -> HarpoonReaction:
	Audio.play_at(&"harpoon_wall", pos, -4.0)
	shake_loose(0.3)
	return HarpoonReaction.IGNORE


func _heard_loud_noise() -> bool:
	for n in level.noises:
		if n.source != self and n.radius >= LOUD and pos.distance_to(n.pos) < n.radius * REACH:
			return true
	return false


func _segment_distance(p: Vector2) -> float:
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, base(), tip()))


## Brushing past a hanging spike knocks it loose and nudges the sub away.
func _bump_sub() -> void:
	var sub := level.player
	if sub == null or not sub.alive:
		return
	var reach := Submarine.RADIUS + 0.3 * size
	if _segment_distance(sub.pos) < reach:
		var away := sub.pos - Geometry2D.get_closest_point_to_segment(sub.pos, base(), tip())
		sub.vel += away.normalized() * 4.0
		shake_loose(0.5)


## Damages everything the falling spike passes through, once each.
func _strike() -> void:
	var sub := level.player
	if sub and sub.alive and not _struck.has(sub) and _segment_distance(sub.pos) < Submarine.RADIUS + 0.3 * size:
		_struck.append(sub)
		sub.take_damage(SUB_DAMAGE * size, tip() + Vector2(0.0, 2.0), self)
	var victims: Array[Entity] = level.targets_in_radius(pos, LENGTH * 0.5 * size + 1.0)
	if is_instance_valid(level.guardian) and level.guardian.alive:
		victims.append(level.guardian)
	for e in victims:
		var c := e as Creature
		if c and not _struck.has(c) and _segment_distance(c.pos) < c.radius + 0.3 * size:
			_struck.append(c)
			c.take_damage(CREATURE_DAMAGE * size, base(), &"rock")


func _shatter() -> void:
	var at := tip()
	Audio.play_at(&"rock_shatter", at, 0.0)
	Fx.ichor(level, at, level.biome.sediment_tint, 26)
	Fx.bubble_burst(level, at, 14, 1.2)
	Fx.rubble(level, at, _chunk, _model.material_override, 9)
	Events.shake_requested.emit(0.3)
	level.emit_noise(at, SHATTER_NOISE, self)
	despawn()


func _explain() -> void:
	var sub := level.player
	if _explained or sub == null or sub.pos.distance_to(pos) > 30.0:
		return
	_explained = true
	Events.toast.emit("Loose rock! Loud noises bring stalactites down - on you, or on whatever is below.",
		UiTheme.WARN)


## Wet calcite dripstone in the biome's own colours, the drip's glow
## through its tip.
static func _material(biome: BiomeDef) -> ShaderMaterial:
	if not _materials.has(biome.id):
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter(&"calcite", biome.rock_tint.lerp(Color(0.86, 0.82, 0.74), 0.6))
		m.set_shader_parameter(&"rock_tint", biome.rock_tint)
		m.set_shader_parameter(&"sediment_tint", biome.sediment_tint)
		m.set_shader_parameter(&"drip_color", biome.glow_color)
		_materials[biome.id] = m
	return _materials[biome.id]


## A dripstone spike, base up, tip down, centred on the origin: flared where
## it meets the ceiling, ringed with growth, fluted where water ran down it,
## two lesser spikes fused to its root, and a thin straw at its tip.
## COLOR.r is how far down it a point is; COLOR.g a shade of its own.
static func _build_mesh() -> Mesh:
	var b := ModelBuilder.new()
	var noise := FastNoiseLite.new()
	noise.seed = 31
	noise.frequency = 1.3
	_spike(b, noise, Vector3(0.0, LENGTH * 0.5, 0.0), LENGTH, 0.62, 0.0, Vector2.ZERO)
	_spike(b, noise, Vector3(0.34, LENGTH * 0.5 - 0.1, 0.14), LENGTH * 0.42, 0.26, 0.3, Vector2(0.1, 0.04))
	_spike(b, noise, Vector3(-0.24, LENGTH * 0.5 - 0.05, -0.26), LENGTH * 0.3, 0.2, 0.6, Vector2(-0.08, -0.07))
	return b.commit()


## One spike hanging from [param top], [param length] long and [param radius]
## wide below its flare; [param seed_shift] varies its flutes, [param lean]
## swings its tip (x, z per metre).
static func _spike(b: ModelBuilder, noise: FastNoiseLite, top: Vector3, length: float, radius: float,
		seed_shift: float, lean: Vector2) -> void:
	var rings := 28
	var around := 20
	var rows := []
	var ns := []
	var shade := []
	for i in rings + 1:
		var t := float(i) / rings
		# Flared root, a long taper, a thin straw at the end.
		var r := radius * (1.0 + 0.35 * pow(1.0 - minf(t / 0.15, 1.0), 2.0)) * pow(1.0 - t * 0.93, 1.25)
		if t > 0.9:
			r = minf(r, radius * 0.07)
		r *= 1.0 + 0.06 * sin(t * length * 13.0)
		var c := top + Vector3(lean.x * t * t * length, -t * length, lean.y * t * t * length)
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		var srow := PackedFloat32Array()
		for j in around + 1:
			var a := TAU * (j % around) / around
			var flute := sin(a * 9.0 + seed_shift * 5.0 + noise.get_noise_2d(t * 4.0, seed_shift * 9.0) * 2.0)
			flute = signf(flute) * pow(absf(flute), 0.6)
			var lump := 1.0 + noise.get_noise_3d(cos(a) * 1.5, t * length * 1.4, sin(a) * 1.5 + seed_shift * 7.0) * 0.18
			var rr := r * lump * (1.0 + 0.15 * flute * smoothstep(0.05, 0.3, t) * (1.0 - smoothstep(0.85, 0.95, t)))
			var d := Vector3(cos(a), 0.0, sin(a))
			row.append(c + d * rr)
			nrow.append((d + Vector3(0.0, -0.25 + 0.6 * (1.0 - t), 0.0)).normalized())
			srow.append(0.5 + 0.5 * flute)
		rows.append(row)
		ns.append(nrow)
		shade.append(srow)
	var start := b.verts.size()
	for i in rows.size():
		var row: PackedVector3Array = rows[i]
		for j in row.size():
			b.add(row[j], (ns[i] as PackedVector3Array)[j], Color(float(i) / rings, (shade[i] as PackedFloat32Array)[j],
				0.0, 0.0))
	var w := around + 1
	for i in rings:
		for j in around:
			var a := start + i * w + j
			b.quad(a, a + 1, a + w + 1, a + w)
	var tip: Vector3 = (rows[rings] as PackedVector3Array)[0]
	var centre := top + Vector3(lean.x * length, -length, lean.y * length)
	b.disc(centre, Vector3.DOWN, tip.distance_to(centre), Color(1.0, 0.5, 0.0, 0.0), around)


## A lumpy chunk of the same rock, for the pieces it shatters into.
static func _chunk_mesh() -> Mesh:
	var b := ModelBuilder.new()
	var noise := FastNoiseLite.new()
	noise.frequency = 2.2
	var rows := []
	var ns := []
	for i in 7:
		var lat := lerpf(-PI * 0.5, PI * 0.5, i / 6.0)
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		for j in 11:
			var lon := TAU * (j % 10) / 10.0
			var d := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
			row.append(d * Vector3(1.0, 0.7, 0.85) * (1.0 + noise.get_noise_3dv(d) * 0.35))
			nrow.append(d)
		rows.append(row)
		ns.append(nrow)
	b.grid(rows, ns, Color(0.6, 0.5, 0.0, 0.0))
	return b.commit()
