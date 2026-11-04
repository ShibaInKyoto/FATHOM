class_name ToolBelt
extends Node
## The submarine's secondary tools: flares, torpedoes, decoys and the shock pulse.
## The available set and ammunition come from [SubStats] and [RunState].

signal changed

const COOLDOWNS: Dictionary[StringName, float] = {&"flare": 0.6, &"torpedo": 0.9, &"shock": 1.2, &"decoy": 0.8}

var index := 0
var _sub: Submarine
var _cooldown := 0.0


func setup(sub: Submarine) -> void:
	_sub = sub


func current() -> StringName:
	var tools := _sub.stats.tools
	if tools.is_empty():
		return &""
	index = clampi(index, 0, tools.size() - 1)
	return tools[index]


func cycle() -> void:
	var tools := _sub.stats.tools
	if tools.size() < 2:
		return
	index = (index + 1) % tools.size()
	Audio.play(&"tool_cycle", -6.0)
	changed.emit()


## Ammo left for the current tool; -1 if the tool uses battery instead.
func ammo(tool: StringName) -> int:
	match tool:
		&"flare":
			return _sub.run.flares
		&"torpedo":
			return _sub.run.torpedoes
		&"decoy":
			return _sub.run.decoys
	return -1


func tick(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)


func use(aim: Vector2) -> void:
	var tool := current()
	if tool == &"" or _cooldown > 0.0 or not _sub.alive:
		return
	var ok := false
	match tool:
		&"flare":
			ok = _fire_flare(aim)
		&"torpedo":
			ok = _fire_torpedo(aim)
		&"shock":
			ok = _shock()
		&"decoy":
			ok = _launch_decoy(aim)
	if ok:
		_cooldown = COOLDOWNS.get(tool, 0.5)
		changed.emit()
	else:
		Audio.play(&"denied", -4.0)


func _fire_flare(aim: Vector2) -> bool:
	if _sub.run.flares <= 0:
		Events.toast.emit("Out of flares", Color(1.0, 0.5, 0.3))
		return false
	_sub.run.flares -= 1
	var flare := Flare.new()
	flare.pos = _sub.launch_point(&"flare", 1.4)
	flare.vel = aim * 17.0 + _sub.vel * 0.5
	_sub.level.add_entity(flare)
	Audio.play_at(&"flare_launch", _sub.pos, -2.0)
	return true


func _launch_decoy(aim: Vector2) -> bool:
	if _sub.run.decoys <= 0:
		Events.toast.emit("Out of decoys", Color(1.0, 0.5, 0.3))
		return false
	_sub.run.decoys -= 1
	var decoy := Decoy.new()
	decoy.pos = _sub.launch_point(&"decoy", 1.4)
	decoy.vel = aim * 13.0 + _sub.vel * 0.5
	_sub.level.add_entity(decoy)
	Audio.play_at(&"flare_launch", _sub.pos, -4.0, 0.05, 0.7)
	return true


func _fire_torpedo(aim: Vector2) -> bool:
	if _sub.run.torpedoes <= 0:
		Events.toast.emit("Out of torpedoes", Color(1.0, 0.5, 0.3))
		return false
	_sub.run.torpedoes -= 1
	var torpedo := Torpedo.new()
	torpedo.pos = _sub.launch_point(&"torpedo", 1.8)
	# Straight down the aim, carrying only the sub's speed along it.
	torpedo.vel = aim * (8.0 + maxf(_sub.vel.dot(aim), 0.0))
	torpedo.damage = _sub.stats.torpedo_damage
	torpedo.owner_sub = _sub
	_sub.level.add_entity(torpedo)
	Audio.play_at(&"torpedo_launch", _sub.pos, 0.0)
	_sub.level.emit_noise(_sub.pos, 20.0, _sub)
	return true


func _shock() -> bool:
	var cost := _sub.stats.shock_cost
	if _sub.run.battery < cost:
		Events.toast.emit("Battery too low for shock pulse", Color(1.0, 0.5, 0.3))
		return false
	_sub.run.battery -= cost
	var r := _sub.stats.shock_radius
	Fx.shockwave(_sub.level, _sub.pos, r, Color(0.4, 0.8, 1.0))
	if _sub.model:
		_sub.model.flash_shock()
	Fx.flash(_sub.level, _sub.pos, Color(0.5, 0.85, 1.0), r * 2.0, 0.35)
	Audio.play(&"shock", 0.0)
	Events.shake_requested.emit(0.4)
	_sub.level.emit_noise(_sub.pos, 25.0, _sub)
	for e in _sub.level.targets_in_radius(_sub.pos, r):
		if e is Creature:
			var c := e as Creature
			c.take_damage(_sub.stats.shock_damage, _sub.pos, &"shock")
			c.stun(2.5)
	return true
