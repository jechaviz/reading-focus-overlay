module main

// Raw Win32 surface used by the app: types, constants and C declarations.
// Kept in one file so the platform dependency is easy to audit; the logic that
// uses it lives in app_win32.c.v.

#include <windows.h>

#flag windows -luser32
#flag windows -lgdi32
#flag windows -lkernel32

struct CPoint {
mut:
	x i32
	y i32
}

struct Size {
mut:
	cx i32
	cy i32
}

struct WinRect {
mut:
	left   i32
	top    i32
	right  i32
	bottom i32
}

struct Msg {
mut:
	hwnd    voidptr
	message u32
	wparam  u64
	lparam  i64
	time    u32
	pt      CPoint
}

struct WndClassExW {
	cb_size         u32
	style           u32
	lpfn_wnd_proc   voidptr
	cb_cls_extra    i32
	cb_wnd_extra    i32
	h_instance      voidptr
	h_icon          voidptr
	h_cursor        voidptr
	hbr_background  voidptr
	lpsz_menu_name  &u16 = unsafe { nil }
	lpsz_class_name &u16 = unsafe { nil }
	h_icon_sm       voidptr
}

struct PaintStruct {
mut:
	hdc          voidptr
	f_erase      i32
	rc_paint     WinRect
	f_restore    i32
	f_inc_update i32
	reserved     [32]u8
}

struct BitmapInfoHeader {
mut:
	size          u32
	width         i32
	height        i32
	planes        u16
	bit_count     u16
	compression   u32
	size_image    u32
	x_pels        i32
	y_pels        i32
	clr_used      u32
	clr_important u32
}

struct BitmapInfo {
mut:
	header BitmapInfoHeader
	colors [4]u8
}

struct BlendFunction {
	op     u8
	flags  u8
	alpha  u8
	format u8
}

struct KbdLlHookStruct {
	vk_code    u32
	scan_code  u32
	flags      u32
	time       u32
	extra_info u64
}

struct MouseLlHookStruct {
	pt         CPoint
	mouse_data u32
	flags      u32
	time       u32
	extra_info u64
}

// window messages
const wm_destroy = u32(0x0002)
const wm_close = u32(0x0010)
const wm_paint = u32(0x000F)
const wm_erasebkgnd = u32(0x0014)
const wm_setcursor = u32(0x0020)
const wm_mouseactivate = u32(0x0021)
const wm_keydown = u32(0x0100)
const wm_keyup = u32(0x0101)
const wm_syskeydown = u32(0x0104)
const wm_syskeyup = u32(0x0105)
const wm_timer = u32(0x0113)
const wm_mousemove = u32(0x0200)
const wm_lbuttondown = u32(0x0201)
const wm_lbuttonup = u32(0x0202)
const wm_hotkey = u32(0x0312)
const wm_app = u32(0x8000)
const wm_app_key = wm_app + 1

const ma_noactivate = i64(3)

// window styles
const ws_popup = u32(0x80000000)
const ws_ex_topmost = u32(0x00000008)
const ws_ex_transparent = u32(0x00000020)
const ws_ex_toolwindow = u32(0x00000080)
const ws_ex_layered = u32(0x00080000)
const ws_ex_noactivate = u32(0x08000000)

const sw_hide = 0
const sw_shownoactivate = 4

const swp_nosize = u32(0x0001)
const swp_nomove = u32(0x0002)
const swp_noactivate = u32(0x0010)
const swp_showwindow = u32(0x0040)

const hwnd_topmost = i64(-1)
const hwnd_message = i64(-3)

const ulw_alpha = u32(0x00000002)
const ac_src_over = u8(0)
const ac_src_alpha = u8(1)

const wh_keyboard_ll = 13
const wh_mouse_ll = 14
const hc_action = 0
const llkhf_altdown = u32(0x20)

const srccopy = u32(0x00CC0020)
const captureblt = u32(0x40000000)
const halftone = 4
const dib_rgb_colors = u32(0)
const bi_rgb = u32(0)

const sm_cxscreen = 0
const sm_cyscreen = 1

const idc_cross = i64(32515)
const ocr_normal = u32(32512)
const spi_setcursors = u32(0x0057)

const error_already_exists = u32(183)
const transparent_bk = 1

const dt_center = u32(0x0001)
const dt_vcenter = u32(0x0004)
const dt_singleline = u32(0x0020)
const dt_noprefix = u32(0x0800)

const vk_lwin = u32(0x5B)
const vk_rwin = u32(0x5C)
const vk_tab = u32(0x09)
const vk_control = 0x11
const vk_shift = 0x10
const vk_menu = 0x12

fn C.CreateWindowExW(u32, &u16, &u16, u32, int, int, int, int, voidptr, voidptr, voidptr, voidptr) voidptr
fn C.DefWindowProcW(voidptr, u32, u64, i64) i64
fn C.RegisterClassExW(&WndClassExW) u16
fn C.GetModuleHandleW(&u16) voidptr
fn C.GetLastError() u32
fn C.DestroyWindow(voidptr) int
fn C.ShowWindow(voidptr, int) int
fn C.IsWindow(voidptr) int
fn C.IsWindowVisible(voidptr) int
fn C.SetWindowPos(voidptr, voidptr, int, int, int, int, u32) int
fn C.GetWindowRect(voidptr, &WinRect) int
fn C.FindWindowW(&u16, &u16) voidptr
fn C.FindWindowExW(voidptr, voidptr, &u16, &u16) voidptr
fn C.GetMessageW(&Msg, voidptr, u32, u32) int
fn C.TranslateMessage(&Msg) int
fn C.DispatchMessageW(&Msg) i64
fn C.PostMessageW(voidptr, u32, u64, i64) int
fn C.PostQuitMessage(int)
fn C.SetTimer(voidptr, u64, u32, voidptr) u64
fn C.KillTimer(voidptr, u64) int
fn C.RegisterHotKey(voidptr, int, u32, u32) int
fn C.UnregisterHotKey(voidptr, int) int
fn C.VkKeyScanW(u16) i16
fn C.GetAsyncKeyState(int) i16
fn C.GetCursorPos(&CPoint) int
fn C.SetCursor(voidptr) voidptr
fn C.LoadCursorW(voidptr, voidptr) voidptr
fn C.LoadCursorFromFileW(&u16) voidptr
fn C.CreateCursor(voidptr, int, int, int, int, voidptr, voidptr) voidptr
fn C.SetSystemCursor(voidptr, u32) int
fn C.SystemParametersInfoW(u32, u32, voidptr, u32) int
fn C.SetCapture(voidptr) voidptr
fn C.ReleaseCapture() int
fn C.GetSystemMetrics(int) int
fn C.SetProcessDPIAware() int
fn C.SetWindowsHookExW(int, voidptr, voidptr, u32) voidptr
fn C.UnhookWindowsHookEx(voidptr) int
fn C.CallNextHookEx(voidptr, int, u64, i64) i64
fn C.CreateMutexW(voidptr, int, &u16) voidptr
fn C.Sleep(u32)
fn C.UpdateLayeredWindow(voidptr, voidptr, &CPoint, &Size, voidptr, &CPoint, u32, &BlendFunction, u32) int
fn C.InvalidateRect(voidptr, voidptr, int) int
fn C.BeginPaint(voidptr, &PaintStruct) voidptr
fn C.EndPaint(voidptr, &PaintStruct) int
fn C.FillRect(voidptr, &WinRect, voidptr) int
fn C.DrawTextW(voidptr, &u16, int, &WinRect, u32) int
fn C.GetTextExtentPoint32W(voidptr, &u16, int, &Size) int
fn C.MessageBoxW(voidptr, &u16, &u16, u32) int

fn C.GetDC(voidptr) voidptr
fn C.ReleaseDC(voidptr, voidptr) int
fn C.CreateCompatibleDC(voidptr) voidptr
fn C.DeleteDC(voidptr) int
fn C.CreateCompatibleBitmap(voidptr, int, int) voidptr
fn C.CreateDIBSection(voidptr, &BitmapInfo, u32, &voidptr, voidptr, u32) voidptr
fn C.SelectObject(voidptr, voidptr) voidptr
fn C.DeleteObject(voidptr) int
fn C.BitBlt(voidptr, int, int, int, int, voidptr, int, int, u32) int
fn C.StretchBlt(voidptr, int, int, int, int, voidptr, int, int, int, int, u32) int
fn C.SetStretchBltMode(voidptr, int) int
fn C.CreateSolidBrush(u32) voidptr
fn C.CreatePen(int, int, u32) voidptr
fn C.CreateFontW(int, int, int, int, int, u32, u32, u32, u32, u32, u32, u32, u32, &u16) voidptr
fn C.SetBkMode(voidptr, int) int
fn C.SetTextColor(voidptr, u32) u32
fn C.Rectangle(voidptr, int, int, int, int) int
fn C.GdiFlush() int

fn wide(s string) &u16 {
	return s.to_wide()
}

// rgb builds a GDI COLORREF.
fn rgb(r int, g int, b int) u32 {
	return u32(r & 0xff) | (u32(g & 0xff) << 8) | (u32(b & 0xff) << 16)
}

// loword/hiword helpers for packed coordinates (signed, like GET_X_LPARAM).
fn lparam_x(lp i64) int {
	return int(i16(u64(lp) & 0xffff))
}

fn lparam_y(lp i64) int {
	return int(i16((u64(lp) >> 16) & 0xffff))
}

// ---- tray / misc additions for the redesigned shell ----------------------------------

#include <shellapi.h>
#flag windows -lshell32

struct TrackMouseEventS {
	cb_size    u32
	flags      u32
	hwnd_track voidptr
	hover_time u32
}

struct IconInfo {
	f_icon    u32
	x_hotspot u32
	y_hotspot u32
	hbm_mask  voidptr
	hbm_color voidptr
}

struct NotifyIconDataW {
mut:
	cb_size           u32
	hwnd              voidptr
	uid               u32
	uflags            u32
	ucallback_message u32
	hicon             voidptr
	sz_tip            [128]u16
	dw_state          u32
	dw_state_mask     u32
	sz_info           [256]u16
	u_version         u32
	sz_info_title     [64]u16
	dw_info_flags     u32
	guid_item         [16]u8
	h_balloon_icon    voidptr
}

const wm_activate = u32(0x0006)
const wm_mouseleave = u32(0x02A3)
const wm_rbuttonup = u32(0x0205)
const wm_app_tray = wm_app + 2
const tme_leave = u32(2)
const nim_add = u32(0)
const nim_modify = u32(1)
const nim_delete = u32(2)
const nif_message = u32(1)
const nif_icon = u32(2)
const nif_tip = u32(4)
const spi_getworkarea = u32(0x30)
const idc_arrow = i64(32512)
const sm_cxsmicon = 49
const sw_show = 5

fn C.GetDpiForSystem() u32
fn C.GetTickCount64() u64
fn C.TrackMouseEvent(&TrackMouseEventS) int
fn C.Shell_NotifyIconW(u32, &NotifyIconDataW) int
fn C.RegisterWindowMessageW(&u16) u32
fn C.CreateIconIndirect(&IconInfo) voidptr
fn C.DestroyIcon(voidptr) int
fn C.CreateBitmap(int, int, u32, u32, voidptr) voidptr
fn C.ShellExecuteW(voidptr, &u16, &u16, &u16, &u16, int) voidptr
fn C.SetForegroundWindow(voidptr) int
