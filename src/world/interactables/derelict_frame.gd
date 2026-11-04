class_name DerelictFrame
extends Entity
## A submarine nobody has flown in years, lying off the main way through the
## zone its builders lost it in (see [member Catalog.FrameDef.found_in]): the
## Mako prototype in the Twilight Reef, the old Bathysphere in the Midnight
## Caverns, the Whisper drone among the Abyssal Vents. Holding the sub
## alongside it feeds its memory core from the battery until its schematics
## have been copied, and from then on the hangar can build one.

## Seconds alongside to copy the schematics, and the battery that costs.
const COPY_TIME := 3.5
const COPY_DRAIN := 5.0
const REACH := 1.6

var frame_id: StringName = &"mako"
var progress := 0.0
var recovered := false
var _t := 0.0
var _announced := false
var _model: SubmarineModel
var _beacon: OmniLight3D
var _label: Label3D


## Lays the derelict of [param frame_id] in a quiet corner of [param level],
## away from the main way through. Null when there is nowhere fit.
static func place(level: Level, frame: StringName, used: PackedVector2Array) -> DerelictFrame:
	var layout := level.layout
	var rng := level.rng
	var best := Vector2.INF
	var best_off := 0.0
	for _i in 400:
		if layout.anchors.is_empty():
			break
		var a: LevelLayout.Anchor = layout.anchors[rng.randi() % layout.anchors.size()]
		if a.normal.y < 0.7 or a.pos.distance_to(layout.start) < 30.0 or a.pos.distance_to(layout.exit) < 15.0:
			continue
		var p := a.pos + a.normal * 1.4
		if level.field.sample(p) < 1.6 or not layout.is_reachable(p) or not _clear_of(p, used, 8.0):
			continue
		# As far off the main way as a short search finds.
		var off := INF
		for q in layout.main_path:
			off = minf(off, q.distance_to(p))
		if off > best_off:
			best_off = off
			best = p
	if best == Vector2.INF:
		return null
	var d := DerelictFrame.new()
	d.frame_id = frame
	d.pos = best
	level.add_entity(d)
	used.append(best)
	return d


static func _clear_of(p: Vector2, used: PackedVector2Array, dist: float) -> bool:
	for u in used:
		if u.distance_to(p) < dist:
			return false
	return true


func setup() -> void:
	radius = 1.5
	active_radius = 90.0
	targetable = true
	_model = SubmarineModel.new()
	add_child(_model)
	_model.build(frame_id)
	_model.fit_equipment([])
	_model.darken_hull(0.55)
	_model.set_cockpit_glow(0.0)
	# Settled where it came to rest, nose down a little.
	_model.rotation = Vector3(0.1, level.rng.randf_range(-0.3, 0.3), -0.18)
	_beacon = OmniLight3D.new()
	_beacon.light_color = Color(1.0, 0.75, 0.25)
	_beacon.omni_range = 8.0
	_beacon.position = Vector3(0.0, 1.3, 1.0)
	add_child(_beacon)
	_label = Fx.float_label(UiTheme.ACCENT)
	_label.font_size = 30
	_label.position = Vector3(0.0, 2.6, 0.5)
	_label.visible = false
	add_child(_label)


func display_name() -> String:
	return Catalog.frame(frame_id).name


func tick(delta: float) -> void:
	_t += delta
	var sub := level.player
	if not _announced and sub:
		_announced = true
		Events.toast.emit("Sonar: a hull signature somewhere in this zone, lying still. Not one of ours.", UiTheme.ACCENT)
	if recovered:
		_beacon.light_energy = lerpf(_beacon.light_energy, 0.0, 1.0 - exp(-1.0 * delta))
		return
	# A slow amber blink: something in there still has power.
	_beacon.light_energy = 1.8 if fmod(_t, 2.6) < 0.3 else 0.12
	var docked := sub and sub.alive and sub.pos.distance_to(pos) < Submarine.RADIUS + radius + REACH \
		and sub.run.battery > 0.5
	if docked:
		progress += delta / COPY_TIME
		sub.run.battery = maxf(sub.run.battery - COPY_DRAIN * delta, 0.0)
		_label.visible = true
		_label.text = "COPYING SCHEMATICS  %d%%" % int(progress * 100.0)
		_model.set_cockpit_glow(2.0 * progress)
		if progress >= 1.0:
			_recover()
	elif progress > 0.0:
		_label.text = "HOLD ALONGSIDE  %d%%" % int(progress * 100.0)


func on_sonar(_origin: Vector2, _mark_time: float) -> void:
	_t = 0.0


func _recover() -> void:
	recovered = true
	_label.visible = false
	_model.set_cockpit_glow(0.4)
	Game.meta.unlock_frame(frame_id)
	Game.save_game()
	Audio.play_at(&"wonder_chime", pos, 0.0)
	Fx.sparkle(level, pos, UiTheme.ACCENT)
	Events.banner.emit("%s RECOVERED" % display_name().to_upper(),
		"Its schematics are copied. The hangar can build you one.")
	Game.check_challenges()
