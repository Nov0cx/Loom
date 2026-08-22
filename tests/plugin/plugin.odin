package plugin

import link "../link"
import ui "../../loom"

@(export)
plugin_load :: proc "c" (l: ^link.Link) {
	context = l.odin_ctx
	ui.set_globals(l.ui_globals)
	ui.make_current(l.ui_ctx)
}

@(export)
plugin_adopted :: proc "c" (l: ^link.Link) -> bool {
	context = l.odin_ctx
	return ui.get_globals() == l.ui_globals
}

@(export)
plugin_frame :: proc "c" (l: ^link.Link) -> ui.Id {
	context = l.odin_ctx

	it := ui.begin({key = link.PANEL_KEY, props = {dir = .Column}})
	c := ui.state(link.Counter)
	c.frames += 1
	ui.leaf({key = link.ROW_KEY, text = "from the plugin"})
	ui.end()
	return it.id
}

@(export)
plugin_frames :: proc "c" (l: ^link.Link, id: ui.Id) -> int {
	context = l.odin_ctx
	n := ui.find(id)
	if n == nil {
		return -1
	}
	return ui.state_of(n, link.Counter).frames
}
