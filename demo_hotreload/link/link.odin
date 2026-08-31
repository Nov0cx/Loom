package hot_link

import "base:runtime"
import demo "../../demo"
import ui "../../loom"

VERSION :: 1

Link :: struct {
	odin_ctx:   runtime.Context,
	ui_globals: ^ui.Globals,
	ui_ctx:     ^ui.Context,
	app:        ^demo.App,
	reloads:    int,
}
