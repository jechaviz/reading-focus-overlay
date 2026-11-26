module main

// Pure geometry used by the focus-frame selection logic. No platform code here
// so every rule (minimum sizes, polygon closing radius, bounding boxes) can be
// unit-tested without a desktop.

struct Pt {
mut:
	x int
	y int
}

struct Rect {
mut:
	x int
	y int
	w int
	h int
}

fn min_i(a int, b int) int {
	return if a < b { a } else { b }
}

fn max_i(a int, b int) int {
	return if a > b { a } else { b }
}

fn abs_i(a int) int {
	return if a < 0 { -a } else { a }
}

fn clamp_i(v int, lo int, hi int) int {
	return max_i(lo, min_i(hi, v))
}

// rect_from_points builds the normalized rectangle spanned by two corners,
// whatever the drag direction was.
fn rect_from_points(a Pt, b Pt) Rect {
	return Rect{
		x: min_i(a.x, b.x)
		y: min_i(a.y, b.y)
		w: abs_i(b.x - a.x)
		h: abs_i(b.y - a.y)
	}
}

fn (r Rect) at_least(min_w int, min_h int) bool {
	return r.w >= min_w && r.h >= min_h
}

fn (r Rect) is_empty() bool {
	return r.w <= 0 || r.h <= 0
}

fn (r Rect) right() int {
	return r.x + r.w
}

fn (r Rect) bottom() int {
	return r.y + r.h
}

fn (r Rect) contains(p Pt) bool {
	return p.x >= r.x && p.x < r.right() && p.y >= r.y && p.y < r.bottom()
}

// near reports whether both axes are strictly closer than tol pixels. The
// original script used 10 px to snap-close a polygon on its first vertex.
fn near(a Pt, b Pt, tol int) bool {
	return abs_i(a.x - b.x) < tol && abs_i(a.y - b.y) < tol
}

// bbox_polygons returns the union bounding box of every polygon with at least
// three vertices; none when there is nothing valid.
fn bbox_polygons(polys [][]Pt) ?Rect {
	mut have := false
	mut min_x := 0
	mut min_y := 0
	mut max_x := 0
	mut max_y := 0
	for poly in polys {
		if poly.len < 3 {
			continue
		}
		for p in poly {
			if !have {
				min_x, max_x, min_y, max_y = p.x, p.x, p.y, p.y
				have = true
				continue
			}
			min_x = min_i(min_x, p.x)
			max_x = max_i(max_x, p.x)
			min_y = min_i(min_y, p.y)
			max_y = max_i(max_y, p.y)
		}
	}
	if !have {
		return none
	}
	return Rect{
		x: min_x
		y: min_y
		w: max_x - min_x
		h: max_y - min_y
	}
}

fn bbox_rects(rects []Rect) ?Rect {
	if rects.len == 0 {
		return none
	}
	mut min_x := rects[0].x
	mut min_y := rects[0].y
	mut max_x := rects[0].right()
	mut max_y := rects[0].bottom()
	for r in rects[1..] {
		min_x = min_i(min_x, r.x)
		min_y = min_i(min_y, r.y)
		max_x = max_i(max_x, r.right())
		max_y = max_i(max_y, r.bottom())
	}
	return Rect{
		x: min_x
		y: min_y
		w: max_x - min_x
		h: max_y - min_y
	}
}

fn (r Rect) inflate(d int) Rect {
	return Rect{r.x - d, r.y - d, r.w + 2 * d, r.h + 2 * d}
}
