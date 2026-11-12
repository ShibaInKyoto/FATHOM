class_name Autopilot
extends Node
## Debug/test driver that flies the submarine along the zone's main path,
## pings and fires at threats. Used by the smoke test and screenshot tooling.
##
## Enabled with user args:  -- --autopilot [--shots=<dir>] [--time=<seconds>]
## [--zone=<n>] [--frame=<id>] [--seed=<n>]. Exits the game when time runs out and prints a summary.

var sub: Submarine
var level: Level
var shots_dir := ""
var time_limit := 60.0
var shot_interval := 4.0

## With --stops the decompression stop UI is shown (for screenshots).
var show_stops := false
## --event=<id> forces a zone event in every zone (for screenshots).
var force_event: StringName = &""
var ping_interval := 12.0
var _elapsed := 0.0
var _shot_timer := 1.5
var _path_index := 0
var _ping_timer := 0.0
var _tool_timer := 4.0
## Set while the Lamplighter fight has the lamp switched off.
var _ran_dark := false
var _guardian_seen := false
var _shots := 0
var _stuck_timer := 0.0
var _last_pos := Vector2.ZERO
var _zones_cleared := 0
var _route := PackedVector2Array()
var _force_exit_at := -1.0
var _max_draw_calls := 0
var _max_primitives := 0
var _max_frame_ms := 0.0
var _frame_ms_sum := 0.0
var _frames := 0
var _reported := false
var _glass: SingingGlass
var _choir_part := -1
## Where the route leads: the exit, or a glow bulb when the battery runs low.
var _goal := Vector2.ZERO
var _bulb: GlowBulb


static func requested() -> bool:
	return OS.get_cmdline_user_args().has("--autopilot")


static func arg(name: String, default: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.split("=", true, 1)[1]
	return default


func _ready() -> void:
	shots_dir = arg("shots", "")
	time_limit = float(arg("time", "60"))
	shot_interval = float(arg("interval", "4"))
	show_stops = OS.get_cmdline_user_args().has("--stops")
	force_event = StringName(arg("event", ""))
	_force_exit_at = float(arg("force-exit", "-1"))
	ping_interval = float(arg("ping", "12"))
	var zone := int(arg("zone", "-1"))
	if zone >= 0 and Game.run:
		Game.run.zone = zone
	var run_seed := int(arg("seed", "-1"))
	if run_seed >= 0 and Game.run:
		Game.run.run_seed = run_seed
	var frame := StringName(arg("frame", ""))
	if Catalog.frame(frame) and Game.run:
		Game.run.frame_id = frame
		Game.run.rebuild_stats(Game.meta.upgrades)
		Game.run.refill()
	process_mode = Node.PROCESS_MODE_ALWAYS
	Events.terrain_changed.connect(func(rect: Rect2) -> void:
		if sub:
			print("AUTOPILOT: rock moved at %.1f s, %.0f m from the sub, zone %d" % [_elapsed,
				rect.get_center().distance_to(sub.pos), Game.run.zone if Game.run else -1]))


func bind(p_sub: Submarine, p_level: Level) -> void:
	if sub != null:
		_zones_cleared += 1
	sub = p_sub
	level = p_level
	sub.input_enabled = false
	_guardian_seen = false
	_path_index = 0
	_last_pos = sub.pos
	_goal = level.layout.exit
	_bulb = null
	_route = _plan_route(sub.pos)
	_glass = null
	for e in level.entities:
		if e is SingingGlass:
			_glass = e


func drive(delta: float) -> void:
	if sub == null or not sub.alive:
		return
	if level.boss and level.boss.active:
		_fight_boss()
		return
	var guardian: Guardian = level.guardian if is_instance_valid(level.guardian) else null
	if guardian and guardian.active:
		if not _guardian_seen:
			_guardian_seen = true
			print("AUTOPILOT: %s woke at %.1f s, hull %.0f" % [guardian.title, _elapsed, sub.run.hull])
		if guardian is BlindMother:
			_fight_mother(guardian as BlindMother, delta)
		elif guardian is Ironclad:
			_fight_ironclad(guardian as Ironclad, delta)
		else:
			_fight_lamplighter(guardian as Lamplighter, delta)
		return
	if _ran_dark:
		_ran_dark = false
		sub.lamp_on = true
	_seek_power()
	# The lamp is life support's biggest draw: kept off once charge runs low.
	sub.lamp_on = sub.run.battery > sub.stats.max_battery * 0.3
	var move := _route_move()
	var threat := _nearest_threat()
	if threat:
		sub.aim = (threat.pos - sub.pos).normalized()
		if sub.harpoon.state == Harpoon.State.IDLE and sub.pos.distance_to(threat.pos) < sub.stats.harpoon_range:
			sub.harpoon.throw(sub.aim)
	else:
		sub.aim = sub.aim.slerp(move, 0.1).normalized()
	sub.facing = 1.0 if sub.aim.x >= 0.0 else -1.0
	sub.external_move = move
	_use_tools(threat, move, delta)

	_ping_timer -= delta
	if _ping_timer <= 0.0 and sub.run.battery > sub.stats.sonar_cost + sub.stats.max_battery * 0.3:
		_ping_timer = ping_interval
		sub.try_ping()
	_ring_glass()

	# Unstick: if we have not moved for a while, plan again from here.
	_stuck_timer += delta
	if _stuck_timer > 3.0:
		if sub.pos.distance_to(_last_pos) < 3.0:
			_route = _plan_route(sub.pos)
			_path_index = _nearest_index(_route, sub.pos)
		_stuck_timer = 0.0
		_last_pos = sub.pos


## Passing the singing glass, it pings as fast as the sonar allows to ring it open.
func _ring_glass() -> void:
	if _glass and _glass.shattered:
		print("AUTOPILOT: the singing glass shattered at %.1f s" % _elapsed)
		_glass = null
	if _glass == null or sub.pos.distance_to(_glass.pos) > 30.0:
		return
	if sub.try_ping():
		print("AUTOPILOT: pinged the singing glass at %.1f s (%d ringing)" % [_elapsed, _glass.rings])


## The way on along the route to the exit, steering clear of rock.
func _route_move() -> Vector2:
	var path := _route
	# Advance along the path once we are close to the current waypoint.
	while _path_index < path.size() - 1 and sub.pos.distance_to(path[_path_index]) < 4.0:
		_path_index += 1
	var ahead := mini(_path_index + 1, path.size() - 1)
	# Never steer into the rock: round a sharp corner the next waypoint can be
	# out of sight, so fall back to the nearest one that is not.
	while ahead > _path_index and not level.field.line_of_sight(sub.pos, path[ahead], Submarine.RADIUS * 0.9):
		ahead -= 1
	var target := path[ahead]
	if _path_index >= path.size() - 2:
		target = _goal
	var move := (target - sub.pos).normalized()
	# Pressed against a wall, push off it rather than grinding into it.
	if level.field.sample(sub.pos) < Submarine.RADIUS + 0.25:
		move = (move + level.field.normal(sub.pos) * 0.8).normalized()
	return move


## Index of the waypoint closest to [param p] (a fresh route starts there;
## the zone's main path, the fallback, is picked up where the sub already is).
static func _nearest_index(route: PackedVector2Array, p: Vector2) -> int:
	var best := 0
	for i in route.size():
		if route[i].distance_squared_to(p) < route[best].distance_squared_to(p):
			best = i
	return best


## Running low on charge, it detours to the nearest ripe glow bulb, then
## carries on to the exit.
func _seek_power() -> void:
	if _bulb and (not is_instance_valid(_bulb) or not _bulb.is_ripe()):
		_bulb = null
		_goal = level.layout.exit
		_route = _plan_route(sub.pos)
		_path_index = _nearest_index(_route, sub.pos)
	if _bulb or sub.run.battery > sub.stats.max_battery * 0.35:
		return
	var best: GlowBulb = null
	for e in level.entities:
		var g := e as GlowBulb
		if g and g.is_ripe() and g.pos.distance_to(sub.pos) < 50.0 \
				and (best == null or g.pos.distance_to(sub.pos) < best.pos.distance_to(sub.pos)):
			best = g
	if best == null:
		return
	_goal = best.pos + best.normal * 1.2
	var route := _plan_route(sub.pos)
	if route.is_empty() or route == level.layout.main_path:
		_goal = level.layout.exit
		return
	_bulb = best
	_route = route
	_path_index = 0


## The roomiest route from [param from] to the exit: the shortest path keeps
## only just enough clearance, so it can hug a wall round a sharp corner.
func _plan_route(from: Vector2) -> PackedVector2Array:
	for clearance: float in [2.2, 1.7, 1.3]:
		var route := level.layout.find_path(from, _goal, clearance)
		if not route.is_empty():
			return route
	return level.layout.main_path


## Holds position near an organ, answers every wave and strikes open organs.
func _fight_boss() -> void:
	var boss := level.boss
	if boss.part != _choir_part:
		_choir_part = boss.part
		print("AUTOPILOT: the Choir's song reached part %d at %.1f s, hull %.0f" % [boss.part, _elapsed, sub.run.hull])
	var eta := boss.next_arrival(sub.pos, sub)
	if eta < 0.12:
		sub.try_ping()
	# The nearest organ in sight whose standoff point (9 m off it) the hull can
	# swim to in a straight line; with none, follow the route on into the open
	# arena (heading straight across rock wedges the sub for the whole fight).
	if boss.part != ChoirBoss.Part.CALL:
		_fight_heart(boss)
		return
	var organ: ChoirOrgan = null
	for o in boss.organs:
		var standoff := o.pos - (o.pos - sub.pos).normalized() * 9.0
		if level.field.line_of_sight(sub.pos, o.pos) \
				and level.field.line_of_sight(sub.pos, standoff, Submarine.RADIUS * 0.9) \
				and (organ == null or o.pos.distance_to(sub.pos) < organ.pos.distance_to(sub.pos)):
			organ = o
	if organ == null:
		sub.external_move = _route_move() if not boss.organs.is_empty() else Vector2.ZERO
	else:
		var to := organ.pos - sub.pos
		sub.external_move = (organ.pos - to.normalized() * 9.0 - sub.pos).limit_length(1.0)
		sub.aim = to.normalized()
	# Strike whatever the song summoned once it closes in, else the organs while they are open.
	if not _strike_close_threat() and organ and boss.vulnerable > 0.3:
		sub.aim = (organ.pos - sub.pos).normalized()
		if sub.harpoon.state == Harpoon.State.IDLE and sub.pos.distance_to(organ.pos) < sub.stats.harpoon_range:
			sub.harpoon.throw(sub.aim)
	sub.facing = 1.0 if sub.aim.x >= 0.0 else -1.0


## The Reach and the Duet: keep off the heart (and out of a rising
## tentacle's arc), answering, and harpoon the heart whenever its throat opens.
func _fight_heart(boss: ChoirBoss) -> void:
	var to := boss.pos - sub.pos
	var standoff := boss.pos - to.normalized() * 15.0
	sub.external_move = (standoff - sub.pos).limit_length(1.0)
	var line := boss.slam_line()
	if not is_nan(line):
		# Off the line a tentacle is about to slam down along.
		var across := Vector2.from_angle(line).orthogonal()
		var side := signf(across.dot(sub.pos - boss.pos))
		sub.external_move = across * (side if side != 0.0 else 1.0)
	sub.aim = to.normalized()
	if not _strike_close_threat() and boss.part == ChoirBoss.Part.REACH and boss.vulnerable > 0.3:
		if sub.harpoon.state == Harpoon.State.IDLE and to.length() < sub.stats.harpoon_range + boss.heart.radius:
			sub.harpoon.throw(sub.aim)
	sub.facing = 1.0 if sub.aim.x >= 0.0 else -1.0


## Against the Blind Mother: hold station near the lair floor and ping to draw
## a lunge, sidestep the charge, then harpoon her while she is stuck.
func _fight_mother(mother: BlindMother, delta: float) -> void:
	var to := mother.pos - sub.pos
	sub.aim = to.normalized()
	sub.facing = 1.0 if sub.aim.x >= 0.0 else -1.0
	match mother.state:
		BlindMother.State.AIM, BlindMother.State.LUNGE:
			# Dodge across the line of the charge.
			sub.external_move = Vector2(-to.y, to.x).normalized()
		BlindMother.State.STUCK:
			sub.external_move = (to - to.normalized() * 7.0).limit_length(1.0)
			# Every second of her gills open counts: call the harpoon back from anything else.
			if sub.harpoon.state == Harpoon.State.ATTACHED and sub.harpoon.target != mother:
				sub.harpoon.release()
			if sub.harpoon.state == Harpoon.State.IDLE and to.length() < sub.stats.harpoon_range:
				sub.harpoon.throw(sub.aim)
		_:
			var threat := _nearest_threat()
			if threat and threat != mother:
				sub.aim = (threat.pos - sub.pos).normalized()
				if sub.harpoon.state == Harpoon.State.IDLE and sub.pos.distance_to(threat.pos) < sub.stats.harpoon_range:
					sub.harpoon.throw(sub.aim)
			var station := mother.lair_center + Vector2(0.0, -mother.lair_radius.y * 0.55)
			sub.external_move = (station - sub.pos).limit_length(1.0) * 0.6
			_ping_timer -= delta
			# While she is wary of the rock a lunge would only glance off it: keep quiet.
			if _ping_timer <= 0.0 and mother.stun_guard <= 0.0:
				_ping_timer = 3.0
				sub.try_ping()


## Against the Ironclad: hang high over the lair vent nearest it, out of
## the column and its reach, pinging so it walks over and stands listening
## beneath; when the vent blows and cracks its shell, harpoon it from above.
func _fight_ironclad(boss: Ironclad, delta: float) -> void:
	var to := boss.pos - sub.pos
	sub.aim = to.normalized()
	sub.facing = 1.0 if sub.aim.x >= 0.0 else -1.0
	var vent: ThermalVent = null
	for e in level.entities:
		var v := e as ThermalVent
		if v and v.in_lair and (vent == null or v.pos.distance_to(boss.pos) < vent.pos.distance_to(boss.pos)):
			vent = v
	var station := boss.pos + Vector2(0.0, Ironclad.SLAM_RANGE + 5.0)
	if vent:
		# Straight above the vent's mouth: the ping draws it there, and a
		# tilted column leans away from the perch.
		station = level.field.resolve_circle(vent.pos + Vector2(0.0, ThermalVent.HEIGHT + 3.0), 2.0)
		_ping_timer -= delta
		if _ping_timer <= 0.0 and boss.exposed <= 0.0:
			_ping_timer = 4.5
			sub.try_ping()
	# Running flat: dash down for a glow bulb the Ironclad is not standing on.
	if sub.run.battery < 22.0 and boss.exposed <= 0.0:
		var bulb: GlowBulb = null
		for e in level.entities:
			var g := e as GlowBulb
			if g and g.is_ripe() and boss.in_lair(g.pos, 1.6) and g.pos.distance_to(boss.pos) > 15.0 \
					and (bulb == null or g.pos.distance_to(sub.pos) < bulb.pos.distance_to(sub.pos)):
				bulb = g
		if bulb:
			station = bulb.pos
	var striking := boss.state == Ironclad.State.REAR or boss.state == Ironclad.State.SLAM
	if striking and to.length() < Ironclad.SLAM_RANGE + 4.0:
		station = sub.pos - to.normalized() * 8.0
	# Out of any column that is blowing (or about to).
	for e in level.entities:
		var v := e as ThermalVent
		if v and v.state != ThermalVent.State.DORMANT and v.column_strength(sub.pos, Submarine.RADIUS + 1.5) > 0.0:
			station = sub.pos + v.normal.orthogonal() * signf((sub.pos - v.pos).dot(v.normal.orthogonal()) + 0.01) * 6.0
	sub.external_move = (station - sub.pos).limit_length(1.0)
	# Out of the way of scalding globs on their way in - unless that is into a column.
	for e in level.entities:
		var glob := e as ScaldGlob
		if glob and glob.pos.distance_to(sub.pos) < 9.0 and glob.vel.dot(sub.pos - glob.pos) > 0.0:
			var across := glob.vel.normalized().orthogonal()
			var dodge := across * signf(across.dot(sub.pos - glob.pos) + 0.01)
			if not _in_any_column(sub.pos + dodge * 3.0):
				sub.external_move = dodge
			break
	if boss.exposed > 0.3 and sub.harpoon.state == Harpoon.State.IDLE and to.length() < sub.stats.harpoon_range:
		sub.harpoon.throw(sub.aim)
	elif boss.exposed <= 0.0:
		_strike_close_threat()


func _in_any_column(p: Vector2) -> bool:
	for e in level.entities:
		var v := e as ThermalVent
		if v and v.state != ThermalVent.State.DORMANT and v.column_strength(p, Submarine.RADIUS + 1.5) > 0.0:
			return true
	return false


## Against the Lamplighter: run dark and ping to break the lure's pull, keep
## clear of the lure, then light her eyes up close (or feed her a flare) and
## harpoon her while she is dazzled.
func _fight_lamplighter(angler: Lamplighter, delta: float) -> void:
	_ran_dark = true
	var head := angler.head_pos()
	var to := head - sub.pos
	var d := to.length()
	sub.aim = to.normalized()
	sub.facing = 1.0 if sub.aim.x >= 0.0 else -1.0
	_ping_timer -= delta
	# On emergency power the charge goes to the lamp, which is what dazzles her.
	if _ping_timer <= 0.0 and sub.run.battery > sub.stats.sonar_cost + sub.stats.max_battery * 0.12:
		_ping_timer = 3.0
		sub.try_ping()
	var away_from_lure := (sub.pos - angler.lure_pos()).normalized()
	match angler.state:
		Lamplighter.State.WINDUP, Lamplighter.State.CHARGE:
			sub.lamp_on = false
			sub.external_move = Vector2(-to.y, to.x).normalized()
		Lamplighter.State.DAZZLED:
			sub.lamp_on = false
			sub.external_move = (to - to.normalized() * 8.0).limit_length(1.0) * 0.6
			if sub.harpoon.state == Harpoon.State.IDLE and d < sub.stats.harpoon_range:
				sub.harpoon.throw(sub.aim)
		Lamplighter.State.LURK:
			# Lure dark: keep moving away and ping to see where she is.
			sub.lamp_on = false
			sub.external_move = (-to.normalized()).rotated(0.6)
			if sub.sonar_cooldown <= 0.0 and sub.run.battery > sub.stats.sonar_cost + 10.0:
				sub.try_ping()
		Lamplighter.State.STALK when angler.stun_guard > 0.0:
			# Eyes shut to light: hang back in the dark until she opens them.
			sub.lamp_on = false
			var hold := (to - to.normalized() * 18.0).limit_length(1.0)
			if sub.pos.distance_to(angler.lure_pos()) < Lamplighter.SNAP_REACH + 4.0:
				hold = away_from_lure
			sub.external_move = hold * 0.7
			_strike_close_threat()
		Lamplighter.State.STALK:
			if sub.tools.current() == &"flare" and sub.run.flares > 0 and d < 20.0:
				_tool_timer -= delta
				if _tool_timer <= 0.0:
					_tool_timer = 6.0
					sub.tools.use(sub.aim)
			# Close in to dazzling range, never onto the lure itself.
			var want := (to - to.normalized() * 10.0).limit_length(1.0)
			if sub.pos.distance_to(angler.lure_pos()) < Lamplighter.SNAP_REACH + 2.5:
				want = away_from_lure
			sub.external_move = want * 0.8
			sub.lamp_on = d < Lamplighter.DAZZLE_RANGE - 2.0
			_strike_close_threat()
		_:
			sub.lamp_on = false
			sub.external_move = away_from_lure * 0.7
			_strike_close_threat()


## Every few seconds near a threat, uses the current tool and cycles to the
## next: weapons at the threat, lures (flares, decoys) back along the route.
func _use_tools(threat: Creature, move: Vector2, delta: float) -> void:
	_tool_timer -= delta
	if threat == null or _tool_timer > 0.0:
		return
	_tool_timer = 8.0
	var tool := sub.tools.current()
	sub.tools.use(sub.aim if tool == &"torpedo" or tool == &"shock" else -move)
	sub.tools.cycle()


## Harpoons the nearest ordinary hunter within [param reach] (never a guardian
## or an organ), turning to face it. False if nothing is that close.
func _strike_close_threat(reach := 9.0) -> bool:
	var threat := _nearest_threat(true)
	if threat == null or threat.pos.distance_to(sub.pos) > reach:
		return false
	sub.aim = (threat.pos - sub.pos).normalized()
	sub.facing = 1.0 if sub.aim.x >= 0.0 else -1.0
	if sub.harpoon.state == Harpoon.State.IDLE:
		sub.harpoon.throw(sub.aim)
	return true


## The nearest hostile creature in sight; with [param minor_only], leaving out
## guardians and the Choir's organs.
func _nearest_threat(minor_only := false) -> Creature:
	var best: Creature = null
	var best_d := 14.0
	for e in level.targets_in_radius(sub.pos, 14.0):
		var c := e as Creature
		# Leave the entranced audience over the station alone, as a careful pilot would.
		if c and c.is_hostile() and not c.entranced and not (minor_only and (c is Guardian or c is ChoirOrgan)):
			var d := c.pos.distance_to(sub.pos)
			if d < best_d and level.field.line_of_sight(sub.pos, c.pos):
				best = c
				best_d = d
	return best


func _process(delta: float) -> void:
	# The clock starts once the first zone has loaded, so loading time (long in
	# frames when running headless at a fixed frame rate) never eats the budget.
	if sub == null:
		return
	_elapsed += delta
	_frames += 1
	_frame_ms_sum += delta * 1000.0
	if _elapsed > 2.0:
		_max_frame_ms = maxf(_max_frame_ms, delta * 1000.0)
	_max_draw_calls = maxi(_max_draw_calls,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	_max_primitives = maxi(_max_primitives,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	if shots_dir != "":
		_shot_timer -= delta
		if _shot_timer <= 0.0:
			_shot_timer = shot_interval
			var img := get_viewport().get_texture().get_image()
			img.save_png(shots_dir.path_join("shot_%03d.png" % _shots))
			_shots += 1
	if _force_exit_at > 0.0 and _elapsed >= _force_exit_at and level:
		_force_exit_at = -1.0
		level.exit_reached.emit()
	if _elapsed >= time_limit and not _reported:
		_reported = true
		_report_and_quit()


func _report_and_quit() -> void:
	var run := Game.run
	print("AUTOPILOT: time=%.1f zone=%d zones_cleared=%d hull=%.0f battery=%.0f salvage=%d kills=%d fps=%d seed=%d" % [
		_elapsed, run.zone if run else -1, _zones_cleared, run.hull if run else 0.0, run.battery if run else 0.0,
		run.salvage if run else 0, run.kills if run else 0, Engine.get_frames_per_second(), run.run_seed if run else 0])
	print("RENDER: max_draw_calls=%d max_primitives=%d avg_frame=%.1fms worst_frame=%.1fms entities=%d" % [
		_max_draw_calls, _max_primitives, _frame_ms_sum / maxi(_frames, 1), _max_frame_ms,
		level.entities.size() if level else 0])
	Router.quit()
