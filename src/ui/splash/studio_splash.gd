extends Control
## The studio splash at startup: the Krypt Keepers lantern alone, no name.
## Out of the black the lantern appears, lit; the flame burns a moment, is
## doused in a puff of smoke, and the cold lantern fades back into the black.
## Then the title screen. Any key, button or click skips it.

const LANTERN := preload("res://assets/branding/lantern.png")
const FLAME := preload("res://assets/branding/lantern_flame.png")
## Where the flame's foot and tip sit on the lantern image (pixels).
const FLAME_BASE := Vector2(208.0, 520.0)
const FLAME_TIP := Vector2(204.0, 330.0)
## The lantern stands this tall on screen, as a share of its height.
const HEIGHT_SHARE := 0.46
## Seconds: black, lantern lit, burning, doused, cold, black again.
const T_APPEAR := 0.5
const T_LIT := 1.4
const T_BURN := 1.5
const T_DOUSE := 0.55
const T_COLD := 1.1
const T_FADE := 1.2
const T_HOLD := 0.5
const WARM := Color(1.0, 0.82, 0.55)

## Everything but the black: it fades in and out, the black never does.
var _stage: Control
var _lantern: TextureRect
var _flame: TextureRect
var _glow: TextureRect
var _halo: TextureRect
var _smoke: CPUParticles2D
var _t := 0.0
var _burning := 1.0
var _done := false
var _doused := false
var _tween: Tween


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(black)
	_stage = Control.new()
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	var glow_tex := _radial()
	# A wide warm halo round the whole lantern, and a hot core round the flame.
	_halo = _glow_rect(glow_tex, 0.22)
	_lantern = TextureRect.new()
	_lantern.texture = LANTERN
	_lantern.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_lantern.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_stage.add_child(_lantern)
	_glow = _glow_rect(glow_tex, 0.55)
	_flame = TextureRect.new()
	_flame.texture = FLAME
	_flame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_flame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_stage.add_child(_flame)
	_smoke = _make_smoke(glow_tex)
	_stage.add_child(_smoke)
	_layout()
	resized.connect(_layout)
	_stage.modulate = Color(1, 1, 1, 0)
	_run()


func _glow_rect(tex: Texture2D, strength: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.modulate = Color(WARM, strength)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	r.material = mat
	_stage.add_child(r)
	return r


func _layout() -> void:
	var view := size if size.y > 0.0 else get_viewport_rect().size
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
	_smoke.position = at + FLAME_TIP * k
	_smoke.scale_amount_min = 0.5 * k * 2.0
	_smoke.scale_amount_max = 0.9 * k * 2.0


func _run() -> void:
	_tween = create_tween()
	_tween.tween_interval(T_APPEAR)
	_tween.tween_callback(func() -> void: Audio.play(&"lantern_flame", -4.0))
	_tween.tween_property(_stage, ^"modulate:a", 1.0, T_LIT).set_trans(Tween.TRANS_SINE)
	_tween.tween_interval(T_BURN)
	_tween.tween_callback(_douse)
	_tween.tween_property(self, ^"_burning", 0.0, T_DOUSE).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_tween.tween_interval(T_COLD)
	_tween.tween_property(_stage, ^"modulate:a", 0.0, T_FADE).set_trans(Tween.TRANS_SINE)
	_tween.tween_interval(T_HOLD)
	_tween.tween_callback(_finish)


func _douse() -> void:
	_doused = true
	Audio.play(&"lantern_douse", -2.0)
	_smoke.emitting = true
	get_tree().create_timer(0.7).timeout.connect(func() -> void: _smoke.emitting = false)


func _process(delta: float) -> void:
	_t += delta
	# A living flame: it sways and stretches, and gutters as it is put out.
	var n := sin(_t * 11.0) * 0.5 + sin(_t * 17.3 + 1.0) * 0.3 + sin(_t * 5.1) * 0.2
	var dying := 1.0 - _burning
	var jitter := n * (0.04 + dying * 0.25)
	_flame.scale = Vector2(1.0 + jitter * 0.5 + dying * 0.2, maxf(_burning * (1.0 + jitter), 0.02))
	_flame.rotation = n * (0.025 + dying * 0.08)
	var out := 0.0 if _doused and _burning < 0.08 else 1.0
	_flame.modulate = Color(1, 1, 1, clampf(_burning * (0.92 + 0.08 * n) * out, 0.0, 1.0))
	var glow := _burning * (0.85 + 0.15 * n)
	_glow.modulate = Color(WARM, 0.55 * glow)
	_halo.modulate = Color(WARM, 0.22 * glow)


func _unhandled_input(event: InputEvent) -> void:
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


## A soft white disc fading to nothing at its rim.
static func _radial() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t


## A thin wisp of smoke rising from where the flame was.
static func _make_smoke(tex: Texture2D) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = tex
	p.emitting = false
	p.amount = 40
	p.lifetime = 2.6
	p.direction = Vector2(0.0, -1.0)
	p.spread = 12.0
	p.initial_velocity_min = 22.0
	p.initial_velocity_max = 40.0
	p.gravity = Vector2(4.0, -14.0)
	p.damping_min = 4.0
	p.damping_max = 8.0
	p.angular_velocity_min = -40.0
	p.angular_velocity_max = 40.0
	p.tangential_accel_min = -12.0
	p.tangential_accel_max = 12.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.3))
	grow.add_point(Vector2(1.0, 1.6))
	p.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	fade.colors = PackedColorArray([Color(0.85, 0.83, 0.8, 0.0), Color(0.85, 0.83, 0.8, 0.5), Color(0.6, 0.6, 0.6, 0.0)])
	p.color_ramp = fade
	return p
