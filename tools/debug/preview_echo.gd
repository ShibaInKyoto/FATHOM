extends "res://tools/debug/preview_stage.gd"
## Debug helper: stages a Hadal Trench zone, pings once and saves screenshots
## of the answer rising from below eleven seconds later.
## "film" films from just before the deep stirs until the wave has passed,
## a frame every fifteenth of a second; "dark" keeps the lamp off; "life"
## puts a school of lanternfish and a few hunters round the sub, to watch the
## wave hush them as it passes.
## Usage: xvfb-run godot --path . res://tools/debug/preview_echo.tscn -- <out_dir> [seed] [film] [dark] [life]

var _pinged := false
var _dark := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var zone := BiomeLibrary.ZONES_PER_BIOME * (BiomeLibrary.BIOME_COUNT - 1)
	stage(zone, int(args[1]) if args.size() > 1 else 99, &"lantern", true)
	LevelPopulator.populate(level, run)
	var path := level.layout.main_path
	place_sub(path[int(0.2 * (path.size() - 1))], 1.3)
	add_hud()
	shot_prefix = "echo"
	shot_times = [2.0, 10.2, 11.9, 12.6, 13.4, 14.4]
	if args.has("film"):
		shot_times = []
		for i in 120:
			shot_times.append(8.5 + i / 15.0)
	_dark = args.has("dark")
	if args.has("life"):
		var spots := [[&"shoal", Vector2(7.0, 2.5)], [&"shoal", Vector2(-6.0, -2.0)], [&"lancer", Vector2(9.0, -3.0)],
			[&"ghostfin", Vector2(-9.0, 3.0)], [&"jelly", Vector2(3.0, 5.0)]]
		for spot: Array in spots:
			var c: Creature = LevelPopulator.SPECIES[spot[0]].new()
			c.pos = level.field.resolve_circle(sub.pos + (spot[1] as Vector2), 1.5)
			level.add_entity(c)


func direct(_dt: float) -> void:
	sub.run.hull = sub.stats.max_hull
	sub.run.battery = sub.stats.max_battery
	if _dark:
		sub.lamp_on = false
	if not _pinged and t > 0.5:
		_pinged = sub.try_ping()
