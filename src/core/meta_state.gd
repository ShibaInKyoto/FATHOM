class_name MetaState
extends RefCounted
## Progress that persists between dives: banked currencies, hangar upgrades,
## unlocked frames, codex and statistics. Serialized to JSON by [SaveSystem].

const VERSION := 1
const MAX_RECORDS := 5

var salvage := 0
var research := 0
## Upgrade id (String) -> purchased level.
var upgrades: Dictionary = {}
## Ids of the [Research] projects finished.
var projects: Array[String] = []
var unlocked_frames: Array[String] = ["lantern"]
var selected_frame := "lantern"
## Creature id (String) -> number of times scanned.
var codex: Dictionary = {}
var logs_found: Array[String] = []
## Ids of the [Wonders] witnessed.
var wonders: Array[String] = []
var deepest_zone := 0
var deepest_depth := 0
var dives := 0
var wins := 0
var pressure_unlocked := 0
var pressure_selected := 0
var tutorial_done := false
var total_salvage := 0
var total_kills := 0
var stalkers_killed := 0
var mothers_killed := 0
var anglers_killed := 0
## Meridian survey probes recovered, over every dive.
var probes_recovered := 0
var best_pressure_win := -1
## Ids of the [Challenges] won.
var challenges_won: Array[String] = []
## Challenges shown on the HUD while diving (at most [constant Challenges.MAX_TRACKED]).
var tracked: Array[String] = ["first_descent", "naturalist"]
## Best progress yet on each dive challenge, by id.
var challenge_best: Dictionary = {}
## Livery id applied to each frame (frame id -> [SubSkins] id; none = factory paint).
var liveries: Dictionary = {}
## Victories over the Choir in each frame (frame id -> count).
var frame_wins: Dictionary = {}
## Daily dive record for [member daily_date] (YYYY-MM-DD).
var daily_date := ""
var daily_best_depth := 0
var daily_attempts := 0
var daily_won := false
## Best dives, highest score first (see [method DiveScore.record]).
var records: Array[Dictionary] = []
## The wreck of the last sub to implode: its zone (-1 = none), frame and the
## cargo insurance did not cover, waiting to be recovered (see [LostWreck]).
var wreck_zone := -1
var wreck_frame := ""
var wreck_cargo := 0
## How it was lost: "implosion" (crushed) or "power" (dark but whole).
var wreck_kind := ""
## Contract taken in the hangar for the next dive ("" = none); used up when it starts.
var contract_selected := ""


func upgrade_level(id: StringName) -> int:
	return upgrades.get(String(id), 0)


func can_afford(cost: int) -> bool:
	return salvage >= cost


## The livery id applied to [param frame_id] ("" = factory paint).
func livery(frame_id: StringName) -> String:
	return liveries.get(String(frame_id), "")


## Applies a won livery that fits the frame ("" restores the factory paint).
## Returns false (and changes nothing) for one not won or made for another frame.
func set_livery(frame_id: StringName, skin_id: String) -> bool:
	if skin_id == "":
		liveries.erase(String(frame_id))
		return true
	var skin := SubSkins.find(skin_id)
	if skin == null or not challenges_won.has(skin_id) or not skin.is_paint() and skin.frame != frame_id:
		return false
	liveries[String(frame_id)] = skin_id
	return true


## Hands the HUD slots of tracked challenges now won to the next ones not
## yet won, in the order the hangar lists them.
func retire_tracked() -> void:
	var freed := tracked.size()
	tracked.assign(tracked.filter(func(id: String) -> bool: return not challenges_won.has(id)))
	freed -= tracked.size()
	for c in Challenges.all():
		if freed <= 0:
			break
		if not challenges_won.has(c.id) and not tracked.has(c.id):
			tracked.append(c.id)
			freed -= 1


## Tracks [param id] on the HUD, or stops tracking it. Tracking one more than
## the HUD has room for drops the oldest.
func toggle_tracked(id: String) -> void:
	if tracked.has(id):
		tracked.erase(id)
		return
	tracked.append(id)
	while tracked.size() > Challenges.MAX_TRACKED:
		tracked.pop_front()


## Buys the next level of an upgrade. Returns false if maxed or unaffordable.
func buy_upgrade(id: StringName) -> bool:
	var def := Catalog.upgrade(id)
	if def == null:
		return false
	var level := upgrade_level(id)
	if level >= def.max_level():
		return false
	var cost := def.costs[level]
	if salvage < cost or not Research.upgrade_open(self, id):
		return false
	salvage -= cost
	upgrades[String(id)] = level + 1
	return true


## Spends research on a project. False if it is done, blocked or unaffordable.
func research_project(id: String) -> bool:
	var p := Research.find(id)
	if p == null or projects.has(id) or research < p.cost or Research.blocker(self, p) != "":
		return false
	research -= p.cost
	projects.append(id)
	return true


## Files a finished dive. Returns its place in the records (0 = new best),
## or -1 if it did not make the table.
func record_dive(entry: Dictionary) -> int:
	if int(entry.get("score", 0)) <= 0:
		return -1
	var rank := records.size()
	for i in records.size():
		if int(entry.score) > int(records[i].score):
			rank = i
			break
	if rank >= MAX_RECORDS:
		return -1
	records.insert(rank, entry)
	if records.size() > MAX_RECORDS:
		records.resize(MAX_RECORDS)
	return rank


func record_wreck(zone: int, frame: StringName, cargo: int, kind := "implosion") -> void:
	wreck_zone = zone
	wreck_frame = String(frame)
	wreck_cargo = cargo
	wreck_kind = kind


func clear_wreck() -> void:
	wreck_zone = -1
	wreck_frame = ""
	wreck_cargo = 0
	wreck_kind = ""


func has_wreck() -> bool:
	return wreck_zone >= 0 and wreck_cargo > 0


func best_score() -> int:
	return int(records[0].score) if not records.is_empty() else 0


func is_frame_unlocked(id: StringName) -> bool:
	return unlocked_frames.has(String(id))


## Adds a frame to the hangar (its derelict has been found; see [DerelictFrame]).
func unlock_frame(id: StringName) -> bool:
	if Catalog.frame(id) == null or is_frame_unlocked(id):
		return false
	unlocked_frames.append(String(id))
	return true


func record_scan(id: StringName) -> bool:
	var key := String(id)
	var first := not codex.has(key)
	codex[key] = codex.get(key, 0) + 1
	return first


## Starts a daily attempt, resetting the record when the day has changed.
func begin_daily(date: String) -> void:
	if daily_date != date:
		daily_date = date
		daily_best_depth = 0
		daily_attempts = 0
		daily_won = false
	daily_attempts += 1


## Today's daily record, or an empty string if there is none yet.
func daily_summary(date: String) -> String:
	if daily_date != date or daily_attempts == 0:
		return ""
	var best := "Choir silenced" if daily_won else "best %s m" % UiUtil.thousands(daily_best_depth)
	return "%s, %d attempt%s" % [best, daily_attempts, "" if daily_attempts == 1 else "s"]


func to_dict() -> Dictionary:
	return {
		"version": VERSION,
		"salvage": salvage,
		"research": research,
		"upgrades": upgrades,
		"projects": projects,
		"unlocked_frames": unlocked_frames,
		"selected_frame": selected_frame,
		"codex": codex,
		"logs_found": logs_found,
		"wonders": wonders,
		"deepest_zone": deepest_zone,
		"deepest_depth": deepest_depth,
		"dives": dives,
		"wins": wins,
		"pressure_unlocked": pressure_unlocked,
		"pressure_selected": pressure_selected,
		"tutorial_done": tutorial_done,
		"total_salvage": total_salvage,
		"total_kills": total_kills,
		"stalkers_killed": stalkers_killed,
		"mothers_killed": mothers_killed,
		"anglers_killed": anglers_killed,
		"probes_recovered": probes_recovered,
		"best_pressure_win": best_pressure_win,
		"challenges_won": challenges_won,
		"tracked": tracked,
		"challenge_best": challenge_best,
		"liveries": liveries,
		"frame_wins": frame_wins,
		"daily_date": daily_date,
		"daily_best_depth": daily_best_depth,
		"daily_attempts": daily_attempts,
		"daily_won": daily_won,
		"records": records,
		"wreck_zone": wreck_zone,
		"wreck_frame": wreck_frame,
		"wreck_cargo": wreck_cargo,
		"wreck_kind": wreck_kind,
		"contract_selected": contract_selected,
	}


static func from_dict(d: Dictionary) -> MetaState:
	var m := MetaState.new()
	m.salvage = int(d.get("salvage", 0))
	m.research = int(d.get("research", 0))
	var ups: Dictionary = d.get("upgrades", {})
	for k in ups:
		var level := int(ups[k])
		# Tools are no longer hangar upgrades: give back what they cost.
		if Catalog.RETIRED_UPGRADES.has(String(k)):
			var costs: Array = Catalog.RETIRED_UPGRADES[String(k)]
			for i in mini(level, costs.size()):
				m.salvage += int(costs[i])
			continue
		m.upgrades[String(k)] = level
	for id in d.get("projects", []):
		if Research.find(String(id)) and not m.projects.has(String(id)):
			m.projects.append(String(id))
	m.unlocked_frames.clear()
	for f in d.get("unlocked_frames", ["lantern"]):
		m.unlocked_frames.append(String(f))
	if not m.unlocked_frames.has("lantern"):
		m.unlocked_frames.append("lantern")
	m.selected_frame = String(d.get("selected_frame", "lantern"))
	if not m.unlocked_frames.has(m.selected_frame):
		m.selected_frame = "lantern"
	var codex: Dictionary = d.get("codex", {})
	for k in codex:
		m.codex[String(k)] = int(codex[k])
	for l in d.get("logs_found", []):
		m.logs_found.append(String(l))
	for w in d.get("wonders", []):
		m.wonders.append(String(w))
	m.deepest_zone = int(d.get("deepest_zone", 0))
	m.deepest_depth = int(d.get("deepest_depth", 0))
	m.dives = int(d.get("dives", 0))
	m.wins = int(d.get("wins", 0))
	m.pressure_unlocked = int(d.get("pressure_unlocked", 0))
	m.pressure_selected = clampi(int(d.get("pressure_selected", 0)), 0, m.pressure_unlocked)
	m.tutorial_done = bool(d.get("tutorial_done", false))
	m.total_salvage = int(d.get("total_salvage", 0))
	m.total_kills = int(d.get("total_kills", 0))
	m.stalkers_killed = int(d.get("stalkers_killed", 0))
	m.mothers_killed = int(d.get("mothers_killed", 0))
	m.anglers_killed = int(d.get("anglers_killed", 0))
	m.probes_recovered = int(d.get("probes_recovered", 0))
	m.best_pressure_win = int(d.get("best_pressure_win", -1))
	# Saves from before challenges called them milestones.
	for id in d.get("challenges_won", d.get("milestones", [])):
		if Challenges.find(String(id)) and not m.challenges_won.has(String(id)):
			m.challenges_won.append(String(id))
	if d.has("tracked"):
		m.tracked.clear()
		for id in d.tracked:
			if Challenges.find(String(id)) and m.tracked.size() < Challenges.MAX_TRACKED:
				m.tracked.append(String(id))
	m.retire_tracked()
	var best: Dictionary = d.get("challenge_best", {})
	for id in best:
		m.challenge_best[String(id)] = int(best[id])
	var wins_by: Dictionary = d.get("frame_wins", {})
	for f in wins_by:
		m.frame_wins[String(f)] = int(wins_by[f])
	var liveries: Dictionary = d.get("liveries", {})
	# One paint for every frame, before liveries were chosen per frame.
	var old_paint := String(d.get("paint", ""))
	if old_paint != "" and liveries.is_empty():
		for f in Catalog.frames():
			liveries[String(f.id)] = old_paint
	for f in liveries:
		m.set_livery(StringName(f), String(liveries[f]))
	m.daily_date = String(d.get("daily_date", ""))
	m.daily_best_depth = int(d.get("daily_best_depth", 0))
	m.daily_attempts = int(d.get("daily_attempts", 0))
	m.daily_won = bool(d.get("daily_won", false))
	for r: Variant in d.get("records", []):
		if r is Dictionary:
			m.records.append(_clean_record(r))
	m.wreck_zone = clampi(int(d.get("wreck_zone", -1)), -1, BiomeLibrary.TOTAL_ZONES - 1)
	m.wreck_frame = String(d.get("wreck_frame", ""))
	m.wreck_cargo = maxi(int(d.get("wreck_cargo", 0)), 0)
	m.wreck_kind = String(d.get("wreck_kind", "implosion"))
	m.contract_selected = String(d.get("contract_selected", ""))
	if Contracts.find(StringName(m.contract_selected)) == null:
		m.contract_selected = ""
	if Catalog.frame(StringName(m.wreck_frame)) == null:
		m.clear_wreck()
	m.records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
	if m.records.size() > MAX_RECORDS:
		m.records.resize(MAX_RECORDS)
	return m


## A records entry with every field present and of the right type.
static func _clean_record(r: Dictionary) -> Dictionary:
	return {
		"score": int(r.get("score", 0)), "frame": String(r.get("frame", "lantern")),
		"depth": int(r.get("depth", 0)), "zone": int(r.get("zone", 0)), "outcome": String(r.get("outcome", "")),
		"pressure": int(r.get("pressure", 0)), "daily": bool(r.get("daily", false)),
		"date": String(r.get("date", "")), "contract": String(r.get("contract", "")),
	}
