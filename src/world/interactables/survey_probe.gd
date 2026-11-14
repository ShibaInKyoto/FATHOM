class_name SurveyProbe
extends Entity
## One of Meridian Deep's survey probes, dropped down the trench years ago to
## log temperature, pressure and song, and lost in its side passages. Most
## lie in the rooms off the main way down, still blinking. Hook one with the
## harpoon and reel it in (or bump into it) to download what it recorded:
## research, more the deeper it lay.

const RESEARCH_BASE := 6
const RESEARCH_PER_ZONE := 2
const BLINK := 1.8
const COLOR := Color(1.0, 0.72, 0.2)

const SHADER := preload("res://src/fx/shaders/equipment.gdshader")
const CREAM := Color(0.8, 0.78, 0.7)
const ORANGE := Color(0.92, 0.45, 0.1)

static var _mesh: ArrayMesh

var _recovered := false
var _t := 0.0
var _light: OmniLight3D
var _mat: ShaderMaterial


## Lays [param count] probes in the side rooms of [param level], away from
## the start and the way down. Returns how many found a place.
static func scatter(level: Level, rng: RandomNumberGenerator, used: PackedVector2Array, count: int) -> int:
	var layout := level.layout
	var rooms := layout.chambers.filter(func(c: LevelLayout.Chamber) -> bool:
		return c.kind == &"loot" and c.center.distance_to(layout.start) > 30.0 and c.center.distance_to(layout.exit) > 20.0)
	for i in range(rooms.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: LevelLayout.Chamber = rooms[i]
		rooms[i] = rooms[j]
		rooms[j] = swap
	var placed := 0
	for room: LevelLayout.Chamber in rooms:
		if placed >= count:
			break
		var p := layout.point_in_chamber(rng, room, 1.5)
		if p == Vector2.INF or not layout.is_reachable(p):
			continue
		# Settled on the floor of the room, where there is one.
		var floor_y := MeridianStation.floor_below(level.field, p, room.radius.y * 2.0)
		if floor_y != -INF and level.field.sample(Vector2(p.x, floor_y + 0.9)) > 0.7:
			p = Vector2(p.x, floor_y + 0.9)
		var clear := true
		for u in used:
			if u.distance_to(p) < 6.0:
				clear = false
				break
		if not clear:
			continue
		var probe := SurveyProbe.new()
		probe.pos = p
		level.add_entity(probe)
		used.append(p)
		placed += 1
	return placed


func setup() -> void:
	radius = 0.8
	active_radius = 90.0
	targetable = true
	if _mesh == null:
		_mesh = build()
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter(&"lamp_color", COLOR)
	_mat.set_shader_parameter(&"sediment_tint", level.biome.sediment_tint)
	_mat.set_shader_parameter(&"detail", 7.0)
	var body := MeshInstance3D.new()
	body.mesh = _mesh
	body.material_override = _mat
	# Lying on the floor where it came to rest, a little askew.
	body.position = Vector3(0.0, -0.68, 0.0)
	body.rotation = Vector3(level.rng.randf_range(-0.3, 0.3), level.rng.randf_range(-0.4, 0.4),
		level.rng.randf_range(-0.12, 0.12))
	add_child(body)
	_light = OmniLight3D.new()
	_light.light_color = COLOR
	_light.omni_range = 5.0
	_light.position = Vector3(0.1, 0.1, 0.6)
	add_child(_light)
	_t = level.rng.randf() * BLINK


## The probe, lying along x (nose at +x), its belly at y = -0.22: a cream
## pressure housing with an orange nose, a dark sensor collar studded with
## ports, hydrophones on its back, four tail fins in a shroud, a stub mast
## with its blinking lamp and a whip antenna, and a lifting eye.
static func build() -> ArrayMesh:
	var b := ModelBuilder.new()
	var cream := Color(CREAM, 0.0)
	var orange := Color(ORANGE, 0.0)
	var dark := Color(0.1, 0.1, 0.1, 0.3)
	var metal := Color(0.7, 0.0, 0.0, 0.2)
	var r := 0.22
	# The hull: body, nose, tail cone (lathes along x).
	_lathe(b, [Vector2(-0.42, r), Vector2(0.18, r)], cream)
	_lathe(b, [Vector2(0.18, r), Vector2(0.3, r)], orange)
	_lathe(b, [Vector2(0.3, r * 1.07), Vector2(0.42, r * 1.07)], dark)
	_lathe(b, [Vector2(0.42, r), Vector2(0.55, r)], cream)
	var nose: Array = []
	for k in 9:
		var t := k / 8.0
		nose.append(Vector2(0.55 + 0.22 * sin(t * PI * 0.5), r * cos(t * PI * 0.5) + 0.0005))
	_lathe(b, nose, orange)
	_lathe(b, [Vector2(-0.72, 0.07), Vector2(-0.62, 0.13), Vector2(-0.42, r)], cream)
	b.disc(Vector3(-0.72, 0.0, 0.0), Vector3.LEFT, 0.07, dark, 14)
	b.cylinder(Vector3(-0.78, 0.0, 0.0), Vector3(-0.7, 0.0, 0.0), 0.035, metal, 8)
	# Reflective tape round the body.
	for x: float in [-0.3, 0.05]:
		_lathe(b, [Vector2(x, r * 1.012), Vector2(x + 0.035, r * 1.012)], Color(1, 1, 1, 0.8))
	# Ports round the sensor collar.
	for k in 6:
		var a := TAU * k / 6.0
		var d := Vector3(0.0, cos(a), sin(a))
		b.disc(Vector3(0.36, 0.0, 0.0) + d * (r * 1.075), d, 0.025, Color(0, 0, 0, 0.6), 10)
	# Hydrophones on its back.
	for x: float in [-0.2, -0.05]:
		b.capsule(Vector3(x - 0.04, r + 0.03, 0.0), Vector3(x + 0.04, r + 0.03, 0.0), 0.025, dark)
	# Fins in their shroud.
	for k in 4:
		var a := TAU * (k + 0.5) / 4.0
		var d := Vector3(0.0, cos(a), sin(a))
		b.plate([Vector3(-0.45, 0.0, 0.0) + d * 0.18, Vector3(-0.6, 0.0, 0.0) + d * 0.1,
			Vector3(-0.7, 0.0, 0.0) + d * 0.24, Vector3(-0.52, 0.0, 0.0) + d * 0.24], orange)
	b.torus(Vector3(-0.62, 0.0, 0.0), Vector3.RIGHT, 0.25, 0.018, metal, 24, 6)
	# The mast, its lamp, the whip antenna; the lifting eye.
	b.cylinder(Vector3(0.05, r - 0.02, 0.0), Vector3(0.05, r + 0.42, 0.0), 0.022, metal, 8)
	b.cylinder(Vector3(0.05, r + 0.42, 0.0), Vector3(0.05, r + 0.45, 0.0), 0.05, dark, 12)
	b.cylinder(Vector3(0.05, r + 0.45, 0.0), Vector3(0.05, r + 0.55, 0.0), 0.04, Color(1, 0, 0, 0.6), 12)
	b.cylinder(Vector3(0.05, r + 0.55, 0.0), Vector3(0.05, r + 0.57, 0.0), 0.05, dark, 12)
	b.tube(PackedVector3Array([Vector3(-0.1, r, 0.04), Vector3(-0.12, r + 0.35, 0.05), Vector3(-0.2, r + 0.7, 0.07)]),
		PackedFloat32Array([0.008, 0.006, 0.003]), 5, metal)
	b.torus(Vector3(0.25, r + 0.04, 0.0), Vector3.BACK, 0.04, 0.012, metal, 12, 5)
	return b.commit()


## A surface of revolution about x through [param prof] (x, radius).
static func _lathe(b: ModelBuilder, prof: Array, color: Color) -> void:
	var around := 24
	var start := b.verts.size()
	var count := prof.size()
	for i in count:
		var p: Vector2 = prof[i]
		var d: Vector2 = (prof[mini(i + 1, count - 1)] as Vector2) - prof[maxi(i - 1, 0)]
		var nn := Vector2(-d.y, d.x).normalized()
		for j in around + 1:
			var a := TAU * j / around
			var dir := Vector3(0.0, cos(a), sin(a))
			b.add(Vector3(p.x, 0.0, 0.0) + dir * p.y, Vector3(nn.x, 0.0, 0.0) + dir * nn.y, color)
	for i in count - 1:
		for j in around:
			var a := start + i * (around + 1) + j
			b.quad(a, a + 1, a + around + 2, a + around + 1)


func tick(delta: float) -> void:
	_t += delta
	var on := fmod(_t, BLINK) < 0.18
	_light.light_energy = 1.6 if on else 0.05
	_mat.set_shader_parameter(&"lamp", 1.0 if on else 0.0)
	var sub := level.player
	if sub and sub.alive and sub.pos.distance_to(pos) < Submarine.RADIUS + radius + 0.3:
		recover(sub)


func on_harpoon_hit(_harpoon: Node, _damage: float) -> HarpoonReaction:
	return HarpoonReaction.DRAG


func on_reeled_in(sub: Submarine) -> void:
	recover(sub)


## The research it holds, by how deep it lay.
func research() -> int:
	return RESEARCH_BASE + RESEARCH_PER_ZONE * level.zone


func recover(sub: Submarine) -> void:
	if _recovered:
		return
	_recovered = true
	var gain := research()
	sub.run.research += gain
	sub.run.probes += 1
	sub.show_gain(gain, " research", UiTheme.ACCENT)
	Game.meta.probes_recovered += 1
	Audio.play_at(&"scan_complete", pos, 0.0, 0.05, 0.8)
	Fx.sparkle(level, pos, COLOR)
	Events.toast.emit("Survey probe recovered: its logs are worth %d research." % gain, UiTheme.ACCENT)
	despawn()
