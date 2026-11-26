module main

import math

// Tween eases a value toward a target with exponential smoothing: it never
// overshoots, reacts instantly to a new target and needs no duration book-keeping.
struct Tween {
mut:
	cur    f64
	target f64
}

fn (mut t Tween) set(v f64) {
	t.cur = v
	t.target = v
}

// step advances by dt seconds; it reports whether the value changed, so callers
// know when another frame must be drawn.
fn (mut t Tween) step(dt f64, speed f64) bool {
	d := t.target - t.cur
	if math.abs(d) < 0.002 {
		changed := t.cur != t.target
		t.cur = t.target
		return changed
	}
	t.cur += d * (1.0 - math.exp(-speed * dt))
	return true
}

fn (t &Tween) idle() bool {
	return t.cur == t.target
}

fn ease_out_cubic(t f64) f64 {
	k := 1.0 - clamp_f(t, 0, 1)
	return 1.0 - k * k * k
}
