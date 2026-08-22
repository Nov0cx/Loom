package link

import "base:runtime"
import ui "../../loom"

Link :: struct {
	odin_ctx:   runtime.Context,
	ui_globals: ^ui.Globals,
	ui_ctx:     ^ui.Context,
}

Counter :: struct {
	frames: int,
}

PANEL_KEY :: "plugin.panel"
ROW_KEY :: "plugin.row"
