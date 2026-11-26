module main

import math
import vraster

// Scene composition: turns the Selection state into the pixels of the full-screen overlay (dim
// layer with soft holes, accent outlines, rubber band, dimension badge, cursor guides, commit
// pulse). Pure V, no OS calls.

struct Visuals {
mut:
	dim         f64 // current dim alpha, 0..255 (animated by the caller)
	fade        f64 = 1.0 // overall opacity of the guides, 0..1
	t_ms        int // monotonic clock for marching dashes and pulses
	cursor      Pt
	have_cursor bool
	pulse       f64 = -1.0 // commit pulse progress 0..1, negative = none
}

fn to_pt2(pts []Pt) []vraster.Pt2 {
	mut out := []vraster.Pt2{cap: pts.len}
	for p in pts {
		out << vraster.Pt2{f64(p.x), f64(p.y)}
	}
	return out
}

fn badge_width(text string, k &Kit) int {
	return k.width(text, .badge) + k.th.px(22)
}

// draw_badge paints a dark pill with text, centred on cx, top edge at top.
fn draw_badge(mut cv vraster.Canvas, k &Kit, text string, cx int, top int, fa f64) {
	th := k.th
	w := badge_width(text, k)
	h := th.px(26)
	x := clamp_i(cx - w / 2, 8, max_i(8, cv.w - w - 8))
	y := clamp_i(top, 8, max_i(8, cv.h - h - 8))
	cv.drop_shadow(x, y, w, h, h / 2, th.px(5), th.px(3), rgba(0, 0, 0, int(120.0 * fa)))
	cv.fill_round_rect(x, y, w, h, h / 2, rgba(20, 22, 32, int(240.0 * fa)))
	cv.stroke_round_rect(x, y, w, h, h / 2, 1, rgba(255, 255, 255, int(48.0 * fa)))
	k.text_c(mut cv, text, .badge, x + w / 2, y + h / 2, rgba(240, 242, 249, int(255.0 * fa)))
}

@[direct_array_access]
fn fill_dim(mut cv vraster.Canvas, mask &vraster.Mask, dim f64, floor_a int) {
	mut lut := []u8{len: 256}
	for c in 0 .. 256 {
		a := int(dim * f64(255 - c) / 255.0 + 0.5)
		lut[c] = u8(max_i(a, floor_a))
	}
	n := min_i(cv.w * cv.h, mask.cov.len)
	for i in 0 .. n {
		j := i * 4
		cv.px[j] = 0
		cv.px[j + 1] = 0
		cv.px[j + 2] = 0
		cv.px[j + 3] = lut[mask.cov[i]]
	}
}

fn (s &Selection) compose(mut cv vraster.Canvas, mut mask vraster.Mask, v Visuals, k &Kit) {
	th := k.th
	pal := palette()
	fa := clamp_f(v.fade, 0, 1)
	rad := th.px(10)
	preview := s.preview_rect()

	// 1. hole coverage: finished shapes, the drag preview and the polygon being drawn
	mask.clear()
	for r in s.rects {
		mask.add_round_rect(r.x, r.y, r.w, r.h, rad)
	}
	if p := preview {
		mask.add_round_rect(p.x, p.y, p.w, p.h, rad)
	}
	for poly in s.polys {
		mask.add_polygon(to_pt2(poly))
	}
	if s.active && s.cur_poly.len >= 3 {
		mask.add_polygon(to_pt2(s.cur_poly))
	}

	// 2. dim layer. While selecting every pixel keeps alpha >= 1 so the layered window stays
	// hittable; the final holes are fully transparent (click-through).
	fill_dim(mut cv, mask, v.dim, if s.active { 1 } else { 0 })

	// 3. outlines of finished and in-progress shapes
	mut outlines := s.rects.clone()
	if p := preview {
		outlines << p
	}
	ring_a := if s.active { 255 } else { 175 }
	glow_a := if s.active { 100 } else { 64 }
	ring_t := if s.active { th.px(2) } else { max_i(1, th.px(1.6)) }
	ring_col := th.acc(int(f64(ring_a) * fa))
	for r in outlines {
		cv.glow_round_rect(r.x, r.y, r.w, r.h, rad, th.f(22), th.acc(int(f64(glow_a) * fa)), true)
		cv.stroke_round_rect(r.x, r.y, r.w, r.h, rad, ring_t, ring_col)
	}
	white := vraster.with_alpha(pal.white, fa)
	for poly in s.polys {
		cv.stroke_polyline(to_pt2(poly), f64(ring_t), ring_col, true)
		if s.active {
			for p in poly {
				cv.fill_circle_f(f64(p.x), f64(p.y), th.f(4), white)
				cv.stroke_circle(f64(p.x), f64(p.y), th.f(4), th.f(1.6), ring_col)
			}
		}
	}

	if s.active && s.cur_poly.len > 0 {
		cur_col := th.acc(int(255.0 * fa))
		cv.stroke_polyline(to_pt2(s.cur_poly), th.f(2), cur_col, false)
		if v.have_cursor {
			last := s.cur_poly[s.cur_poly.len - 1]
			cv.line_dashed(f64(last.x), f64(last.y), f64(v.cursor.x), f64(v.cursor.y), th.f(1.6),
				th.f(6), th.f(5), f64(v.t_ms) * 0.03, th.acc(int(210.0 * fa)))
		}
		if s.cur_poly.len >= 3 {
			first := s.cur_poly[0]
			pulse := 0.5 + 0.5 * math.sin(f64(v.t_ms) * 0.008)
			hot := v.have_cursor && near(v.cursor, first, close_radius)
			cv.stroke_circle(f64(first.x), f64(first.y), th.f(f64(close_radius) + 2.0 + 2.0 * pulse),
				th.f(1.5), th.acc(int((90.0 + 110.0 * pulse) * fa)))
			if hot {
				cv.fill_circle_f(f64(first.x), f64(first.y), th.f(7), cur_col)
			}
		}
		for p in s.cur_poly {
			cv.fill_circle_f(f64(p.x), f64(p.y), th.f(4.6), white)
			cv.stroke_circle(f64(p.x), f64(p.y), th.f(4.6), th.f(1.8), cur_col)
		}
	}

	// 4. cursor guides and live readouts
	if s.active && v.have_cursor {
		if !s.dragging {
			guide := rgba(255, 255, 255, int(36.0 * fa))
			cv.fill_rect(0, v.cursor.y, cv.w, 1, guide)
			cv.fill_rect(v.cursor.x, 0, 1, cv.h, guide)
			label := '${v.cursor.x}, ${v.cursor.y}'
			bw := badge_width(label, k)
			draw_badge(mut cv, k, label, v.cursor.x + th.px(18) + bw / 2, v.cursor.y + th.px(22),
				fa)
		}
		if p := preview {
			label := '${p.w} × ${p.h}'
			below := p.bottom() + th.px(12)
			top := if below + th.px(26) + 8 > cv.h { p.y - th.px(26) - th.px(12) } else { below }
			draw_badge(mut cv, k, label, p.x + p.w / 2, top, fa)
		}
	}

	// 5. commit pulse: a ring that expands from the new frame and fades out
	if v.pulse >= 0.0 && v.pulse < 1.0 && s.have_frame && !s.active && !s.frame.is_empty() {
		grow := int(th.f(26) * ease_out_cubic(v.pulse))
		alpha := (1.0 - v.pulse) * 190.0 * fa
		f := s.frame.inflate(grow)
		cv.stroke_round_rect(f.x, f.y, f.w, f.h, rad + grow, th.px(2.5), th.acc(int(alpha)))
	}
}
