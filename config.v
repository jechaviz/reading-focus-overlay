module main

import os

// Configuration. The original kept hotkeys in config.ahk as AutoHotkey
// strings ("^+R"); the same notation is accepted here, optionally overridden
// from a `config.ini` that sits next to the executable.

const mod_alt = u32(0x0001)
const mod_control = u32(0x0002)
const mod_shift = u32(0x0004)
const mod_win = u32(0x0008)

struct Hotkey {
mut:
	mods u32
	key  string // upper-cased key name: "R", "F5", "ESC", "'" ...
}

struct Config {
mut:
	toggle_overlay    string = '^+R'
	toggle_clickblock string = '^+B'
	toggle_blur       string = '^+D'
	toggle_focus      string = '^+F'
	select_focus      string = '+Esc'
	toggle_alttab     string = "^+'"
	quit              string = '^+Q'
	panel             string = '^+P'
	accent            u32    = 0xFF7C6CFF
	style             Style
	pencil_max_edge   int = 300
	pencil_offset_x   int = 5
	pencil_offset_y   int = 10
}

// parse_hotkey understands the AutoHotkey modifier prefixes ^ (Ctrl), + (Shift),
// ! (Alt) and # (Win) followed by a key name or a single character.
fn parse_hotkey(spec string) !Hotkey {
	mut hk := Hotkey{}
	mut rest := spec.trim_space()
	for rest.len > 1 {
		c := rest[0]
		match c {
			`^` { hk.mods |= mod_control }
			`+` { hk.mods |= mod_shift }
			`!` { hk.mods |= mod_alt }
			`#` { hk.mods |= mod_win }
			else { break }
		}
		rest = rest[1..]
	}
	if rest.len == 0 {
		return error('empty hotkey "${spec}"')
	}
	hk.key = rest.to_upper()
	return hk
}

// apply_ini merges `[Shortcuts]` / `[Appearance]` ini text into cfg and returns
// the list of problems found (unknown keys, bad numbers, bad hotkeys) so the
// caller can show them instead of silently ignoring a typo.
fn (mut cfg Config) apply_ini(text string) []string {
	mut problems := []string{}
	mut section := ''
	for raw in text.split_into_lines() {
		line := raw.trim_space().trim_string_left('﻿')
		if line.len == 0 || line.starts_with(';') || line.starts_with('#') {
			continue
		}
		if line.starts_with('[') && line.ends_with(']') {
			section = line[1..line.len - 1].to_lower()
			continue
		}
		eq := line.index('=') or {
			problems << 'ignored line: ${line}'
			continue
		}
		key := line[..eq].trim_space().to_upper()
		val := line[eq + 1..].trim_space().trim('"')
		match section {
			'shortcuts' {
				parse_hotkey(val) or {
					problems << '${key}: ${err.msg()}'
					continue
				}
				match key {
					'HOTKEY_TOGGLE_OVERLAY' { cfg.toggle_overlay = val }
					'HOTKEY_TOGGLE_CLICKBLOCK' { cfg.toggle_clickblock = val }
					'HOTKEY_TOGGLE_BLUR' { cfg.toggle_blur = val }
					'HOTKEY_TOGGLE_FOCUS' { cfg.toggle_focus = val }
					'HOTKEY_SELECT_FOCUS' { cfg.select_focus = val }
					'HOTKEY_TOGGLE_ALTTAB' { cfg.toggle_alttab = val }
					'HOTKEY_QUIT' { cfg.quit = val }
					'HOTKEY_PANEL' { cfg.panel = val }
					else { problems << 'unknown shortcut ${key}' }
				}
			}
			'appearance' {
				if key == 'ACCENT' {
					if c := parse_hex_color(val) {
						cfg.accent = c
					} else {
						problems << 'ACCENT: "${val}" is not a #RRGGBB colour'
					}
					continue
				}
				n := val.int()
				ok := val.len > 0 && (val == '0' || n != 0)
				if !ok {
					problems << '${key}: "${val}" is not a number'
					continue
				}
				match key {
					'DIM_DRAG' { cfg.style.dim_drag = clamp_i(n, 0, 255) }
					'DIM_FINAL' { cfg.style.dim_final = clamp_i(n, 0, 255) }
					'PENCIL_MAX_EDGE' { cfg.pencil_max_edge = clamp_i(n, 16, 2048) }
					'PENCIL_OFFSET_X' { cfg.pencil_offset_x = n }
					'PENCIL_OFFSET_Y' { cfg.pencil_offset_y = n }
					else { problems << 'unknown appearance key ${key}' }
				}
			}
			else {
				problems << 'ignored ${key} outside a known section'
			}
		}
	}
	return problems
}

fn (cfg &Config) to_ini() string {
	mut s := '; Reading Focus Overlay configuration.\n'
	s += '; Hotkeys use AutoHotkey notation: ^ Ctrl, + Shift, ! Alt, # Win.\n'
	s += '[Shortcuts]\n'
	s += 'HOTKEY_TOGGLE_OVERLAY=${cfg.toggle_overlay}\n'
	s += 'HOTKEY_TOGGLE_CLICKBLOCK=${cfg.toggle_clickblock}\n'
	s += 'HOTKEY_TOGGLE_BLUR=${cfg.toggle_blur}\n'
	s += 'HOTKEY_TOGGLE_FOCUS=${cfg.toggle_focus}\n'
	s += 'HOTKEY_SELECT_FOCUS=${cfg.select_focus}\n'
	s += 'HOTKEY_TOGGLE_ALTTAB=${cfg.toggle_alttab}\n'
	s += 'HOTKEY_QUIT=${cfg.quit}\n'
	s += 'HOTKEY_PANEL=${cfg.panel}\n'
	s += '\n[Appearance]\n'
	s += 'DIM_DRAG=${cfg.style.dim_drag}\n'
	s += 'DIM_FINAL=${cfg.style.dim_final}\n'
	s += 'PENCIL_MAX_EDGE=${cfg.pencil_max_edge}\n'
	s += 'PENCIL_OFFSET_X=${cfg.pencil_offset_x}\n'
	s += 'PENCIL_OFFSET_Y=${cfg.pencil_offset_y}\n'
	s += 'ACCENT=${hex_color(cfg.accent)}\n'
	return s
}

// named_vk maps the portable part of the key vocabulary (letters, digits,
// function keys and the common named keys) to Windows virtual-key codes.
// Punctuation is layout dependent and resolved by the platform layer.
fn named_vk(key string) ?u32 {
	k := key.to_upper()
	if k.len == 1 {
		c := k[0]
		if (c >= `A` && c <= `Z`) || (c >= `0` && c <= `9`) {
			return u32(c)
		}
		return none
	}
	if k.len >= 2 && k[0] == `F` {
		n := k[1..].int()
		if n >= 1 && n <= 24 && k[1..] == n.str() {
			return u32(0x70 + n - 1)
		}
	}
	return match k {
		'ESC', 'ESCAPE' { u32(0x1B) }
		'TAB' { u32(0x09) }
		'SPACE' { u32(0x20) }
		'ENTER', 'RETURN' { u32(0x0D) }
		'BACKSPACE', 'BS' { u32(0x08) }
		'DELETE', 'DEL' { u32(0x2E) }
		'INSERT', 'INS' { u32(0x2D) }
		'HOME' { u32(0x24) }
		'END' { u32(0x23) }
		'PGUP' { u32(0x21) }
		'PGDN' { u32(0x22) }
		'LEFT' { u32(0x25) }
		'UP' { u32(0x26) }
		'RIGHT' { u32(0x27) }
		'DOWN' { u32(0x28) }
		else { none }
	}
}

// parse_hex_color reads #RRGGBB (or RRGGBB) into an opaque 0xFFRRGGBB.
fn parse_hex_color(s string) ?u32 {
	t := s.trim_space().trim_string_left('#')
	if t.len != 6 {
		return none
	}
	for ch in t {
		if !((ch >= `0` && ch <= `9`) || (ch >= `a` && ch <= `f`) || (ch >= `A` && ch <= `F`)) {
			return none
		}
	}
	return u32(0xFF000000) | u32(t.parse_uint(16, 32) or { return none })
}

fn hex_color(c u32) string {
	h := (c & 0xffffff).hex().to_upper()
	pad := '0'.repeat(if h.len < 6 { 6 - h.len } else { 0 })
	return '#' + pad + h
}

// hotkey_caps splits an AutoHotkey-style spec into keycap labels: ^+R -> [Ctrl, Shift, R].
fn hotkey_caps(spec string) []string {
	hk := parse_hotkey(spec) or { return [spec] }
	mut caps := []string{}
	if hk.mods & mod_control != 0 {
		caps << 'Ctrl'
	}
	if hk.mods & mod_alt != 0 {
		caps << 'Alt'
	}
	if hk.mods & mod_shift != 0 {
		caps << 'Shift'
	}
	if hk.mods & mod_win != 0 {
		caps << 'Win'
	}
	key := match hk.key {
		'ESC', 'ESCAPE' { 'Esc' }
		else {
			if hk.key.len > 1 { hk.key[..1] + hk.key[1..].to_lower() } else { hk.key }
		}
	}
	caps << key
	return caps
}

fn load_config(path string) (Config, []string) {
	mut cfg := Config{}
	if path.len == 0 || !os.exists(path) {
		return cfg, []string{}
	}
	text := os.read_file(path) or { return cfg, ['cannot read ${path}: ${err.msg()}'] }
	problems := cfg.apply_ini(text)
	return cfg, problems
}
