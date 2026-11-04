class_name RunSummary
extends CanvasLayer
## End-of-dive report. Banks the run through [method Game.end_run] and offers
## a way back to the hangar or straight into another dive.


func show_result(run: RunState, outcome: RunState.Outcome) -> void:
	layer = 45
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var run_salvage := run.salvage
	var banked := Game.end_run(outcome)
	var column := UiUtil.modal(self, 0.85, 900)
	var title := ""
	var subtitle := ""
	var color := UiTheme.TEXT
	match outcome:
		RunState.Outcome.IMPLODED:
			title = "SIGNAL LOST"
			if run.lost_power():
				title = "POWER LOST"
				subtitle = "The %s's cells ran dry at %d m. It sank dark, but whole." % [
					Catalog.frame(run.frame_id).name, run.deepest_depth]
			elif run.hull > 0.0:
				subtitle = "You abandoned the dive at %d m." % run.deepest_depth
			else:
				subtitle = "The %s imploded at %d m, sunk by %s." % [Catalog.frame(run.frame_id).name,
					run.deepest_depth, DeathTips.describe(run.last_hit_by)]
			color = UiTheme.DANGER
			Audio.play_music(&"loss", 1.0)
		RunState.Outcome.SURFACED:
			title = "SURFACED"
			subtitle = "You made it back up from %d m." % run.deepest_depth
			color = UiTheme.GOOD
		RunState.Outcome.VICTORY:
			title = "THE CHOIR IS SILENT"
			subtitle = "You reached the bottom of the world."
			color = UiTheme.ACCENT
	column.add_child(UiUtil.label(title, &"TitleLabel", 72, color))
	column.add_child(UiUtil.label(subtitle, &"HeaderLabel"))
	_add_score(column, run)
	var panel := PanelContainer.new()
	column.add_child(panel)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 60)
	grid.add_theme_constant_override(&"v_separation", 8)
	panel.add_child(grid)
	var rows: Array = [
		["Deepest point", "%d m" % run.deepest_depth],
		["Zones cleared", "%d" % (run.zone - run.start_zone)],
		["Dive time", UiUtil.format_time(run.time)],
		["Creatures defeated", "%d" % run.kills],
		["Species scanned", "%d" % run.scans],
		["Signal logs", "%d" % run.logs],
		["Salvage recovered", "%d" % run_salvage],
		["Expedition pay", "%d" % Game.expedition_pay(run)],
		["Salvage banked", "%d" % banked],
		["Research gained", "%d" % run.research],
	]
	for r: Array in rows:
		grid.add_child(UiUtil.label(r[0], &"DimLabel", 22))
		grid.add_child(UiUtil.label(r[1], &"MonoLabel", 24))
	var terms := Contracts.find(run.contract)
	if terms:
		column.add_child(UiUtil.label("Contract: %s  (%s)" % [terms.name, terms.rewards()], &"", 20, UiTheme.WARN))
	if run.daily:
		column.add_child(UiUtil.label("Daily dive %s  -  %s" % [Game.meta.daily_date,
				Game.meta.daily_summary(Game.meta.daily_date)], &"", 22, UiTheme.ACCENT))
	if not run.wonders.is_empty():
		var names: Array[String] = []
		for id in run.wonders:
			names.append(Wonders.get_wonder(id).get("name", id))
		column.add_child(UiUtil.label("Wonders witnessed: %s" % ", ".join(names), &"", 22, UiTheme.GOOD))
	for id in run.challenges_won:
		var c := Challenges.find(id)
		column.add_child(UiUtil.label("Challenge complete: %s  -  %s waiting in the hangar" % [c.name,
				Challenges.reward_text(c)], &"", 22, UiTheme.WARN))
	if outcome == RunState.Outcome.IMPLODED:
		var insured := "Insurance recovered %d%% of your salvage." % int(run.stats.insurance * 100)
		if run.stats.insurance <= 0.0:
			insured = "Uninsured: none of the salvage aboard was banked (research was transmitted as you went)."
		column.add_child(UiUtil.label(insured, &"DimLabel"))
		var sank := run.hull <= 0.0 or run.lost_power()
		if sank and Game.meta.has_wreck() and Game.meta.wreck_zone == run.zone:
			var how := "all of it still aboard" if run.lost_power() else "what the implosion did not scatter"
			column.add_child(UiUtil.label("The %s went down with %d salvage in its wreck in zone %d, %s. " %
					[Catalog.frame(run.frame_id).name, Game.meta.wreck_cargo, run.zone + 1, how] +
					"Recover it on your next dive.", &"", 20, UiTheme.WARN))
		if sank:
			var tip := UiUtil.label("TIP  " + DeathTips.tip(run.last_hit_by), &"", 20, UiTheme.ACCENT)
			tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			column.add_child(tip)
			# Several early losses in a row: point at the gentler way to play.
			if Game.meta.dives >= 3 and Game.meta.deepest_zone < 4 and not Settings.assist:
				column.add_child(UiUtil.label("Finding it rough? Assist mode in Settings softens damage and timing.",
						&"DimLabel"))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 20)
	column.add_child(row)
	var hangar := UiUtil.button("Return to hangar", func() -> void: Router.go_to(Router.HANGAR), 320)
	row.add_child(hangar)
	row.add_child(UiUtil.button("Dive again", func() -> void:
		Game.start_run()
		Router.go_to(Router.DIVE), 260))
	hangar.grab_focus()
	if Autopilot.requested():
		print("AUTOPILOT: run over outcome=%s zone=%d time=%.1f kills=%d banked=%d cause=%s score=%d" % [
			RunState.Outcome.keys()[outcome], run.zone, run.time, run.kills, banked, run.last_hit_by, Game.last_score])
		get_tree().create_timer(1.0).timeout.connect(Router.quit)


## B (or Esc) goes back to the hangar, like the default button.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		Router.go_to(Router.HANGAR)


## The dive's score, counting up, with how it was earned and where it places.
func _add_score(column: VBoxContainer, run: RunState) -> void:
	var score := UiUtil.label("SCORE  0", &"MonoLabel", 44, UiTheme.ACCENT)
	column.add_child(score)
	var total := Game.last_score
	var count := func(v: float) -> void: score.text = "SCORE  %s" % UiUtil.thousands(int(v))
	create_tween().tween_method(count, 0.0, float(total), clampf(total / 4000.0, 0.4, 1.6)) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	var how := UiUtil.label(DiveScore.describe(run), &"DimLabel", 17)
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(how)
	var place := ""
	if Game.last_rank == 0:
		place = "NEW PERSONAL BEST" if Game.meta.records.size() > 1 else "Your first entry in the records"
	elif Game.last_rank > 0:
		place = "#%d in your records" % (Game.last_rank + 1)
	if place != "":
		column.add_child(UiUtil.label(place, &"HeaderLabel", 26, UiTheme.WARN))
		if Game.last_rank == 0 and Game.meta.records.size() > 1:
			Audio.play_ui(&"purchase")
