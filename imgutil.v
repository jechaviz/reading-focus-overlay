module main

import math

// Small image helpers for the pencil sprite.

// premultiply_rgba converts straight RGBA8888 to premultiplied in place.
fn premultiply_rgba(mut px []u8) {
	for i := 0; i + 3 < px.len; i += 4 {
		a := int(px[i + 3])
		px[i] = u8((int(px[i]) * a + 127) / 255)
		px[i + 1] = u8((int(px[i + 1]) * a + 127) / 255)
		px[i + 2] = u8((int(px[i + 2]) * a + 127) / 255)
	}
}

// resize_premul scales premultiplied RGBA8888 bilinearly (correct for alpha edges because the colour
// channels are already weighted by coverage).
fn resize_premul(src []u8, sw int, sh int, dw int, dh int) []u8 {
	mut out := []u8{len: dw * dh * 4}
	if sw <= 0 || sh <= 0 || dw <= 0 || dh <= 0 {
		return out
	}
	for y in 0 .. dh {
		fy := (f64(y) + 0.5) * f64(sh) / f64(dh) - 0.5
		y0 := clamp_i(int(math.floor(fy)), 0, sh - 1)
		y1 := clamp_i(y0 + 1, 0, sh - 1)
		ty := clamp_f(fy - f64(y0), 0, 1)
		for x in 0 .. dw {
			fx := (f64(x) + 0.5) * f64(sw) / f64(dw) - 0.5
			x0 := clamp_i(int(math.floor(fx)), 0, sw - 1)
			x1 := clamp_i(x0 + 1, 0, sw - 1)
			tx := clamp_f(fx - f64(x0), 0, 1)
			for c in 0 .. 4 {
				p00 := f64(src[(y0 * sw + x0) * 4 + c])
				p10 := f64(src[(y0 * sw + x1) * 4 + c])
				p01 := f64(src[(y1 * sw + x0) * 4 + c])
				p11 := f64(src[(y1 * sw + x1) * 4 + c])
				top := p00 + (p10 - p00) * tx
				bot := p01 + (p11 - p01) * tx
				out[(y * dw + x) * 4 + c] = u8(clamp_i(int(top + (bot - top) * ty + 0.5), 0, 255))
			}
		}
	}
	return out
}

// fit_max_edge keeps the aspect ratio so the longest edge equals max_edge.
fn fit_max_edge(w int, h int, max_edge int) (int, int) {
	if w <= 0 || h <= 0 {
		return 0, 0
	}
	if w > h {
		return max_edge, max_i(1, int(f64(max_edge) * f64(h) / f64(w) + 0.5))
	}
	return max_i(1, int(f64(max_edge) * f64(w) / f64(h) + 0.5)), max_edge
}
