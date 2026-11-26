module main

import vraster

fn scene_kit() Kit {
	return new_kit(Theme{}) or { panic(err) }
}

fn scene_with(mut s Selection, dim f64) (vraster.Canvas, vraster.Mask) {
	k := scene_kit()
	mut cv := vraster.new_canvas(120, 120)
	mut mask := vraster.new_mask(0, 0, 120, 120)
	s.compose(mut cv, mut mask, Visuals{ dim: dim }, &k)
	return cv, mask
}

fn test_final_rect_has_clickthrough_hole_and_dim_elsewhere() {
	mut s := Selection{}
	s.toggle_focus()
	drag(mut s, Pt{20, 20}, Pt{80, 80})
	cv, _ := scene_with(mut s, 225)
	assert cv.at(50, 50).a == 0 // hole is fully transparent (click-through)
	assert cv.at(5, 5).a == 225
	assert cv.at(110, 110).a == 225
}

fn test_selecting_keeps_hole_hittable_and_draws_the_ring() {
	mut s := Selection{}
	s.toggle_focus()
	s.mouse_down(Pt{20, 20})
	s.mouse_move(Pt{80, 80})
	cv, _ := scene_with(mut s, 120)
	assert cv.at(50, 50).a >= 1 // never 0 while selecting: stays hittable
	assert cv.at(50, 50).a < 20
	ring := cv.at(50, 20) // top edge of the preview rectangle
	assert ring.a > 200
	assert cv.at(5, 5).a >= 120
}

fn test_polygon_hole_after_apply() {
	mut s := Selection{}
	s.toggle_focus()
	s.on_key(0x33, false)
	click(mut s, 10, 10)
	click(mut s, 100, 10)
	click(mut s, 55, 100)
	s.on_key(vk_space, false)
	cv, _ := scene_with(mut s, 225)
	assert cv.at(55, 30).a == 0
	assert cv.at(5, 110).a == 225
}

fn test_dim_level_zero_removes_the_dim_but_final_state_stays_clickthrough() {
	mut s := Selection{}
	s.toggle_focus()
	drag(mut s, Pt{20, 20}, Pt{80, 80})
	cv, _ := scene_with(mut s, 0)
	assert cv.at(5, 5).a == 0
}

fn test_polygon_in_progress_previews_its_hole_live() {
	mut s := Selection{}
	s.toggle_focus()
	s.on_key(0x33, false)
	click(mut s, 10, 10)
	click(mut s, 100, 10)
	click(mut s, 55, 100)
	cv, _ := scene_with(mut s, 150)
	assert cv.at(55, 30).a < 40 // already see-through while still drawing
}

fn test_commit_pulse_draws_outside_the_frame() {
	mut s := Selection{}
	s.toggle_focus()
	drag(mut s, Pt{40, 40}, Pt{80, 80})
	k := scene_kit()
	mut with_pulse := vraster.new_canvas(120, 120)
	mut mask := vraster.new_mask(0, 0, 120, 120)
	s.compose(mut with_pulse, mut mask, Visuals{ dim: 225, pulse: 0.2 }, &k)
	mut without := vraster.new_canvas(120, 120)
	s.compose(mut without, mut mask, Visuals{ dim: 225 }, &k)
	mut differs := false
	for i in 0 .. with_pulse.px.len {
		if with_pulse.px[i] != without.px[i] {
			differs = true
			break
		}
	}
	assert differs
}

fn test_to_pt2_preserves_order() {
	p := to_pt2([Pt{1, 2}, Pt{3, 4}])
	assert p.len == 2 && p[1].x == 3.0 && p[1].y == 4.0
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
