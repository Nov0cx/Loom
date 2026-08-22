package demo

import ui "../loom"

FAST :: ui.Transition {
	props = {.Bg, .Color, .Opacity, .Radius, .Border_Color},
	dur   = 0.12,
	ease  = .Out_Quad,
}

PAD :: 16
GAP :: 12
RADIUS :: 8

button_el :: proc() -> ui.Element {
	t := ui.theme()
	return ui.Element {
		flags = {.Clickable, .Focusable},
		props = {
			pad = ui.xy(12, 8),
			bg = t.raised,
			color = t.text,
			radius = ui.rad(6),
			cursor = .Pointer,
			w = ui.FIT,
			h = ui.FIT,
		},
		hover = {bg = t.overlay},
		active = {bg = t.accent, color = t.accent_text},
		focus = {border = {width = ui.all(1), color = t.accent}},
		disabled = {opacity = 0.4, cursor = .Not_Allowed},
		transition = FAST,
	}
}

card_el :: proc(key: string) -> ui.Element {
	t := ui.theme()
	return ui.Element {
		key = key,
		props = {
			dir = .Column,
			gap = {0, 6},
			pad = ui.all(12),
			bg = t.surface,
			radius = ui.rad(RADIUS),
			border = {width = ui.all(1), color = t.border},
		},
	}
}

with_text :: proc(el: ui.Element, text: string) -> ui.Element {
	e := el
	e.text, e.key = text, text
	return e
}
