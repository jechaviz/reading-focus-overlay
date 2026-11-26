module main

fn test_parse_hotkey_modifiers() {
	hk := parse_hotkey('^+R')!
	assert hk.mods == (mod_control | mod_shift)
	assert hk.key == 'R'
	esc := parse_hotkey('+Esc')!
	assert esc.mods == mod_shift
	assert esc.key == 'ESC'
	q := parse_hotkey("^+'")!
	assert q.key == "'"
	assert q.mods == (mod_control | mod_shift)
}

fn test_parse_hotkey_bare_modifier_char_is_the_key() {
	// "+" alone means the plus key, not an empty chord
	hk := parse_hotkey('+')!
	assert hk.key == '+'
	assert hk.mods == 0
	if _ := parse_hotkey('  ') {
		assert false
	}
}

fn test_ini_overrides_and_reports_problems() {
	mut cfg := Config{}
	problems := cfg.apply_ini('[Shortcuts]\nHOTKEY_TOGGLE_FOCUS=!F8\nHOTKEY_BOGUS=^A\n[Appearance]\nDIM_FINAL=300\nDIM_DRAG=abc\n')
	assert cfg.toggle_focus == '!F8'
	assert cfg.style.dim_final == 255
	assert cfg.style.dim_drag == 120
	assert problems.len == 2
}

fn test_named_vk() {
	assert named_vk('R')? == u32(0x52)
	assert named_vk('5')? == u32(0x35)
	assert named_vk('ESC')? == u32(0x1B)
	assert named_vk('f5')? == u32(0x74)
	assert named_vk('F24')? == u32(0x87)
	assert named_vk('F')? == u32(0x46) // the letter F, not a function key
	if _ := named_vk('F25') {
		assert false
	}
	if _ := named_vk("'") {
		assert false // punctuation is resolved by the platform layer
	}
}

fn test_ini_roundtrip() {
	mut cfg := Config{}
	cfg.toggle_overlay = '^!P'
	cfg.style.dim_final = 200
	mut back := Config{}
	problems := back.apply_ini(cfg.to_ini())
	assert problems.len == 0
	assert back.toggle_overlay == '^!P'
	assert back.style.dim_final == 200
}

fn test_accent_colour_parsing_and_roundtrip() {
	assert parse_hex_color('#7C6CFF')? == u32(0xFF7C6CFF)
	assert parse_hex_color('00ff80')? == u32(0xFF00FF80)
	if _ := parse_hex_color('#12345') {
		assert false
	}
	if _ := parse_hex_color('#GGGGGG') {
		assert false
	}
	mut cfg := Config{}
	problems := cfg.apply_ini('[Appearance]\nACCENT=#112233\n')
	assert problems.len == 0 && cfg.accent == u32(0xFF112233)
	assert hex_color(cfg.accent) == '#112233'
	mut back := Config{}
	assert back.apply_ini(cfg.to_ini()).len == 0
	assert back.accent == cfg.accent
	assert cfg.apply_ini('[Appearance]\nACCENT=nope\n').len == 1
}

fn test_hotkey_caps_are_human_readable() {
	assert hotkey_caps('^+R') == ['Ctrl', 'Shift', 'R']
	assert hotkey_caps('+Esc') == ['Shift', 'Esc']
	assert hotkey_caps('^!F5') == ['Ctrl', 'Alt', 'F5']
	assert hotkey_caps('#Space') == ['Win', 'Space']
}

fn test_panel_hotkey_is_configurable() {
	mut cfg := Config{}
	assert cfg.panel == '^+P'
	cfg.apply_ini('[Shortcuts]\nHOTKEY_PANEL=^!P\n')
	assert cfg.panel == '^!P'
}
