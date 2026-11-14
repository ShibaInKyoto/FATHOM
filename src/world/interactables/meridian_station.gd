class_name MeridianStation
extends Entity
## The ruins of Meridian Deep, the research station whose logs tell the
## story, settled on the floor of the final zone's station gallery (off the
## middle chamber) behind the playfield (see [StationModel]). Two habitat
## modules flank a domed hub; a few windows still have power. The trench
## grew rock over the escape lock. The mast beacon that
## drew the expedition down still pings: each ping charts the cave around
## it, marks what swims nearby and is loud enough to draw hunters. The first
## time the sub comes near, its arrival is announced and the survey earns
## research.

## How far behind the play plane the station stands.
const DEPTH := -7.0
const BEACON_PERIOD := 7.0
const BEACON_RANGE := 28.0
const ARRIVE_RANGE := 16.0
## The beacon only pings while the sub is this close.
const HEARING := 70.0
const SURVEY_RESEARCH := 10
const ACTIVE_RADIUS := 220.0
## Seconds after arriving before the hull speakers start the lullaby.
const LULLABY_DELAY := 3.0
const BEACON_COLOR := Color(0.4, 1.0, 0.6)
const STATION_SHADER := preload("res://src/fx/shaders/station.gdshader")
const FLOWSTONE_SHADER := preload("res://src/fx/shaders/flowstone.gdshader")
## How far the station leans (it settled unevenly).
const TILT := 0.035
## The model's scale (it is built in metres a little smaller than life).
const SCALE := 1.3

var greeted := false
## How far Okafor's lullaby has got: 0 not begun, 1 the speakers, 2 the
## answer from below, 3 over.
var lullaby_stage := 0
var _lullaby_t := -1.0
var _t := 0.0
var _flicker := 1.0
var _flicker_timer := 0.0
var _mat: ShaderMaterial
var _rig := Transform3D.IDENTITY
## How high the mast reaches, under the cave's roof (in the rig's space).
var _mast_top := StationModel.MAST_TOP
var _warm: OmniLight3D
var _lamp: SpotLight3D
var _beacon_light: OmniLight3D
var _hum: AudioStreamPlayer3D


## The y of the floor straight below [param p] (which must be in open water),
## or -INF if there is rock at [param p] or no floor within [param max_drop].
static func floor_below(field: TerrainField, p: Vector2, max_drop := 30.0) -> float:
	if field.sample(p) <= 0.5:
		return -INF
	var q := p
	while p.y - q.y < max_drop:
		if field.sample(q) < 0.05:
			# The field is steep near rock: home in on the surface itself.
			var above := q.y + 0.25
			var below := q.y
			for _i in 6:
				var mid := (above + below) * 0.5
				if field.sample(Vector2(q.x, mid)) < 0.0:
					below = mid
				else:
					above = mid
			return (above + below) * 0.5
		q.y -= 0.25
	return -INF


func setup() -> void:
	radius = 0.0
	active_radius = ACTIVE_RADIUS
	var rig := Node3D.new()
	# The floor behind the play plane rises, so the rig sits a little higher.
	rig.position = Vector3(0.0, PropScatter.surface_offset(DEPTH) - 0.3, DEPTH)
	rig.rotation.z = TILT
	rig.scale = Vector3.ONE * SCALE
	add_child(rig)
	_rig = rig.transform
	var body := MeshInstance3D.new()
	if level:
		_mast_top = clampf(_roof_at(StationModel.MAST_X, 0.0) - 1.4, StationModel.MAST_LOWEST,
			StationModel.MAST_TOP)
	var station := StationModel.build(_floor_at if level else func(_x: float, _z: float) -> float: return -0.2,
		_mast_top)
	body.mesh = station
	_mat = ShaderMaterial.new()
	_mat.shader = STATION_SHADER
	_mat.set_shader_parameter(&"sediment_tint", level.biome.sediment_tint if level else Color(0.4, 0.38, 0.34))
	_mat.set_shader_parameter(&"beacon_color", BEACON_COLOR)
	body.material_override = _mat
	rig.add_child(body)
	if level:
		rig.add_child(_rock())
	rig.add_child(_stencil())
	# The glow of the lit windows on the floor in front.
	_warm = OmniLight3D.new()
	_warm.light_color = Color(1.0, 0.75, 0.45)
	_warm.omni_range = 9.0
	_warm.light_energy = 0.6
	_warm.position = Vector3(-4.5, 2.6, 2.6)
	rig.add_child(_warm)
	# The one floodlight still working, on the hub, washing the floor.
	var hub_dir := Vector3(-0.45, -0.42, 0.79).normalized()
	_lamp = SpotLight3D.new()
	_lamp.light_color = Color(1.0, 0.82, 0.55)
	_lamp.spot_range = 11.0
	_lamp.spot_angle = 34.0
	_lamp.spot_attenuation = 0.9
	_lamp.light_energy = 1.6
	_lamp.position = StationModel.HUB + hub_dir * (StationModel.HUB_R + 0.55)
	rig.add_child(_lamp)
	_lamp.look_at_from_position(_lamp.position, _lamp.position + Vector3(-0.2, -0.45, 1.0))
	_beacon_light = OmniLight3D.new()
	_beacon_light.light_color = BEACON_COLOR
	_beacon_light.omni_range = 14.0
	_beacon_light.light_energy = 0.0
	_beacon_light.position = StationModel.beacon_at(_mast_top) + Vector3(0.0, 0.0, 1.0)
	rig.add_child(_beacon_light)
	# The failing power hums, and stutters with the lights.
	_hum = AudioStreamPlayer3D.new()
	var hum := Audio.get_stream(&"station_hum")
	if hum is AudioStreamOggVorbis:
		(hum as AudioStreamOggVorbis).loop = true
	_hum.stream = hum
	_hum.bus = &"SFX"
	_hum.unit_size = 8.0
	_hum.max_distance = 45.0
	_hum.volume_db = -10.0
	_hum.position = Vector3(0.0, 3.2, 1.0)
	rig.add_child(_hum)
	if hum:
		_hum.play()
	_t = BEACON_PERIOD - 1.5


## The floor's height (y, in the rig's space) under the rig's point (x, z):
## where the terrain's relief surface lies, so the legs and the rock stand
## in it, not over it.
func _floor_at(x: float, z: float) -> float:
	var lo := -4.0
	var hi := 8.0
	for _i in 18:
		var mid := (lo + hi) * 0.5
		var w := Vector3(pos.x, pos.y, 0.0) + _rig * Vector3(x, mid, z)
		# In front of the surface there (open water): the floor is lower.
		if TerrainRelief.height(level.field, Vector2(w.x, w.y)) < w.z:
			hi = mid
		else:
			lo = mid
	return (lo + hi) * 0.5


## The height (y, in the rig's space) of the cave's roof over the rig's
## point (x, z), or 12 m up if it is higher than that.
func _roof_at(x: float, z: float) -> float:
	var y := 5.0
	while y < 12.0:
		var w := Vector3(pos.x, pos.y, 0.0) + _rig * Vector3(x, y, z)
		if TerrainRelief.height(level.field, Vector2(w.x, w.y)) >= w.z:
			return y
		y += 0.2
	return y


## "MERIDIAN DEEP" painted along the left module, under its windows, and
## the module numbers.
func _stencil() -> Node3D:
	var marks := Node3D.new()
	var lines := [["MERIDIAN DEEP", 64, 0.0062, StationModel.left_xf(), Vector3(0.0, 0, 0), StationModel.NAME_UP],
		["HAB-1", 40, 0.004, StationModel.left_xf(), Vector3(-2.5, 0, 0), 0.05],
		["HAB-2", 40, 0.004, StationModel.right_xf(), Vector3(-2.5, 0, 0), 0.05]]
	for line: Array in lines:
		var text := Label3D.new()
		text.text = line[0]
		text.font = UiTheme.TITLE_FONT_FILE
		text.font_size = line[1]
		text.outline_size = 0
		text.pixel_size = line[2]
		text.modulate = Color(0.06, 0.07, 0.1, 0.92)
		text.shaded = true
		text.double_sided = false
		text.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
		var up: float = line[5]
		var xf: Transform3D = line[3]
		var r := StationModel.MODULE_R + (0.056 if line[0] != "MERIDIAN DEEP" else 0.006)
		text.transform = xf * Transform3D(Basis(Vector3.RIGHT, -up), (line[4] as Vector3) + StationModel.round_dir(up) * r)
		marks.add_child(text)
	return marks


## The rock the trench grew over the escape lock: lumps of flowstone heaped
## over it out of the floor, swallowing the right module's nose, fluted
## where they ran down, and one tongue run on over the nose's top; built in
## the rig's space.
func _rock() -> MeshInstance3D:
	var noise := FastNoiseLite.new()
	noise.seed = hash(pos)
	noise.frequency = 0.75
	noise.fractal_octaves = 3
	var right := StationModel.right_xf()
	var lock := right * Vector3((StationModel.LOCK_FROM + StationModel.LOCK_TO) * 0.5, 0.0, 0.0)
	var b := ModelBuilder.new()
	# One mound poured over the lock, a pool spread at its foot and a tongue
	# run on over the nose: [centre, half size, how far its skirt runs down
	# into the floor, how lumpy].
	var pool := Vector2(lock.x + 0.9, 1.35)
	var lumps := [[lock + Vector3(0.2, -0.45, 0.05), Vector3(2.0, 1.85, 1.65), 1.8, 0.1],
		[Vector3(pool.x, _floor_at(pool.x, pool.y) + 0.02, pool.y), Vector3(1.45, 0.3, 0.85), 2.0, 0.05],
		[right * Vector3(2.75, 1.2, 0.3), Vector3(1.05, 0.36, 0.62), 1.0, 0.04]]
	for l: Array in lumps:
		_lump(b, l[0], l[1], l[2], l[3], noise)
	var rock := MeshInstance3D.new()
	rock.mesh = b.commit()
	var mat := ShaderMaterial.new()
	mat.shader = FLOWSTONE_SHADER
	mat.set_shader_parameter(&"rock_albedo", TerrainRenderer.ROCK_ALBEDO)
	mat.set_shader_parameter(&"rock_rough", TerrainRenderer.ROCK_ROUGH)
	mat.set_shader_parameter(&"rock_tint", level.biome.rock_tint)
	mat.set_shader_parameter(&"rock_tint_deep", level.biome.rock_tint_deep)
	mat.set_shader_parameter(&"sediment_tint", level.biome.sediment_tint)
	# Lit as the rock nearer the front is, so it shows against the floor.
	mat.set_shader_parameter(&"back_depth", 20.0)
	rock.material_override = mat
	return rock


## One lump of flowstone round [param c], [param half] its half size, its
## lower half stretched [param skirt] times down so it spreads into the
## floor; swelling gently by [param lumpy] with [param noise], and fluted
## down its sides where it ran.
static func _lump(b: ModelBuilder, c: Vector3, half: Vector3, skirt: float, lumpy: float,
		noise: FastNoiseLite) -> void:
	var rings := 26
	var around := 96
	var rows: Array[PackedVector3Array] = []
	for i in rings + 1:
		var lat := lerpf(-PI * 0.5, PI * 0.5, float(i) / rings)
		var row := PackedVector3Array()
		for j in around + 1:
			var lon := TAU * (j % around) / around
			var d := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
			var q := d * half
			if lat < 0.0:
				# Spread at its foot, as rock that has run down does.
				q.y *= skirt
				q.x *= 1.0 - 0.3 * sin(lat)
				q.z *= 1.0 - 0.3 * sin(lat)
			var bump := noise.get_noise_3dv((c + q) * 0.6) * lumpy * 2.0
			# Flutes: narrow and uneven, from the shoulders down.
			var wave := sin(lon * 23.0 + noise.get_noise_3dv(c + q * 0.3) * 6.0)
			var flute := 0.035 * signf(wave) * pow(absf(wave), 0.6) * cos(lat) \
				* (1.0 - smoothstep(-0.1, 0.75, sin(lat))) * smoothstep(0.03, 0.08, lumpy)
			row.append(c + q * (1.0 + bump + flute))
		rows.append(row)
	var ns := []
	for i in rings + 1:
		var nrow := PackedVector3Array()
		for j in around + 1:
			var p := rows[i][j]
			var across := rows[i][(j + 1) % around] - rows[i][(j + around - 1) % around]
			var up := rows[mini(i + 1, rings)][j] - rows[maxi(i - 1, 0)][j]
			var n := across.cross(up).normalized()
			if n.dot(p - c) < 0.0:
				n = -n
			if i == 0 or i == rings:
				n = Vector3(0.0, signf(float(i) - 0.5), 0.0)
			nrow.append(n)
		ns.append(nrow)
	b.grid(rows, ns, Color(0.3, 0.0, 0.0))


## Where the beacon pings from, on the gameplay plane.
func beacon_pos() -> Vector2:
	var rig := _rig
	if rig == Transform3D.IDENTITY:
		rig = Transform3D(Basis(Vector3.BACK, TILT).scaled(Vector3.ONE * SCALE),
			Vector3(0.0, PropScatter.surface_offset(DEPTH) - 0.3, DEPTH))
	var at := rig * StationModel.beacon_at(_mast_top)
	return pos + Vector2(at.x, at.y)


func tick(delta: float) -> void:
	_t += delta
	if _t >= BEACON_PERIOD:
		_t -= BEACON_PERIOD
		_ping()
	# Each ping shows as a flash of the beacon and the sonar wave it sends.
	var flash := maxf(1.0 - _t * 1.5, 0.0)
	_beacon_light.light_energy = 3.0 * flash
	_mat.set_shader_parameter(&"beacon", flash)
	# The failing circuit stutters: long stretches lit, sudden drop-outs.
	_flicker_timer -= delta
	if _flicker_timer <= 0.0:
		var out := level.rng.randf() < 0.3
		_flicker = level.rng.randf_range(0.0, 0.15) if out else level.rng.randf_range(0.9, 1.3)
		_flicker_timer = level.rng.randf_range(0.04, 0.16) if out else level.rng.randf_range(0.3, 2.2)
	_mat.set_shader_parameter(&"failing_energy", 1.6 * _flicker)
	_warm.light_energy = 0.4 + 0.3 * _flicker
	_hum.volume_db = -10.0 + linear_to_db(clampf(_flicker, 0.1, 1.0))
	var sub := level.player
	if not greeted and sub and sub.alive and sub.pos.distance_to(pos + Vector2(0.0, 3.0)) < ARRIVE_RANGE:
		_greet(sub)
	if _lullaby_t >= 0.0:
		_play_lullaby(delta)


func _ping() -> void:
	var at := beacon_pos()
	# Quiet while the Choir sings (its duel needs every ping slot for the
	# pilot's answers) and when nobody is near enough to hear it.
	var sub := level.player
	if level.boss and level.boss.active or sub == null or sub.pos.distance_to(at) > HEARING:
		return
	Audio.play_at(&"beacon_ping", at, -1.0, 0.02, 0.8)
	level.ping(at, BEACON_RANGE, 2.5)
	level.emit_noise(at, 12.0, self)


func _greet(sub: Submarine) -> void:
	greeted = true
	Events.banner.emit("MERIDIAN DEEP", "Its beacon is still pinging.")
	sub.run.research += SURVEY_RESEARCH
	sub.show_gain(SURVEY_RESEARCH, " research", UiTheme.ACCENT)
	Events.toast.emit("Station survey: +%d research" % SURVEY_RESEARCH, UiTheme.ACCENT)
	_lullaby_t = 0.0
	# Zone-wide while it plays, so it plays out (and hands the music back)
	# wherever the sub goes.
	active_radius = 1.0e6


## Okafor's lullaby (log_08): the hull speakers still play it, then something
## far below sings it back, and the audience over the station turns to listen.
func _play_lullaby(delta: float) -> void:
	_lullaby_t += delta
	# The Choir's own song takes over once it wakes.
	var singing := level.boss != null and level.boss.active
	match lullaby_stage:
		0:
			if singing:
				_end_lullaby()
			elif _lullaby_t >= LULLABY_DELAY:
				_next_lullaby_stage()
				Audio.stop_music(2.0)
				Audio.play_at(&"lullaby_speaker", pos + Vector2(-2.0, 5.0), 3.0, 0.0)
				Events.toast.emit("The station's speakers crackle into life: Okafor's lullaby, still playing.",
					UiTheme.ACCENT)
		1:
			if _lullaby_t >= _length(&"lullaby_speaker") - 3.0:
				_next_lullaby_stage()
				if singing:
					_end_lullaby()
					return
				Audio.play(&"lullaby_choir", 0.0)
				# For the sound cues: it comes up from below.
				Audio.sound_at.emit(&"lullaby_choir", pos + Vector2(0.0, -30.0))
				Events.toast.emit("Something far below sings it back. Perfectly.", UiTheme.ACCENT)
				for e in level.entities:
					if e is StationAudience:
						(e as StationAudience).listen()
		2:
			if _lullaby_t >= _length(&"lullaby_choir") - 4.0:
				_end_lullaby()
				Wonders.witness("lullaby")
				if not singing:
					Audio.play_music(level.biome.music, 4.0)


func _end_lullaby() -> void:
	lullaby_stage = 3
	_lullaby_t = -1.0
	active_radius = ACTIVE_RADIUS


func _next_lullaby_stage() -> void:
	lullaby_stage += 1
	_lullaby_t = 0.0


static func _length(sound: StringName) -> float:
	var stream := Audio.get_stream(sound)
	return stream.get_length() if stream else 4.0
