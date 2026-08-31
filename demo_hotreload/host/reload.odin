package main

import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import hot_link "../link"

DLL :: ".dll" when ODIN_OS == .Windows else ".dylib" when ODIN_OS == .Darwin else ".so"
PANELS :: "panels" + DLL

Loaded :: struct {
	lib:  dynlib.Library,
	path: string,
}

Watch :: struct {
	dir:      string,
	src:      string,
	stamp:    time.Time,
	pending:  time.Time,
	has_pend: bool,
	primed:   bool,
	gen:      int,
	modules:  [dynamic]Loaded,
	version:  proc "c" () -> int,
	load:     proc "c" (l: ^hot_link.Link),
	frame:    proc "c" (l: ^hot_link.Link),
	unload:   proc "c" (l: ^hot_link.Link),
}

watch_init :: proc(w: ^Watch) {
	exe, err := os.get_executable_path(context.allocator)
	if err != nil {
		w.dir = strings.clone(".")
	} else {
		w.dir = strings.clone(filepath.dir(exe))
		delete(exe)
	}
	w.src, _ = filepath.join({w.dir, PANELS}, context.allocator)
	w.modules = make([dynamic]Loaded, 0, 8)
	sweep_copies(w)
}

watch_destroy :: proc(w: ^Watch) {
	for m in w.modules {
		dynlib.unload_library(m.lib)
		delete(m.path)
	}
	delete(w.modules)
	delete(w.src)
	delete(w.dir)
}

@(private)
copy_name :: proc(w: ^Watch, gen: int) -> string {
	path, _ := filepath.join({w.dir, fmt.tprintf("panels_hot_%d%s", gen, DLL)}, context.allocator)
	return path
}

@(private)
sweep_copies :: proc(w: ^Watch) {
	entries, err := os.read_directory_by_path(w.dir, -1, context.temp_allocator)
	if err != nil {
		return
	}
	for e in entries {
		if strings.has_prefix(e.name, "panels_hot_") && strings.has_suffix(e.name, DLL) {
			os.remove(e.fullpath)
		}
	}
}

poll_reload :: proc(w: ^Watch, l: ^hot_link.Link) {
	stamp, err := os.last_write_time_by_name(w.src)
	if err != nil || stamp == w.stamp {
		return
	}

	if w.primed && (!w.has_pend || w.pending != stamp) {
		w.pending = stamp
		w.has_pend = true
		return
	}
	w.primed = true

	bytes, rerr := os.read_entire_file_from_path(w.src, context.allocator)
	if rerr != nil {
		return
	}
	defer delete(bytes)

	w.gen += 1
	path := copy_name(w, w.gen)
	if werr := os.write_entire_file(path, bytes); werr != nil {
		fmt.eprintfln("hot: could not stage %s: %v", path, werr)
		delete(path)
		return
	}

	lib, loaded := dynlib.load_library(path)
	if !loaded {
		fmt.eprintfln("hot: could not load %s", path)
		delete(path)
		return
	}

	version := (proc "c" () -> int)(sym(lib, "panels_version"))
	load := (proc "c" (l: ^hot_link.Link))(sym(lib, "panels_load"))
	frame := (proc "c" (l: ^hot_link.Link))(sym(lib, "panels_frame"))
	unload := (proc "c" (l: ^hot_link.Link))(sym(lib, "panels_unload"))

	if version == nil || load == nil || frame == nil || unload == nil {
		fmt.eprintfln("hot: %s is missing an entry point, keeping the old module", PANELS)
		dynlib.unload_library(lib)
		delete(path)
		return
	}
	if version() != hot_link.VERSION {
		fmt.eprintfln(
			"hot: %s is Link version %v and the host is %v, keeping the old module",
			PANELS,
			version(),
			hot_link.VERSION,
		)
		dynlib.unload_library(lib)
		delete(path)
		return
	}

	if w.unload != nil {
		w.unload(l)
	}

	append(&w.modules, Loaded{lib = lib, path = path})
	load(l)

	w.version = version
	w.load = load
	w.frame = frame
	w.unload = unload

	w.stamp = stamp
	w.has_pend = false
	if l.reloads > 0 {
		fmt.printfln("hot: reloaded %s (%v)", PANELS, l.reloads)
	}
	l.reloads += 1
}

@(private)
sym :: proc(lib: dynlib.Library, name: string) -> rawptr {
	ptr, found := dynlib.symbol_address(lib, name)
	return found ? ptr : nil
}
