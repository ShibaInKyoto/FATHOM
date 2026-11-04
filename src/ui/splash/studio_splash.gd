extends Control
## The studio splash at startup: the Krypt Keepers lantern alone, no name.
## Out of the black the lantern appears, lit. Dark water rises from below,
## laps at the wick and puts the flame out in a hiss of steam and a burst of
## bubbles, then closes over the lantern. The sunken lantern fades into the
## black, then the title screen. Any key, button or click skips it.

const LANTERN := preload("res://assets/branding/lantern.png")
const FLAME := preload("res://assets/branding/lantern_flame.png")
const WATER := preload("res://src/ui/splash/water_rise.gdshader")
## Where the flame's foot and tip sit on the lantern image (pixels), and the
## height the water puts it out at, a little above its foot.
const FLAME_BASE := Vector2(208.0, 520.0)
const FLAME_TIP := Vector2(204.0, 330.0)
const WICK_Y := 502.0
## The lantern stands this tall on screen, as a share of its height.
const HEIGHT_SHARE := 0.46
## Seconds: black, lantern lit, burning, the water climbing to the flame,
## lapping at the wick, closing over the lantern, sunk, black again.
const T_APPEAR := 0.4
const T_LIT := 1.2
const T_BURN := 0.7
const T_RISE := 1.7
const T_LAP := 0.7
const T_SINK := 1.8
const T_UNDER := 0.7
const T_FADE := 1.1
const T_HOLD := 0.3
## Water height (share of the screen from the top): below the screen at the
## start, a sliver above the lantern's handle at the end.
const LEVEL_START := 1.04
const LEVEL_END := 0.1
const WARM := Color(1.0, 0.82, 0.55)
const BUBBLE := Color(0.72, 0.9, 1.0)

var _lantern: TextureRect
var _flame: TextureRect
var _glow: TextureRect
var _halo: TextureRect
var _steam: CPUParticles2D
var _water: ColorRect
## Clips the bubbles to the water, so they burst at the surface.
var _under: Control
var _fizz: CPUParticles2D
var _burst: CPUParticles2D
var _trail: CPUParticles2D
## A black sheet over everything: it lifts to show the lantern and falls again.
var _curtain: ColorRect
var _level := LEVEL_START
var _stir := 0.0
var _flame_line := 0.6
var _wick := Vector2.ZERO
var _t := 0.0
var _burning := 1.0
var _done := false
var _doused := false
var _tween: Tween


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var black := _rect(Color.BLACK)
	add_child(black)
	var glow_tex := _radial()
	# A wide warm halo round the whole lantern, and a hot core round the flame.
	_halo = _glow_rect(glow_tex, 0.22)
	_lantern = _image(LANTERN)
	_glow = _glow_rect(glow_tex, 0.55)
	_flame = _image(FLAME)
	_steam = _make_steam(glow_tex)
	add_child(_steam)
	_water = _rect(Color.WHITE)
	var mat := ShaderMaterial.new()
	mat.shader = WATER
	_water.material = mat
	add_child(_water)
	_under = Control.new()
	_under.clip_contents = true
	_under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_under)
	var ring := _ring()
	_fizz = _make_bubbles(ring, 26, 3.4, 0.0)
	_fizz.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_burst = _make_bubbles(ring, 30, 2.6, 0.85)
	_burst.one_shot = true
	_trail = _make_bubbles(ring, 14, 2.4, 0.0)
	for p: CPUParticles2D in [_fizz, _burst, _trail]:
		_under.add_child(p)
	_curtain = _rect(Color.BLACK)
	add_child(_curtain)
	_layout()
	resized.connect(_layout)
	_run()


func _image(tex: Texture2D) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r


func _glow_rect(tex: Texture2D, strength: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.modulate = Color(WARM, strength)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	r.material = mat
	add_child(r)
	return r


func _layout() -> void:
	var view := _view()
	var k := view.y * HEIGHT_SHARE / LANTERN.get_height()
	var lantern_size := Vector2(LANTERN.get_width(), LANTERN.get_height()) * k
	var at := (view - lantern_size) * 0.5
	for r: TextureRect in [_lantern, _flame]:
		r.position = at
		r.size = lantern_size
	_flame.pivot_offset = FLAME_BASE * k
	var flame_mid := at + (FLAME_BASE + FLAME_TIP) * 0.5 * k
	_glow.size = Vector2.ONE * 420.0 * k
	_glow.position = flame_mid - _glow.size * 0.5
	_halo.size = Vector2.ONE * 1500.0 * k
	_halo.position = flame_mid - _halo.size * 0.5
	_wick = at + Vector2(FLAME_BASE.x, WICK_Y) * k
	_flame_line = _wick.y / view.y
	_steam.emission_rect_extents = Vector2(34.0, 4.0) * k
	var s := view.y / 1080.0
	for p: CPUParticles2D in [_steam, _fizz, _burst, _trail]:
		p.scale_amount_min = p.get_meta(&"scale_min", 1.0) * s
		p.scale_amount_max = p.get_meta(&"scale_max", 1.0) * s
	_fizz.emission_rect_extents = Vector2(view.x * 0.5, 30.0)
	_burst.emission_sphere_radius = 10.0 * k * 2.0
	_trail.emission_sphere_radius = 4.0 * k * 2.0
	var mat := _water.material as ShaderMaterial
	mat.set_shader_parameter(&"flame_x", _wick.x / view.x)
	_place_water()


func _view() -> Vector2:
	return size if size.y > 0.0 else get_viewport_rect().size


func _run() -> void:
	_tween = create_tween()
	_tween.tween_interval(T_APPEAR)
	_tween.tween_callback(func() -> void: Audio.play(&"lantern_flame", -4.0))
	_tween.tween_property(_curtain, ^"color:a", 0.0, T_LIT).set_trans(Tween.TRANS_SINE)
	_tween.tween_interval(T_BURN)
	_tween.tween_callback(_flood)
	# The water slows as it nears the flame, laps at the wick, then swallows the lantern.
	_tween.tween_property(self, ^"_level", _flame_line - 0.004, T_RISE) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, ^"_level", _flame_line - 0.03, T_LAP).set_trans(Tween.TRANS_SINE)
	_tween.tween_property(self, ^"_level", LEVEL_END, T_SINK) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_interval(T_UNDER)
	_tween.tween_property(_curtain, ^"color:a", 1.0, T_FADE).set_trans(Tween.TRANS_SINE)
	_tween.tween_interval(T_HOLD)
	_tween.tween_callback(_finish)


func _flood() -> void:
	Audio.play(&"water_rise", -3.0)
	_fizz.emitting = true


func _douse() -> void:
	_doused = true
	Audio.play(&"lantern_douse", -1.0)
	_steam.position = Vector2(_wick.x, _level * _view().y - 6.0)
	_steam.emitting = true
	_burst.restart()
	_burst.emitting = true
	_trail.emitting = true
	_stir = 1.0
	get_tree().create_timer(0.3).timeout.connect(func() -> void: _steam.emitting = false)
	get_tree().create_timer(1.8).timeout.connect(func() -> void: _trail.emitting = false)
	# A last sputter as the water takes the wick, then nothing.
	var out := create_tween()
	out.tween_property(self, ^"_burning", 1.25, 0.05)
	out.tween_property(self, ^"_burning", 0.0, 0.2).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


func _process(delta: float) -> void:
	_t += delta
	if not _doused and _level <= _flame_line:
		_douse()
	_stir = maxf(_stir - delta * 0.6, 0.0)
	# A living flame: it sways and stretches, and gutters as the water nears it.
	var n := sin(_t * 11.0) * 0.5 + sin(_t * 17.3 + 1.0) * 0.3 + sin(_t * 5.1) * 0.2
	var near := clampf(1.0 - (_level - _flame_line) / 0.1, 0.0, 1.0) if not _doused else 1.0
	var dying := clampf(1.0 - _burning, 0.0, 1.0)
	var jitter := n * (0.04 + near * 0.08 + dying * 0.25)
	_flame.scale = Vector2(1.0 + jitter * 0.5 + dying * 0.2, maxf(_burning * (1.0 + jitter), 0.02))
	_flame.rotation = n * (0.025 + near * 0.03 + dying * 0.08)
	var lit := 0.0 if _doused and _burning < 0.08 else 1.0
	_flame.modulate = Color(1, 1, 1, clampf(_burning * (0.92 + 0.08 * n) * lit, 0.0, 1.0))
	var glow := _burning * (0.85 + 0.15 * n)
	_glow.modulate = Color(WARM, 0.55 * glow)
	_halo.modulate = Color(WARM, 0.22 * glow)
	var mat := _water.material as ShaderMaterial
	mat.set_shader_parameter(&"warm", clampf(glow, 0.0, 1.2) * near)
	mat.set_shader_parameter(&"stir", _stir)
	_place_water()


## Moves the water to its level, with the bubbles' clip and emitters in step.
func _place_water() -> void:
	var view := _view()
	(_water.material as ShaderMaterial).set_shader_parameter(&"level", _level)
	var line := _level * view.y
	_under.position = Vector2(0.0, line)
	_under.size = Vector2(view.x, maxf(view.y - line, 0.0))
	# The emitters stay put on screen while the clip that holds them climbs.
	_fizz.position = Vector2(view.x * 0.5, view.y + 20.0) - _under.position
	_burst.position = _wick + Vector2(0.0, 6.0) - _under.position
	_trail.position = _burst.position


func _input(event: InputEvent) -> void:
	if _done:
		return
	var pressed: bool = event is InputEventKey and event.pressed or event is InputEventMouseButton and event.pressed \
		or event is InputEventJoypadButton and event.pressed
	if pressed:
		get_viewport().set_input_as_handled()
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	if _tween:
		_tween.kill()
	Router.go_to(Router.TITLE, 0.3)


func _rect(color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## A soft white disc fading to nothing at its rim.
static func _radial() -> GradientTexture2D:
	return _disc(PackedFloat32Array([0.0, 0.35, 1.0]),
		PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)]))


## A bubble: a clear middle inside a thin bright skin.
static func _ring() -> GradientTexture2D:
	return _disc(PackedFloat32Array([0.0, 0.6, 0.8, 0.9, 1.0]), PackedColorArray([
		Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.12), Color(1, 1, 1, 0.95), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)]))


static func _disc(offsets: PackedFloat32Array, colors: PackedColorArray) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = offsets
	g.colors = colors
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


## A puff of steam thrown up off the water where the flame went out.
static func _make_steam(tex: Texture2D) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = tex
	p.emitting = false
	p.amount = 40
	p.lifetime = 2.0
	p.explosiveness = 0.4
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.direction = Vector2(0.0, -1.0)
	p.spread = 28.0
	p.initial_velocity_min = 150.0
	p.initial_velocity_max = 280.0
	p.gravity = Vector2(6.0, -45.0)
	p.damping_min = 70.0
	p.damping_max = 120.0
	p.angular_velocity_min = -60.0
	p.angular_velocity_max = 60.0
	p.tangential_accel_min = -20.0
	p.tangential_accel_max = 20.0
	p.set_meta(&"scale_min", 1.3)
	p.set_meta(&"scale_max", 2.3)
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(1.0, 2.2))
	p.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.1, 1.0])
	fade.colors = PackedColorArray([Color(0.95, 0.96, 0.97, 0.0), Color(0.95, 0.96, 0.97, 0.5),
		Color(0.8, 0.84, 0.86, 0.0)])
	p.color_ramp = fade
	return p


## Bubbles wobbling up through the water. They stay where they were let go
## of while the water's clip moves, and vanish when they reach the surface.
static func _make_bubbles(tex: Texture2D, amount: int, life: float, burst: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = tex
	p.emitting = false
	p.local_coords = false
	p.amount = amount
	p.lifetime = life
	p.explosiveness = burst
	p.randomness = 0.5
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.initial_velocity_min = 40.0 if burst > 0.0 else 50.0
	p.initial_velocity_max = 170.0 if burst > 0.0 else 120.0
	p.spread = 70.0 if burst > 0.0 else 10.0
	p.direction = Vector2(0.0, -1.0)
	p.gravity = Vector2(0.0, -110.0)
	p.damping_min = 20.0
	p.damping_max = 40.0
	p.tangential_accel_min = -40.0
	p.tangential_accel_max = 40.0
	p.set_meta(&"scale_min", 0.08 if burst <= 0.0 else 0.1)
	p.set_meta(&"scale_max", 0.22 if burst <= 0.0 else 0.32)
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.08, 0.85, 1.0])
	fade.colors = PackedColorArray([Color(BUBBLE, 0.0), Color(BUBBLE, 0.8), Color(BUBBLE, 0.6), Color(BUBBLE, 0.0)])
	p.color_ramp = fade
	return p
