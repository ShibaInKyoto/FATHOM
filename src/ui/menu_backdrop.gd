class_name MenuBackdrop
extends Node3D
## Live 3D scene behind the menus: a real generated zone with the submarine
## idling in its entry chamber, a slowly drifting camera and periodic pings.

## Codex specimens too big for the viewport, and how far to shrink them.
const SPECIMEN_SCALE: Dictionary[StringName, float] = {&"choir": 0.28}
## Specimens whose bodies take shape as they swim.
const WARM_UP: Array[StringName] = [&"shoal"]

var level: Level
var sub: Submarine
var camera: Camera3D
## Horizontal camera offset; negative values push the submarine to the right
## of the screen to leave room for menus on the left.
var view_shift := -5.0
## Zone to show; -1 picks the deepest biome the player has reached.
var force_zone := -1
## In the Sunlit Shelf, a whale passes behind the submarine now and then.
var whale := false
var _t := 0.0
var _ping_timer := 2.0
var _anchor := Vector2.ZERO
var _run: RunState
## A codex species shown in place of the submarine (see [method preview_creature]).
var _specimen: Node3D
## A livery shown instead of the applied one (see [method preview_skin]).
var _skin: SubSkins.Livery


func _ready() -> void:
	var zone := clampi(Game.meta.deepest_zone, 0, BiomeLibrary.BIOME_COUNT * BiomeLibrary.ZONES_PER_BIOME - 1)
	# Show the deepest biome reached so far; the backdrop evolves with progress.
	zone = zone - zone % BiomeLibrary.ZONES_PER_BIOME
	if force_zone >= 0:
		zone = force_zone
	var layout := LevelGenerator.new().generate(BiomeLibrary.biome_for_zone(zone), 777 + zone, zone)
	level = Level.new()
	add_child(level)
	level.build(layout, Settings.quality)
	PropScatter.scatter(level)
	_run = RunState.new()
	_run.frame_id = StringName(Game.meta.selected_frame)
	_run.rebuild_stats(Game.meta.upgrades)
	_run.refill()
	sub = Submarine.new()
	level.add_child(sub)
	_anchor = _pick_spot(layout)
	sub.setup(level, _run, _anchor)
	sub.input_enabled = false
	sub.invulnerable = true
	sub.external_move = Vector2.ZERO
	level.player = sub
	# A shoal for life, and in the shallows a puffer that swells at each ping.
	var shoal := Shoal.new()
	shoal.pos = _anchor + Vector2(8, 3)
	level.add_entity(shoal)
	if whale and layout.biome.id == &"shelf":
		_add_whale(level)
	if layout.biome.creatures.has(&"puffer"):
		var puffer := Puffer.new()
		puffer.pos = layout.field.resolve_circle(_anchor + Vector2(-5.5, -1.5), 1.2)
		level.add_entity(puffer)
	camera = Camera3D.new()
	camera.fov = 40.0
	camera.far = 140.0
	add_child(camera)
	camera.current = true
	camera.position = Vector3(_anchor.x + view_shift, _anchor.y + 1.5, 17.0)
	var water := WaterFx.new()
	level.add_child(water)
	water.setup(layout.biome, layout.size(), camera, Settings.quality)


func _add_whale(on: Level) -> void:
	for rise: float in [-4.0, -5.5, 4.0, 5.5, -7.0, 7.0]:
		var way := PassingWhale.stretch_through(on.field, _anchor, rise)
		if not way.is_empty():
			var w := PassingWhale.new()
			w.backdrop = true
			w.from = way[0]
			w.to = way[1]
			w.pos = _anchor
			on.add_entity(w)
			return


func _pick_spot(layout: LevelLayout) -> Vector2:
	for c in layout.chambers:
		if c.kind == &"main" and c.radius.x > 12.0:
			return c.center
	return layout.start + Vector2(0, -4)


## Rebuilds the displayed submarine when the selected frame or paint changes.
func refresh_sub() -> void:
	_show_frame(StringName(Game.meta.selected_frame))


## Shows another frame (e.g. a locked one being browsed) without selecting it.
func preview_frame(frame_id: StringName) -> void:
	if sub and (frame_id != _run.frame_id or _skin):
		_show_frame(frame_id)


## Shows a livery (won or not) on the frame it fits: its own for a skin, the
## selected one for a paint.
func preview_skin(skin: SubSkins.Livery) -> void:
	if sub == null or skin == _skin:
		return
	_show_frame(StringName(Game.meta.selected_frame) if skin.is_paint() else skin.frame, skin)


## Shows a scanned species where the submarine idles (&"" brings the sub back).
## The specimen is never ticked, so it holds still with no behaviour running.
func preview_creature(id: StringName) -> void:
	if is_instance_valid(_specimen):
		# Out of the entity list now: freeing it later from outside a level tick
		# would leave a dead entry behind.
		if _specimen is Entity:
			level.entities.erase(_specimen)
		_specimen.queue_free()
	_specimen = null
	if sub:
		sub.model.visible = true
	var specimen: Node3D = null
	if LevelPopulator.SPECIES.has(id):
		specimen = LevelPopulator.SPECIES[id].new()
	elif id == &"mimic":
		specimen = Mimic.new()
	elif id == &"lamplighter":
		specimen = Lamplighter.new()
	elif id == &"ironclad":
		specimen = Ironclad.new()
	elif id == &"choir":
		specimen = ChoirBoss.specimen()
	if specimen == null or sub == null:
		return
	# Hide only the hull: the sub's lamp and fill light keep the specimen lit.
	sub.model.visible = false
	if specimen is Creature:
		var c := specimen as Creature
		# Placed first: some build their bodies round where they start.
		c.pos = sub.pos
		level.add_entity(c)
		c.active_radius = 0.0
		c.targetable = false
		c.scannable = false
		c.pos = sub.pos
		# Bodies laid out as they move (a school's fish, the Mother's coils)
		# get a moment to settle into shape.
		if WARM_UP.has(id):
			# With the sub out of the picture, or a school would scatter from it.
			level.player = null
			for i in 40:
				c.tick(1.0 / 30.0)
			level.player = sub
			c.vel = Vector2.ZERO
			c.pos = sub.pos
		if c.has_method(&"reveal"):
			# A creature that hides what it is, shown as it really is.
			c.call(&"reveal")
		c.sync_transform()
	else:
		level.add_child(specimen)
		specimen.position = Vector3(sub.pos.x, sub.pos.y, 0.0)
	# The giants, shrunk to fit the viewport.
	specimen.scale = Vector3.ONE * SPECIMEN_SCALE.get(id, 1.0)
	_specimen = specimen


func _show_frame(frame_id: StringName, skin: SubSkins.Livery = null) -> void:
	if sub == null:
		return
	var pos := sub.pos
	sub.queue_free()
	_run.frame_id = frame_id
	_run.rebuild_stats(Game.meta.upgrades)
	_run.refill()
	_skin = skin
	sub = Submarine.new()
	sub.skin = skin
	level.add_child(sub)
	sub.setup(level, _run, pos)
	sub.input_enabled = false
	sub.invulnerable = true
	sub.external_move = Vector2.ZERO
	level.player = sub


func _process(frame_delta: float) -> void:
	var delta := minf(frame_delta, 1.0 / 20.0)
	_t += delta
	var drift := Vector2(sin(_t * 0.23) * 3.0, sin(_t * 0.31) * 1.5)
	sub.external_move = ((_anchor + drift) - sub.pos).limit_length(1.0) * 0.25
	sub.aim = Vector2(cos(_t * 0.4) * 0.8 + 0.4, sin(_t * 0.27) * 0.5 - 0.2).normalized()
	sub.facing = 1.0 if sub.aim.x > 0.0 else -1.0
	_run.battery = _run.stats.max_battery
	_ping_timer -= delta
	if _ping_timer <= 0.0:
		_ping_timer = 7.0
		level.ping(sub.pos, 60.0, 3.0)
		level.emit_noise(sub.pos, 17.0, sub)
		Audio.play(&"sonar_ping", -12.0)
	sub.tick(delta)
	level.tick(delta)
	var target := Vector3(sub.pos.x + view_shift + sin(_t * 0.1) * 1.5, sub.pos.y + 1.5, 17.0 + sin(_t * 0.13) * 1.5)
	camera.position = camera.position.lerp(target, 1.0 - exp(-0.8 * delta))
	camera.look_at(Vector3(sub.pos.x + view_shift * 0.55, sub.pos.y, 0.0))
