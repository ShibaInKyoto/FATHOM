extends Node3D
## The hangar: spend salvage on upgrades, research on new frames, browse the
## codex and recovered logs, pick a pressure level and a contract, and start a dive.

enum Tab { UPGRADES, RESEARCH, FRAMES, CODEX, LOGS, CHALLENGES }

var _backdrop: MenuBackdrop
var _content: VBoxContainer
var _currency: Label
var _tab := Tab.UPGRADES
var _tab_buttons: Array[Button] = []
var _pressure_label: Label
var _contract_button: Button
var _contract_desc: Label
var _scroll: ScrollContainer


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_backdrop = MenuBackdrop.new()
	_backdrop.view_shift = -8.75
	add_child(_backdrop)
	Audio.play_music(&"title")
	add_child(PostFx.new())
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var ui := Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.theme = UiTheme.get_theme()
	layer.add_child(ui)

	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.color = Color(0.0, 0.02, 0.04, 0.45)
	ui.add_child(shade)

	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 60
	root.offset_top = 40
	root.offset_right = -60
	root.offset_bottom = -40
	ui.add_child(root)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(1040, 0)
	left.add_theme_constant_override(&"separation", 12)
	root.add_child(left)

	var header := HBoxContainer.new()
	left.add_child(header)
	header.add_child(UiUtil.label("HANGAR", &"TitleLabel", 60))
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(fill)
	_currency = UiUtil.label("", &"HeaderLabel")
	_currency.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_currency)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override(&"separation", 8)
	left.add_child(tabs)
	var tab_names := [[Tab.UPGRADES, "Upgrades"], [Tab.RESEARCH, "Research"], [Tab.FRAMES, "Submarines"],
		[Tab.CODEX, "Codex"], [Tab.LOGS, "Archive"], [Tab.CHALLENGES, "Challenges"]]
	for t: Array in tab_names:
		var tab_id: Tab = t[0]
		var b := UiUtil.button(t[1], func() -> void: _show_tab(tab_id), 166)
		b.toggle_mode = true
		tabs.add_child(b)
		_tab_buttons.append(b)

	var scroll := ScrollContainer.new()
	_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Gamepad and keyboard focus moving down the list scrolls it into view.
	scroll.follow_focus = true
	left.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override(&"separation", 10)
	scroll.add_child(_content)

	var contract_row := HBoxContainer.new()
	contract_row.add_theme_constant_override(&"separation", 14)
	left.add_child(contract_row)
	contract_row.add_child(UiUtil.label("CONTRACT", &"HeaderLabel", 22))
	_contract_button = UiUtil.button("", _cycle_contract, 250)
	contract_row.add_child(_contract_button)
	_contract_desc = UiUtil.label("", &"DimLabel", 17)
	_contract_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_contract_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_contract_desc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	contract_row.add_child(_contract_desc)
	_refresh_contract()

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override(&"separation", 14)
	left.add_child(footer)
	footer.add_child(UiUtil.button("Back", func() -> void: Router.go_to(Router.TITLE), 180))
	if Game.meta.pressure_unlocked > 0:
		footer.add_child(UiUtil.button("-", func() -> void: _change_pressure(-1), 60))
		_pressure_label = UiUtil.label("", &"MonoLabel")
		_pressure_label.custom_minimum_size = Vector2(300, 0)
		_pressure_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_pressure_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		footer.add_child(_pressure_label)
		footer.add_child(UiUtil.button("+", func() -> void: _change_pressure(1), 60))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var dive := UiUtil.button("Begin dive", func() -> void:
		Game.start_run()
		Router.go_to(Router.DIVE), 300)
	footer.add_child(dive)

	_show_tab(_initial_tab())
	dive.grab_focus()


## Debug: `-- --hangar --hangar-tab=1` opens on a given tab (for screenshots).
## The right stick scrolls the list, for the codex and archive (which have
## nothing on them to focus).
func _process(delta: float) -> void:
	var axis := 0.0
	for pad in Input.get_connected_joypads():
		var a := Input.get_joy_axis(pad, JOY_AXIS_RIGHT_Y)
		if absf(a) > absf(axis):
			axis = a
	if absf(axis) > 0.2 and _scroll:
		_scroll.scroll_vertical += int(axis * 900.0 * delta)


static func _initial_tab() -> Tab:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hangar-tab="):
			return clampi(int(a.get_slice("=", 1)), 0, Tab.size() - 1) as Tab
	return Tab.UPGRADES


func _refresh_header() -> void:
	_currency.text = "%d SALVAGE    %d RESEARCH" % [Game.meta.salvage, Game.meta.research]
	if _pressure_label:
		var p := Game.meta.pressure_selected
		_pressure_label.text = "PRESSURE %d" % p if p > 0 else "PRESSURE 0 (standard)"
		_pressure_label.tooltip_text = "\n".join(Pressure.DESCRIPTIONS.slice(1, p + 1))


## Steps through the biomes a dive can start in.
func _cycle_contract() -> void:
	var ids: Array[String] = [""]
	for c in Contracts.all():
		ids.append(String(c.id))
	var next := (ids.find(Game.meta.contract_selected) + 1) % ids.size()
	Game.meta.contract_selected = ids[next]
	Game.save_game()
	_refresh_contract()


func _refresh_contract() -> void:
	var terms := Contracts.find(StringName(Game.meta.contract_selected))
	if terms:
		_contract_button.text = terms.name
		_contract_desc.text = "%s  Reward: %s. Covers the next dive only." % [terms.description, terms.rewards()]
	else:
		_contract_button.text = "None"
		_contract_desc.text = "Optional: take on a handicap for the next dive in exchange for a bigger score and payout."


func _change_pressure(delta: int) -> void:
	Game.meta.pressure_selected = clampi(Game.meta.pressure_selected + delta, 0, Game.meta.pressure_unlocked)
	Game.save_game()
	_refresh_header()
	_show_tab(_tab)


func _show_tab(tab: Tab) -> void:
	_tab = tab
	# Drop any frame or creature preview from browsing the other tabs.
	_backdrop.preview_creature(&"")
	_backdrop.preview_frame(StringName(Game.meta.selected_frame))
	for i in _tab_buttons.size():
		_tab_buttons[i].button_pressed = i == tab
	UiUtil.clear(_content)
	match tab:
		Tab.UPGRADES:
			_build_upgrades()
		Tab.RESEARCH:
			_build_research()
		Tab.FRAMES:
			_build_frames()
		Tab.CODEX:
			_build_codex()
		Tab.LOGS:
			_build_logs()
		Tab.CHALLENGES:
			_build_challenges()
	_refresh_header()


func _row_panel() -> HBoxContainer:
	var panel := PanelContainer.new()
	_content.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 18)
	panel.add_child(row)
	return row


func _build_upgrades() -> void:
	if Game.meta.pressure_selected > 0:
		var notes := "Active pressure modifiers: " + ", ".join(Pressure.DESCRIPTIONS.slice(1,
				Game.meta.pressure_selected + 1))
		var l := UiUtil.label(notes, &"DimLabel", 18, UiTheme.WARN)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(l)
	for up in Catalog.upgrades():
		var row := _row_panel()
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		info.add_child(UiUtil.label(up.name, &"HeaderLabel", 26))
		info.add_child(UiUtil.label(up.description, &"DimLabel"))
		var level := Game.meta.upgrade_level(up.id)
		var pips := HBoxContainer.new()
		pips.add_theme_constant_override(&"separation", 5)
		pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for i in up.max_level():
			var pip := Panel.new()
			pip.custom_minimum_size = Vector2(22, 10)
			var style := StyleBoxFlat.new()
			style.set_corner_radius_all(2)
			style.bg_color = UiTheme.ACCENT if i < level else Color(0.3, 0.6, 0.7, 0.18)
			pip.add_theme_stylebox_override(&"panel", style)
			pips.add_child(pip)
		row.add_child(pips)
		var b: Button
		if not Research.upgrade_open(Game.meta, up.id):
			b = UiUtil.button("Research first", func() -> void: _show_tab(Tab.RESEARCH), 220)
			info.add_child(UiUtil.label("Needs the %s research project." % Research.project_for_upgrade(up.id).name,
				&"", 17, UiTheme.WARN))
		elif level >= up.max_level():
			b = UiUtil.button("Maxed", func() -> void: pass, 220)
			b.disabled = true
		else:
			var cost := up.costs[level]
			var id := up.id
			b = UiUtil.button("Upgrade  %d" % cost, func() -> void:
				if Game.meta.buy_upgrade(id):
					Audio.play_ui(&"purchase")
					Game.save_game()
				else:
					Audio.play_ui(&"denied")
				_show_tab(Tab.UPGRADES), 220)
			b.disabled = not Game.meta.can_afford(cost)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(b)


func _build_research() -> void:
	var meta := Game.meta
	var intro := UiUtil.label("Research comes from scanning creatures, recovering signal logs and witnessing " +
		"wonders. Projects add modules to what the relay lockers can offer and open new upgrade lines.",
		&"DimLabel", 18)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(intro)
	for p in Research.all():
		var row := _row_panel()
		var done := meta.projects.has(p.id)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		info.add_child(UiUtil.label(p.name, &"HeaderLabel", 26, UiTheme.ACCENT if done else UiTheme.TEXT))
		info.add_child(UiUtil.label(p.description, &"DimLabel"))
		var unlocks := UiUtil.label(Research.unlocks_text(p), &"MonoLabel", 17, UiTheme.GOOD if done else UiTheme.TEXT_DIM)
		unlocks.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(unlocks)
		var blocker := Research.blocker(meta, p)
		if not done and blocker != "":
			info.add_child(UiUtil.label(blocker + ".", &"", 17, UiTheme.WARN))
		var b: Button
		if done:
			b = UiUtil.button("Done", func() -> void: pass, 220)
			b.disabled = true
		else:
			var id := p.id
			b = UiUtil.button("Research  %d" % p.cost, func() -> void:
				if Game.meta.research_project(id):
					Audio.play_ui(&"purchase")
					Game.save_game()
				else:
					Audio.play_ui(&"denied")
				_show_tab(Tab.RESEARCH), 220)
			b.disabled = blocker != "" or meta.research < p.cost
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(b)


func _build_frames() -> void:
	for f in Catalog.frames():
		var row := _row_panel()
		var frame_id := f.id
		row.get_parent().mouse_entered.connect(func() -> void: _backdrop.preview_frame(frame_id))
		var swatch := ColorRect.new()
		swatch.color = Game.livery(f.id).color
		swatch.custom_minimum_size = Vector2(14, 80)
		row.add_child(swatch)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		info.add_child(UiUtil.label(f.name, &"HeaderLabel", 28))
		var desc := UiUtil.label(f.description, &"DimLabel")
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(desc)
		var stats := SubStats.build(f.id, {}, [])
		var tools := ", ".join(stats.tools.map(func(t: StringName) -> String: return Catalog.TOOL_NAMES.get(t, String(t))))
		info.add_child(UiUtil.label("Hull %d   Battery %d   Speed %.1f   Tools: %s" % [
			stats.max_hull, stats.max_battery, stats.max_speed, tools if tools != "" else "harpoon only"], &"MonoLabel", 18))
		var id := f.id
		var b: Button
		if Game.meta.selected_frame == String(id):
			b = UiUtil.button("Selected", func() -> void: pass, 220)
			b.disabled = true
		elif Game.meta.is_frame_unlocked(id):
			b = UiUtil.button("Select", func() -> void:
				Game.meta.selected_frame = String(id)
				Game.save_game()
				_backdrop.refresh_sub()
				_show_tab(Tab.FRAMES), 220)
		else:
			var biome := BiomeLibrary.biome_for_zone(f.found_in)
			var where := UiUtil.label("Not yet found. Its derelict lies somewhere in the %s (zone %d): hold " %
				[biome.display_name, f.found_in + 1] + "alongside it to copy its schematics.", &"", 18, UiTheme.WARN)
			where.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			info.add_child(where)
			b = UiUtil.button("Not found", func() -> void: pass, 220)
			b.disabled = true
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.focus_entered.connect(func() -> void: _backdrop.preview_frame(frame_id))
		b.mouse_entered.connect(func() -> void: _backdrop.preview_frame(frame_id))
		row.add_child(b)
	_content.add_child(UiUtil.label("New submarines are not bought: find their derelicts down in the trench.",
		&"DimLabel"))


func _build_codex() -> void:
	var known := 0
	for e in CreatureCodex.entries():
		var scanned := Game.meta.codex.has(String(e.id))
		known += 1 if scanned else 0
		var row := _row_panel()
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		if scanned:
			# Hovering a scanned species shows it in the viewport.
			var id := e.id
			(row.get_parent() as Control).mouse_entered.connect(func() -> void: _backdrop.preview_creature(id))
			info.add_child(UiUtil.label("%s   %s" % [e.name, e.latin], &"HeaderLabel", 26))
			var notes := UiUtil.label(e.notes)
			notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			info.add_child(notes)
			info.add_child(UiUtil.label("Threat: %s   -   Scanned %d times" % [e.threat,
					Game.meta.codex[String(e.id)]], &"DimLabel"))
		else:
			info.add_child(UiUtil.label("? ? ?", &"HeaderLabel", 26, UiTheme.TEXT_DIM))
			info.add_child(UiUtil.label("Not yet scanned. Hold your lamp on a creature to scan it.", &"DimLabel"))
	var head := UiUtil.label("%d / %d species catalogued" % [known, CreatureCodex.entries().size()], &"MonoLabel")
	_content.add_child(head)
	_content.move_child(head, 0)


func _build_logs() -> void:
	var found := Game.meta.logs_found
	_content.add_child(UiUtil.label("%d / %d logs recovered" % [SignalLogs.found_count(found), SignalLogs.count()],
		&"MonoLabel"))
	for l in SignalLogs.LOGS:
		var row := _row_panel()
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		if found.has(l.id):
			info.add_child(UiUtil.label("%s  -  %s" % [l.title, l.author], &"HeaderLabel", 24))
			var text := UiUtil.label(l.text)
			text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			info.add_child(text)
		else:
			info.add_child(UiUtil.label("[ encrypted ]", &"HeaderLabel", 24, UiTheme.TEXT_DIM))
			info.add_child(UiUtil.label("Recover this log from a black-box beacon in the trench.", &"DimLabel"))
	for l in SignalLogs.EXTRAS:
		if not found.has(l.id):
			continue
		var row := _row_panel()
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		info.add_child(UiUtil.label("%s  -  %s" % [l.title, l.author], &"HeaderLabel", 24, UiTheme.ACCENT))
		var text := UiUtil.label(l.text)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(text)
	_build_wonders()


## The sights witnessed in the trench, beside the logs that told of them.
func _build_wonders() -> void:
	var seen := Game.meta.wonders
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	_content.add_child(gap)
	_content.add_child(UiUtil.label("%d / %d wonders witnessed" % [Wonders.found_count(seen), Wonders.ALL.size()],
		&"MonoLabel"))
	for w in Wonders.ALL:
		var row := _row_panel()
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		if seen.has(w.id):
			# The moment it was first witnessed.
			var shot := Wonders.snapshot(w.id)
			if shot:
				var pic := TextureRect.new()
				pic.texture = shot
				pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				pic.custom_minimum_size = Vector2(176, 99)
				row.add_child(pic)
				row.move_child(pic, 0)
			info.add_child(UiUtil.label(w.name, &"HeaderLabel", 24, UiTheme.GOOD))
			var text := UiUtil.label(w.text)
			text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			info.add_child(text)
			if w.has("log") and Game.meta.logs_found.has(w.log):
				info.add_child(UiUtil.label("As told in \"%s\"" % SignalLogs.get_log(StringName(w.log)).title,
					&"DimLabel"))
		else:
			info.add_child(UiUtil.label("? ? ?", &"HeaderLabel", 24, UiTheme.TEXT_DIM))
			info.add_child(UiUtil.label("Not yet witnessed. Somewhere %s." % w.where, &"DimLabel"))


func _build_challenges() -> void:
	var meta := Game.meta
	var frame := StringName(meta.selected_frame)
	var head := HBoxContainer.new()
	_content.add_child(head)
	head.add_child(UiUtil.label("%d / %d won  -  track up to %d to keep them on your HUD" % [
		meta.challenges_won.size(), Challenges.all().size(), Challenges.MAX_TRACKED], &"MonoLabel"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var factory := UiUtil.button("Factory paint", func() -> void: _apply_livery(frame, ""), 220)
	factory.disabled = meta.livery(frame) == ""
	head.add_child(factory)
	var best := "the Choir still sings"
	if meta.best_pressure_win >= 0:
		best = "best win at pressure %d" % meta.best_pressure_win
	var records := "Records:  %d dives  -  %d victories  -  deepest %s m  -  %d creatures  -  %d Stalkers  -  %s"
	_content.add_child(UiUtil.label(records % [meta.dives, meta.wins, UiUtil.thousands(meta.deepest_depth),
		meta.total_kills, meta.stalkers_killed, best], &"DimLabel", 18))
	var section := ""
	for c in Challenges.all():
		var reward := c.reward()
		var heading := "PAINTS  -  for any submarine" if reward.is_paint() else "%s SKINS" % \
			Catalog.frame(reward.frame).name.to_upper()
		if heading != section:
			section = heading
			_content.add_child(UiUtil.spacer(6))
			_content.add_child(UiUtil.label(heading, &"HeaderLabel", 22, UiTheme.ACCENT))
		_challenge_row(c, reward)


func _challenge_row(c: Challenges.Challenge, reward: SubSkins.Livery) -> void:
	var meta := Game.meta
	var row := _row_panel()
	var won := meta.challenges_won.has(c.id)
	row.get_parent().mouse_entered.connect(func() -> void: _backdrop.preview_skin(reward))
	row.add_child(_swatch(reward, won))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var title := c.name + ("   (one dive)" if c.per_dive else "")
	info.add_child(UiUtil.label(title, &"HeaderLabel", 24, UiTheme.ACCENT if won else UiTheme.TEXT))
	var desc := UiUtil.label(c.description, &"DimLabel")
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(desc)
	var progress := Challenges.progress_text(c, meta, null)
	if c.per_dive and not won:
		progress = "best %d / %d" % [int(meta.challenge_best.get(c.id, 0)), c.target] if c.target > 1 else "not yet"
	info.add_child(UiUtil.label("Reward: %s   -   %s" % [Challenges.reward_text(c), progress], &"MonoLabel", 17,
		UiTheme.GOOD if won else UiTheme.TEXT_DIM))
	var buttons := VBoxContainer.new()
	buttons.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(buttons)
	var id := c.id
	var track: Button
	if won:
		# Won: wear it (a skin goes on its own frame, a paint on the selected one).
		var on := StringName(meta.selected_frame) if reward.is_paint() else reward.frame
		if meta.livery(on) == id:
			track = UiUtil.button("Applied", func() -> void: pass, 200)
			track.disabled = true
		else:
			track = UiUtil.button("Apply", func() -> void: _apply_livery(on, id), 200)
	else:
		track = UiUtil.button("Tracked" if meta.tracked.has(id) else "Track", func() -> void:
			Game.meta.toggle_tracked(id)
			Game.save_game()
			Audio.play_ui(&"tool_cycle", -6.0)
			_show_tab(Tab.CHALLENGES), 200)
		track.toggle_mode = true
		track.button_pressed = meta.tracked.has(id)
	track.focus_entered.connect(func() -> void: _backdrop.preview_skin(reward))
	track.mouse_entered.connect(func() -> void: _backdrop.preview_skin(reward))
	buttons.add_child(track)


## A sample of a livery: its pattern for a skin, its color for a paint.
func _swatch(skin: SubSkins.Livery, won: bool) -> Control:
	if skin.is_paint():
		var rect := ColorRect.new()
		rect.color = skin.color if won else skin.color.darkened(0.7)
		rect.custom_minimum_size = Vector2(16, 72)
		return rect
	var tex := TextureRect.new()
	tex.texture = SubSkins.textures(skin)[0]
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tex.custom_minimum_size = Vector2(72, 72)
	tex.modulate = Color.WHITE if won else Color(0.4, 0.4, 0.4)
	return tex


func _apply_livery(frame: StringName, id: String) -> void:
	if Game.meta.set_livery(frame, id):
		Game.save_game()
		Audio.play_ui(&"module_install", -4.0)
	if frame == StringName(Game.meta.selected_frame):
		_backdrop.refresh_sub()
	_show_tab(Tab.CHALLENGES)
