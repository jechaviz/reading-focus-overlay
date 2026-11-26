module main

// Focus-frame state machine. It is the pure-V replacement for the ~1800 lines
// of GUI juggling in focus_frame.ahk: no windows, hooks or timers live here,
// only the rules (what a click, key or toggle does). The Win32 layer feeds
// events in; scene.v turns the state into pixels.

const vk_back = u32(0x08)
const vk_return = u32(0x0D)
const vk_escape = u32(0x1B)
const vk_space = u32(0x20)

const min_commit_size = 4 // a drag smaller than this is an accidental click
const min_preview_size = 2
const close_radius = 10 // click this close to the first vertex to close a polygon

enum Mode {
	rect
	multi_rect
	polygon
}

fn (m Mode) label() string {
	return match m {
		.rect { 'rectangle' }
		.multi_rect { 'multi-rectangle' }
		.polygon { 'polygon' }
	}
}

struct Style {
mut:
	dim_drag  int = 120 // overlay alpha while selecting (0-255)
	dim_final int = 225 // overlay alpha once the frame is set (0-255)
}

struct Selection {
mut:
	mode       Mode = .rect
	active     bool // selection (snip) mode is running
	have_frame bool // a finished selection exists
	dim_shown  bool
	dragging   bool
	drag_start Pt
	drag_cur   Pt
	cur_poly   []Pt
	polys      [][]Pt
	rects      []Rect
	frame      Rect // bounding box of the finished selection
}

fn (mut s Selection) clear_shapes() {
	s.dragging = false
	s.cur_poly = []
	s.polys = [][]Pt{}
	s.rects = []Rect{}
	s.frame = Rect{}
}

// toggle_focus is the Ctrl+Shift+F behaviour: start selecting the first time,
// afterwards flip the dimmer on and off keeping the chosen area.
fn (mut s Selection) toggle_focus() {
	if s.active {
		return
	}
	if !s.have_frame {
		s.mode = .rect
		s.begin()
		return
	}
	s.dim_shown = !s.dim_shown
}

fn (mut s Selection) begin() {
	if s.active {
		return
	}
	s.clear_shapes()
	s.active = true
	s.have_frame = false
	s.dim_shown = true
}

// cancel leaves selection mode and removes the dimmer completely.
fn (mut s Selection) cancel() {
	if !s.active {
		return
	}
	s.active = false
	s.have_frame = false
	s.dim_shown = false
	s.clear_shapes()
}

// reselect is Shift+Esc: abort a running selection, or throw away the current
// frame and start a new one (always back in rectangle mode).
fn (mut s Selection) reselect() {
	if s.active {
		s.cancel()
		return
	}
	if s.dim_shown || s.have_frame {
		s.clear_shapes()
		s.have_frame = false
		s.mode = .rect
		s.begin()
	}
}

fn (mut s Selection) set_mode(m Mode) {
	if !s.active {
		return
	}
	s.mode = m
	s.clear_shapes()
	s.have_frame = false
}

fn (mut s Selection) finalize() {
	mut bounds := []Rect{}
	for r in s.rects {
		bounds << r
	}
	if pb := bbox_polygons(s.polys) {
		bounds << pb
	}
	s.frame = bbox_rects(bounds) or { Rect{} }
	s.dragging = false
	s.cur_poly = []
	s.active = false
	s.have_frame = true
	s.dim_shown = true
}

fn (mut s Selection) finish_current_polygon() {
	if s.cur_poly.len >= 3 {
		s.polys << s.cur_poly.clone()
	}
	s.cur_poly = []
}

// can_undo / can_apply / undo / apply back both the keyboard shortcuts and the
// dock buttons, so the two input paths cannot drift apart.
fn (s &Selection) can_undo() bool {
	if !s.active {
		return false
	}
	return match s.mode {
		.rect { false }
		.multi_rect { s.rects.len > 0 }
		.polygon { s.cur_poly.len > 0 || s.polys.len > 0 }
	}
}

fn (s &Selection) can_apply() bool {
	if !s.active {
		return false
	}
	return match s.mode {
		.rect { false }
		.multi_rect { s.rects.len > 0 }
		.polygon { s.polys.len > 0 || s.cur_poly.len >= 3 }
	}
}

// undo removes the last vertex, polygon or rectangle. last_shape forces the
// polygon variant that drops a whole polygon (Shift+Backspace).
fn (mut s Selection) undo(last_shape bool) {
	match s.mode {
		.polygon {
			if !last_shape && s.cur_poly.len > 0 {
				s.cur_poly.delete_last()
			} else if s.polys.len > 0 {
				s.polys.delete_last()
			}
		}
		.multi_rect {
			if s.rects.len > 0 {
				s.rects.delete_last()
			}
		}
		.rect {}
	}
}

fn (mut s Selection) apply() {
	if !s.can_apply() {
		return
	}
	if s.mode == .polygon {
		s.finish_current_polygon()
	}
	s.finalize()
}

fn (mut s Selection) mouse_down(p Pt) {
	if !s.active {
		return
	}
	match s.mode {
		.rect, .multi_rect {
			s.dragging = true
			s.drag_start = p
			s.drag_cur = p
		}
		.polygon {
			if s.cur_poly.len >= 3 && near(p, s.cur_poly[0], close_radius) {
				s.finish_current_polygon()
				return
			}
			if s.cur_poly.len > 0 && near(p, s.cur_poly[s.cur_poly.len - 1], 2) {
				return // ignore double-click duplicates
			}
			s.cur_poly << p
		}
	}
}

fn (mut s Selection) mouse_move(p Pt) {
	if s.active && s.dragging {
		s.drag_cur = p
	}
}

fn (mut s Selection) mouse_up(p Pt) {
	if !s.active || !s.dragging {
		return
	}
	s.drag_cur = p
	s.dragging = false
	r := rect_from_points(s.drag_start, p)
	if !r.at_least(min_commit_size, min_commit_size) {
		return // accidental click: stay in selection mode
	}
	match s.mode {
		.rect {
			s.rects = [r]
			s.finalize()
		}
		.multi_rect {
			s.rects << r
		}
		.polygon {}
	}
}

// wants_key tells the keyboard hook whether a key press belongs to selection
// mode (and must therefore be swallowed). Esc with Shift is left alone because
// it is the global Re-select hotkey.
fn (s &Selection) wants_key(vk u32, shift bool, ctrl_or_alt bool) bool {
	if !s.active || ctrl_or_alt {
		return false
	}
	match vk {
		vk_escape {
			return !shift
		}
		0x31...0x34, 0x61...0x64 {
			return true
		}
		vk_return {
			return s.mode != .rect
		}
		vk_space {
			return s.mode == .polygon
		}
		vk_back {
			return s.mode != .rect
		}
		else {
			return false
		}
	}
}

fn (mut s Selection) on_key(vk u32, shift bool) {
	if !s.active {
		return
	}
	match vk {
		vk_escape {
			s.cancel()
		}
		0x31, 0x61 {
			s.set_mode(.rect)
		}
		0x32, 0x62 {
			s.set_mode(.multi_rect)
		}
		0x33, 0x63 {
			s.set_mode(.polygon)
		}
		0x34, 0x64 {
			s.cancel()
		}
		vk_return {
			match s.mode {
				.polygon { s.finish_current_polygon() } // close this shape, keep selecting
				.multi_rect { s.apply() }
				.rect {}
			}
		}
		vk_space {
			if s.mode == .polygon {
				s.apply()
			}
		}
		vk_back {
			s.undo(shift)
		}
		else {}
	}
}

// preview_rect is the rectangle currently being dragged, if big enough to show.
fn (s &Selection) preview_rect() ?Rect {
	if !s.active || !s.dragging || s.mode == .polygon {
		return none
	}
	r := rect_from_points(s.drag_start, s.drag_cur)
	if !r.at_least(min_preview_size, min_preview_size) {
		return none
	}
	return r
}
