module main

import os
import stbi
import vraster

const usage = "Reading Focus Overlay (V)

Usage: reading_focus_overlay [options]

  --config <file>     read hotkeys/appearance from this ini (default: config.ini
                      next to the executable)
  --print-config      print the effective configuration as ini and exit
  --write-config      write the effective configuration to the config path and exit
  --demo <prefix>     render the UI to <prefix>_rect/_polygon/_final/_panel.png
                      (no desktop needed); --scale <n> renders at n x DPI
  -h, --help          show this help

Default hotkeys:
  Ctrl+Shift+F  focus frame           Ctrl+Shift+R  pencil cursor
  Ctrl+Shift+B  block clicks          Ctrl+Shift+D  blur taskbar
  Ctrl+Shift+'  block Alt+Tab          Shift+Esc     re-select focus area
  Ctrl+Shift+P  control panel         Ctrl+Shift+Q  quit

The tray icon opens the control panel too. While selecting: 1 rectangle,
2 multi-area, 3 polygon, 4/Esc cancel; Enter, Space and Backspace as shown in the dock.
"

fn flag_value(args []string, name string) ?string {
	for i, a in args {
		if a == name && i + 1 < args.len {
			return args[i + 1]
		}
		if a.starts_with(name + '=') {
			return a[name.len + 1..]
		}
	}
	return none
}

fn default_config_path() string {
	exe_dir := os.dir(os.executable())
	next_to_exe := os.join_path(exe_dir, 'config.ini')
	if os.exists(next_to_exe) {
		return next_to_exe
	}
	cwd := os.join_path(os.getwd(), 'config.ini')
	if os.exists(cwd) {
		return cwd
	}
	return next_to_exe
}

// ---- offscreen demo ---------------------------------------------------------------------------

fn demo_page(k &Kit, w int, h int) vraster.Canvas {
	th := k.th
	mut c := vraster.new_canvas(w, h)
	c.clear(rgba(246, 245, 240, 255))
	ink := rgba(52, 58, 72, 255)
	soft := rgba(110, 118, 135, 255)
	lines := [
		'The quiet discipline of reading',
		'',
		'A page is a small room. Everything outside it is a corridor you can walk later,',
		'so close the doors, dim the hallway and let one paragraph fill your whole view.',
		'Reading is not a race. It is a slow conversation with someone who is not here,',
		'and it deserves the kind of attention you would give a person across the table.',
		'',
		'Focus is the habit of returning. The mind wanders; the frame is simply a place',
		'to come back to. Every time you notice a drift and return, you strengthen the',
		'muscle that makes deep work possible, and the paragraph gets a little clearer.',
		'',
		'Choose the passage that matters, mark its edges and let the rest fall into shadow.',
		'Nothing is lost by looking away from the noise. The notifications will keep.',
		'The tabs will wait. The sentence in front of you will not wait forever, though.',
		'',
		'When you are done, lift the frame and the whole screen returns, exactly as it was.',
	]
	mut y := th.px(46)
	for i, line in lines {
		if line.len > 0 {
			if i == 0 {
				k.semi.draw_text(mut c, line, th.px(70), y - th.px(10), th.px(26), ink)
				y += th.px(14)
			} else {
				k.reg.draw_text(mut c, line, th.px(70), y - th.px(8), th.px(16), if i > 10 {
					soft
				} else {
					ink
				})
			}
		}
		y += th.px(31)
	}
	return c
}

fn compose_scene(page &vraster.Canvas, sel &Selection, v Visuals, k &Kit, dock bool, toast_text string) vraster.Canvas {
	mut out := page.clone()
	mut ov := vraster.new_canvas(page.w, page.h)
	mut mask := vraster.new_mask(0, 0, page.w, page.h)
	sel.compose(mut ov, mut mask, v, k)
	out.composite_over(ov, 0, 0, 255)
	if dock {
		ui := new_dock_ui(k.th)
		mut st := DockState{}
		st.pill.set(f64(mode_index(sel.mode)))
		st.set_hot(.apply)
		st.hov[int(DockId.apply)].set(1.0)
		d := dock_render(&ui, &st, sel, k)
		out.composite_over(d, (page.w - ui.lay.card.w) / 2 - ui.lay.margin, k.th.px(28) - ui.lay.margin,
			255)
	}
	if toast_text.len > 0 {
		t := toast_frame(toast_text, .on, k)
		lay := toast_layout(toast_text, k)
		out.composite_over(t, (page.w - lay.cw) / 2, page.h - lay.card.h - k.th.px(34) - lay.card.y,
			255)
	}
	return out
}

fn save_png(c &vraster.Canvas, path string) ! {
	mut buf := []u8{len: c.w * c.h * 3}
	for i in 0 .. c.w * c.h {
		buf[i * 3] = c.px[i * 4]
		buf[i * 3 + 1] = c.px[i * 4 + 1]
		buf[i * 3 + 2] = c.px[i * 4 + 2]
	}
	stbi.stbi_write_png(path, c.w, c.h, 3, buf.data, c.w * 3)!
}

fn render_demo(prefix string, scale f64, cfg Config) ! {
	th := Theme{
		s:      scale
		accent: accent_from_u32(cfg.accent)
	}
	k := new_kit(th)!
	w := th.px(1280)
	h := th.px(720)
	page := demo_page(&k, w, h)
	px := fn [th] (v int) int {
		return th.px(f64(v))
	}

	// 1. dragging a rectangle: crosshair released, dimension badge, glow
	mut s1 := Selection{}
	s1.toggle_focus()
	s1.mouse_down(Pt{px(120), px(150)})
	s1.mouse_move(Pt{px(780), px(430)})
	img1 := compose_scene(&page, &s1, Visuals{
		dim:         f64(cfg.style.dim_drag)
		cursor:      Pt{px(780), px(430)}
		have_cursor: true
	}, &k, true, '')
	save_png(&img1, '${prefix}_rect.png')!

	// 2. polygon mode: one finished shape, one in progress with a rubber band
	mut s2 := Selection{}
	s2.toggle_focus()
	s2.set_mode(.polygon)
	for p in [Pt{px(90), px(130)}, Pt{px(560), px(120)}, Pt{px(540), px(250)}, Pt{px(100), px(262)}] {
		s2.mouse_down(p)
		s2.mouse_up(p)
	}
	s2.on_key(vk_return, false)
	for p in [Pt{px(640), px(330)}, Pt{px(1040), px(310)}, Pt{px(1070), px(470)}, Pt{px(700), px(500)}] {
		s2.mouse_down(p)
		s2.mouse_up(p)
	}
	img2 := compose_scene(&page, &s2, Visuals{
		dim:         f64(cfg.style.dim_drag)
		t_ms:        900
		cursor:      Pt{px(650), px(345)}
		have_cursor: true
	}, &k, true, '')
	save_png(&img2, '${prefix}_polygon.png')!

	// 3. committed: dark dim, click-through holes, commit pulse, toast
	mut s3 := Selection{}
	s3.toggle_focus()
	s3.mouse_down(Pt{px(120), px(150)})
	s3.mouse_up(Pt{px(820), px(470)})
	img3 := compose_scene(&page, &s3, Visuals{
		dim:   f64(cfg.style.dim_final)
		pulse: 0.28
	}, &k, false, 'Focus frame on')
	save_png(&img3, '${prefix}_final.png')!

	// 4. the tray control panel
	pui := new_panel_ui(&k)
	mut pst := PanelState{}
	pst.set_hot(.row2)
	pst.hov[int(PanelId.row2)].set(1.0)
	on := [true, true, false, true, false]
	rows := [
		PanelRow{'Focus frame', hotkey_caps(cfg.toggle_focus), .focus, on[0]},
		PanelRow{'Pencil cursor', hotkey_caps(cfg.toggle_overlay), .pencil, on[1]},
		PanelRow{'Block clicks', hotkey_caps(cfg.toggle_clickblock), .block, on[2]},
		PanelRow{'Blur taskbar', hotkey_caps(cfg.toggle_blur), .blur, on[3]},
		PanelRow{'Block Alt+Tab', hotkey_caps(cfg.toggle_alttab), .alttab, on[4]},
	]
	for i in 0 .. 5 {
		pst.sw[i].set(if on[i] { 1.0 } else { 0.0 })
	}
	panel := panel_render(&pui, &pst, rows, &k)
	mut img4 := page.clone()
	img4.composite_over(panel, w - pui.lay.cw - px(40), h - pui.lay.ch - px(10), 255)
	save_png(&img4, '${prefix}_panel.png')!
}

fn main() {
	args := os.args[1..]
	if '-h' in args || '--help' in args {
		print(usage)
		return
	}
	cfg_path := flag_value(args, '--config') or { default_config_path() }
	cfg, problems := load_config(cfg_path)
	if '--print-config' in args {
		print(cfg.to_ini())
		for p in problems {
			eprintln('config: ${p}')
		}
		return
	}
	if '--write-config' in args {
		os.write_file(cfg_path, cfg.to_ini()) or {
			eprintln('cannot write ${cfg_path}: ${err.msg()}')
			exit(1)
		}
		println('wrote ${cfg_path}')
		return
	}
	if prefix := flag_value(args, '--demo') {
		scale := (flag_value(args, '--scale') or { '1' }).f64()
		render_demo(prefix, if scale > 0 { scale } else { 1.0 }, cfg) or {
			eprintln('demo failed: ${err.msg()}')
			exit(1)
		}
		println('wrote ${prefix}_rect/_polygon/_final/_panel.png')
		return
	}
	exit(run_app(cfg, cfg_path, problems))
}
