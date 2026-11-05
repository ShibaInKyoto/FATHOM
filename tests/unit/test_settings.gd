extends TestCase
## Graphics presets: how big a picture each renders the 3D view at, for the
## size of the screen.


func test_big_screens_render_3d_at_a_capped_height() -> void:
	# A 1080p or 1440p screen renders exactly as before.
	check_eq(Settings.render_scale(Settings.Quality.HIGH, 1080), 1.0, "High at 1080p: native")
	check_eq(Settings.render_scale(Settings.Quality.HIGH, 1440), 1.0, "High at 1440p: native")
	check_eq(Settings.render_scale(Settings.Quality.LOW, 1080), 0.67, "Low keeps its own scale")
	check_eq(Settings.render_scale(Settings.Quality.MEDIUM, 1080), 0.85, "Medium keeps its own scale")
	# A 4K screen: the 3D view at the preset's height, upscaled.
	check_near(Settings.render_scale(Settings.Quality.HIGH, 2160) * 2160.0, 1440.0, 0.5, "High at 4K: 1440 rows")
	check_near(Settings.render_scale(Settings.Quality.ULTRA, 2160) * 2160.0, 1800.0, 0.5, "Ultra at 4K: 1800 rows")
	check(Settings.render_scale(Settings.Quality.LOW, 2160) * 2160.0 <= 900.5, "Low at 4K: at most 900 rows")
