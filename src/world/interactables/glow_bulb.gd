class_name GlowBulb
extends Entity
## A bioluminescent bulb growing on the cave wall: a glowing sac on a fleshy
## stalk, rooted in the rock, with two buds beside it, breathing as it
## pulses. Touching it harvests its stored charge into the battery; it then
## dims and deflates.

const CHARGE := 28.0
const SHADER := preload("res://src/fx/shaders/glow_bulb.gdshader")
const FLESH := 0.0
const SAC := 1.0

var normal := Vector2.UP
var color := Color(0.4, 1.0, 0.8)
var _harvested := false
var _mat: ShaderMaterial
var _light: OmniLight3D
var _t := 0.0
var _charge := 1.0


func setup() -> void:
	radius = 0.8
	active_radius = 60.0
	var holder := Node3D.new()
	holder.rotation.z = normal.angle() - PI * 0.5
	add_child(holder)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(pos)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter(&"glow", color)
	_mat.set_shader_parameter(&"flesh", level.biome.rock_tint.darkened(0.55).lerp(color.darkened(0.8), 0.25))
	var model := MeshInstance3D.new()
	model.mesh = build(rng)
	model.material_override = _mat
	holder.add_child(model)
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.omni_range = 6.0
	_light.light_energy = 1.2
	_light.light_volumetric_fog_energy = 0.5
	_light.position = Vector3(normal.x * 0.8, normal.y * 0.8, 1.0)
	add_child(_light)
	_t = rng.randf() * TAU


## The bulb, in its holder's space (+Y out of the rock, the rock's face at
## y = -0.5): roots gripping the rock, a curving stalk, the glowing sac and
## two smaller buds. COLOR.a 0 flesh (COLOR.r how near the sac), 1 a sac
## (COLOR.g how much it breathes).
static func build(rng: RandomNumberGenerator) -> ArrayMesh:
	var b := ModelBuilder.new()
	var root := Vector3(0.0, -0.55, 0.0)
	# Roots spreading over the rock and down into it.
	for k in 6:
		var a := TAU * k / 6.0 + rng.randf_range(-0.3, 0.3)
		var d := Vector3(cos(a), 0.0, sin(a))
		var length := rng.randf_range(0.35, 0.7)
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		for i in 5:
			var t := i / 4.0
			pts.append(root + d * length * t + Vector3(0.0, 0.06 * sin(t * PI) - 0.12 * t * t, 0.0)
				+ d.cross(Vector3.UP) * 0.08 * sin(t * 5.0 + a))
			radii.append(lerpf(0.06, 0.012, t))
		b.tube(pts, radii, 6, Color(0.2, 0.0, 0.0, FLESH))
	b.ellipsoid(root + Vector3(0.0, 0.02, 0.0), Vector3(0.2, 0.08, 0.2), Color(0.3, 0.0, 0.0, FLESH), 12, 6)
	# The stalk, curving up to the sac.
	var bend := Vector3(rng.randf_range(-0.12, 0.12), 0.0, rng.randf_range(-0.08, 0.08))
	var top := Vector3(bend.x * 1.5, 0.12, bend.z)
	var stalk := PackedVector3Array()
	var sr := PackedFloat32Array()
	for i in 7:
		var t := i / 6.0
		stalk.append(root.lerp(top, t) + bend * sin(t * PI))
		sr.append(lerpf(0.11, 0.06, t) * (1.0 + 0.15 * sin(t * 14.0)))
	# It runs on up inside the sac (so the sac never parts from it, even
	# deflated), through a fleshy collar where they join.
	stalk.append(top + Vector3(0.0, 0.32, 0.0))
	sr.append(0.05)
	b.tube(stalk, sr, 10, Color(0.6, 0.0, 0.0, FLESH))
	b.tube(PackedVector3Array([top - Vector3(0.0, 0.06, 0.0), top + Vector3(0.0, 0.04, 0.0),
		top + Vector3(0.0, 0.12, 0.0)]), PackedFloat32Array([0.075, 0.11, 0.15]), 12, Color(0.9, 0.0, 0.0, FLESH))
	_sac(b, top + Vector3(0.0, 0.3, 0.0), Vector3(0.48, 0.52, 0.46), rng)
	# Two buds on their own short stalks.
	for k in 2:
		var a := rng.randf_range(0.0, TAU) if k == 0 else rng.randf_range(0.0, TAU) + PI
		var d := Vector3(cos(a), 0.0, sin(a))
		var foot := root + d * 0.12 + Vector3(0.0, 0.06, 0.0)
		var tip := foot + d * rng.randf_range(0.25, 0.4) + Vector3(0.0, rng.randf_range(0.2, 0.35), 0.0)
		var bud := rng.randf_range(0.11, 0.16)
		b.tube(PackedVector3Array([foot, foot.lerp(tip, 0.5) + Vector3(0.0, 0.04, 0.0), tip,
			tip + Vector3(0.0, bud * 0.7, 0.0)]), PackedFloat32Array([0.045, 0.035, 0.032, 0.025]), 7,
			Color(0.5, 0.0, 0.0, FLESH))
		b.ellipsoid(tip + Vector3(0.0, 0.01, 0.0), Vector3(0.045, 0.035, 0.045), Color(0.9, 0.0, 0.0, FLESH), 10, 5)
		_sac(b, tip + Vector3(0.0, bud * 0.6, 0.0), Vector3(bud, bud * 1.15, bud), rng)
	return b.commit()


## A sac round [param c] of half size [param half], a little pear-shaped,
## pinched where it meets its stalk.
static func _sac(b: ModelBuilder, c: Vector3, half: Vector3, rng: RandomNumberGenerator) -> void:
	var rings := 14
	var around := 24
	var rows := []
	var ns := []
	var lobe := rng.randf() * TAU
	for i in rings + 1:
		var lat := lerpf(-PI * 0.5, PI * 0.5, float(i) / rings)
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		for j in around + 1:
			var lon := TAU * (j % around) / around
			var d := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
			# Fuller above, narrowing to its neck below; faintly lobed.
			var pear := 1.0 + 0.12 * sin(lat) - 0.25 * pow(maxf(-sin(lat), 0.0), 3.0)
			var lobes := 1.0 + 0.04 * sin(lon * 5.0 + lobe) * cos(lat)
			row.append(c + d * half * pear * lobes)
			nrow.append(d)
		rows.append(row)
		ns.append(nrow)
	var start := b.verts.size()
	for i in rows.size():
		var row: PackedVector3Array = rows[i]
		for j in row.size():
			b.add(row[j], (ns[i] as PackedVector3Array)[j], Color(1.0, half.x, 0.0, SAC))
	var w := around + 1
	for i in rings:
		for j in around:
			var a := start + i * w + j
			b.quad(a, a + 1, a + w + 1, a + w)


func tick(delta: float) -> void:
	_t += delta
	if _harvested:
		# Spent: it dims and deflates.
		_charge = move_toward(_charge, 0.06, delta / 1.4)
		_mat.set_shader_parameter(&"charge", _charge)
		_mat.set_shader_parameter(&"pulse", 1.0)
		return
	var pulse := 0.85 + 0.15 * sin(_t * 1.7)
	_mat.set_shader_parameter(&"pulse", pulse)
	_light.light_energy = 1.2 * pulse
	var sub := level.player
	if sub and sub.alive and sub.pos.distance_to(pos) < Submarine.RADIUS + radius + 0.4:
		_harvest(sub)


func is_ripe() -> bool:
	return not _harvested


func _harvest(sub: Submarine) -> void:
	_harvested = true
	sub.run.bulbs += 1
	Events.bulb_harvested.emit(pos)
	var gain := CHARGE * sub.stats.bulb_mult
	sub.add_battery(gain)
	Audio.play_at(&"bulb_harvest", pos, -2.0)
	Events.toast.emit("Battery +%d" % int(gain), UiTheme.ACCENT)
	Fx.sparkle(level, pos, color)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_light, ^"light_energy", 0.0, 1.2)
