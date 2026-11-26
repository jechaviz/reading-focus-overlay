module main

import vraster

// LayerWin: a per-pixel-alpha top-level window fed from a vraster.Canvas. Every visual element
// (dim overlay, dock, panel, toast, pencil, blurred taskbar) is one of these.

struct LayerWin {
mut:
	hwnd  voidptr
	dc    voidptr
	bmp   voidptr
	old   voidptr
	bits  voidptr
	w     int
	h     int
	shown bool
}

fn nilp() voidptr {
	return unsafe { nil }
}

fn topmost() voidptr {
	return unsafe { voidptr(hwnd_topmost) }
}

fn (l &LayerWin) exists() bool {
	return !isnil(l.hwnd)
}

fn (mut l LayerWin) create(class string, extra_ex u32, inst voidptr) bool {
	if l.exists() {
		return true
	}
	l.hwnd = C.CreateWindowExW(ws_ex_layered | ws_ex_topmost | ws_ex_toolwindow | extra_ex,
		wide(class), wide('Reading Focus Overlay'), ws_popup, 0, 0, 1, 1, nilp(), nilp(),
		inst, nilp())
	return l.exists()
}

fn (mut l LayerWin) free_surface() {
	if !isnil(l.dc) {
		if !isnil(l.old) {
			C.SelectObject(l.dc, l.old)
		}
		C.DeleteDC(l.dc)
	}
	if !isnil(l.bmp) {
		C.DeleteObject(l.bmp)
	}
	l.dc = nilp()
	l.bmp = nilp()
	l.old = nilp()
	l.bits = nilp()
	l.w = 0
	l.h = 0
}

fn (mut l LayerWin) ensure_surface(w int, h int) bool {
	if !isnil(l.bits) && l.w == w && l.h == h {
		return true
	}
	l.free_surface()
	screen := C.GetDC(nilp())
	l.dc = C.CreateCompatibleDC(screen)
	mut bi := BitmapInfo{}
	bi.header.size = u32(sizeof(BitmapInfoHeader))
	bi.header.width = w
	bi.header.height = -h // top-down
	bi.header.planes = 1
	bi.header.bit_count = 32
	bi.header.compression = bi_rgb
	mut bits := nilp()
	l.bmp = C.CreateDIBSection(screen, &bi, dib_rgb_colors, &bits, nilp(), 0)
	C.ReleaseDC(nilp(), screen)
	if isnil(l.bmp) || isnil(bits) {
		l.free_surface()
		return false
	}
	l.bits = bits
	l.old = C.SelectObject(l.dc, l.bmp)
	l.w = w
	l.h = h
	return true
}

// present uploads the canvas and shows the window at (x, y) with a constant opacity on top of the
// per-pixel alpha. show_cmd is SW_SHOWNOACTIVATE for passive windows.
fn (mut l LayerWin) present(cv &vraster.Canvas, x int, y int, opacity u8, show_cmd int) {
	if !l.exists() || !l.ensure_surface(cv.w, cv.h) {
		return
	}
	cv.copy_bgra(l.bits, 255)
	screen := C.GetDC(nilp())
	dst := CPoint{i32(x), i32(y)}
	src := CPoint{0, 0}
	size := Size{i32(cv.w), i32(cv.h)}
	blend := BlendFunction{ac_src_over, 0, opacity, ac_src_alpha}
	C.UpdateLayeredWindow(l.hwnd, screen, &dst, &size, l.dc, &src, 0, &blend, ulw_alpha)
	C.ReleaseDC(nilp(), screen)
	if !l.shown {
		C.ShowWindow(l.hwnd, show_cmd)
		l.shown = true
	}
}

fn (mut l LayerWin) raise() {
	if l.exists() && l.shown {
		C.SetWindowPos(l.hwnd, topmost(), 0, 0, 0, 0, swp_nomove | swp_nosize | swp_noactivate)
	}
}

fn (mut l LayerWin) hide() {
	if l.exists() && l.shown {
		C.ShowWindow(l.hwnd, sw_hide)
	}
	l.shown = false
}

fn (mut l LayerWin) destroy() {
	if l.exists() {
		C.DestroyWindow(l.hwnd)
	}
	l.hwnd = nilp()
	l.free_surface()
	l.shown = false
}

// icon_from_canvas builds an HICON from a premultiplied canvas (used for the tray).
fn icon_from_canvas(cv &vraster.Canvas) voidptr {
	screen := C.GetDC(nilp())
	mut bi := BitmapInfo{}
	bi.header.size = u32(sizeof(BitmapInfoHeader))
	bi.header.width = cv.w
	bi.header.height = -cv.h
	bi.header.planes = 1
	bi.header.bit_count = 32
	bi.header.compression = bi_rgb
	mut bits := nilp()
	color := C.CreateDIBSection(screen, &bi, dib_rgb_colors, &bits, nilp(), 0)
	C.ReleaseDC(nilp(), screen)
	if isnil(color) || isnil(bits) {
		return nilp()
	}
	cv.copy_bgra(bits, 255)
	zeros := []u8{len: ((cv.w + 15) / 16) * 2 * cv.h}
	mask := C.CreateBitmap(cv.w, cv.h, 1, 1, zeros.data)
	info := IconInfo{
		f_icon:    1
		hbm_mask:  mask
		hbm_color: color
	}
	icon := C.CreateIconIndirect(&info)
	C.DeleteObject(color)
	C.DeleteObject(mask)
	return icon
}
