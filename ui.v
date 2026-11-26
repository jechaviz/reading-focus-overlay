module main

import vraster

// UI components - the selection dock, the tray control panel and toasts - built on vraster
// (shapes, shadows) and vfonts (text/icons). Pure V: layouts, hit-tests and rendering can all be
// exercised without a desktop. Static parts (shadow, glass, dividers) are rendered once into a base
// canvas; each frame clones it and only draws the animated content on top.

fn glass_base(cw int, ch int, card Rect, th Theme) vraster.Canvas {
	pal := palette()
	mut cv := vraster.new_canvas(cw, ch)
	rad := th.px(20)
	cv.drop_shadow(card.x, card.y, card.w, card.h, rad, th.px(13), th.px(10), pal.shadow)
	cv.drop_shadow(card.x, card.y, card.w, card.h, rad, th.px(4), th.px(2), pal.shadow_lo)
	cv.fill_round_rect_vgradient(card.x, card.y, card.w, card.h, rad, pal.glass_top, pal.glass_bot)
	cv.stroke_round_rect(card.x, card.y, card.w, card.h, rad, 1, pal.border)
	// a faint top highlight gives the glass its edge light
	cv.fill_rect(card.x + th.px(16), card.y + 1, card.w - th.px(32), 1, rgba(255, 255, 255, 44))
	return cv
}

fn draw_keycap(mut cv vraster.Canvas, k &Kit, x int, cy int, text string) int {
	pal := palette()
	th := k.th
	tw := k.width(text, .key)
	w := if tw + th.px(14) > th.px(24) { tw + th.px(14) } else { th.px(24) }
	h := th.px(22)
	y := cy - h / 2
	rad := th.px(6)
	cv.fill_round_rect_vgradient(x, y, w, h, rad, pal.key_top, pal.key_bot)
	cv.stroke_round_rect(x, y, w, h, rad, 1, pal.key_bd)
	k.text_c(mut cv, text, .key, x + w / 2, cy, pal.text)
	return w
}

fn draw_logo(mut cv vraster.Canvas, r Rect, k &Kit) {
	th := k.th
	rad := int(f64(r.w) * 0.3)
	cv.glow_round_rect(r.x, r.y, r.w, r.h, rad, th.f(10), th.acc(80), false)
	cv.fill_round_rect_vgradient(r.x, r.y, r.w, r.h, rad, th.acc_top(), th.acc_bot())
	cv.stroke_round_rect(r.x, r.y, r.w, r.h, rad, 1, rgba(255, 255, 255, 72))
	k.icons.draw_icon_center(mut cv, icon_code(.focus), r.x + r.w / 2, r.y + r.h / 2,
		int(f64(r.w) * 0.52), rgba(255, 255, 255, 245))
}

// ---- dock ----------------------------------------------------------------------------

enum DockId {
	none
	grip
	seg_rect
	seg_multi
	seg_poly
	undo
	apply
	close
}

struct DockLayout {
mut:
	cw       int
	ch       int
	margin   int
	card     Rect
	grip     Rect
	seg_box  Rect
	seg      [3]Rect
	title_x  int
	title_cy int
	sub_cy   int
	undo     Rect
	apply    Rect
	close    Rect
	div_y    int
	hint_cy  int
	pad      int
}

fn dock_layout(th Theme) DockLayout {
	m := th.px(54)
	pad := th.px(12)
	row_h := th.px(58)
	hint_h := th.px(42)
	card := Rect{m, m, th.px(612), row_h + 1 + hint_h}
	cy := m + row_h / 2
	mut l := DockLayout{
		margin:   m
		pad:      pad
		card:     card
		cw:       card.w + 2 * m
		ch:       card.h + 2 * m
		title_cy: cy - th.px(8)
		sub_cy:   cy + th.px(10)
		div_y:    m + row_h
		hint_cy:  m + row_h + 1 + hint_h / 2
	}
	l.grip = Rect{m + pad, cy - th.px(14), th.px(14), th.px(28)}
	box_h := th.px(42)
	l.seg_box = Rect{l.grip.right() + th.px(8), cy - box_h / 2, th.px(3 * 52 + 8), box_h}
	for i in 0 .. 3 {
		l.seg[i] = Rect{l.seg_box.x + th.px(4) + i * th.px(52), l.seg_box.y + th.px(4), th.px(52), box_h - th.px(8)}
	}
	l.title_x = l.seg_box.right() + th.px(16)
	btn := th.px(38)
	l.close = Rect{card.right() - pad - btn, cy - btn / 2, btn, btn}
	l.apply = Rect{l.close.x - th.px(8) - th.px(94), cy - btn / 2, th.px(94), btn}
	l.undo = Rect{l.apply.x - th.px(8) - btn, cy - btn / 2, btn, btn}
	return l
}

fn (l &DockLayout) hit(x int, y int) DockId {
	p := Pt{x, y}
	if l.close.contains(p) {
		return .close
	}
	if l.apply.contains(p) {
		return .apply
	}
	if l.undo.contains(p) {
		return .undo
	}
	if l.seg[0].contains(p) {
		return .seg_rect
	}
	if l.seg[1].contains(p) {
		return .seg_multi
	}
	if l.seg[2].contains(p) {
		return .seg_poly
	}
	if l.grip.inflate(4).contains(p) {
		return .grip
	}
	return .none
}

struct DockState {
mut:
	hov  [8]Tween
	pill Tween
	hot  DockId
}

fn (mut d DockState) set_hot(id DockId) {
	d.hot = id
	for i in 0 .. 8 {
		d.hov[i].target = if i == int(id) { 1.0 } else { 0.0 }
	}
}

// step advances every animation and reports whether another frame is needed.
fn (mut d DockState) step(dt f64) bool {
	mut moving := false
	for i in 0 .. 8 {
		if d.hov[i].step(dt, 22) {
			moving = true
		}
	}
	if d.pill.step(dt, 17) {
		moving = true
	}
	return moving
}

fn mode_index(m Mode) int {
	return match m {
		.rect { 0 }
		.multi_rect { 1 }
		.polygon { 2 }
	}
}

fn mode_title(m Mode) string {
	return match m {
		.rect { 'Rectangle' }
		.multi_rect { 'Multi-area' }
		.polygon { 'Polygon' }
	}
}

fn mode_hint(m Mode) string {
	return match m {
		.rect { 'Drag to select an area' }
		.multi_rect { 'Drag several areas, then apply' }
		.polygon { 'Click points to outline a shape' }
	}
}

struct Hint {
	key   string
	label string
}

fn dock_hints(m Mode) []Hint {
	return match m {
		.rect {
			[Hint{'Drag', 'select'}, Hint{'1-3', 'mode'}, Hint{'Esc', 'cancel'}]
		}
		.multi_rect {
			[Hint{'Drag', 'add area'}, Hint{'Enter', 'apply'}, Hint{'Bksp', 'undo'},
				Hint{'Esc', 'cancel'}]
		}
		.polygon {
			[Hint{'Click', 'add point'}, Hint{'Enter', 'close shape'}, Hint{'Space', 'apply'},
				Hint{'Bksp', 'undo'}, Hint{'Esc', 'cancel'}]
		}
	}
}

struct DockUi {
	lay  DockLayout
	base vraster.Canvas
}

fn new_dock_ui(th Theme) DockUi {
	pal := palette()
	lay := dock_layout(th)
	mut base := glass_base(lay.cw, lay.ch, lay.card, th)
	base.fill_round_rect(lay.seg_box.x, lay.seg_box.y, lay.seg_box.w, lay.seg_box.h, th.px(14),
		rgba(255, 255, 255, 14))
	base.stroke_round_rect(lay.seg_box.x, lay.seg_box.y, lay.seg_box.w, lay.seg_box.h, th.px(14),
		1, rgba(255, 255, 255, 18))
	base.fill_rect(lay.card.x + th.px(14), lay.div_y, lay.card.w - th.px(28), 1, pal.divider)
	return DockUi{
		lay:  lay
		base: base
	}
}

fn dock_render(ui &DockUi, st &DockState, sel &Selection, k &Kit) vraster.Canvas {
	pal := palette()
	th := k.th
	lay := ui.lay
	mut cv := ui.base.clone()

	// grip
	grip_col := vraster.mix(pal.text3, pal.text2, st.hov[int(DockId.grip)].cur)
	gcx := f64(lay.grip.x) + f64(lay.grip.w) / 2.0
	gcy := f64(lay.grip.y) + f64(lay.grip.h) / 2.0
	for c in [-1.0, 1.0] {
		for r in [-1.0, 0.0, 1.0] {
			cv.fill_circle_f(gcx + c * th.f(3.2), gcy + r * th.f(5.5), th.f(1.4), grip_col)
		}
	}

	// sliding accent pill behind the active mode
	pf := clamp_f(st.pill.cur / 2.0, 0, 1)
	px := int(lerp_f(f64(lay.seg[0].x), f64(lay.seg[2].x), pf) + 0.5)
	pr := th.px(11)
	cv.glow_round_rect(px, lay.seg[0].y, lay.seg[0].w, lay.seg[0].h, pr, th.f(12), th.acc(100),
		true)
	cv.fill_round_rect_vgradient(px, lay.seg[0].y, lay.seg[0].w, lay.seg[0].h, pr, th.acc_top(),
		th.acc_bot())
	cv.stroke_round_rect(px, lay.seg[0].y, lay.seg[0].w, lay.seg[0].h, pr, 1, rgba(255, 255, 255, 64))
	icons := [Icon.rect, Icon.multi, Icon.poly]
	ids := [DockId.seg_rect, DockId.seg_multi, DockId.seg_poly]
	cur := mode_index(sel.mode)
	for i in 0 .. 3 {
		r := lay.seg[i]
		hov := st.hov[int(ids[i])].cur
		if i != cur {
			cv.fill_round_rect(r.x, r.y, r.w, r.h, pr, vraster.with_alpha(pal.hover, hov))
		}
		closeness := 1.0 - clamp_f(abs_f(st.pill.cur - f64(i)), 0, 1)
		col := vraster.mix(vraster.mix(pal.text2, pal.text, hov), pal.white, closeness)
		k.icon(mut cv, icons[i], r.x + r.w / 2, r.y + r.h / 2, 17, col)
	}

	// title block
	k.text_l(mut cv, mode_title(sel.mode), .semibold, lay.title_x, lay.title_cy, pal.text)
	k.text_l(mut cv, mode_hint(sel.mode), .small, lay.title_x, lay.sub_cy, pal.text2)

	// undo
	can_undo := sel.can_undo()
	uh := st.hov[int(DockId.undo)].cur
	if can_undo {
		cv.fill_round_rect(lay.undo.x, lay.undo.y, lay.undo.w, lay.undo.h, th.px(12),
			vraster.with_alpha(pal.hover, uh))
	}
	k.icon(mut cv, .undo, lay.undo.x + lay.undo.w / 2, lay.undo.y + lay.undo.h / 2, 16, if can_undo {
		vraster.mix(pal.text2, pal.text, uh)
	} else {
		pal.text3
	})

	// apply
	can_apply := sel.can_apply()
	ah := st.hov[int(DockId.apply)].cur
	a := lay.apply
	if can_apply {
		cv.glow_round_rect(a.x, a.y, a.w, a.h, th.px(12), th.f(12), th.acc(int(70.0 + 70.0 * ah)),
			true)
		cv.fill_round_rect_vgradient(a.x, a.y, a.w, a.h, th.px(12), vraster.mix(th.acc_top(),
			pal.white, ah * 0.2), th.acc_bot())
		cv.stroke_round_rect(a.x, a.y, a.w, a.h, th.px(12), 1, rgba(255, 255, 255, 64))
	} else {
		cv.fill_round_rect(a.x, a.y, a.w, a.h, th.px(12), rgba(255, 255, 255, 12))
	}
	ac := if can_apply { pal.white } else { pal.text3 }
	acy := a.y + a.h / 2
	k.icon(mut cv, .check, a.x + th.px(26), acy, 14, ac)
	k.text_l(mut cv, 'Apply', .semibold, a.x + th.px(44), acy, ac)

	// close
	ch := st.hov[int(DockId.close)].cur
	c := lay.close
	cv.fill_round_rect(c.x, c.y, c.w, c.h, c.w / 2, vraster.mix(rgba(255, 255, 255, 12),
		rgba(255, 98, 120, 80), ch))
	k.icon(mut cv, .close, c.x + c.w / 2, c.y + c.h / 2, 15, vraster.mix(pal.text2, pal.danger, ch))

	// hint strip
	mut x := lay.card.x + lay.pad + th.px(2)
	for h in dock_hints(sel.mode) {
		x += draw_keycap(mut cv, k, x, lay.hint_cy, h.key) + th.px(8)
		x += k.text_l(mut cv, h.label, .small, x, lay.hint_cy, pal.text2) + th.px(20)
	}
	return cv
}

fn abs_f(v f64) f64 {
	return if v < 0 { -v } else { v }
}

// ---- control panel (tray) --------------------------------------------------------------

enum PanelId {
	none
	row0
	row1
	row2
	row3
	row4
	edit
	quit
}

struct PanelRow {
mut:
	label string
	caps  []string
	icon  Icon
	on    bool
}

struct PanelLayout {
mut:
	cw     int
	ch     int
	margin int
	card   Rect
	logo   Rect
	rows   [5]Rect
	sw     [5]Rect
	edit   Rect
	quit   Rect
	div1   int
	div2   int
}

fn panel_layout(th Theme) PanelLayout {
	m := th.px(54)
	head_h := th.px(80)
	row_h := th.px(52)
	foot_h := th.px(60)
	pad := th.px(6)
	card_h := head_h + 1 + pad + 5 * row_h + pad + 1 + foot_h
	card := Rect{m, m, th.px(372), card_h}
	mut l := PanelLayout{
		margin: m
		card:   card
		cw:     card.w + 2 * m
		ch:     card.h + 2 * m
		logo:   Rect{card.x + th.px(20), card.y + th.px(20), th.px(40), th.px(40)}
		div1:   card.y + head_h
	}
	for i in 0 .. 5 {
		r := Rect{card.x + th.px(10), card.y + head_h + 1 + pad + i * row_h, card.w - th.px(20), row_h}
		l.rows[i] = r
		sw_w := th.px(44)
		sw_h := th.px(24)
		l.sw[i] = Rect{r.right() - th.px(14) - sw_w, r.y + (row_h - sw_h) / 2, sw_w, sw_h}
	}
	l.div2 = card.y + head_h + 1 + pad + 5 * row_h + pad
	fy := l.div2 + 1
	l.edit = Rect{card.x + th.px(16), fy + (foot_h - th.px(36)) / 2, th.px(132), th.px(36)}
	l.quit = Rect{card.right() - th.px(16) - th.px(92), fy + (foot_h - th.px(36)) / 2, th.px(92), th.px(36)}
	return l
}

fn (l &PanelLayout) hit(x int, y int) PanelId {
	p := Pt{x, y}
	if l.quit.contains(p) {
		return .quit
	}
	if l.edit.contains(p) {
		return .edit
	}
	ids := [PanelId.row0, PanelId.row1, PanelId.row2, PanelId.row3, PanelId.row4]
	for i in 0 .. 5 {
		if l.rows[i].contains(p) {
			return ids[i]
		}
	}
	return .none
}

struct PanelState {
mut:
	hov  [8]Tween
	sw   [5]Tween
	open Tween
	hot  PanelId
}

fn (mut s PanelState) set_hot(id PanelId) {
	s.hot = id
	for i in 0 .. 8 {
		s.hov[i].target = if i == int(id) { 1.0 } else { 0.0 }
	}
}

fn (mut s PanelState) step(dt f64) bool {
	mut moving := false
	for i in 0 .. 8 {
		if s.hov[i].step(dt, 22) {
			moving = true
		}
	}
	for i in 0 .. 5 {
		if s.sw[i].step(dt, 18) {
			moving = true
		}
	}
	if s.open.step(dt, 15) {
		moving = true
	}
	return moving
}

struct PanelUi {
	lay  PanelLayout
	base vraster.Canvas
}

fn new_panel_ui(k &Kit) PanelUi {
	th := k.th
	pal := palette()
	lay := panel_layout(th)
	mut base := glass_base(lay.cw, lay.ch, lay.card, th)
	draw_logo(mut base, lay.logo, k)
	tx := lay.logo.right() + th.px(14)
	k.text_l(mut base, 'Reading Focus', .title, tx, lay.logo.y + th.px(13), pal.text)
	k.text_l(mut base, 'Stay on the page', .small, tx, lay.logo.y + th.px(31), pal.text2)
	base.fill_rect(lay.card.x + th.px(16), lay.div1, lay.card.w - th.px(32), 1, pal.divider)
	base.fill_rect(lay.card.x + th.px(16), lay.div2, lay.card.w - th.px(32), 1, pal.divider)
	return PanelUi{
		lay:  lay
		base: base
	}
}

fn panel_render(ui &PanelUi, st &PanelState, rows []PanelRow, k &Kit) vraster.Canvas {
	pal := palette()
	th := k.th
	lay := ui.lay
	mut cv := ui.base.clone()

	ids := [PanelId.row0, PanelId.row1, PanelId.row2, PanelId.row3, PanelId.row4]
	for i in 0 .. 5 {
		if i >= rows.len {
			break
		}
		row := rows[i]
		r := lay.rows[i]
		hov := st.hov[int(ids[i])].cur
		sw_t := clamp_f(st.sw[i].cur, 0, 1)
		cv.fill_round_rect(r.x, r.y, r.w, r.h, th.px(14), vraster.with_alpha(pal.hover, hov))
		cy := r.y + r.h / 2
		tile := Rect{r.x + th.px(8), cy - th.px(17), th.px(34), th.px(34)}
		cv.fill_round_rect(tile.x, tile.y, tile.w, tile.h, th.px(11), vraster.mix(rgba(255, 255,
			255, 16), th.acc(64), sw_t))
		icon_col := vraster.mix(pal.text2, vraster.mix(pal.white, th.acc_top(), 0.45), sw_t)
		k.icon(mut cv, row.icon, tile.x + tile.w / 2, tile.y + tile.h / 2, 16, icon_col)
		k.text_l(mut cv, row.label, .body, tile.right() + th.px(14), cy, pal.text)

		// keycaps, right-aligned against the switch
		mut cap_w := 0
		for n, cap in row.caps {
			tw := k.width(cap, .key)
			cw := if tw + th.px(14) > th.px(24) { tw + th.px(14) } else { th.px(24) }
			cap_w += cw + if n > 0 { th.px(4) } else { 0 }
		}
		mut kx := lay.sw[i].x - th.px(14) - cap_w
		for cap in row.caps {
			kx += draw_keycap(mut cv, k, kx, cy, cap) + th.px(4)
		}

		// switch
		s := lay.sw[i]
		if sw_t > 0.01 {
			cv.glow_round_rect(s.x, s.y, s.w, s.h, s.h / 2, th.f(9), th.acc(int(90.0 * sw_t)), true)
		}
		cv.fill_round_rect(s.x, s.y, s.w, s.h, s.h / 2, vraster.mix(pal.track_off, th.acc(255),
			sw_t))
		kr := f64(s.h) / 2.0 - th.f(3)
		kx0 := f64(s.x) + f64(s.h) / 2.0
		kx1 := f64(s.right()) - f64(s.h) / 2.0
		knob_x := lerp_f(kx0, kx1, sw_t)
		cv.fill_circle_f(knob_x, f64(cy) + th.f(1), kr + th.f(1.5), rgba(0, 0, 0, 60))
		cv.fill_circle_f(knob_x, f64(cy), kr, pal.white)
	}

	eh := st.hov[int(PanelId.edit)].cur
	e := lay.edit
	cv.fill_round_rect(e.x, e.y, e.w, e.h, th.px(12), vraster.mix(rgba(255, 255, 255, 16), pal.press,
		eh))
	cv.stroke_round_rect(e.x, e.y, e.w, e.h, th.px(12), 1, rgba(255, 255, 255, 30))
	k.text_c(mut cv, 'Edit config', .semibold, e.x + e.w / 2, e.y + e.h / 2, pal.text)
	qh := st.hov[int(PanelId.quit)].cur
	q := lay.quit
	cv.fill_round_rect(q.x, q.y, q.w, q.h, th.px(12), vraster.mix(rgba(255, 98, 120, 28),
		rgba(255, 98, 120, 96), qh))
	cv.stroke_round_rect(q.x, q.y, q.w, q.h, th.px(12), 1, rgba(255, 98, 120, 80))
	k.text_c(mut cv, 'Quit', .semibold, q.x + q.w / 2, q.y + q.h / 2, vraster.mix(pal.danger,
		pal.white, qh * 0.5))
	return cv
}

// ---- toast ------------------------------------------------------------------------------

enum ToastKind {
	info
	on
	off
	warn
}

struct ToastLayout {
	cw   int
	ch   int
	card Rect
}

fn toast_layout(text string, k &Kit) ToastLayout {
	th := k.th
	m := th.px(54)
	h := th.px(48)
	w := th.px(14) + th.px(28) + th.px(12) + k.width(text, .body) + th.px(22)
	return ToastLayout{
		cw:   w + 2 * m
		ch:   h + 2 * m
		card: Rect{m, m, w, h}
	}
}

// toast_frame renders a finished toast (static: the window fades it with a constant alpha).
fn toast_frame(text string, kind ToastKind, k &Kit) vraster.Canvas {
	pal := palette()
	th := k.th
	lay := toast_layout(text, k)
	card := lay.card
	rad := card.h / 2
	mut cv := vraster.new_canvas(lay.cw, lay.ch)
	cv.drop_shadow(card.x, card.y, card.w, card.h, rad, th.px(12), th.px(8), pal.shadow)
	cv.drop_shadow(card.x, card.y, card.w, card.h, rad, th.px(4), th.px(2), pal.shadow_lo)
	cv.fill_round_rect_vgradient(card.x, card.y, card.w, card.h, rad, pal.glass_top, pal.glass_bot)
	cv.stroke_round_rect(card.x, card.y, card.w, card.h, rad, 1, pal.border)
	cy := card.y + card.h / 2
	icx := card.x + th.px(14 + 14)
	col := match kind {
		.info { th.acc(255) }
		.on { pal.ok }
		.off { pal.text2 }
		.warn { pal.warn }
	}
	cv.fill_circle_f(f64(icx), f64(cy), th.f(14), vraster.with_alpha(col, 0.2))
	cv.stroke_circle(f64(icx), f64(cy), th.f(13.4), th.f(1), vraster.with_alpha(col, 0.55))
	ic := match kind {
		.info { Icon.info }
		.on { Icon.check }
		.off { Icon.minus }
		.warn { Icon.warn }
	}
	k.icon(mut cv, ic, icx, cy, 13, col)
	k.text_l(mut cv, text, .body, card.x + th.px(14 + 28 + 12), cy, pal.text)
	return cv
}
