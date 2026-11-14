class_name ChoirEcho
extends Entity
## In the Hadal Trench something answers the sub's sonar the way it answered
## Meridian's (log_03): eleven seconds after a ping, the ping comes back up
## from far below, slowed down and stretched into something like a word. The
## returning wave charts the cave around the sub again, and makes no sound a
## hunter can follow. The first ping in a zone is always answered; after
## that, only sometimes.
##
## It is seen coming: a little before it, the deep below the sub stirs (a
## violet light welling up, silt drifting upwards); then it rises, a violet
## wave of uneven bands like the syllables of a word, wavering as it goes,
## across the water as well as the walls (see sonar.gdshaderinc's echo), and
## the sub shudders as it passes.

const DELAY := 11.0
const CHANCE := 0.35
const COOLDOWN := 40.0
## How far below the sub the answer rises from.
const DEPTH := 30.0
## How long before the answer the deep stirs.
const STIR_TIME := 2.5
const COLOR := Color(0.78, 0.5, 1.0)
const WAVE_SHADER := preload("res://src/fx/shaders/echo_wave.gdshader")

## Shown once per session, the first time something answers.
static var _explained := false

var answers := 0
var _wait := -1.0
var _cooldown := 0.0
var _rng := RandomNumberGenerator.new()
## The sheet the wave is seen on in open water, its material, the light
## welling up from below, the rising silt, and where the answer comes from.
var _sheet: MeshInstance3D
var _sheet_mat: ShaderMaterial
var _glow: OmniLight3D
var _silt: GPUParticles3D
var _from := Vector2.ZERO
## Time since the answer set out (-1 none), and whether it has passed the sub.
var _since := -100.0
var _passed := false


func setup() -> void:
	radius = 0.0
	active_radius = 1.0e6
	_rng.seed = level.layout.zone_seed + 11
	Events.sonar_pinged.connect(_on_ping)


func _exit_tree() -> void:
	if Events.sonar_pinged.is_connected(_on_ping):
		Events.sonar_pinged.disconnect(_on_ping)


## Whether an answer is on its way.
func pending() -> bool:
	return _wait >= 0.0


func tick(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_animate(delta)
	if _wait < 0.0:
		return
	if _wait > STIR_TIME and _wait - delta <= STIR_TIME:
		_stir()
	_wait -= delta
	if _wait <= 0.0:
		_wait = -1.0
		_answer()


func _on_ping(origin: Vector2, _range: float) -> void:
	# Only the sub's own pings (not the answer itself, which rises from below).
	var sub := level.player
	if sub == null or not sub.alive or origin.distance_to(sub.pos) > 1.5:
		return
	if pending() or _cooldown > 0.0:
		return
	if answers > 0 and _rng.randf() >= CHANCE:
		return
	_wait = DELAY
	_cooldown = COOLDOWN


func _answer() -> void:
	var sub := level.player
	if sub == null or not sub.alive:
		return
	answers += 1
	Wonders.witness("echo")
	var from := sub.pos + Vector2(0.0, -DEPTH)
	_from = from
	_since = 0.0
	_passed = false
	_build()
	var reach := DEPTH + sub.stats.sonar_range
	_sheet.mesh.size = Vector2.ONE * reach * 2.2
	_sheet.global_position = Vector3(from.x, from.y, -0.6)
	_sheet_mat.set_shader_parameter(&"stir_from", from)
	Audio.play(&"choir_echo", -3.0)
	# For the sound cues: it comes up from below.
	Audio.sound_at.emit(&"choir_echo", from)
	level.ping(from, reach, sub.stats.sonar_mark_time, true, true)
	if not _explained:
		_explained = true
		Events.toast.emit("Eleven seconds later, something far below pinged back.", UiTheme.ACCENT)


## The pieces it is seen by, made the first time they are needed.
func _build() -> void:
	if _sheet:
		return
	_sheet_mat = ShaderMaterial.new()
	_sheet_mat.shader = WAVE_SHADER
	_sheet = MeshInstance3D.new()
	_sheet.mesh = QuadMesh.new()
	_sheet.material_override = _sheet_mat
	_sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sheet.top_level = true
	_sheet.visible = false
	add_child(_sheet)
	_glow = OmniLight3D.new()
	_glow.light_color = COLOR
	_glow.omni_range = 26.0
	_glow.omni_attenuation = 1.6
	_glow.light_energy = 0.0
	_glow.top_level = true
	add_child(_glow)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22.0, 3.0, 4.0)
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 10.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 3.5
	pm.gravity = Vector3.ZERO
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.scale_min = 0.4
	pm.scale_max = 1.0
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color(COLOR, 0.0), Color(COLOR.lightened(0.3), 0.55), Color(COLOR, 0.0)])
	fade.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	_silt = GPUParticles3D.new()
	_silt.amount = 90
	_silt.lifetime = 5.0
	_silt.emitting = false
	_silt.process_material = pm
	var speck := QuadMesh.new()
	speck.size = Vector2(0.09, 0.09)
	speck.material = Fx.particle_material(Fx.soft_texture(), true)
	_silt.draw_pass_1 = speck
	_silt.visibility_aabb = AABB(Vector3(-26, -6, -6), Vector3(52, 40, 12))
	_silt.top_level = true
	add_child(_silt)


## The deep below the sub stirs: light welling up, silt drifting upwards.
func _stir() -> void:
	var sub := level.player
	if sub == null:
		return
	_build()
	_from = sub.pos + Vector2(0.0, -DEPTH)
	_since = -STIR_TIME
	_sheet.mesh.size = Vector2.ONE * (DEPTH + sub.stats.sonar_range) * 2.2
	_sheet.global_position = Vector3(_from.x, _from.y, -0.6)
	_sheet_mat.set_shader_parameter(&"stir_from", _from)
	_sheet.visible = true
	_silt.global_position = Vector3(sub.pos.x, sub.pos.y - 16.0, 0.0)
	_silt.restart()
	_silt.emitting = true


func _animate(delta: float) -> void:
	if _sheet == null or _since < -STIR_TIME - 0.01:
		return
	_since += delta
	# Welling up before it comes, gone as it rises.
	var stir := smoothstep(-STIR_TIME, -0.2, _since) * (1.0 - smoothstep(0.0, 2.5, _since))
	_sheet_mat.set_shader_parameter(&"stir", stir)
	var sub := level.player
	if sub:
		_glow.global_position = Vector3(sub.pos.x, sub.pos.y - 18.0 + clampf(_since, 0.0, 3.0) * 6.0, 2.0)
	_glow.light_energy = 1.0 * stir
	if _since > 0.0 and _silt.emitting:
		_silt.emitting = false
	# As the wave passes the sub, the hull shudders.
	if not _passed and sub and _since * Level.ECHO_SPEED >= sub.pos.distance_to(_from) - 1.0:
		_passed = true
		Events.shake_requested.emit(0.18)
		Settings.rumble_pulse(0.15, 0.35)
	var life := (DEPTH + 80.0) / Level.ECHO_SPEED + 3.0
	if _since > life:
		_sheet.visible = false
		_since = -100.0
