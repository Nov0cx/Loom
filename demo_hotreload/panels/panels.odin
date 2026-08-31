package panels

import demo "../../demo"
import ui "../../loom"
import hot_link "../link"

@(export)
panels_version :: proc "c" () -> int {
	return hot_link.VERSION
}

@(export)
panels_load :: proc "c" (l: ^hot_link.Link) {
	context = l.odin_ctx
	ui.set_globals(l.ui_globals)
	ui.make_current(l.ui_ctx)
}

@(export)
panels_frame :: proc "c" (l: ^hot_link.Link) {
	context = l.odin_ctx
	demo.root(l.app)
}

@(export)
panels_unload :: proc "c" (l: ^hot_link.Link) {
	context = l.odin_ctx
}
