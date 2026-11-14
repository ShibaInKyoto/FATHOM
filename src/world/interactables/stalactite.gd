class_name Stalactite
extends Entity
## A loose stalactite hanging from a cavern ceiling on a cracked plug of
## rock (see [StalactiteModel]). A very loud noise nearby (a ping, a boost,
## an explosion), a harpoon strike or a bump shakes it loose: it wobbles on
## its plug, grit pouring from the crack, then drops, tumbling, skewering
## whatever is below, and breaks apart with a crack loud enough to bring
## down its neighbours.

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

static var _chunk: Mesh
static var _materials: Dictionary[StringName, ShaderMaterial] = {}
## The first one a pilot sees come loose explains itself, once per session.
static var _explained := false

var state := State.HANGING
var size := 1.0
var _timer := 0.0
## The stalactite swings on its plug from [member _pivot] (at the ceiling),
## its three sections under it.
var _pivot: Node3D
var _sections: Array[MeshInstance3D] = []
var _variant := 0
var _spin := Vector3.ZERO
var _grit := 0.0
var _drip_mat: StandardMaterial3D
var _drop: MeshInstance3D
var _drop_in := 0.0
var _drop_t := -1.0
var _struck: Array[Node] = []


func setup() -> void:
	radius = 0.9 * size
	active_radius = 90.0
	targetable = true
	if _chunk == null:
		_chunk = _chunk_mesh()
	_variant = level.rng.randi() % StalactiteModel.VARIANTS
	_pivot = Node3D.new()
	_pivot.position = Vector3(0.0, StalactiteModel.CEILING * size, 0.0)
	_pivot.rotation.y = level.rng.randf() * TAU
	add_child(_pivot)
	var mat := _material(level.biome)
	for mesh in StalactiteModel.sections(_variant):
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.scale = Vector3.ONE * size
		mi.position = Vector3(0.0, -StalactiteModel.CEILING * size, 0.0)
		_pivot.add_child(mi)
		_sections.append(mi)
	# A bead of mineral water glowing at the tip marks it in the dark, and
	# every few seconds a drop falls from it.
	var drip := MeshInstance3D.new()
	drip.mesh = MeshKit.sphere(0.045)
	_drip_mat = MeshKit.emissive_material(level.biome.glow_color, 2.5)
	drip.material_override = _drip_mat
	drip.position = Vector3(0.0, -LENGTH * 0.5 - 0.04, 0.0)
	drip.scale = Vector3(1.0, 1.3, 1.0)
	_sections[2].add_child(drip)
	_drop = MeshInstance3D.new()
	_drop.mesh = MeshKit.sphere(0.03)
	_drop.material_override = _drip_mat
	_drop.visible = false
	add_child(_drop)
	_drop_in = level.rng.randf_range(0.5, DROP_EVERY.y)


## Sets an instance shader parameter on every section.
func _set_param(param: StringName, value: float) -> void:
	for mi in _sections:
		mi.set_instance_shader_parameter(param, value)


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
			_wobble(delta)
			_bump_sub()
			if _timer <= 0.0:
				state = State.FALLING
				_spin = Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.9, 0.9))
				Fx.ichor(level, base(), level.biome.sediment_tint, 14)
		State.FALLING:
			vel.y -= GRAVITY * delta
			pos += vel * delta
			# It tumbles a little as it drops.
			_pivot.rotation.x += _spin.x * delta
			_pivot.rotation.z += _spin.z * delta
			_strike()
			if level.field.sample(tip()) < 0.15:
				_shatter()


## Coming loose: it rocks on its plug, harder as the crack opens, sinking
## a little, grit trickling out round it; its drip flares.
func _wobble(delta: float) -> void:
	var held := 1.0 - _timer / SHAKE_TIME
	var swing := (0.015 + 0.06 * held) * size
	var t := level.time * 15.0
	_pivot.rotation.x = sin(t) * swing
	_pivot.rotation.z = sin(t * 1.3 + 1.0) * swing * 0.8
	_pivot.position.y = (StalactiteModel.CEILING - 0.06 * held) * size
	_set_param(&"crack", held)
	_set_param(&"drip", 1.0 + 2.0 * held * (0.5 + 0.5 * sin(t * 2.0)))
	_drip_mat.emission_energy_multiplier = 2.5 + 5.0 * held
	_grit -= delta
	if _grit <= 0.0:
		_grit = 0.18
		var a := randf() * TAU
		Fx.ichor(level, base() + Vector2(cos(a) * 0.7, -0.4) * size, level.biome.sediment_tint, 3)


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
	_break_apart()
	Fx.rubble(level, at, _chunk, _sections[0].material_override, 9)
	Events.shake_requested.emit(0.3)
	level.emit_noise(at, SHATTER_NOISE, self)
	despawn()


## Its three sections thrown apart where it struck, tumbling, sinking and
## crumbling away.
func _break_apart() -> void:
	var holder := level as Node3D
	for k in _sections.size():
		var mi := _sections[k]
		var xf := mi.global_transform
		mi.get_parent().remove_child(mi)
		holder.add_child(mi)
		mi.global_transform = xf
		var away := Vector3(randf_range(-1.0, 1.0) * (1.5 + k), randf_range(0.2, 1.2), randf_range(-0.4, 0.4))
		var tween := mi.create_tween().set_parallel(true)
		tween.tween_property(mi, ^"global_position", xf.origin + away - Vector3(0.0, 0.4, 0.0), 1.2) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(mi, ^"rotation", mi.rotation + Vector3(randf_range(-1.5, 1.5), randf_range(-1.0, 1.0),
			randf_range(-1.5, 1.5)), 1.2)
		tween.tween_property(mi, ^"scale", Vector3.ONE * 0.02, 0.6).set_delay(1.4)
		tween.chain().tween_callback(mi.queue_free)


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
		m.set_shader_parameter(&"rock_albedo", TerrainRenderer.ROCK_ALBEDO)
		m.set_shader_parameter(&"calcite", biome.rock_tint.lerp(Color(0.86, 0.82, 0.74), 0.6))
		m.set_shader_parameter(&"rock_tint", biome.rock_tint)
		m.set_shader_parameter(&"sediment_tint", biome.sediment_tint)
		m.set_shader_parameter(&"drip_color", biome.glow_color)
		_materials[biome.id] = m
	return _materials[biome.id]


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
	b.grid(rows, ns, Color(0.4, 0.5, 0.5, 0.0))
	return b.commit()
