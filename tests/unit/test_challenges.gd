extends TestCase
## Challenges: each pays a livery, dive challenges count one dive in their own
## frame, and the hangar tracks a few of them for the HUD.


func test_every_challenge_pays_a_livery_that_fits() -> void:
	for c in Challenges.all():
		var reward := c.reward()
		check(reward != null, "%s has a reward" % c.id)
		if reward and not reward.is_paint():
			check(Catalog.frame(reward.frame) != null, "%s: a skin for a real frame" % c.id)
			check_eq(reward.frame, c.frame if c.per_dive else reward.frame, "%s: done in the frame it dresses" % c.id)


func test_a_dive_challenge_counts_only_in_its_frame() -> void:
	var meta := MetaState.new()
	var run := RunState.new()
	run.frame_id = &"lantern"
	run.kills = 30
	var tiger := Challenges.find("mako_tiger")
	check_eq(Challenges.progress(tiger, meta, run), 0, "kills in the Lantern do not count")
	Challenges.check(meta, run)
	check(not meta.challenges_won.has("mako_tiger"))
	run.frame_id = &"mako"
	run.kills = 12
	Challenges.check(meta, run)
	check_eq(int(meta.challenge_best.get("mako_tiger", 0)), 12, "the best try is remembered")
	run.kills = 25
	Challenges.check(meta, run)
	check(meta.challenges_won.has("mako_tiger"), "25 in the Mako wins it")
	check(run.challenges_won.has("mako_tiger"), "and the dive remembers it was won then")
	check(meta.set_livery(&"mako", "mako_tiger"), "its skin can be worn")


func test_tracking_keeps_the_newest_few() -> void:
	var meta := MetaState.new()
	meta.tracked.clear()
	for id in ["hoarder", "veteran", "codex", "fleet"]:
		meta.toggle_tracked(id)
	check_eq(meta.tracked.size(), Challenges.MAX_TRACKED)
	check(not meta.tracked.has("hoarder"), "the oldest gives way")
	meta.toggle_tracked("fleet")
	check(not meta.tracked.has("fleet"), "tracking again stops tracking")


func test_every_livery_builds() -> void:
	for skin in SubSkins.all():
		var model := SubmarineModel.new()
		model.build(skin.frame if skin.frame != &"" else &"lantern", skin)
		var hull := model.hull_material
		var drawn: bool = hull.get_shader_parameter(&"pattern_tex") != null \
			or hull.get_shader_parameter(&"paint_map") != null
		check(drawn, "%s is drawn" % skin.id)
		if skin.finish == &"glow" or skin.finish == &"pulse":
			check(float(hull.get_shader_parameter(&"glow_energy")) > 0.0, "%s glows" % skin.id)
		model.free()


func test_won_challenges_hand_on_their_slot() -> void:
	var meta := MetaState.new()
	meta.tracked.assign(["first_descent", "hoarder"])
	meta.challenges_won.assign(["first_descent", "twilight"])
	meta.retire_tracked()
	check(not meta.tracked.has("first_descent"), "a won challenge leaves the HUD")
	check(meta.tracked.has("hoarder"), "the rest stay")
	check(meta.tracked.has("midnight"), "and the next one not yet won takes its place")
	check_eq(meta.tracked.size(), 2)
