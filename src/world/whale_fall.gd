class_name WhaleFall
extends Entity
## The "whale fall" zone event: the skeleton of a sperm whale lying on the
## floor behind the playfield (see [WhaleFallModel]), the silt about it soured
## black and patched with bacterial mats, bone-eating worms glowing red all
## over it. Life gathers at a fall: the populator adds shoals and glow bulbs
## around it, and the first close look at the carcass earns research.

const DEPTH := -5.0
const VERTEBRAE := 15
const SPACING := 1.15
const SURVEY_RANGE := 12.0
const SURVEY_RESEARCH := 6
const WORM := Color(1.0, 0.3, 0.35)
const BONE_SHADER := preload("res://src/fx/shaders/bone.gdshader")
const WORM_SHADER := preload("res://src/fx/shaders/bone_worm.gdshader")
const HAGFISH_SHADER := preload("res://src/fx/shaders/hagfish.gdshader")
## How many hagfish feed at the fall.
const HAGFISH := 7

static var _mat_textures: Dictionary[int, ImageTexture] = {}

## Spine points on the gameplay plane, tail first.
var spine := PackedVector2Array()
## +1 if the skull lies to the right of the tail.
var heading := 1.0
var surveyed := false
var _light: OmniLight3D
var _t := 0.0
## The hagfish, and each one's loop: [centre, x radius, z radius, height
## over the floor, speed (signed), how far round it is].
var _hagfish: MultiMesh
var _loops: Array = []


## Finds the longest stretch of floor that a skeleton can lie along, clear of
## [param avoid], and adds the fall there; returns it, or null if the zone
## has no stretch long enough.
static func place(level: Level, rng: RandomNumberGenerator, avoid: PackedVector2Array) -> WhaleFall:
	var layout := level.layout
	var best := PackedVector2Array()
	var anchors := layout.anchors.duplicate()
	for i in range(anchors.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp: LevelLayout.Anchor = anchors[i]
		anchors[i] = anchors[j]
		anchors[j] = tmp
	var tried := 0
	for a: LevelLayout.Anchor in anchors:
		if tried >= 60:
			break
		if a.normal.y < 0.75 or a.pos.distance_to(layout.start) < 25.0 or a.pos.distance_to(layout.exit) < 18.0:
			continue
		if not layout.is_reachable(a.pos + a.normal * 3.0) or not _clear_of(a.pos, avoid, 10.0):
			continue
		tried += 1
		var line := _floor_line(level.field, a.pos)
		if line.size() > best.size():
			best = line
		if best.size() >= VERTEBRAE:
			break
	if best.size() < 10:
		return null
	var fall := WhaleFall.new()
	fall.spine = best
	fall.heading = 1.0 if rng.randf() < 0.5 else -1.0
	if fall.heading < 0.0:
		fall.spine.reverse()
	@warning_ignore("integer_division")
	fall.pos = best[best.size() / 2]
	level.add_entity(fall)
	# The bones lie in a clearing of their own: no kelp or coral over them.
	var bounds := Rect2(best[0], Vector2.ZERO)
	for p in best:
		bounds = bounds.expand(p)
	level.clearings.append(bounds.grow_individual(2.5, 2.0, 2.5, 3.5))
	return fall


## Floor heights at vertebra spacing either side of [param from], as long as
## the floor stays within a step of its neighbour (a skeleton drapes over
## gentle slopes, not cliffs).
static func _floor_line(field: TerrainField, from: Vector2) -> PackedVector2Array:
	var y0 := MeridianStation.floor_below(field, from + Vector2(0.0, 2.5), 5.0)
	if y0 == -INF:
		return PackedVector2Array()
	var at := Vector2(from.x, y0)
	var line := PackedVector2Array([at])
	for dir: float in [-1.0, 1.0]:
		var last := at
		for k in VERTEBRAE:
			var x := last.x + dir * SPACING
			var y := MeridianStation.floor_below(field, Vector2(x, last.y + 2.5), 5.0)
			if y == -INF or absf(y - last.y) > 1.2:
				break
			last = Vector2(x, y)
			if dir < 0.0:
				line.insert(0, last)
			else:
				line.append(last)
			if line.size() >= VERTEBRAE:
				return line
	return line


static func _clear_of(p: Vector2, points: PackedVector2Array, dist: float) -> bool:
	for q in points:
		if q.distance_squared_to(p) < dist * dist:
			return false
	return true


func setup() -> void:
	radius = 0.0
	active_radius = 120.0
	# The rig is built in world space: entity position is only its anchor.
	var rig := Node3D.new()
	rig.top_level = true
	add_child(rig)
	var line := PackedVector3Array()
	for p in spine:
		line.append(Vector3(p.x, _floor_at(p.x, DEPTH), DEPTH))
	var built := WhaleFallModel.build(line, _floor_at, hash(spine))
	var bones := MeshInstance3D.new()
	bones.mesh = built.mesh
	var mat := ShaderMaterial.new()
	mat.shader = BONE_SHADER
	mat.set_shader_parameter(&"sediment_tint", level.biome.sediment_tint)
	bones.material_override = mat
	rig.add_child(bones)
	rig.add_child(_worms(built.tufts))
	rig.add_child(_add_hagfish(line))
	_add_mats(rig, line)
	var middle: Vector3 = built.middle
	_light = OmniLight3D.new()
	_light.light_color = WORM
	_light.omni_range = 10.0
	_light.light_energy = 0.5
	_light.position = middle + Vector3(0.0, 2.5, 3.0)
	rig.add_child(_light)


## The floor's height at ([param x], [param z]) about the skeleton: the
## floor line under it, rising towards the back of the cave as the rock does.
func _floor_at(x: float, z: float) -> float:
	var y := spine[0].y
	var lo := 0
	for i in range(1, spine.size()):
		if (spine[i].x - x) * (spine[i - 1].x - x) <= 0.0:
			lo = i - 1
			break
		if absf(spine[i].x - x) < absf(spine[lo].x - x):
			lo = i
	var a := spine[lo]
	var b := spine[mini(lo + 1, spine.size() - 1)]
	y = a.y if is_equal_approx(a.x, b.x) else lerpf(a.y, b.y, clampf((x - a.x) / (b.x - a.x), 0.0, 1.0))
	return y + PropScatter.surface_offset(z) - 0.15


## Hagfish weaving slow loops through the bones, nosing along low over them.
func _add_hagfish(line: PackedVector3Array) -> MultiMeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(spine) + 2
	_hagfish = MultiMesh.new()
	_hagfish.transform_format = MultiMesh.TRANSFORM_3D
	_hagfish.use_custom_data = true
	_hagfish.mesh = WhaleFallModel.hagfish()
	_hagfish.instance_count = HAGFISH
	for i in HAGFISH:
		var c := line[rng.randi_range(1, line.size() - 2)]
		_loops.append([c, rng.randf_range(1.2, 2.8), rng.randf_range(0.6, 1.6), rng.randf_range(0.25, 0.7),
			rng.randf_range(0.18, 0.32) * (1.0 if rng.randf() < 0.5 else -1.0), rng.randf() * TAU])
		_hagfish.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), 0.0, 0.0))
	_place_hagfish(0.0)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _hagfish
	var m := ShaderMaterial.new()
	m.shader = HAGFISH_SHADER
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


func _place_hagfish(delta: float) -> void:
	for i in _loops.size():
		var l: Array = _loops[i]
		l[5] += l[4] * delta
		var a: float = l[5]
		var c: Vector3 = l[0]
		var p := c + Vector3(cos(a) * l[1], 0.0, sin(a) * l[2])
		p.y = _floor_at(p.x, p.z) + l[3] + sin(a * 2.0) * 0.15
		# Heading along its loop.
		var ahead := c + Vector3(cos(a + signf(l[4]) * 0.1) * l[1], 0.0, sin(a + signf(l[4]) * 0.1) * l[2])
		ahead.y = _floor_at(ahead.x, ahead.z) + l[3] + sin((a + signf(l[4]) * 0.1) * 2.0) * 0.15
		var x := (ahead - p).normalized()
		var z := x.cross(Vector3.UP).normalized()
		_hagfish.set_instance_transform(i, Transform3D(Basis(x, z.cross(x), z), p))


## The worm tufts, one draw for them all.
func _worms(at: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = WhaleFallModel.tuft(7)
	mm.instance_count = at.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(spine) + 1
	for i in at.size():
		mm.set_instance_transform(i, at[i])
		mm.set_instance_custom_data(i, Color(rng.randf(), 0.0, 0.0, 0.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var worm := ShaderMaterial.new()
	worm.shader = WORM_SHADER
	mmi.material_override = worm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


## The silt round the fall: blackened where the rot has soured it, and
## patched with pale yellow and orange bacterial mats, laid on in stretches
## that follow the floor.
func _add_mats(rig: Node3D, line: PackedVector3Array) -> void:
	var step := 4
	var i := 0
	var k := 0
	while i < line.size() - 1:
		var j := mini(i + step, line.size() - 1)
		var a := line[i]
		var b := line[j]
		var along := Vector3(b.x - a.x, b.y - a.y, 0.0)
		var span := along.length()
		# Square to the floor: its slope along the bones, and the way it rises
		# towards the back of the cave.
		var up := Vector3(-along.y / maxf(absf(along.x), 0.01) * signf(along.x), 1.0, 0.32).normalized()
		var x := along.normalized()
		x = (x - up * x.dot(up)).normalized()
		var basis := Basis(x, up, x.cross(up))
		for dark: bool in [true, false]:
			var d := Decal.new()
			d.size = Vector3(span + (3.0 if dark else 1.5), 2.2, 6.5 if dark else 5.0)
			d.texture_albedo = _mat_texture(k * 2 + (0 if dark else 1), dark)
			if not dark:
				# The mats glow faintly (only where they are: the emission
				# texture is black between them).
				d.texture_emission = _mat_texture(k * 2 + 1, false, true)
				d.emission_energy = 0.35
			# Only on the floor, never up the rock behind it.
			d.normal_fade = 0.75
			d.upper_fade = 0.25
			d.lower_fade = 0.25
			d.sorting_offset = 0.0 if dark else 1.0
			rig.add_child(d)
			d.transform = Transform3D(basis, (a + b) * 0.5 + Vector3(0.0, 0.3, 0.0))
		i = j
		k += 1


## A patch of soured silt ([param dark]) or of bacterial mat, one of a few
## kinds by [param kind]; [param glow] gives the mat's glow instead (its
## colour where it is, black elsewhere).
static func _mat_texture(kind: int, dark: bool, glow := false) -> ImageTexture:
	var key := ((kind % 6) * 2 + (1 if dark else 0)) * 2 + (1 if glow else 0)
	if _mat_textures.has(key):
		return _mat_textures[key]
	var w := 160
	var h := 96
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var lumps := FastNoiseLite.new()
	lumps.seed = 31 + key / 2
	lumps.frequency = 0.05
	lumps.fractal_octaves = 3
	lumps.fractal_gain = 0.4
	var hue := FastNoiseLite.new()
	hue.seed = 77 + key / 2
	hue.frequency = 0.03
	for y in h:
		for x in w:
			var u := float(x) / (w - 1) * 2.0 - 1.0
			var v := float(y) / (h - 1) * 2.0 - 1.0
			var edge := clampf(1.0 - (u * u * 0.85 + v * v), 0.0, 1.0)
			var n := lumps.get_noise_2d(x, y) * 0.5 + 0.5
			var c: Color
			if dark:
				c = Color(0.035, 0.035, 0.04, smoothstep(0.0, 0.8, edge) * (0.2 + n * 0.3))
			else:
				# Mostly a white fluff, yellowing here and there, a little orange.
				var tone := clampf(hue.get_noise_2d(x, y) * 1.2 + 0.3, 0.0, 1.0)
				c = Color(0.95, 0.95, 0.9).lerp(Color(0.93, 0.85, 0.5), clampf(tone * 1.4, 0.0, 1.0))
				c = c.lerp(Color(0.9, 0.55, 0.25), clampf(tone * 2.0 - 1.5, 0.0, 1.0))
				c.a = smoothstep(0.55, 0.75, n + edge * 0.25 - 0.1) * smoothstep(0.0, 0.45, edge) * 0.6
				if glow:
					c = Color(c.r * c.a, c.g * c.a, c.b * c.a, 1.0)
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_mat_textures[key] = tex
	return tex


func tick(delta: float) -> void:
	_t += delta
	_light.light_energy = 0.45 + 0.08 * sin(_t * 1.1)
	_place_hagfish(delta)
	var sub := level.player
	if not surveyed and sub and sub.alive and sub.pos.distance_to(pos) < SURVEY_RANGE:
		surveyed = true
		Wonders.witness("whale_fall")
		sub.run.research += SURVEY_RESEARCH
		sub.show_gain(SURVEY_RESEARCH, " research", UiTheme.ACCENT)
		Events.toast.emit("Whale fall surveyed: +%d research" % SURVEY_RESEARCH, UiTheme.ACCENT)
