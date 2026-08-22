package demo

import ui "../loom"

Track :: struct {
	id, title, artist: string
}

Nav :: enum {
	Songs,
	Albums,
	Artists,
}

App :: struct {
	dock:      ui.Dock_Id,
	laid_out:  bool,
	dark:      bool,
	menu:      bool,
	notify:    bool,
	compact:   bool,
	nav:       Nav,
	volume:    f32,
	search:    [dynamic]byte,
	tracks:    []Track,
	playing:   string,
	cursor_at: ui.Cursor,
}

@(rodata)
TRACKS := []Track {
	{"t1", "Kiln", "Rival Consoles"},
	{"t2", "Windswept", "Bibio"},
	{"t3", "An Ending", "Brian Eno"},
	{"t4", "Nightcall", "Kavinsky"},
	{"t5", "Teardrop", "Massive Attack"},
	{"t6", "Svefn-g-englar", "Sigur Ros"},
	{"t7", "Open Eye Signal", "Jon Hopkins"},
	{"t8", "Weightless", "Marconi Union"},
}

@(rodata)
LINEAR_STOPS := []ui.Stop{{0, {110, 114, 240, 255}}, {1, {79, 191, 139, 255}}}

@(rodata)
MULTI_STOPS := []ui.Stop {
	{0.0, {229, 99, 107, 255}},
	{0.5, {224, 165, 74, 255}},
	{1.0, {79, 163, 217, 255}},
}

@(rodata)
RADIAL_STOPS := []ui.Stop{{0, {244, 245, 255, 255}}, {1, {41, 48, 63, 255}}}

@(rodata)
CURSORS := []ui.Cursor {
	.Default,
	.Pointer,
	.Text,
	.Resize_H,
	.Resize_V,
	.Grab,
	.Grabbing,
	.Not_Allowed,
}

init_app :: proc(app: ^App) {
	app^ = {}
	app.tracks = TRACKS
	app.playing = "t3"
	app.volume = 0.6
	app.dark = true
	app.search = make([dynamic]byte, 0, 32)
	ui.buf_set(&app.search, "ambient")
}

destroy_app :: proc(app: ^App) {
	delete(app.search)
}

frame :: proc(app: ^App, input: ui.Input) -> ui.Draw_List {
	ui.begin_frame(input)
	root(app)
	return ui.end_frame()
}

root :: proc(app: ^App) {
	t := ui.theme()
	ui.scope(
		{
			props = {
				w = ui.Grow(1),
				h = ui.Grow(1),
				dir = .Column,
				bg = t.bg,
				color = t.text,
				font_size = 14,
				line_height = 1.4,
			},
		},
	)
	header(app)
	body(app)
}

header :: proc(app: ^App) {
	t := ui.theme()
	ui.scope(
		{
			key = "header",
			props = {
				w = ui.STRETCH,
				dir = .Row,
				align = .Center,
				gap = {GAP, 0},
				pad = ui.xy(PAD, 10),
				bg = t.surface,
				border = {width = {b = 1}, color = t.border},
			},
		},
	)

	ui.label("Loom", {props = {font_size = 20, color = t.accent}})
	ui.label("opengl and raylib", {props = {color = t.text_muted, font_size = 12}})
	ui.spacer()

	ui.label("volume", {props = {color = t.text_muted, font_size = 12}})
	ui.slider(&app.volume, 0, 1, {props = {w = ui.Px(120)}})

	if ui.button(app.dark ? "light" : "dark", button_el()).clicked {
		app.dark = !app.dark
		ui.set_theme(app.dark ? ui.LOOM_DARK : ui.LOOM_LIGHT)
	}

	more := ui.button("...", with_text(button_el(), "..."))
	if more.clicked {
		app.menu = !app.menu
	}
	if ui.popup(&app.menu, more.id) {
		defer ui.end()
		if ui.button("reset layout", with_text(button_el(), "reset layout")).clicked {
			app.menu = false
		}
		if ui.button("about", with_text(button_el(), "about")).clicked {
			app.menu = false
		}
	}
}

body :: proc(app: ^App) {
	app.dock = ui.dockspace("main", {mode = .Detachable})

	if !app.laid_out {
		_, right := ui.dock_split(app.dock, "", .Right, 0.6)
		ui.dock_panel(app.dock, "Tracks", right)
		app.laid_out = true
	}

	if ui.panel(app.dock, "Widgets") {
		widgets_panel(app)
		ui.end_panel()
	}
	if ui.panel(app.dock, "Conformance") {
		conformance_panel(app)
		ui.end_panel()
	}
	if ui.panel(app.dock, "Tracks") {
		tracks_panel(app)
		ui.end_panel()
	}
}

widgets_panel :: proc(app: ^App) {
	t := ui.theme()
	ui.scroll({key = "widgets.scroll", props = {pad = ui.all(PAD), gap = {0, GAP}}})
	defer ui.end()

	section("Buttons")
	{
		ui.scope({key = "btns", props = {dir = .Row, gap = {8, 0}, w = ui.STRETCH}})
		ui.button("Primary", with_text(accent_button(), "Primary"))
		ui.button("Secondary", with_text(button_el(), "Secondary"))
		dis := button_el()
		dis.flags += {.Disabled}
		ui.button("Disabled", with_text(dis, "Disabled"))
	}

	section("Toggles")
	{
		ui.scope({key = "toggles", props = {dir = .Row, gap = {GAP, 0}, align = .Center}})
		ui.checkbox("notify me", &app.notify)
		ui.checkbox("compact", &app.compact)
	}
	{
		ui.scope({key = "radios", props = {dir = .Row, gap = {GAP, 0}, align = .Center}})
		ui.radio("songs", &app.nav, Nav.Songs)
		ui.radio("albums", &app.nav, Nav.Albums)
		ui.radio("artists", &app.nav, Nav.Artists)
	}

	section("Text input")
	ui.input(&app.search, {props = {w = ui.STRETCH}}, "search the library")
	ui.label(
		ui.buf_text(&app.search),
		{props = {color = t.text_muted, font_size = 12, text_wrap = .Ellipsis}},
	)

	section("Group hover")
	{
		ui.scope(
			{
				key = "grouped",
				flags = {.Group},
				props = {
					dir = .Row,
					align = .Center,
					gap = {8, 0},
					pad = ui.all(8),
					radius = ui.rad(6),
					bg = t.surface,
				},
			},
		)
		ui.label("hover this row")
		ui.spacer()
		ui.leaf(
			{
				key = "x",
				text = "x",
				flags = {.Clickable},
				props = {opacity = 0, color = t.text_muted, pad = ui.all(4)},
				group_hover = {opacity = 1},
				hover = {color = t.danger},
				transition = FAST,
			},
		)
	}

	section("Tooltip")
	tip := ui.button("hover me", with_text(button_el(), "hover me"))
	ui.tooltip("this is a tooltip", tip.id)
}

conformance_panel :: proc(app: ^App) {
	t := ui.theme()
	ui.scroll({key = "conform.scroll", props = {pad = ui.all(PAD), gap = {0, GAP}}})
	defer ui.end()

	section("Per-corner radius")
	{
		ui.scope({key = "radii", props = {dir = .Row, gap = {8, 0}, wrap = .Wrap}})
		swatch("r.tl", {tl = 16, tr = 0, br = 0, bl = 0}, t.accent)
		swatch("r.tr", {tl = 0, tr = 16, br = 0, bl = 0}, t.accent)
		swatch("r.br", {tl = 0, tr = 0, br = 16, bl = 0}, t.accent)
		swatch("r.all", ui.rad(16), t.accent)
	}

	section("Gradients")
	{
		ui.scope({key = "grads", props = {dir = .Row, gap = {8, 0}, wrap = .Wrap}})
		gradient_box("g0", ui.Gradient{kind = .Linear, angle = 0, stops = LINEAR_STOPS})
		gradient_box("g90", ui.Gradient{kind = .Linear, angle = 1.5708, stops = LINEAR_STOPS})
		gradient_box("gmulti", ui.Gradient{kind = .Linear, angle = 0.7854, stops = MULTI_STOPS})
		gradient_box("gradial", ui.Gradient{kind = .Radial, stops = RADIAL_STOPS})
	}

	section("Shadows")
	{
		ui.scope({key = "shadows", props = {dir = .Row, gap = {GAP, 0}, wrap = .Wrap}})
		ui.leaf(
			{
				key = "outer",
				text = "outer",
				props = {
					w = ui.Px(120),
					h = ui.Px(64),
					pad = ui.all(10),
					bg = t.raised,
					radius = ui.rad(RADIUS),
					shadow = {offset = {0, 6}, blur = 18, color = t.shadow},
				},
			},
		)
		ui.leaf(
			{
				key = "inset",
				text = "inset",
				props = {
					w = ui.Px(120),
					h = ui.Px(64),
					pad = ui.all(10),
					bg = t.raised,
					radius = ui.rad(RADIUS),
					shadow = {blur = 16, color = t.shadow, inset = true},
				},
			},
		)
	}

	section("Nested clipping")
	{
		ui.scope(
			{
				key = "clip1",
				flags = {.Clip},
				props = {
					w = ui.Px(240),
					h = ui.Px(90),
					pad = ui.all(10),
					bg = t.surface,
					radius = ui.rad(RADIUS),
					overflow = {.Hidden, .Hidden},
				},
			},
		)
		ui.scope(
			{
				key = "clip2",
				flags = {.Clip},
				props = {
					w = ui.Px(300),
					h = ui.Px(60),
					pad = ui.all(8),
					bg = t.raised,
					overflow = {.Hidden, .Hidden},
				},
			},
		)
		ui.scope(
			{
				key = "clip3",
				flags = {.Clip},
				props = {w = ui.Px(400), h = ui.Px(40), bg = t.accent, overflow = {.Hidden, .Hidden}},
			},
		)
		ui.label(
			"three levels of clipping, this line runs past every one of them",
			{props = {color = t.accent_text, text_wrap = .None}},
		)
	}

	section("Cursors")
	{
		ui.scope({key = "cursors", props = {dir = .Row, gap = {6, 6}, wrap = .Wrap}})
		for cur, i in CURSORS {
			e := button_el()
			e.key = cursor_name(cur)
			e.text = cursor_name(cur)
			e.props.cursor = cur
			e.props.font_size = 12
			ui.leaf(e)
			_ = i
		}
	}

	section("Font sizes on one baseline")
	{
		ui.scope({key = "baseline", props = {dir = .Row, gap = {10, 0}, align = .Baseline}})
		ui.label("12", {props = {font_size = 12}})
		ui.label("18", {props = {font_size = 18}})
		ui.label("28", {props = {font_size = 28}})
		ui.label("baseline", {props = {color = t.text_muted}})
	}
}

tracks_panel :: proc(app: ^App) {
	t := ui.theme()
	ui.scroll({key = "tracks.scroll", props = {pad = ui.all(8), gap = {0, 2}}})
	defer ui.end()

	for track in app.tracks {
		row := ui.begin(
			{
				key = track.id,
				flags = {.Clickable, .Group},
				props = {
					w = ui.STRETCH,
					dir = .Row,
					align = .Center,
					gap = {GAP, 0},
					pad = ui.xy(10, 8),
					radius = ui.rad(6),
					cursor = .Pointer,
				},
				hover = {bg = t.surface},
				state = track.id == app.playing ? {.Checked} : {},
				rules = []ui.Rule{{on = {.Checked}, props = {bg = ui.fade(t.accent, 0.25)}}},
				transition = FAST,
			},
		)

		ui.label(track.title, {props = {w = ui.Grow(2), text_wrap = .Ellipsis}})
		ui.label(
			track.artist,
			{props = {w = ui.Grow(1), color = t.text_muted, text_wrap = .Ellipsis}},
		)
		ui.leaf(
			{
				key = "fav",
				text = "*",
				flags = {.Clickable},
				props = {opacity = 0, color = t.text_muted, pad = ui.all(4)},
				group_hover = {opacity = 1},
				hover = {color = t.accent},
				transition = FAST,
			},
		)

		ui.end()
		if row.double_clicked {
			app.playing = track.id
		}
	}
}

section :: proc(title: string, loc := #caller_location) {
	t := ui.theme()
	ui.label(
		title,
		{props = {color = t.text_muted, font_size = 11, w = ui.STRETCH, margin = {t = 4}}},
		loc,
	)
}

accent_button :: proc() -> ui.Element {
	t := ui.theme()
	e := button_el()
	e.props.bg = t.accent
	e.props.color = t.accent_text
	e.hover = {bg = t.accent_hover}
	return e
}

swatch :: proc(key: string, radius: ui.Radius, col: ui.Color) {
	ui.leaf({key = key, props = {w = ui.Px(64), h = ui.Px(64), bg = col, radius = radius}})
}

gradient_box :: proc(key: string, g: ui.Gradient) {
	ui.leaf(
		{key = key, props = {w = ui.Px(96), h = ui.Px(64), bg = g, radius = ui.rad(RADIUS)}},
	)
}

cursor_name :: proc(cur: ui.Cursor) -> string {
	switch cur {
	case .Default:
		return "default"
	case .Pointer:
		return "pointer"
	case .Text:
		return "text"
	case .Resize_H:
		return "resize-h"
	case .Resize_V:
		return "resize-v"
	case .Grab:
		return "grab"
	case .Grabbing:
		return "grabbing"
	case .Not_Allowed:
		return "not-allowed"
	}
	return "default"
}
