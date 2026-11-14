class_name HushFx
extends MultiMeshInstance3D
## The mark of a pulse of the Choir's song holding a creature (see
## [method Level.choir_wave]): a violet ring swelling out through it as the
## song reaches it, and a violet glow round it for as long as it is held.

const SHADER := preload("res://src/fx/shaders/trance_halo.gdshader")
## The most creatures marked at once.
const MAX := 48
## How long the ring takes to swell out, and the glow to fade after.
const SWELL := 0.7
const FADE := 0.35

var level: Level
## The creatures held: [creature, when it is reached, when it is let go, size].
var _held: Array = []


func _init() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	mm.mesh = quad
	mm.instance_count = MAX
	mm.visible_instance_count = 0
	multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	material_override = mat


## Marks [param c], held from its [member Creature.hush_at] to its
## [member Creature.hush_end].
func mark(c: Creature) -> void:
	for h: Array in _held:
		if h[0] == c:
			h[1] = c.hush_at
			h[2] = c.hush_end
			return
	_held.append([c, c.hush_at, c.hush_end, clampf(c.radius * 5.0, 3.0, 9.0)])


func _process(_delta: float) -> void:
	if level == null:
		return
	var now := level.time
	var mm := multimesh
	var shown := 0
	var keep: Array = []
	for h: Array in _held:
		var c: Variant = h[0]
		if not is_instance_valid(c) or not (c as Creature).alive or now > float(h[2]) + FADE:
			continue
		keep.append(h)
		if now < float(h[1]) or shown >= MAX:
			continue
		var creature: Creature = c
		var size: float = h[3]
		var strength := 1.0 - smoothstep(float(h[2]), float(h[2]) + FADE, now)
		mm.set_instance_transform(shown, Transform3D(Basis().scaled(Vector3.ONE * size),
			Vector3(creature.pos.x, creature.pos.y, -0.6)))
		mm.set_instance_custom_data(shown, Color((now - float(h[1])) / SWELL, strength, strength, 0.0))
		shown += 1
	_held = keep
	mm.visible_instance_count = shown
