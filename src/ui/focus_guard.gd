class_name FocusGuard
extends Node
## Keeps keyboard and gamepad menus from ever losing their place. If a menu
## move or press arrives while nothing has focus (the focused button was
## rebuilt or freed, a panel closed), the press puts focus back on the
## frontmost menu's first button instead of doing nothing, so the pad can
## never be locked out of a menu. Panels opened with [method UiUtil.modal]
## also hand focus back to the button that opened them when they close.

## The menu actions that should always land on something.
const NAV: Array[StringName] = [&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_accept",
	&"ui_focus_next", &"ui_focus_prev"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if event is InputEventMouse or not event.is_pressed() or event.is_echo():
		return
	if not NAV.any(func(a: StringName) -> bool: return event.is_action_pressed(a)):
		return
	if has_focus_target(get_viewport()):
		return
	var target := frontmost(get_tree().root)
	if target:
		target.grab_focus()
		get_viewport().set_input_as_handled()


## True when something visible on [param viewport] holds the focus.
static func has_focus_target(viewport: Viewport) -> bool:
	var owner := viewport.gui_get_focus_owner()
	return owner != null and owner.is_visible_in_tree() and not owner.is_queued_for_deletion()


## The control a lost focus should go to: on the frontmost canvas layer that
## has one, its first focusable control in tree order (an enabled one before
## a disabled one). Null when no menu is showing.
static func frontmost(root: Node) -> Control:
	var best: Control = null
	var best_rank := -INF
	var stack: Array[Node] = [root]
	var order := 0
	var found: Array = []
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.is_queued_for_deletion():
			continue
		if n is CanvasItem and not (n as CanvasItem).visible:
			continue
		if n is CanvasLayer and not (n as CanvasLayer).visible:
			continue
		if n is Control and focusable(n as Control):
			found.append([n, order])
		order += 1
		var kids := n.get_children()
		for i in range(kids.size() - 1, -1, -1):
			stack.append(kids[i])
	for f: Array in found:
		var c: Control = f[0]
		var layer := c.get_canvas_layer_node()
		var disabled := c is BaseButton and (c as BaseButton).disabled
		# Frontmost layer first, then enabled before disabled, then tree order.
		var rank: float = (layer.layer if layer else 0) * 1e7 - (5e6 if disabled else 0.0) - float(f[1])
		if rank > best_rank:
			best_rank = rank
			best = c
	return best


## Whether [param c] is a control a menu can move focus onto.
static func focusable(c: Control) -> bool:
	return c.focus_mode == Control.FOCUS_ALL and c.is_visible_in_tree() and not c.is_queued_for_deletion() \
		and (c is BaseButton or c is Range or c is LineEdit)


## The focusable controls under [param node], in tree order.
static func focusables(node: Node) -> Array[Control]:
	var out: Array[Control] = []
	for c in node.get_children():
		if c.is_queued_for_deletion():
			continue
		if c is Control and focusable(c as Control):
			out.append(c as Control)
		out.append_array(focusables(c))
	return out
