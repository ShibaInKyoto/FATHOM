extends Node
## Debug helper: plays the studio splash and saves frames at set moments.
## Usage: xvfb-run godot --path . res://tools/debug/preview_splash.tscn -- <out_dir>

const TIMES: Array[float] = [3.8, 3.9, 4.0, 4.15, 4.35, 4.6, 5.6, 7.0]

var _t := 0.0
var _shot := 0


func _ready() -> void:
	add_child(load(Router.SPLASH).instantiate())


func _process(delta: float) -> void:
	_t += delta
	if _shot < TIMES.size() and _t >= TIMES[_shot]:
		var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
		get_viewport().get_texture().get_image().save_png(out.path_join("splash_%d.png" % _shot))
		_shot += 1
		if _shot >= TIMES.size():
			get_tree().quit()
