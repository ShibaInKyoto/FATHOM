class_name HudOverlay
extends Control
## Screen-space drawing tied to world positions: the aiming reticle with the
## sonar cooldown ring, the noise radius, the scan reticle, sonar blips and
## the compass pointing at the descent.

var hud: Hud


func _draw() -> void:
	if hud == null or hud.sub == null or hud.camera == null:
		return
	var sub := hud.sub
	var cam := hud.camera
	if not sub.alive:
		return
	var sub_screen := cam.unproject_position(Vector3(sub.pos.x, sub.pos.y, 0))

	# Noise radius: how far creatures can hear you right now.
	if sub.noise_radius > 5.0:
		var edge := cam.unproject_position(Vector3(sub.pos.x + sub.noise_radius, sub.pos.y, 0))
		var r := edge.x - sub_screen.x
		var a := clampf((sub.noise_radius - 5.0) / 60.0, 0.03, 0.16)
		draw_arc(sub_screen, r, 0.0, TAU, 96, Color(1.0, 0.9, 0.7, a), 2.0, true)

	# Reticle: mouse cursor, or a point along the aim for gamepads.
	var reticle: Vector2
	if Settings.using_gamepad:
		var p := sub.pos + sub.aim * Submarine.RETICLE_REACH
		reticle = cam.unproject_position(Vector3(p.x, p.y, 0))
	else:
		reticle = get_local_mouse_position()
	var col := UiTheme.ACCENT
	draw_arc(reticle, 14.0, 0.0, TAU, 32, Color(col, 0.8), 2.0, true)
	draw_circle(reticle, 2.5, col)
	var cd_frac := 1.0 - sub.sonar_cooldown / maxf(sub.stats.sonar_cooldown, 0.01)
	if cd_frac < 1.0:
		draw_arc(reticle, 21.0, -PI * 0.5, -PI * 0.5 + TAU * cd_frac, 40, Color(col, 0.5), 3.0, true)
	else:
		draw_arc(reticle, 21.0, 0.0, TAU, 40, Color(col, 0.18), 1.5, true)

	# The Choir's approaching song wave: a ring closing in on the submarine.
	# Ping when it meets the inner circle.
	var boss := hud.level.boss
	if boss and boss.active:
		var eta := boss.next_arrival(sub.pos)
		if eta < 1.4:
			var k := clampf(eta / 1.4, 0.0, 1.0)
			var good := absf(eta) < 0.25
			var ring_col := UiTheme.GOOD if good else Color(1.0, 0.4, 0.9)
			draw_arc(sub_screen, 34.0, 0.0, TAU, 48, Color(ring_col, 0.9), 3.0, true)
			draw_arc(sub_screen, 34.0 + k * 170.0, 0.0, TAU, 64, Color(1.0, 0.4, 0.9, 0.35 + (1.0 - k) * 0.6), 4.0, true)
			if good:
				_label(sub_screen + Vector2(0, -58), "PING!", UiTheme.GOOD)

	# Scan reticle.
	if sub.scan_target and is_instance_valid(sub.scan_target):
		var t := sub.scan_target
		var c := cam.unproject_position(Vector3(t.pos.x, t.pos.y, 0))
		var edge2 := cam.unproject_position(Vector3(t.pos.x + t.radius + 1.0, t.pos.y, 0))
		var r2 := maxf(edge2.x - c.x, 28.0)
		draw_arc(c, r2, 0.0, TAU, 48, Color(UiTheme.GOOD, 0.25), 2.0, true)
		draw_arc(c, r2, -PI * 0.5, -PI * 0.5 + TAU * sub.scan_progress, 48, UiTheme.GOOD, 4.0, true)
		var font := get_theme_default_font()
		draw_string(font, c + Vector2(-60, -r2 - 12), "SCANNING", HORIZONTAL_ALIGNMENT_CENTER, 120, 16, UiTheme.GOOD)

	# Sonar marks on creatures (visible through darkness).
	for e in hud.level.entities:
		var cr := e as Creature
		if cr == null or not cr.alive or not cr.is_marked():
			continue
		var sp := cam.unproject_position(Vector3(cr.pos.x, cr.pos.y, 0))
		var fade := clampf(cr.mark_fraction(), 0.0, 1.0)
		var danger := cr.is_hostile()
		var mc := UiTheme.DANGER if danger else UiTheme.ACCENT
		draw_arc(sp, 10.0 + cr.radius * 4.0, 0.0, TAU, 20, Color(mc, 0.6 * fade), 2.0, true)

	# "!" over creatures that just noticed the submarine.
	var font := get_theme_default_font()
	for e in hud.level.entities:
		var cr := e as Creature
		if cr == null or not cr.alive or cr.alert_fraction() <= 0.0:
			continue
		var top := cam.unproject_position(Vector3(cr.pos.x, cr.pos.y + cr.radius + 1.2, 0))
		var pop := 1.0 + maxf(cr.alert_fraction() - 0.8, 0.0) * 2.5
		draw_string_outline(font, top + Vector2(-8, 0), "!", HORIZONTAL_ALIGNMENT_CENTER, 16, int(34 * pop), 6,
				Color(0, 0, 0, 0.8))
		draw_string(font, top + Vector2(-8, 0), "!", HORIZONTAL_ALIGNMENT_CENTER, 16, int(34 * pop),
				Color(UiTheme.DANGER, clampf(cr.alert_fraction() * 2.0, 0.0, 1.0)))

	# Descent compass.
	var exit := hud.level.layout.exit
	if hud.level.exit_known or sub.stats.always_compass:
		var exit_screen := cam.unproject_position(Vector3(exit.x, exit.y, 0))
		var rect := get_viewport_rect().grow(-60)
		var dist := sub.pos.distance_to(exit)
		if rect.has_point(exit_screen):
			draw_arc(exit_screen, 26.0, 0.0, TAU, 32, Color(UiTheme.GOOD, 0.8), 2.5, true)
			_label(exit_screen + Vector2(0, -40), "DESCENT", UiTheme.GOOD)
		else:
			var dir := (exit_screen - rect.get_center()).normalized()
			if hud.level.event == &"magnetic":
				# The rock's iron drags the needle about.
				var t := hud.level.time
				dir = dir.rotated(sin(t * 0.6) * 0.55 + sin(t * 1.7 + 1.0) * 0.25)
			var edge_p := _clip_to_rect(rect, rect.get_center(), dir)
			_arrow(edge_p, dir, UiTheme.GOOD)
			_label(edge_p - dir * 46.0, "%d m" % int(dist), UiTheme.GOOD)


func _label(at: Vector2, text: String, color: Color) -> void:
	var font := get_theme_default_font()
	draw_string(font, at + Vector2(-80, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 160, 16, color)


func _arrow(at: Vector2, dir: Vector2, color: Color) -> void:
	var side := dir.orthogonal()
	var pts := PackedVector2Array([at + dir * 18.0, at - dir * 10.0 + side * 12.0, at - dir * 4.0,
			at - dir * 10.0 - side * 12.0])
	draw_colored_polygon(pts, Color(color, 0.85))


static func _clip_to_rect(rect: Rect2, from: Vector2, dir: Vector2) -> Vector2:
	var t := INF
	if absf(dir.x) > 0.0001:
		t = minf(t, ((rect.end.x if dir.x > 0 else rect.position.x) - from.x) / dir.x)
	if absf(dir.y) > 0.0001:
		t = minf(t, ((rect.end.y if dir.y > 0 else rect.position.y) - from.y) / dir.y)
	return from + dir * t
