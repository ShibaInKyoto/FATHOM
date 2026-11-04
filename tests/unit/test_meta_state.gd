extends TestCase
## Persistent progression: purchases, unlocks and serialization.


func test_buy_upgrade_deducts_salvage() -> void:
	var m := MetaState.new()
	m.salvage = 100
	check(m.buy_upgrade(&"hull"))
	check_eq(m.salvage, 25)
	check_eq(m.upgrade_level(&"hull"), 1)
	check(not m.buy_upgrade(&"hull"), "cannot afford level 2")


func test_upgrades_cap_at_max_level() -> void:
	var m := MetaState.new()
	m.salvage = 100000
	m.projects.append("optics")
	for i in 10:
		m.buy_upgrade(&"lamp")
	check_eq(m.upgrade_level(&"lamp"), Catalog.upgrade(&"lamp").max_level())


func test_frames_are_found_not_bought() -> void:
	var m := MetaState.new()
	m.research = 500
	check(m.unlock_frame(&"mako"), "found, the frame joins the hangar")
	check_eq(m.research, 500, "and costs nothing")
	check(m.is_frame_unlocked(&"mako"))
	check(not m.unlock_frame(&"mako"), "only once")
	for f in Catalog.frames():
		check(f.found_in < BiomeLibrary.TOTAL_ZONES - 1, "%s is found above the hadal floor" % f.id)


func test_research_projects_open_upgrades_and_modules() -> void:
	var m := MetaState.new()
	m.salvage = 1000
	check(not m.buy_upgrade(&"lamp"), "lamp upgrades need the Optics Lab")
	check(Research.locked_modules(m).has(&"wide_lens"), "and so does the wide lens")
	m.research = 30
	check(not m.research_project("optics"), "research short")
	m.research = 100
	check(m.research_project("optics"))
	check_eq(m.research, 60)
	check(m.buy_upgrade(&"lamp"), "now the yard sells lamp upgrades")
	check(not Research.locked_modules(m).has(&"wide_lens"), "and the lockers stock the lens")
	check(not m.research_project("optics"), "a project is done once")
	m.research = 1000
	check(not m.research_project("acoustic"), "acoustic dampening needs echo sounding first")
	check(m.research_project("echo"))
	check(not m.research_project("acoustic"), "and a scanned Stalker")
	m.codex["stalker"] = 1
	check(m.research_project("acoustic"))
	var copy := MetaState.from_dict(JSON.parse_string(JSON.stringify(m.to_dict())))
	check(copy.projects.has("acoustic") and copy.projects.has("optics"), "projects persist")


func test_every_module_and_upgrade_can_be_researched() -> void:
	var researched: Array[StringName] = []
	researched.append_array(Research.STARTER_MODULES)
	for p in Research.all():
		researched.append_array(p.modules)
		for r in p.requires:
			check(Research.find(r) != null, "%s needs a real project" % p.id)
		for u in p.upgrades:
			check(Catalog.upgrade(u) != null, "%s opens a real upgrade" % p.id)
	for m in Catalog.modules():
		check(researched.count(m.id) == 1, "%s is in exactly one project or the starter set" % m.id)
	for u in Catalog.upgrades():
		check(Research.STARTER_UPGRADES.has(u.id) or Research.project_for_upgrade(u.id) != null,
			"%s upgrades can be opened" % u.id)


func test_round_trip() -> void:
	var m := MetaState.new()
	m.salvage = 321
	m.research = 12
	m.upgrades["sonar"] = 2
	m.unlocked_frames.append("mako")
	m.selected_frame = "mako"
	m.codex["lancer"] = 3
	m.logs_found.append("log_01")
	m.deepest_depth = 4321
	var copy := MetaState.from_dict(JSON.parse_string(JSON.stringify(m.to_dict())))
	check_eq(copy.salvage, 321)
	check_eq(copy.upgrade_level(&"sonar"), 2)
	check_eq(copy.selected_frame, "mako")
	check_eq(copy.codex.get("lancer"), 3)
	check(copy.logs_found.has("log_01"))
	check_eq(copy.deepest_depth, 4321)


func test_corrupt_data_falls_back() -> void:
	var copy := MetaState.from_dict({"selected_frame": "nonexistent", "unlocked_frames": []})
	check_eq(copy.selected_frame, "lantern")
	check(copy.is_frame_unlocked(&"lantern"))


func test_challenges_award_once_and_persist() -> void:
	var m := MetaState.new()
	m.deepest_zone = 4
	var first := Challenges.check(m, null)
	var ids := first.map(func(x: Challenges.Challenge) -> String: return x.id)
	check(ids.has("first_descent") and ids.has("twilight") and ids.has("midnight"), "depth challenges won")
	check(not ids.has("vents"), "deeper challenge not won yet")
	check(Challenges.check(m, null).is_empty(), "nothing won twice")
	check(m.set_livery(&"mako", "midnight"), "a paint fits any frame")
	var copy := MetaState.from_dict(JSON.parse_string(JSON.stringify(m.to_dict())))
	check_eq(copy.livery(&"mako"), "midnight")
	check_eq(copy.livery(&"lantern"), "", "each frame keeps its own")
	check(copy.challenges_won.has("twilight"))


func test_liveries_must_be_won_and_fit() -> void:
	var m := MetaState.new()
	check(not m.set_livery(&"lantern", "answer"), "unearned paint refused")
	m.challenges_won.append("mako_carbon")
	check(not m.set_livery(&"lantern", "mako_carbon"), "a skin made for the Mako does not fit the Lantern")
	check(m.set_livery(&"mako", "mako_carbon"), "but fits the Mako")
	var copy := MetaState.from_dict({"liveries": {"lantern": "answer"}, "challenges_won": []})
	check_eq(copy.livery(&"lantern"), "", "unearned livery is dropped on load")


func test_old_saves_keep_their_paint() -> void:
	var copy := MetaState.from_dict({"paint": "twilight", "milestones": ["first_descent", "twilight"]})
	check(copy.challenges_won.has("twilight"), "milestones carry over as challenges won")
	for f in Catalog.frames():
		check_eq(copy.livery(f.id), "twilight", "the old paint goes on every frame")


func test_daily_record_resets_each_day() -> void:
	var m := MetaState.new()
	check_eq(m.daily_summary("2026-10-28"), "")
	m.begin_daily("2026-10-28")
	m.daily_best_depth = 1500
	m.begin_daily("2026-10-28")
	check_eq(m.daily_attempts, 2)
	check(m.daily_summary("2026-10-28").contains("1,500"), "summary shows the best depth")
	var restored := MetaState.from_dict(JSON.parse_string(JSON.stringify(m.to_dict())))
	check_eq(restored.daily_best_depth, 1500)
	restored.begin_daily("2026-10-29")
	check_eq(restored.daily_attempts, 1)
	check_eq(restored.daily_best_depth, 0)
	check_eq(m.daily_summary("2026-10-29"), "")


func test_retired_tool_upgrades_are_refunded() -> void:
	var m := MetaState.from_dict({"salvage": 10, "upgrades": {"hull": 2, "torpedoes": 2, "flares": 1}})
	check_eq(m.salvage, 10 + 190 + 325 + 110, "salvage spent on tool upgrades comes back")
	check_eq(m.upgrade_level(&"hull"), 2, "other upgrades are kept")
	check(not m.upgrades.has("torpedoes") and not m.upgrades.has("flares"), "tool upgrades are gone")
