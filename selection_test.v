module main

fn drag(mut s Selection, a Pt, b Pt) {
	s.mouse_down(a)
	s.mouse_move(b)
	s.mouse_up(b)
}

fn click(mut s Selection, x int, y int) {
	s.mouse_down(Pt{x, y})
	s.mouse_up(Pt{x, y})
}

fn test_toggle_first_press_starts_selection_then_flips_dimmer() {
	mut s := Selection{}
	s.toggle_focus()
	assert s.active && s.dim_shown && !s.have_frame
	s.toggle_focus() // ignored while selecting
	assert s.active && s.dim_shown
	drag(mut s, Pt{10, 10}, Pt{200, 120})
	assert !s.active && s.have_frame && s.dim_shown
	assert s.frame == Rect{10, 10, 190, 110}
	s.toggle_focus()
	assert !s.dim_shown && s.have_frame
	s.toggle_focus()
	assert s.dim_shown
}

fn test_tiny_drag_does_not_commit_or_cancel() {
	mut s := Selection{}
	s.toggle_focus()
	drag(mut s, Pt{50, 50}, Pt{52, 52})
	assert s.active && !s.have_frame
}

fn test_esc_cancels_and_clears_everything() {
	mut s := Selection{}
	s.toggle_focus()
	s.on_key(vk_escape, false)
	assert !s.active && !s.dim_shown && !s.have_frame
}

fn test_reselect_resets_to_rect_mode() {
	mut s := Selection{}
	s.toggle_focus()
	drag(mut s, Pt{0, 0}, Pt{100, 100})
	s.reselect()
	assert s.active && s.mode == .rect && !s.have_frame && s.dim_shown
	s.reselect() // while selecting: aborts
	assert !s.active && !s.dim_shown
}

fn test_number_keys_switch_modes_and_four_cancels() {
	mut s := Selection{}
	s.toggle_focus()
	s.on_key(0x32, false)
	assert s.mode == .multi_rect
	s.on_key(0x33, false)
	assert s.mode == .polygon
	s.on_key(0x31, false)
	assert s.mode == .rect
	s.on_key(0x34, false)
	assert !s.active
}

fn test_multi_rect_collects_then_enter_finalizes() {
	mut s := Selection{}
	s.toggle_focus()
	s.on_key(0x32, false)
	drag(mut s, Pt{0, 0}, Pt{50, 50})
	drag(mut s, Pt{100, 100}, Pt{160, 130})
	assert s.active && s.rects.len == 2
	s.on_key(vk_back, false)
	assert s.rects.len == 1
	drag(mut s, Pt{200, 10}, Pt{260, 60})
	s.on_key(vk_return, false)
	assert !s.active && s.have_frame
	assert s.frame == Rect{0, 0, 260, 60}
}

fn test_polygon_enter_space_backspace_flow() {
	mut s := Selection{}
	s.toggle_focus()
	s.on_key(0x33, false)
	click(mut s, 10, 10)
	click(mut s, 100, 10)
	click(mut s, 60, 80)
	s.on_key(vk_return, false) // closes first polygon
	assert s.polys.len == 1 && s.cur_poly.len == 0
	click(mut s, 200, 200)
	click(mut s, 300, 200)
	click(mut s, 250, 300)
	s.on_key(vk_return, false)
	assert s.polys.len == 2
	s.on_key(vk_back, true) // Shift+Backspace drops the last polygon
	assert s.polys.len == 1
	click(mut s, 400, 400)
	s.on_key(vk_back, false) // plain Backspace drops the in-progress point
	assert s.cur_poly.len == 0 && s.polys.len == 1
	s.on_key(vk_space, false)
	assert !s.active && s.have_frame
	assert s.frame == Rect{10, 10, 90, 70}
}

fn test_polygon_closes_by_clicking_first_vertex() {
	mut s := Selection{}
	s.toggle_focus()
	s.on_key(0x33, false)
	click(mut s, 10, 10)
	click(mut s, 100, 10)
	click(mut s, 60, 80)
	click(mut s, 14, 13) // within 10 px of the first vertex
	assert s.polys.len == 1 && s.polys[0].len == 3 && s.cur_poly.len == 0
}

fn test_space_without_polygon_does_nothing() {
	mut s := Selection{}
	s.toggle_focus()
	s.on_key(0x33, false)
	s.on_key(vk_space, false)
	assert s.active && !s.have_frame
}

fn test_wants_key_matrix() {
	mut s := Selection{}
	assert !s.wants_key(vk_escape, false, false) // inactive: never swallow
	s.toggle_focus()
	assert s.wants_key(vk_escape, false, false)
	assert !s.wants_key(vk_escape, true, false) // Shift+Esc is the global hotkey
	assert s.wants_key(0x31, false, false)
	assert !s.wants_key(0x31, false, true) // Ctrl/Alt+1 belongs to the app
	assert !s.wants_key(vk_return, false, false) // rect mode has no Enter action
	assert !s.wants_key(vk_space, false, false)
	s.on_key(0x33, false)
	assert s.wants_key(vk_return, false, false)
	assert s.wants_key(vk_space, false, false)
	assert s.wants_key(vk_back, false, false)
}

fn test_undo_and_apply_back_the_dock_buttons() {
	mut s := Selection{}
	s.toggle_focus()
	assert !s.can_undo() && !s.can_apply() // rectangle mode has neither
	s.on_key(0x32, false)
	assert !s.can_undo() && !s.can_apply()
	drag(mut s, Pt{0, 0}, Pt{50, 50})
	assert s.can_undo() && s.can_apply()
	s.undo(false)
	assert s.rects.len == 0
	drag(mut s, Pt{0, 0}, Pt{50, 50})
	s.apply()
	assert !s.active && s.have_frame
}

fn test_polygon_apply_needs_three_points() {
	mut s := Selection{}
	s.toggle_focus()
	s.on_key(0x33, false)
	click(mut s, 10, 10)
	click(mut s, 100, 10)
	assert s.can_undo() && !s.can_apply()
	click(mut s, 60, 80)
	assert s.can_apply()
	s.apply()
	assert s.have_frame && s.polys.len == 1
}
