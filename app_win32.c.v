@[has_globals]
module main

import os
import stbi
import vraster

// Win32 application layer. All decisions live in selection.v / config.v and all pixels in
// scene.v / ui.v; this file only owns windows, hooks, timers and the animation clock, and turns OS
// events into calls on the pure layers.

const class_main = 'RFO_Main'
const class_overlay = 'RFO_Overlay'
const class_dock = 'RFO_Dock'
const class_panel = 'RFO_Panel'
const class_toast = 'RFO_Toast'
const class_pencil = 'RFO_Pencil'
const class_blur = 'RFO_Blur'

const timer_main = u64(1)
const timer_slow = u64(2)
const tick_ms = u32(10)

enum Action {
	overlay
	clickblock
	blur
	focus
	select_frame
	alttab
	quit
	panel
}

struct HotBind {
	id     int
	action Action
	spec   string
}

struct App {
mut:
	cfg       Config
	cfg_path  string
	sel       Selection
	kit       Kit
	inst      voidptr
	sw        int
	sh        int
	t0        u64
	last_tick u64
	h_main    voidptr
	// layered windows
	ov      LayerWin
	dockw   LayerWin
	panelw  LayerWin
	toastw  LayerWin
	pencilw LayerWin
	blurw   LayerWin
	// overlay
	ov_cv       vraster.Canvas
	ov_mask     vraster.Mask
	dim         Tween
	dirty       bool
	cursor      Pt
	have_cursor bool
	prev_active bool
	commit_ms   u64
	// dock
	dock_ui    DockUi
	dock_st    DockState
	dock_a     Tween
	dock_x     int = -1
	dock_y     int
	dock_drag  bool
	dock_off   Pt
	dock_dirty bool
	dock_track bool
	// panel
	panel_ui     PanelUi
	panel_st     PanelState
	panel_open   bool
	panel_x      int
	panel_y      int
	panel_dirty  bool
	panel_track  bool
	panel_closed u64
	// toast
	toast_cv    vraster.Canvas
	toast_a     Tween
	toast_until u64
	toast_x     int
	toast_y     int
	toast_dirty bool
	// pencil
	pencil_on     bool
	pencil_cv     vraster.Canvas
	pencil_margin int
	last_mouse    CPoint
	// taskbar blur
	blur_on bool
	blur_a  Tween
	blur_cv vraster.Canvas
	blur_x  int
	blur_y  int
	// distraction blockers
	click_block  bool
	alttab_block bool
	kb_hook      voidptr
	mouse_hook   voidptr
	pending_up   map[u32]bool
	// shell
	timer_live  bool
	binds       []HotBind
	plus_cursor voidptr
	tray_icon   voidptr
	tray_added  bool
	tb_created  u32
}

__global (
	app App
)

fn now_ms() u64 {
	return C.GetTickCount64()
}

// ---- setup ------------------------------------------------------------------------------

fn register_class(name string, proc voidptr, bg voidptr, cursor voidptr) bool {
	cls := wide(name)
	wc := WndClassExW{
		cb_size:         u32(sizeof(WndClassExW))
		lpfn_wnd_proc:   proc
		h_instance:      app.inst
		h_cursor:        cursor
		hbr_background:  bg
		lpsz_class_name: cls
	}
	return C.RegisterClassExW(&wc) != 0 || C.GetLastError() == 1410
}

fn load_plus_cursor() voidptr {
	data := $embed_file('assets/plus_cursor.cur').to_bytes()
	tmp := os.join_path(os.temp_dir(), 'rfo_plus_cursor_${os.getpid()}.cur')
	os.write_file(tmp, data.bytestr()) or {
		return C.LoadCursorW(nilp(), unsafe { voidptr(idc_cross) })
	}
	cur := C.LoadCursorFromFileW(wide(tmp))
	os.rm(tmp) or {}
	if isnil(cur) {
		return C.LoadCursorW(nilp(), unsafe { voidptr(idc_cross) })
	}
	return cur
}

fn (mut a App) work_area() WinRect {
	mut r := WinRect{}
	C.SystemParametersInfoW(spi_getworkarea, 0, &r, 0)
	if r.right <= r.left || r.bottom <= r.top {
		return WinRect{0, 0, i32(a.sw), i32(a.sh)}
	}
	return r
}

// ---- overlay ---------------------------------------------------------------------------

fn (mut a App) ensure_overlay() bool {
	return a.ov.create(class_overlay, ws_ex_noactivate, a.inst)
}

fn (mut a App) paint_overlay() {
	if !a.ov.exists() {
		return
	}
	now := now_ms()
	mut pulse := -1.0
	if a.commit_ms > 0 {
		p := f64(now - a.commit_ms) / 480.0
		if p >= 1.0 {
			a.commit_ms = 0
		} else {
			pulse = p
		}
	}
	ref := f64(max_i(1, a.cfg.style.dim_drag))
	v := Visuals{
		dim:         a.dim.cur
		fade:        clamp_f(a.dim.cur / ref, 0, 1)
		t_ms:        int(now - a.t0)
		cursor:      a.cursor
		have_cursor: a.have_cursor
		pulse:       pulse
	}
	a.sel.compose(mut a.ov_cv, mut a.ov_mask, v, &a.kit)
	a.ov.present(&a.ov_cv, 0, 0, 255, sw_shownoactivate)
	a.dirty = false
}

// raise_stack restores the z-order: overlay < dock < panel < toast < pencil.
fn (mut a App) raise_stack() {
	a.dockw.raise()
	a.panelw.raise()
	a.toastw.raise()
	a.pencilw.raise()
}

// sync reconciles every window, hook and animation target with the selection state. It is called
// after any event that may have changed what must be on screen.
fn (mut a App) sync() {
	target := if !a.sel.dim_shown {
		0.0
	} else if a.sel.active {
		f64(a.cfg.style.dim_drag)
	} else {
		f64(a.cfg.style.dim_final)
	}
	if a.sel.dim_shown && !a.ov.exists() {
		if a.ensure_overlay() {
			a.dim.set(0)
			a.raise_stack()
		}
	}
	a.dim.target = target
	if a.prev_active && !a.sel.active && a.sel.have_frame {
		a.commit_ms = now_ms()
	}
	a.prev_active = a.sel.active
	a.dirty = true
	if a.sel.active {
		a.ensure_dock()
		a.dock_a.target = 1
		a.dock_st.pill.target = f64(mode_index(a.sel.mode))
	} else {
		a.dock_a.target = 0
	}
	a.dock_dirty = true
	a.update_hooks()
	a.panel_sync_rows()
	a.tray_update()
	a.wake()
}

// ---- dock ------------------------------------------------------------------------------------

fn (mut a App) ensure_dock() {
	if a.dockw.exists() {
		return
	}
	if !a.dockw.create(class_dock, ws_ex_noactivate, a.inst) {
		return
	}
	if a.dock_x < 0 {
		a.dock_x = (a.sw - a.dock_ui.lay.card.w) / 2
		a.dock_y = a.kit.th.px(28)
	}
	a.dock_st.pill.set(f64(mode_index(a.sel.mode)))
	a.dock_a.set(0)
}

fn (mut a App) dock_present() {
	if !a.dockw.exists() {
		return
	}
	cv := dock_render(&a.dock_ui, &a.dock_st, &a.sel, &a.kit)
	t := ease_out_cubic(a.dock_a.cur)
	yoff := int((1.0 - t) * f64(a.kit.th.px(16)))
	a.dockw.present(&cv, a.dock_x - a.dock_ui.lay.margin, a.dock_y - a.dock_ui.lay.margin - yoff,
		u8(clamp_f(a.dock_a.cur, 0, 1) * 255.0), sw_shownoactivate)
	a.dock_dirty = false
}

fn (mut a App) dock_hover(id DockId) {
	if id != a.dock_st.hot {
		a.dock_st.set_hot(id)
		a.dock_dirty = true
		a.wake()
	}
}

fn (mut a App) dock_click(id DockId) {
	match id {
		.seg_rect {
			a.sel.set_mode(.rect)
		}
		.seg_multi {
			a.sel.set_mode(.multi_rect)
		}
		.seg_poly {
			a.sel.set_mode(.polygon)
		}
		.undo {
			if a.sel.can_undo() {
				a.sel.undo(false)
			}
		}
		.apply {
			a.sel.apply()
		}
		.close {
			a.sel.cancel()
		}
		else {}
	}
	a.sync()
}

// ---- control panel -------------------------------------------------------------------------

fn (a &App) panel_rows() []PanelRow {
	return [
		PanelRow{'Focus frame', hotkey_caps(a.cfg.toggle_focus), .focus, a.sel.dim_shown},
		PanelRow{'Pencil cursor', hotkey_caps(a.cfg.toggle_overlay), .pencil, a.pencil_on},
		PanelRow{'Block clicks', hotkey_caps(a.cfg.toggle_clickblock), .block, a.click_block},
		PanelRow{'Blur taskbar', hotkey_caps(a.cfg.toggle_blur), .blur, a.blur_on},
		PanelRow{'Block Alt+Tab', hotkey_caps(a.cfg.toggle_alttab), .alttab, a.alttab_block},
	]
}

fn (mut a App) panel_sync_rows() {
	rows := a.panel_rows()
	for i in 0 .. 5 {
		a.panel_st.sw[i].target = if rows[i].on { 1.0 } else { 0.0 }
	}
	a.panel_dirty = true
}

fn (mut a App) panel_present() {
	if !a.panelw.exists() {
		return
	}
	cv := panel_render(&a.panel_ui, &a.panel_st, a.panel_rows(), &a.kit)
	t := ease_out_cubic(a.panel_st.open.cur)
	yoff := int((1.0 - t) * f64(a.kit.th.px(14)))
	a.panelw.present(&cv, a.panel_x - a.panel_ui.lay.margin, a.panel_y - a.panel_ui.lay.margin + yoff,
		u8(clamp_f(a.panel_st.open.cur, 0, 1) * 255.0), sw_show)
	a.panel_dirty = false
}

fn (mut a App) open_panel(anchor_x int, from_tray bool) {
	if a.panel_open {
		return
	}
	if !a.panelw.create(class_panel, 0, a.inst) {
		return
	}
	th := a.kit.th
	lay := a.panel_ui.lay
	work := a.work_area()
	cx := if from_tray { anchor_x } else { (int(work.left) + int(work.right)) / 2 }
	lo := int(work.left) + th.px(12)
	hi := max_i(lo, int(work.right) - lay.card.w - th.px(12))
	a.panel_x = clamp_i(cx - lay.card.w / 2, lo, hi)
	a.panel_y = int(work.bottom) - lay.card.h - th.px(14)
	a.panel_open = true
	rows := a.panel_rows()
	for i in 0 .. 5 {
		a.panel_st.sw[i].set(if rows[i].on { 1.0 } else { 0.0 })
	}
	a.panel_st.set_hot(.none)
	a.panel_st.open.set(0)
	a.panel_st.open.target = 1
	a.panel_present()
	C.SetForegroundWindow(a.panelw.hwnd)
	a.wake()
}

fn (mut a App) close_panel() {
	if !a.panel_open {
		return
	}
	a.panel_open = false
	a.panel_closed = now_ms()
	a.panel_st.open.target = 0
	a.panel_st.set_hot(.none)
	a.panel_dirty = true
	a.wake()
}

fn (mut a App) panel_click(id PanelId) {
	match id {
		.row0 {
			a.run_action(.focus)
			if a.sel.active {
				a.close_panel()
			}
		}
		.row1 {
			a.run_action(.overlay)
		}
		.row2 {
			a.run_action(.clickblock)
		}
		.row3 {
			a.run_action(.blur)
		}
		.row4 {
			a.run_action(.alttab)
		}
		.edit {
			a.open_config()
			a.close_panel()
		}
		.quit {
			C.PostMessageW(a.h_main, wm_close, 0, 0)
		}
		else {}
	}
	a.panel_sync_rows()
}

fn (mut a App) open_config() {
	if !os.exists(a.cfg_path) {
		os.write_file(a.cfg_path, a.cfg.to_ini()) or {
			a.toast('Cannot write ${a.cfg_path}', .warn, 3000)
			return
		}
	}
	C.ShellExecuteW(nilp(), wide('open'), wide(a.cfg_path), unsafe { &u16(nil) }, unsafe { &u16(nil) },
		sw_show)
}

// ---- toast -----------------------------------------------------------------------------------

fn (mut a App) toast(text string, kind ToastKind, ms int) {
	if !a.toastw.create(class_toast, ws_ex_noactivate | ws_ex_transparent, a.inst) {
		return
	}
	th := a.kit.th
	a.toast_cv = toast_frame(text, kind, &a.kit)
	lay := toast_layout(text, &a.kit)
	work := a.work_area()
	a.toast_x = (int(work.left) + int(work.right)) / 2 - lay.cw / 2
	a.toast_y = int(work.bottom) - lay.card.h - th.px(30) - lay.card.y
	a.toast_until = now_ms() + u64(ms)
	a.toast_a.target = 1
	a.toast_dirty = true
	a.wake()
}

fn (mut a App) toast_present() {
	if !a.toastw.exists() || a.toast_cv.w == 0 {
		return
	}
	t := ease_out_cubic(a.toast_a.cur)
	yoff := int((1.0 - t) * f64(a.kit.th.px(12)))
	a.toastw.present(&a.toast_cv, a.toast_x, a.toast_y + yoff, u8(clamp_f(a.toast_a.cur, 0, 1) * 255.0),
		sw_shownoactivate)
	a.toast_dirty = false
}

// ---- pencil ----------------------------------------------------------------------------------

fn (mut a App) pencil_load() bool {
	if a.pencil_cv.w > 0 {
		return true
	}
	th := a.kit.th
	data := $embed_file('assets/pencil.png').to_bytes()
	img := stbi.load_from_memory(data.data, data.len, desired_channels: 4) or { return false }
	defer {
		img.free()
	}
	mut src := []u8{len: img.width * img.height * 4}
	unsafe { vmemcpy(src.data, img.data, src.len) }
	premultiply_rgba(mut src)
	dw, dh := fit_max_edge(img.width, img.height, th.px(f64(a.cfg.pencil_max_edge)))
	px := resize_premul(src, img.width, img.height, dw, dh)
	m := th.px(14)
	mut cv := vraster.new_canvas(dw + 2 * m, dh + 2 * m)
	// soft drop shadow: the sprite's alpha, offset and blurred
	sx := th.px(3)
	sy := th.px(5)
	for y in 0 .. dh {
		for x in 0 .. dw {
			al := int(px[(y * dw + x) * 4 + 3])
			if al > 0 {
				cv.px[((y + m + sy) * cv.w + x + m + sx) * 4 + 3] = u8(al * 115 / 255)
			}
		}
	}
	cv.blur_region(0, 0, cv.w, cv.h, th.px(4))
	// sprite over the shadow (premultiplied over)
	for y in 0 .. dh {
		for x in 0 .. dw {
			si := (y * dw + x) * 4
			sa := int(px[si + 3])
			if sa == 0 {
				continue
			}
			inv := 255 - sa
			di := ((y + m) * cv.w + x + m) * 4
			cv.px[di] = u8(int(px[si]) + int(cv.px[di]) * inv / 255)
			cv.px[di + 1] = u8(int(px[si + 1]) + int(cv.px[di + 1]) * inv / 255)
			cv.px[di + 2] = u8(int(px[si + 2]) + int(cv.px[di + 2]) * inv / 255)
			cv.px[di + 3] = u8(sa + int(cv.px[di + 3]) * inv / 255)
		}
	}
	a.pencil_cv = cv
	a.pencil_margin = m
	return true
}

fn invisible_cursor() voidptr {
	and_mask := []u8{len: 128, init: 0xFF}
	xor_mask := []u8{len: 128}
	return C.CreateCursor(app.inst, 0, 0, 32, 32, and_mask.data, xor_mask.data)
}

fn restore_system_cursors() {
	C.SystemParametersInfoW(spi_setcursors, 0, nilp(), 0)
}

fn (mut a App) pencil_start() bool {
	if !a.pencil_load() {
		return false
	}
	if !a.pencilw.create(class_pencil, ws_ex_noactivate | ws_ex_transparent, a.inst) {
		return false
	}
	mut cur := CPoint{}
	C.GetCursorPos(&cur)
	a.pencilw.present(&a.pencil_cv, int(cur.x) + a.cfg.pencil_offset_x - a.pencil_margin,
		int(cur.y) + a.cfg.pencil_offset_y - a.pencil_margin, 255, sw_shownoactivate)
	C.SetSystemCursor(invisible_cursor(), ocr_normal)
	a.last_mouse = cur
	return true
}

fn (mut a App) pencil_stop() {
	a.pencilw.destroy()
	restore_system_cursors()
}

fn (mut a App) toggle_pencil() {
	if a.pencil_on {
		a.pencil_on = false
		a.pencil_stop()
	} else if a.pencil_start() {
		a.pencil_on = true
	} else {
		a.toast('Pencil cursor failed to start', .warn, 2000)
		return
	}
	a.toast(if a.pencil_on { 'Pencil cursor on' } else { 'Pencil cursor off' }, if a.pencil_on {
		ToastKind.on
	} else {
		ToastKind.off
	}, 1400)
	a.after_toggle()
}

fn (mut a App) pencil_follow(force bool) {
	if !a.pencilw.exists() {
		return
	}
	mut cur := CPoint{}
	C.GetCursorPos(&cur)
	if !force && cur.x == a.last_mouse.x && cur.y == a.last_mouse.y {
		return
	}
	a.last_mouse = cur
	C.SetWindowPos(a.pencilw.hwnd, topmost(), int(cur.x) + a.cfg.pencil_offset_x - a.pencil_margin,
		int(cur.y) + a.cfg.pencil_offset_y - a.pencil_margin, 0, 0, swp_nosize | swp_noactivate)
}

// ---- blockers and hooks ----------------------------------------------------------------------

fn (mut a App) after_toggle() {
	a.panel_sync_rows()
	a.tray_update()
	a.update_hooks()
	a.wake()
}

fn (mut a App) toggle_clickblock() {
	a.click_block = !a.click_block
	a.toast(if a.click_block { 'Clicks blocked' } else { 'Clicks allowed' }, if a.click_block {
		ToastKind.on
	} else {
		ToastKind.off
	}, 1400)
	a.after_toggle()
}

fn (mut a App) toggle_alttab() {
	a.alttab_block = !a.alttab_block
	a.toast(if a.alttab_block { 'Alt+Tab blocked' } else { 'Alt+Tab allowed' }, if a.alttab_block {
		ToastKind.on
	} else {
		ToastKind.off
	}, 1800)
	a.after_toggle()
}

fn (mut a App) update_hooks() {
	need_kb := a.sel.active || a.alttab_block
	if need_kb && isnil(a.kb_hook) {
		a.kb_hook = C.SetWindowsHookExW(wh_keyboard_ll, voidptr(&kb_proc), a.inst, 0)
	} else if !need_kb && !isnil(a.kb_hook) {
		C.UnhookWindowsHookEx(a.kb_hook)
		a.kb_hook = nilp()
		a.pending_up.clear()
	}
	if a.click_block && isnil(a.mouse_hook) {
		a.mouse_hook = C.SetWindowsHookExW(wh_mouse_ll, voidptr(&mouse_proc), a.inst, 0)
	} else if !a.click_block && !isnil(a.mouse_hook) {
		C.UnhookWindowsHookEx(a.mouse_hook)
		a.mouse_hook = nilp()
	}
}

fn key_down_now(vk int) bool {
	return C.GetAsyncKeyState(vk) < 0
}

@[callconv: stdcall]
fn kb_proc(code int, wparam u64, lparam i64) i64 {
	if code == hc_action && lparam != 0 {
		k := unsafe { &KbdLlHookStruct(voidptr(lparam)) }
		down := u32(wparam) == wm_keydown || u32(wparam) == wm_syskeydown
		up := u32(wparam) == wm_keyup || u32(wparam) == wm_syskeyup
		alt := k.flags & llkhf_altdown != 0
		win := key_down_now(int(vk_lwin)) || key_down_now(int(vk_rwin))
		if app.alttab_block && k.vk_code == vk_tab && (alt || win) {
			return 1
		}
		if app.sel.active {
			shift := key_down_now(vk_shift)
			ctrl_or_alt := key_down_now(vk_control) || alt
			if down && app.sel.wants_key(k.vk_code, shift, ctrl_or_alt) {
				app.pending_up[k.vk_code] = true
				C.PostMessageW(app.h_main, wm_app_key, u64(k.vk_code), if shift {
					i64(1)
				} else {
					i64(0)
				})
				return 1
			}
			if up && app.pending_up[k.vk_code] {
				app.pending_up.delete(k.vk_code)
				return 1
			}
		}
	}
	return C.CallNextHookEx(app.kb_hook, code, wparam, lparam)
}

@[callconv: stdcall]
fn mouse_proc(code int, wparam u64, lparam i64) i64 {
	if code == hc_action && app.click_block {
		if u32(wparam) == wm_lbuttondown || u32(wparam) == wm_lbuttonup {
			return 1
		}
	}
	return C.CallNextHookEx(app.mouse_hook, code, wparam, lparam)
}

// ---- taskbar blur ------------------------------------------------------------------------------

fn (mut a App) blur_start() bool {
	tray := C.FindWindowW(wide('Shell_TrayWnd'), unsafe { &u16(nil) })
	if isnil(tray) {
		return false
	}
	mut r := WinRect{}
	C.GetWindowRect(tray, &r)
	w := int(r.right - r.left)
	h := int(r.bottom - r.top)
	if w <= 0 || h <= 0 {
		return false
	}
	screen := C.GetDC(nilp())
	mem := C.CreateCompatibleDC(screen)
	mut bi := BitmapInfo{}
	bi.header.size = u32(sizeof(BitmapInfoHeader))
	bi.header.width = w
	bi.header.height = -h
	bi.header.planes = 1
	bi.header.bit_count = 32
	bi.header.compression = bi_rgb
	mut bits := nilp()
	bmp := C.CreateDIBSection(screen, &bi, dib_rgb_colors, &bits, nilp(), 0)
	if isnil(bmp) || isnil(bits) {
		C.DeleteDC(mem)
		C.ReleaseDC(nilp(), screen)
		return false
	}
	old := C.SelectObject(mem, bmp)
	C.BitBlt(mem, 0, 0, w, h, screen, int(r.left), int(r.top), srccopy | captureblt)
	mut cv := vraster.new_canvas(w, h)
	for i in 0 .. w * h {
		unsafe {
			p := &u8(bits)
			cv.px[i * 4] = p[i * 4 + 2]
			cv.px[i * 4 + 1] = p[i * 4 + 1]
			cv.px[i * 4 + 2] = p[i * 4]
			cv.px[i * 4 + 3] = 255
		}
	}
	C.SelectObject(mem, old)
	C.DeleteObject(bmp)
	C.DeleteDC(mem)
	C.ReleaseDC(nilp(), screen)
	// frosted glass: blur the snapshot, tint it dark and add a hairline highlight on the top edge
	cv.acrylic(0, 0, w, h, rgba(14, 16, 26, 150), a.kit.th.px(8))
	cv.fill_rect(0, 0, w, 1, rgba(255, 255, 255, 46))
	a.blur_cv = cv
	a.blur_x = int(r.left)
	a.blur_y = int(r.top)
	if !a.blurw.create(class_blur, ws_ex_noactivate | ws_ex_transparent, a.inst) {
		return false
	}
	a.blur_a.set(0)
	a.blur_a.target = 1
	a.blurw.present(&a.blur_cv, a.blur_x, a.blur_y, 0, sw_shownoactivate)
	return true
}

fn (mut a App) toggle_blur() {
	if a.blur_on {
		a.blur_on = false
		a.blur_a.target = 0
	} else if a.blur_start() {
		a.blur_on = true
	} else {
		a.toast('Taskbar not found', .warn, 1800)
		return
	}
	a.toast(if a.blur_on { 'Taskbar blurred' } else { 'Taskbar visible' }, if a.blur_on {
		ToastKind.on
	} else {
		ToastKind.off
	}, 1400)
	a.after_toggle()
}

// ---- tray --------------------------------------------------------------------------------------

fn (a &App) any_active() bool {
	return a.sel.dim_shown || a.pencil_on || a.click_block || a.blur_on || a.alttab_block
}

fn (a &App) make_tray_icon() voidptr {
	size := max_i(16, C.GetSystemMetrics(sm_cxsmicon))
	pal := palette()
	mut cv := vraster.new_canvas(size, size)
	rad := int(f64(size) * 0.3)
	cv.fill_round_rect_vgradient(0, 0, size, size, rad, a.kit.th.acc_top(), a.kit.th.acc_bot())
	a.kit.icons.draw_icon_center(mut cv, icon_code(.focus), size / 2, size / 2, int(f64(size) * 0.58),
		rgba(255, 255, 255, 245))
	if a.any_active() {
		r := f64(size) * 0.2
		cx := f64(size) - r - 0.5
		cy := f64(size) - r - 0.5
		cv.fill_circle_f(cx, cy, r + 1.2, rgba(20, 22, 32, 255))
		cv.fill_circle_f(cx, cy, r, pal.ok)
	}
	return icon_from_canvas(&cv)
}

fn set_tip(mut nid NotifyIconDataW, text string) {
	w := text.to_wide()
	mut i := 0
	for i < 127 {
		c := unsafe { w[i] }
		if c == 0 {
			break
		}
		nid.sz_tip[i] = c
		i++
	}
	nid.sz_tip[i] = 0
}

fn (mut a App) tray_data() NotifyIconDataW {
	mut nid := NotifyIconDataW{
		cb_size:           u32(sizeof(NotifyIconDataW))
		hwnd:              a.h_main
		uid:               1
		uflags:            nif_message | nif_icon | nif_tip
		ucallback_message: wm_app_tray
		hicon:             a.tray_icon
	}
	set_tip(mut nid, if a.any_active() {
		'Reading Focus - active'
	} else {
		'Reading Focus'
	})
	return nid
}

fn (mut a App) tray_add() {
	old := a.tray_icon
	a.tray_icon = a.make_tray_icon()
	nid := a.tray_data()
	if C.Shell_NotifyIconW(nim_add, &nid) != 0 {
		a.tray_added = true
	}
	if !isnil(old) {
		C.DestroyIcon(old)
	}
}

fn (mut a App) tray_update() {
	if !a.tray_added {
		return
	}
	old := a.tray_icon
	a.tray_icon = a.make_tray_icon()
	nid := a.tray_data()
	C.Shell_NotifyIconW(nim_modify, &nid)
	if !isnil(old) {
		C.DestroyIcon(old)
	}
}

fn (mut a App) tray_remove() {
	if a.tray_added {
		nid := a.tray_data()
		C.Shell_NotifyIconW(nim_delete, &nid)
		a.tray_added = false
	}
	if !isnil(a.tray_icon) {
		C.DestroyIcon(a.tray_icon)
		a.tray_icon = nilp()
	}
}

// ---- clock -------------------------------------------------------------------------------------

fn (mut a App) wake() {
	if !a.timer_live {
		C.SetTimer(a.h_main, timer_main, tick_ms, nilp())
		a.timer_live = true
		a.last_tick = now_ms()
	}
}

fn (mut a App) on_tick() {
	now := now_ms()
	mut dt := f64(now - a.last_tick) / 1000.0
	if dt > 0.05 {
		dt = 0.05
	}
	a.last_tick = now
	mut busy := false

	// overlay
	if a.dim.step(dt, 12) {
		a.dirty = true
		busy = true
	}
	if a.sel.active {
		busy = true
		if a.sel.cur_poly.len > 0 {
			a.dirty = true // marching dashes and the closing-ring pulse
		}
	}
	if a.commit_ms > 0 {
		a.dirty = true
		busy = true
	}
	if a.dirty && a.ov.exists() {
		a.paint_overlay()
	}
	if a.ov.exists() && !a.sel.dim_shown && a.dim.cur < 0.5 {
		a.ov.destroy()
	}

	// dock
	if a.dockw.exists() {
		if a.dock_st.step(dt) {
			a.dock_dirty = true
			busy = true
		}
		if a.dock_a.step(dt, 16) {
			a.dock_dirty = true
			busy = true
		}
		if a.dock_a.cur < 0.01 && a.dock_a.target == 0 {
			a.dockw.hide()
			a.dock_dirty = false
		} else if a.dock_dirty {
			a.dock_present()
		}
	}

	// panel
	if a.panelw.exists() {
		if a.panel_st.step(dt) {
			a.panel_dirty = true
			busy = true
		}
		if !a.panel_open && a.panel_st.open.cur < 0.01 {
			a.panelw.destroy()
		} else if a.panel_dirty {
			a.panel_present()
		}
	}

	// toast
	if a.toastw.exists() {
		if now > a.toast_until && a.toast_a.target > 0 {
			a.toast_a.target = 0
		}
		if a.toast_a.step(dt, 14) {
			a.toast_dirty = true
		}
		if a.toast_a.cur < 0.01 && a.toast_a.target == 0 {
			a.toastw.hide()
			a.toast_dirty = false
		} else {
			busy = true
			if a.toast_dirty {
				a.toast_present()
			}
		}
	}

	// taskbar blur fade
	if a.blurw.exists() {
		if a.blur_a.step(dt, 10) {
			busy = true
			a.blurw.present(&a.blur_cv, a.blur_x, a.blur_y, u8(clamp_f(a.blur_a.cur, 0, 1) * 255.0),
				sw_shownoactivate)
		}
		if !a.blur_on && a.blur_a.cur < 0.01 {
			a.blurw.destroy()
		}
	}

	if a.pencil_on {
		busy = true
		a.pencil_follow(false)
	}
	if !busy {
		C.KillTimer(a.h_main, timer_main)
		a.timer_live = false
	}
}

// keep_on_top re-asserts the always-on-top overlays now and then (the taskbar can climb over them).
fn (mut a App) keep_on_top() {
	if a.blur_on {
		a.blurw.raise()
	}
	if a.sel.dim_shown {
		a.ov.raise()
		a.raise_stack()
	}
}

// ---- hotkeys ----------------------------------------------------------------------------------

fn vk_for(key string) ?u32 {
	if v := named_vk(key) {
		return v
	}
	if key.len == 1 {
		r := C.VkKeyScanW(u16(key[0]))
		if r == -1 {
			return none
		}
		return u32(r) & 0xff
	}
	return none
}

fn (mut a App) register_hotkeys() []string {
	mut failures := []string{}
	specs := [
		HotBind{1, .overlay, a.cfg.toggle_overlay},
		HotBind{2, .clickblock, a.cfg.toggle_clickblock},
		HotBind{3, .blur, a.cfg.toggle_blur},
		HotBind{4, .focus, a.cfg.toggle_focus},
		HotBind{5, .select_frame, a.cfg.select_focus},
		HotBind{6, .alttab, a.cfg.toggle_alttab},
		HotBind{7, .quit, a.cfg.quit},
		HotBind{8, .panel, a.cfg.panel},
	]
	for b in specs {
		hk := parse_hotkey(b.spec) or {
			failures << '${b.spec}: ${err.msg()}'
			continue
		}
		vk := vk_for(hk.key) or {
			failures << '${b.spec}: unknown key'
			continue
		}
		if C.RegisterHotKey(a.h_main, b.id, hk.mods | 0x4000, vk) == 0 {
			failures << '${b.spec} is used by another program'
			continue
		}
		a.binds << b
	}
	return failures
}

fn (mut a App) run_action(act Action) {
	match act {
		.overlay {
			a.toggle_pencil()
		}
		.clickblock {
			a.toggle_clickblock()
		}
		.blur {
			a.toggle_blur()
		}
		.focus {
			a.sel.toggle_focus()
			a.sync()
		}
		.select_frame {
			a.sel.reselect()
			a.sync()
		}
		.alttab {
			a.toggle_alttab()
		}
		.panel {
			if a.panel_open {
				a.close_panel()
			} else {
				a.open_panel(0, false)
			}
		}
		.quit {
			C.PostMessageW(a.h_main, wm_close, 0, 0)
		}
	}
}

// ---- window procedures --------------------------------------------------------------------------

@[callconv: stdcall]
fn main_proc(hwnd voidptr, msg u32, wparam u64, lparam i64) i64 {
	if msg == app.tb_created && app.tb_created != 0 {
		app.tray_added = false
		app.tray_add()
		return 0
	}
	match msg {
		wm_hotkey {
			for b in app.binds {
				if b.id == int(wparam) {
					app.run_action(b.action)
					break
				}
			}
			return 0
		}
		wm_app_key {
			app.sel.on_key(u32(wparam), lparam != 0)
			app.sync()
			return 0
		}
		wm_app_tray {
			ev := u32(u64(lparam) & 0xffff)
			if ev == wm_lbuttonup || ev == wm_rbuttonup {
				if app.panel_open {
					app.close_panel()
				} else if now_ms() - app.panel_closed > 250 {
					mut cur := CPoint{}
					C.GetCursorPos(&cur)
					app.open_panel(int(cur.x), true)
				}
			}
			return 0
		}
		wm_timer {
			if wparam == timer_main {
				app.on_tick()
			} else if wparam == timer_slow {
				app.keep_on_top()
			}
			return 0
		}
		wm_close {
			C.PostQuitMessage(0)
			return 0
		}
		else {}
	}
	return C.DefWindowProcW(hwnd, msg, wparam, lparam)
}

@[callconv: stdcall]
fn overlay_proc(hwnd voidptr, msg u32, wparam u64, lparam i64) i64 {
	match msg {
		wm_setcursor {
			if app.sel.active {
				C.SetCursor(app.plus_cursor)
				return 1
			}
		}
		wm_mouseactivate {
			return ma_noactivate
		}
		wm_lbuttondown {
			if app.sel.active {
				C.SetCapture(hwnd)
				app.sel.mouse_down(Pt{lparam_x(lparam), lparam_y(lparam)})
				app.dirty = true
			}
			return 0
		}
		wm_mousemove {
			if app.sel.active {
				app.cursor = Pt{lparam_x(lparam), lparam_y(lparam)}
				app.have_cursor = true
				app.sel.mouse_move(app.cursor)
				app.dirty = true
			}
			return 0
		}
		wm_lbuttonup {
			C.ReleaseCapture()
			if app.sel.active {
				app.sel.mouse_up(Pt{lparam_x(lparam), lparam_y(lparam)})
				app.sync()
			}
			return 0
		}
		else {}
	}
	return C.DefWindowProcW(hwnd, msg, wparam, lparam)
}

fn track_leave(hwnd voidptr) {
	mut t := TrackMouseEventS{
		cb_size:    u32(sizeof(TrackMouseEventS))
		flags:      tme_leave
		hwnd_track: hwnd
	}
	C.TrackMouseEvent(&t)
}

@[callconv: stdcall]
fn dock_proc(hwnd voidptr, msg u32, wparam u64, lparam i64) i64 {
	match msg {
		wm_mouseactivate {
			return ma_noactivate
		}
		wm_mousemove {
			x := lparam_x(lparam)
			y := lparam_y(lparam)
			if app.dock_drag {
				mut cur := CPoint{}
				C.GetCursorPos(&cur)
				app.dock_x = int(cur.x) - app.dock_off.x
				app.dock_y = int(cur.y) - app.dock_off.y
				app.dock_dirty = true
				app.wake()
				return 0
			}
			if app.have_cursor {
				app.have_cursor = false // hide the crosshair while the pointer is on the dock
				app.dirty = true
			}
			if !app.dock_track {
				track_leave(hwnd)
				app.dock_track = true
			}
			app.dock_hover(app.dock_ui.lay.hit(x, y))
			return 0
		}
		wm_mouseleave {
			app.dock_track = false
			app.dock_hover(.none)
			return 0
		}
		wm_lbuttondown {
			id := app.dock_ui.lay.hit(lparam_x(lparam), lparam_y(lparam))
			if id == .grip {
				mut cur := CPoint{}
				C.GetCursorPos(&cur)
				app.dock_off = Pt{int(cur.x) - app.dock_x, int(cur.y) - app.dock_y}
				app.dock_drag = true
				C.SetCapture(hwnd)
			} else {
				app.dock_click(id)
			}
			return 0
		}
		wm_lbuttonup {
			if app.dock_drag {
				app.dock_drag = false
				C.ReleaseCapture()
			}
			return 0
		}
		else {}
	}
	return C.DefWindowProcW(hwnd, msg, wparam, lparam)
}

@[callconv: stdcall]
fn panel_proc(hwnd voidptr, msg u32, wparam u64, lparam i64) i64 {
	match msg {
		wm_activate {
			if (wparam & 0xffff) == 0 {
				app.close_panel()
			}
			return 0
		}
		wm_keydown {
			if u32(wparam) == vk_escape {
				app.close_panel()
			}
			return 0
		}
		wm_mousemove {
			if !app.panel_track {
				track_leave(hwnd)
				app.panel_track = true
			}
			id := app.panel_ui.lay.hit(lparam_x(lparam), lparam_y(lparam))
			if id != app.panel_st.hot {
				app.panel_st.set_hot(id)
				app.panel_dirty = true
				app.wake()
			}
			return 0
		}
		wm_mouseleave {
			app.panel_track = false
			app.panel_st.set_hot(.none)
			app.panel_dirty = true
			app.wake()
			return 0
		}
		wm_lbuttondown {
			app.panel_click(app.panel_ui.lay.hit(lparam_x(lparam), lparam_y(lparam)))
			return 0
		}
		else {}
	}
	return C.DefWindowProcW(hwnd, msg, wparam, lparam)
}

@[callconv: stdcall]
fn passive_proc(hwnd voidptr, msg u32, wparam u64, lparam i64) i64 {
	if msg == wm_mouseactivate {
		return ma_noactivate
	}
	return C.DefWindowProcW(hwnd, msg, wparam, lparam)
}

// ---- lifecycle -----------------------------------------------------------------------------------

fn (mut a App) cleanup() {
	if !isnil(a.kb_hook) {
		C.UnhookWindowsHookEx(a.kb_hook)
		a.kb_hook = nilp()
	}
	if !isnil(a.mouse_hook) {
		C.UnhookWindowsHookEx(a.mouse_hook)
		a.mouse_hook = nilp()
	}
	for b in a.binds {
		C.UnregisterHotKey(a.h_main, b.id)
	}
	a.binds.clear()
	a.tray_remove()
	a.pencil_on = false
	a.pencil_stop()
	a.blurw.destroy()
	a.dockw.destroy()
	a.panelw.destroy()
	a.toastw.destroy()
	a.ov.destroy()
	if !isnil(a.h_main) {
		C.DestroyWindow(a.h_main)
		a.h_main = nilp()
	}
}

fn replace_previous_instance() {
	parent := unsafe { voidptr(hwnd_message) }
	old := C.FindWindowExW(parent, nilp(), wide(class_main), unsafe { &u16(nil) })
	if isnil(old) {
		return
	}
	C.PostMessageW(old, wm_close, 0, 0)
	for _ in 0 .. 60 {
		C.Sleep(50)
		if isnil(C.FindWindowExW(parent, nilp(), wide(class_main), unsafe { &u16(nil) })) {
			return
		}
	}
}

fn startup_message(cfg Config) string {
	caps := hotkey_caps(cfg.toggle_focus).join('+')
	return 'Reading Focus is running - ${caps} to focus'
}

// run_app is the real entry point: registers classes, hotkeys, the tray icon and pumps messages.
fn run_app(cfg Config, cfg_path string, config_problems []string) int {
	C.SetProcessDPIAware()
	inst := C.GetModuleHandleW(unsafe { &u16(nil) })
	C.CreateMutexW(nilp(), 0, wide('Local\\ReadingFocusOverlayV'))
	if C.GetLastError() == error_already_exists {
		replace_previous_instance()
	}
	dpi := C.GetDpiForSystem()
	th := Theme{
		s:      if dpi >= 96 { f64(dpi) / 96.0 } else { 1.0 }
		accent: accent_from_u32(cfg.accent)
	}
	kit := new_kit(th) or {
		eprintln('cannot load fonts: ${err.msg()}')
		return 1
	}
	sw := C.GetSystemMetrics(sm_cxscreen)
	sh := C.GetSystemMetrics(sm_cyscreen)
	app = App{
		cfg:        cfg
		cfg_path:   cfg_path
		inst:       inst
		kit:        kit
		sw:         sw
		sh:         sh
		t0:         now_ms()
		ov_cv:      vraster.new_canvas(sw, sh)
		ov_mask:    vraster.new_mask(0, 0, sw, sh)
		dock_ui:    new_dock_ui(th)
		panel_ui:   new_panel_ui(&kit)
		pending_up: map[u32]bool{}
	}
	app.plus_cursor = load_plus_cursor()
	arrow := C.LoadCursorW(nilp(), unsafe { voidptr(idc_arrow) })
	classes_ok := register_class(class_main, voidptr(&main_proc), nilp(), nilp())
		&& register_class(class_overlay, voidptr(&overlay_proc), nilp(), nilp())
		&& register_class(class_dock, voidptr(&dock_proc), nilp(), arrow)
		&& register_class(class_panel, voidptr(&panel_proc), nilp(), arrow)
		&& register_class(class_toast, voidptr(&passive_proc), nilp(), nilp())
		&& register_class(class_pencil, voidptr(&passive_proc), nilp(), nilp())
		&& register_class(class_blur, voidptr(&passive_proc), nilp(), nilp())
	if !classes_ok {
		eprintln('failed to register window classes')
		return 1
	}
	app.h_main = C.CreateWindowExW(0, wide(class_main), wide('Reading Focus Overlay'), 0, 0, 0, 0,
		0, unsafe { voidptr(hwnd_message) }, nilp(), inst, nilp())
	if isnil(app.h_main) {
		eprintln('failed to create the message window')
		return 1
	}
	app.tb_created = C.RegisterWindowMessageW(wide('TaskbarCreated'))
	at_exit(fn () {
		restore_system_cursors()
	}) or {}
	C.SetTimer(app.h_main, timer_slow, 400, nilp())
	app.tray_add()
	failures := app.register_hotkeys()
	mut notes := config_problems.clone()
	notes << failures
	if notes.len > 0 {
		eprintln(notes.join('\n'))
		app.toast(notes[0] + if notes.len > 1 { ' (+${notes.len - 1} more)' } else { '' }, .warn,
			6000)
	} else {
		app.toast(startup_message(cfg), .info, 3200)
	}
	mut m := Msg{}
	for C.GetMessageW(&m, nilp(), 0, 0) > 0 {
		C.TranslateMessage(&m)
		C.DispatchMessageW(&m)
	}
	app.cleanup()
	return 0
}
