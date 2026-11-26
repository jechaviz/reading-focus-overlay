module main

import vraster

fn ui_kit(s f64) Kit {
	return new_kit(Theme{ s: s }) or { panic(err) }
}

fn test_dock_hit_map_is_consistent_at_every_scale() {
	for s in [1.0, 1.5, 2.0] {
		th := Theme{
			s: s
		}
		l := dock_layout(th)
		center := fn (r Rect) (int, int) {
			return r.x + r.w / 2, r.y + r.h / 2
		}
		x, y := center(l.seg[0])
		assert l.hit(x, y) == .seg_rect
		x2, y2 := center(l.seg[1])
		assert l.hit(x2, y2) == .seg_multi
		x3, y3 := center(l.seg[2])
		assert l.hit(x3, y3) == .seg_poly
		x4, y4 := center(l.undo)
		assert l.hit(x4, y4) == .undo
		x5, y5 := center(l.apply)
		assert l.hit(x5, y5) == .apply
		x6, y6 := center(l.close)
		assert l.hit(x6, y6) == .close
		x7, y7 := center(l.grip)
		assert l.hit(x7, y7) == .grip
		assert l.hit(l.card.x + l.card.w / 2, l.hint_cy) == .none
		// nothing overlaps: the title block never reaches the undo button
		assert l.title_x < l.undo.x
	}
}

fn test_dock_layout_scales_with_dpi() {
	a := dock_layout(Theme{ s: 1.0 })
	b := dock_layout(Theme{ s: 2.0 })
	assert b.cw > a.cw * 19 / 10 && b.cw < a.cw * 21 / 10
	assert b.card.h > a.card.h * 19 / 10
}

fn test_dock_render_paints_the_card_and_keeps_far_corners_clear() {
	k := ui_kit(1.0)
	ui := new_dock_ui(k.th)
	mut sel := Selection{}
	sel.toggle_focus()
	st := DockState{}
	cv := dock_render(&ui, &st, &sel, &k)
	assert cv.w == ui.lay.cw && cv.h == ui.lay.ch
	assert cv.at(ui.lay.card.x + ui.lay.card.w / 2, ui.lay.card.y + 6).a > 200
	assert cv.at(0, 0).a == 0
}

fn test_dock_apply_button_lights_up_only_when_applicable() {
	k := ui_kit(1.0)
	ui := new_dock_ui(k.th)
	mut sel := Selection{}
	sel.toggle_focus()
	sel.on_key(0x32, false)
	st := DockState{}
	idle := dock_render(&ui, &st, &sel, &k)
	drag(mut sel, Pt{0, 0}, Pt{50, 50})
	ready := dock_render(&ui, &st, &sel, &k)
	a := ui.lay.apply
	// the enabled button is filled with the accent colour, so its blue channel jumps
	assert ready.at(a.x + a.w - 6, a.y + a.h / 2).b > idle.at(a.x + a.w - 6, a.y + a.h / 2).b + 60
}

fn test_dock_hint_row_follows_the_mode() {
	assert dock_hints(.rect).len == 3
	assert dock_hints(.multi_rect).len == 4
	assert dock_hints(.polygon).len == 5
	assert dock_hints(.polygon)[1].key == 'Enter'
}

fn test_panel_hit_and_rows() {
	th := Theme{}
	l := panel_layout(th)
	for i in 0 .. 5 {
		r := l.rows[i]
		id := l.hit(r.x + 20, r.y + r.h / 2)
		assert int(id) == i + 1
		assert l.sw[i].x > r.x && l.sw[i].right() <= r.right()
	}
	assert l.hit(l.quit.x + 4, l.quit.y + 4) == .quit
	assert l.hit(l.edit.x + 4, l.edit.y + 4) == .edit
	assert l.hit(0, 0) == .none
}

fn test_panel_render_shows_switch_state() {
	k := ui_kit(1.0)
	ui := new_panel_ui(&k)
	mut st := PanelState{}
	rows := [PanelRow{'Focus frame', ['Ctrl', 'Shift', 'F'], .focus, true},
		PanelRow{'Pencil', ['Ctrl', 'Shift', 'R'], .pencil, false}, PanelRow{'a', [], .block, false},
		PanelRow{'b', [], .blur, false}, PanelRow{'c', [], .alttab, false}]
	st.sw[0].set(1.0)
	cv := panel_render(&ui, &st, rows, &k)
	on := cv.at(ui.lay.sw[0].x + 6, ui.lay.sw[0].y + ui.lay.sw[0].h / 2)
	off := cv.at(ui.lay.sw[1].x + 6, ui.lay.sw[1].y + ui.lay.sw[1].h / 2)
	assert on.b > off.b + 40 // accent track vs. grey track
}

fn test_toast_grows_with_its_text_and_uses_the_kind_colour() {
	k := ui_kit(1.0)
	short := toast_layout('On', &k)
	long := toast_layout('Taskbar blur is now switched on', &k)
	assert long.cw > short.cw + 60
	ok := toast_frame('Click-block ON', .on, &k)
	warn := toast_frame('Click-block ON', .warn, &k)
	lay := toast_layout('Click-block ON', &k)
	px := lay.card.x + k.th.px(14 + 14) // icon centre column
	py := lay.card.y + lay.card.h / 2
	// the icon halo takes the kind colour: green vs amber differ in the red channel
	assert warn.at(px, py - 9).r != ok.at(px, py - 9).r
}

fn test_tweens_ease_without_overshoot_and_settle() {
	mut t := Tween{}
	t.target = 1.0
	mut prev := 0.0
	mut frames := 0
	for t.step(0.016, 20) {
		assert t.cur >= prev && t.cur <= 1.0
		prev = t.cur
		frames++
		assert frames < 500
	}
	assert t.cur == 1.0
	assert frames > 3
}

fn test_kit_text_metrics_are_positive_and_scale() {
	k1 := ui_kit(1.0)
	k2 := ui_kit(2.0)
	assert k1.width('Apply', .semibold) > 20
	assert k2.width('Apply', .semibold) > k1.width('Apply', .semibold) * 3 / 2
}

fn test_text_is_vertically_centred_on_the_requested_line() {
	k := ui_kit(1.0)
	mut cv := vraster.new_canvas(80, 40)
	k.text_c(mut cv, 'HEH', .body, 40, 20, rgba(255, 255, 255, 255))
	mut top := 99
	mut bot := -1
	for y in 0 .. 40 {
		for x in 0 .. 80 {
			if cv.at(x, y).a > 128 {
				if y < top {
					top = y
				}
				if y > bot {
					bot = y
				}
			}
		}
	}
	assert bot > top
	centre := (top + bot) / 2
	assert centre >= 18 && centre <= 22
}

fn drag(mut s Selection, a Pt, b Pt) {
	s.mouse_down(a)
	s.mouse_move(b)
	s.mouse_up(b)
}

fn click(mut s Selection, x int, y int) {
	s.mouse_down(Pt{x, y})
	s.mouse_up(Pt{x, y})
}
