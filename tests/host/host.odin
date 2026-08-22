package host

import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:strings"
import link "../link"
import ui "../../loom"

PLUGIN :: "plugin.dll" when ODIN_OS == .Windows else "plugin.dylib" when ODIN_OS == .Darwin else "plugin.so"

RELOADS :: 10

Plugin :: struct {
	lib:     dynlib.Library,
	load:    proc "c" (l: ^link.Link),
	adopted: proc "c" (l: ^link.Link) -> bool,
	frame:   proc "c" (l: ^link.Link) -> ui.Id,
	frames:  proc "c" (l: ^link.Link, id: ui.Id) -> int,
}

failures: int

check :: proc(cond: bool, msg: string, args: ..any) {
	if cond {
		fmt.printf("  ok   ")
	} else {
		fmt.printf("  FAIL ")
		failures += 1
	}
	fmt.printfln(msg, ..args)
}

open_plugin :: proc() -> (p: Plugin, ok: bool) {
	lib, loaded := dynlib.load_library(PLUGIN)
	if !loaded {
		fmt.eprintfln("host: could not load %s", PLUGIN)
		return {}, false
	}
	p.lib = lib

	sym :: proc(lib: dynlib.Library, name: string) -> rawptr {
		ptr, found := dynlib.symbol_address(lib, name)
		if !found {
			fmt.eprintfln("host: %s is missing from %s", name, PLUGIN)
			os.exit(1)
		}
		return ptr
	}

	p.load = auto_cast sym(lib, "plugin_load")
	p.adopted = auto_cast sym(lib, "plugin_adopted")
	p.frame = auto_cast sym(lib, "plugin_frame")
	p.frames = auto_cast sym(lib, "plugin_frames")
	return p, true
}

main :: proc() {
	if len(os.args) > 1 && os.args[1] == "mismatch" {
		run_mismatch()
		return
	}

	run_reloads()
	run_mismatch_child()

	if failures > 0 {
		fmt.eprintfln("host: %v check(s) failed", failures)
		os.exit(1)
	}
	fmt.println("host: every check passed")
}

run_reloads :: proc() {
	ctx: ui.Context
	ui.init(&ctx, ui.Config{backend = ui.noop_backend(), prune_after = 4})
	defer ui.destroy(&ctx)

	l := link.Link {
		odin_ctx   = context,
		ui_globals = ui.get_globals(),
		ui_ctx     = &ctx,
	}

	panel_id: ui.Id
	for reload in 0 ..< RELOADS {
		p, ok := open_plugin()
		if !ok {
			failures += 1
			return
		}

		p.load(&l)
		if reload == 0 {
			check(p.adopted(&l), "the plugin adopted the host globals")
		}

		ui.begin_frame(ui.Input{dt = 1.0 / 60.0, viewport = {1280, 720}, dpi = 1})
		ui.begin({key = "host.panel", props = {dir = .Row}})
		ui.leaf({key = "host.row", text = "from the host"})
		ui.end()
		id := p.frame(&l)
		ui.end_frame()

		if reload == 0 {
			panel_id = id
		} else if id != panel_id {
			check(false, "the plugin panel id changed across reload %v", reload)
		}

		got := p.frames(&l, id)
		check(got == reload + 1, "per-node state survived reload %v, frames = %v", reload, got)

		if reload < RELOADS - 1 {
			dynlib.unload_library(p.lib)
			continue
		}

		dump_and_check(&ctx)
		dynlib.unload_library(p.lib)
	}
}

dump_and_check :: proc(ctx: ^ui.Context) {
	dump := ui.dump_tree_string(context.temp_allocator)
	check(strings.contains(dump, "#host.panel"), "the host nodes are in the tree")
	check(strings.contains(dump, "#" + link.PANEL_KEY), "the plugin nodes are in the same tree")
	check(strings.contains(dump, "#" + link.ROW_KEY), "the plugin children are in the same tree")

	nodes := ui.stats().live_nodes
	check(nodes == 5, "one tree holds every node from both modules, live_nodes = %v", nodes)

	fmt.println(dump)
}

run_mismatch :: proc() {
	ctx: ui.Context
	ui.init(&ctx, ui.Config{backend = ui.noop_backend()})

	p, ok := open_plugin()
	if !ok {
		os.exit(2)
	}

	bad := ui.get_globals()^
	bad.version.major += 1

	l := link.Link {
		odin_ctx   = context,
		ui_globals = &bad,
		ui_ctx     = &ctx,
	}
	p.load(&l)

	fmt.eprintln("host: set_globals accepted a mismatched VERSION")
	os.exit(0)
}

run_mismatch_child :: proc() {
	self, perr := os.get_executable_path(context.temp_allocator)
	if perr != nil {
		check(false, "could not resolve this executable: %v", perr)
		return
	}
	desc := os.Process_Desc {
		command = []string{self, "mismatch"},
		stdout  = nil,
		stderr  = nil,
		stdin   = nil,
	}
	p, err := os.process_start(desc)
	if err != nil {
		check(false, "could not spawn the version-mismatch child: %v", err)
		return
	}
	state, werr := os.process_wait(p)
	if werr != nil {
		check(false, "could not wait on the version-mismatch child: %v", werr)
		return
	}
	check(state.exit_code != 0, "a mismatched VERSION aborts on load, child exit code %v", state.exit_code)
}
