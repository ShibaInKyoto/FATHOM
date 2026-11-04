extends TestCase
## A gamepad drives the menus (A presses, B backs out) and the sub, whichever
## device number the system gives it, and the right stick swings the lamp
## round quickly but smoothly, over the top when it turns right about.


func test_a_presses_and_b_backs_out() -> void:
	var a := InputEventJoypadButton.new()
	a.button_index = JOY_BUTTON_A
	a.pressed = true
	var b := InputEventJoypadButton.new()
	b.button_index = JOY_BUTTON_B
	b.pressed = true
	check(a.is_action(&"ui_accept"), "A presses the focused button")
	check(b.is_action(&"ui_cancel"), "B backs out")


func test_every_action_answers_a_pad_numbered_anything() -> void:
	# The system may number the player's pad 1 or higher; events made in code
	# default to device 0, and bindings made that way ignore every other pad.
	for device: int in [0, 1, 3, 7]:
		var button := func(b: JoyButton) -> InputEventJoypadButton:
			var e := InputEventJoypadButton.new()
			e.device = device
			e.button_index = b
			e.pressed = true
			return e
		var axis := func(a: JoyAxis, v: float) -> InputEventJoypadMotion:
			var e := InputEventJoypadMotion.new()
			e.device = device
			e.axis = a
			e.axis_value = v
			return e
		check((button.call(JOY_BUTTON_A) as InputEvent).is_action(&"ui_accept"), "A presses buttons (pad %d)" % device)
		check((button.call(JOY_BUTTON_B) as InputEvent).is_action(&"ui_cancel"), "B backs out (pad %d)" % device)
		check((button.call(JOY_BUTTON_DPAD_DOWN) as InputEvent).is_action(&"ui_down"), "the d-pad moves focus (pad %d)" %
			device)
		check((axis.call(JOY_AXIS_LEFT_Y, 1.0) as InputEvent).is_action(&"ui_down"), "so does the stick (pad %d)" % device)
		check((axis.call(JOY_AXIS_LEFT_X, 1.0) as InputEvent).is_action(&"move_right"), "the left stick moves (pad %d)" %
			device)
		check((axis.call(JOY_AXIS_RIGHT_Y, -1.0) as InputEvent).is_action(&"aim_up"), "the right stick aims (pad %d)" %
			device)
		check((axis.call(JOY_AXIS_TRIGGER_RIGHT, 1.0) as InputEvent).is_action(&"fire"), "the trigger fires (pad %d)" %
			device)
		check((button.call(JOY_BUTTON_RIGHT_SHOULDER) as InputEvent).is_action(&"tool"), "the bumper uses the tool (pad %d)" %
			device)
		check((button.call(JOY_BUTTON_START) as InputEvent).is_action(&"pause"), "Start pauses (pad %d)" % device)


func test_the_lamp_swings_round_smoothly() -> void:
	var aim := Vector2(1.0, 0.0)
	var target := Vector2(-1.0, 0.0)
	var dt := 1.0 / 60.0
	var steps := 0
	var went_over_the_top := false
	while aim.dot(target) < 0.999 and steps < 120:
		aim = Submarine.turn_towards(aim, target, Submarine.AIM_TURN_RATE * dt)
		went_over_the_top = went_over_the_top or aim.y > 0.5
		steps += 1
	check(steps > 5, "it does not jump (%d frames)" % steps)
	check(steps * dt < 0.4, "but it is quick (%.2f s)" % (steps * dt))
	check(went_over_the_top, "and sweeps over the top of the cave")
	# Back the other way, it swings over the top again.
	went_over_the_top = false
	for i in 60:
		aim = Submarine.turn_towards(aim, Vector2(1.0, 0.0), Submarine.AIM_TURN_RATE * dt)
		went_over_the_top = went_over_the_top or aim.y > 0.5
	check(went_over_the_top, "both ways")


func test_bumpers_step_through_tabs() -> void:
	for device: int in [0, 2]:
		var lb := InputEventJoypadButton.new()
		lb.device = device
		lb.button_index = JOY_BUTTON_LEFT_SHOULDER
		lb.pressed = true
		var rb := InputEventJoypadButton.new()
		rb.device = device
		rb.button_index = JOY_BUTTON_RIGHT_SHOULDER
		rb.pressed = true
		check(lb.is_action(&"ui_tab_prev"), "LB goes to the previous tab (pad %d)" % device)
		check(rb.is_action(&"ui_tab_next"), "RB goes to the next tab (pad %d)" % device)


func test_lost_focus_lands_on_the_frontmost_menu() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var host := Node.new()
	tree.root.add_child(host)
	var back := CanvasLayer.new()
	back.layer = 5
	host.add_child(back)
	var behind := Button.new()
	back.add_child(behind)
	var front := CanvasLayer.new()
	front.layer = 60
	host.add_child(front)
	var column := VBoxContainer.new()
	front.add_child(column)
	var off := Button.new()
	off.disabled = true
	column.add_child(off)
	var on := Button.new()
	column.add_child(on)
	check(FocusGuard.frontmost(tree.root) == on, "the panel on top, its first enabled button")
	front.visible = false
	check(FocusGuard.frontmost(tree.root) == behind, "a hidden panel is passed over")
	check_eq(FocusGuard.focusables(column).size(), 0, "nothing in a hidden panel is focusable")
	host.free()
