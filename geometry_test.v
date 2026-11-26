module main

fn test_rect_from_points_normalizes_any_direction() {
	a := Pt{100, 80}
	b := Pt{40, 120}
	r := rect_from_points(a, b)
	assert r == Rect{40, 80, 60, 40}
	assert rect_from_points(b, a) == r
}

fn test_near_is_strict_on_both_axes() {
	assert near(Pt{0, 0}, Pt{9, 9}, 10)
	assert !near(Pt{0, 0}, Pt{10, 0}, 10)
	assert !near(Pt{0, 0}, Pt{0, 10}, 10)
}

fn test_bbox_polygons_skips_degenerate() {
	polys := [
		[Pt{10, 10}, Pt{50, 10}, Pt{30, 40}],
		[Pt{1, 1}, Pt{2, 2}], // < 3 vertices, ignored
		[Pt{60, 5}, Pt{90, 70}, Pt{70, 80}],
	]
	b := bbox_polygons(polys) or { panic('expected a box') }
	assert b == Rect{10, 5, 80, 75}
	if _ := bbox_polygons([[Pt{0, 0}, Pt{1, 1}]]) {
		assert false
	}
}

fn test_bbox_rects_union() {
	b := bbox_rects([Rect{0, 0, 10, 10}, Rect{20, 30, 5, 5}]) or { panic('none') }
	assert b == Rect{0, 0, 25, 35}
	if _ := bbox_rects([]) {
		assert false
	}
}

fn test_fit_max_edge_keeps_aspect() {
	w, h := fit_max_edge(600, 300, 300)
	assert w == 300 && h == 150
	w2, h2 := fit_max_edge(100, 400, 300)
	assert w2 == 75 && h2 == 300
}
