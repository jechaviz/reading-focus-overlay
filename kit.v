module main

import os
import vraster
import vfonts
import vfa_icons

// Design tokens and text/icon helpers on top of the shared libraries:
//   vraster  - anti-aliased shapes, gradients, shadows, masks
//   vfonts   - TrueType text (Segoe UI when installed, bundled Inter/Roboto otherwise)
//   vfa_icons - Font Awesome icon font

fn rgba(r int, g int, b int, a int) vraster.RGBA {
	return vraster.rgba(u8(clamp_i(r, 0, 255)), u8(clamp_i(g, 0, 255)), u8(clamp_i(b, 0, 255)),
		u8(clamp_i(a, 0, 255)))
}

fn clamp_f(v f64, lo f64, hi f64) f64 {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

fn lerp_f(a f64, b f64, t f64) f64 {
	return a + (b - a) * t
}

struct Theme {
mut:
	s      f64          = 1.0
	accent vraster.RGBA = vraster.RGBA{124, 108, 255, 255}
}

fn (t Theme) px(v f64) int {
	return int(v * t.s + 0.5)
}

fn (t Theme) f(v f64) f64 {
	return v * t.s
}

fn (t Theme) acc(alpha int) vraster.RGBA {
	return vraster.RGBA{t.accent.r, t.accent.g, t.accent.b, u8(clamp_i(alpha, 0, 255))}
}

fn (t Theme) acc_top() vraster.RGBA {
	return vraster.mix(t.accent, vraster.RGBA{255, 255, 255, 255}, 0.22)
}

fn (t Theme) acc_bot() vraster.RGBA {
	return vraster.mix(t.accent, vraster.RGBA{0, 0, 0, 255}, 0.2)
}

fn accent_from_u32(c u32) vraster.RGBA {
	return vraster.RGBA{u8((c >> 16) & 0xff), u8((c >> 8) & 0xff), u8(c & 0xff), 255}
}

struct Palette {
	glass_top vraster.RGBA
	glass_bot vraster.RGBA
	border    vraster.RGBA
	divider   vraster.RGBA
	text      vraster.RGBA
	text2     vraster.RGBA
	text3     vraster.RGBA
	hover     vraster.RGBA
	press     vraster.RGBA
	danger    vraster.RGBA
	ok        vraster.RGBA
	warn      vraster.RGBA
	track_off vraster.RGBA
	key_top   vraster.RGBA
	key_bot   vraster.RGBA
	key_bd    vraster.RGBA
	shadow    vraster.RGBA
	shadow_lo vraster.RGBA
	white     vraster.RGBA
}

fn palette() Palette {
	return Palette{
		glass_top: rgba(40, 43, 62, 246)
		glass_bot: rgba(22, 24, 36, 248)
		border:    rgba(255, 255, 255, 36)
		divider:   rgba(255, 255, 255, 22)
		text:      rgba(240, 242, 249, 255)
		text2:     rgba(166, 173, 196, 255)
		text3:     rgba(108, 115, 138, 255)
		hover:     rgba(255, 255, 255, 22)
		press:     rgba(255, 255, 255, 40)
		danger:    rgba(255, 98, 120, 255)
		ok:        rgba(72, 226, 158, 255)
		warn:      rgba(255, 189, 84, 255)
		track_off: rgba(255, 255, 255, 44)
		key_top:   rgba(255, 255, 255, 36)
		key_bot:   rgba(255, 255, 255, 16)
		key_bd:    rgba(255, 255, 255, 56)
		shadow:    rgba(0, 0, 0, 150)
		shadow_lo: rgba(0, 0, 0, 100)
		white:     rgba(255, 255, 255, 255)
	}
}

enum TextStyle {
	title
	body
	semibold
	small
	key
	badge
}

enum Icon {
	rect
	multi
	poly
	close
	check
	undo
	pencil
	block
	blur
	alttab
	focus
	info
	warn
	minus
}

fn icon_code(ic Icon) int {
	return match ic {
		.rect { 0xf5cb } // vector-square
		.multi { 0xf247 } // object-group
		.poly { 0xf5ee } // draw-polygon
		.close { 0xf00d } // xmark
		.check { 0xf00c }
		.undo { 0xf2ea } // rotate-left
		.pencil { 0xf303 }
		.block { 0xf05e } // ban
		.blur { 0xf043 } // droplet
		.alttab { 0xf11c } // keyboard
		.focus { 0xf125 } // crop
		.info { 0xf05a } // circle-info
		.warn { 0xf071 } // triangle-exclamation
		.minus { 0xf068 }
	}
}

struct Kit {
mut:
	th    Theme
	reg   vfonts.Font
	semi  vfonts.Font
	icons vfonts.Font
}

fn load_first(paths []string) !vfonts.Font {
	for p in paths {
		if os.exists(p) {
			return vfonts.load(p)
		}
	}
	return error('no usable font among ${paths}')
}

fn new_kit(th Theme) !Kit {
	win := os.getenv_opt('WINDIR') or { 'C:/Windows' }
	return Kit{
		th:    th
		reg:   load_first(['${win}/Fonts/segoeui.ttf', vfonts.inter_path()])!
		semi:  load_first(['${win}/Fonts/seguisb.ttf', vfonts.roboto_bold_path()])!
		icons: vfonts.load(vfa_icons.solid_font)!
	}
}

fn (k &Kit) face(st TextStyle) (vfonts.Font, int) {
	return match st {
		.title { k.semi, k.th.px(17) }
		.body { k.reg, k.th.px(14) }
		.semibold { k.semi, k.th.px(14) }
		.small { k.reg, k.th.px(12) }
		.key { k.semi, k.th.px(11) }
		.badge { k.semi, k.th.px(12) }
	}
}

fn (k &Kit) width(text string, st TextStyle) int {
	f, px := k.face(st)
	return f.text_width(text, px)
}

fn (k &Kit) text_l(mut cv vraster.Canvas, text string, st TextStyle, x int, cy int, col vraster.RGBA) int {
	f, px := k.face(st)
	return f.draw_text_vcenter(mut cv, text, x, cy, px, col)
}

fn (k &Kit) text_c(mut cv vraster.Canvas, text string, st TextStyle, cx int, cy int, col vraster.RGBA) {
	f, px := k.face(st)
	f.draw_text_center(mut cv, text, cx, cy, px, col)
}

fn (k &Kit) text_r(mut cv vraster.Canvas, text string, st TextStyle, right int, cy int, col vraster.RGBA) {
	f, px := k.face(st)
	f.draw_text_vcenter(mut cv, text, right - f.text_width(text, px), cy, px, col)
}

// icon draws a Font Awesome glyph centred on (cx, cy); size is in design pixels.
fn (k &Kit) icon(mut cv vraster.Canvas, ic Icon, cx int, cy int, size f64, col vraster.RGBA) {
	k.icons.draw_icon_center(mut cv, icon_code(ic), cx, cy, k.th.px(size), col)
}
