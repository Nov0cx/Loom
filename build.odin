package build

import "base:runtime"
import "core:flags"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

Backend_Kind :: enum {
	raylib,
	opengl,
	dx11,
	vulkan_1_2,
	vulkan_1_3,
	sokol,
	all,
}

Mode :: enum {
	debug,
	release,
}

Target :: enum {
	none,
	lib,
	demo,
	tests,
	hot,
	all,
}

Options :: struct {
	target:  Target `usage:"what to build: lib, demo, tests, hot, all (default: lib)"`,
	backend: Backend_Kind `usage:"which example backend the demo links: raylib, opengl, dx11, vulkan_1_2, vulkan_1_3, sokol, all"`,
	mode:    Mode `usage:"debug (default) or release"`,
	run:     bool `usage:"run after building"`,
	vet:     bool `usage:"pass -vet -strict-style -warnings-as-errors"`,
	clean:   bool `usage:"remove build output first"`,
	out:     string `usage:"output directory (default: build)"`,
	verbose: bool `usage:"echo the odin command lines"`,
}

Backend_Info :: struct {
	kind:      Backend_Kind,
	name:      string,
	lib_dir:   string,
	demo_dir:  string,
	platforms: bit_set[runtime.Odin_OS_Type],
	needs:     string,
}

DESKTOP :: bit_set[runtime.Odin_OS_Type]{.Windows, .Linux, .Darwin, .FreeBSD, .OpenBSD, .NetBSD}

BACKENDS :: [6]Backend_Info{
	{
		.raylib,
		"raylib",
		"example_backends/raylib",
		"demo/backends/raylib",
		DESKTOP,
		"raylib (vendor:raylib, ships with Odin)",
	},
	{
		.opengl,
		"opengl",
		"example_backends/opengl",
		"demo/backends/opengl",
		DESKTOP,
		"GLFW and OpenGL 3.3 (vendor:glfw, vendor:OpenGL)",
	},
	{.dx11, "dx11", "example_backends/dx11", "demo/backends/dx11", {.Windows}, "Win32 and Direct3D 11"},
	{
		.vulkan_1_2,
		"vulkan_1_2",
		"example_backends/vulkan_1_2",
		"demo/backends/vulkan_1_2",
		DESKTOP,
		"the Vulkan SDK (1.2) and GLFW",
	},
	{
		.vulkan_1_3,
		"vulkan_1_3",
		"example_backends/vulkan_1_3",
		"demo/backends/vulkan_1_3",
		DESKTOP,
		"the Vulkan SDK (1.3) and GLFW",
	},
	{.sokol, "sokol", "example_backends/sokol", "demo/backends/sokol", DESKTOP, "the sokol-odin bindings"},
}

LIB_DIR :: "loom"
TESTS_DIR :: "tests"
HOST_DIR :: "tests/host"
PLUGIN_DIR :: "tests/plugin"

EXE :: ".exe" when ODIN_OS == .Windows else ""
DLL :: ".dll" when ODIN_OS == .Windows else ".dylib" when ODIN_OS == .Darwin else ".so"

main :: proc() {
	opt: Options
	flags.parse_or_exit(&opt, os.args, .Odin)

	if opt.out == "" {
		opt.out = "build"
	}

	if opt.clean {
		if !do_clean(opt) {
			os.exit(1)
		}
	}

	target := opt.target
	if target == .none {
		if opt.clean {
			return
		}
		target = .lib
	}

	if err := os.make_directory_all(opt.out); err != nil && err != .Exist {
		fmt.eprintfln("could not create %s: %v", opt.out, err)
		os.exit(1)
	}

	ok: bool
	switch target {


		case .none:
			ok = true
		case .lib:
			ok = build_lib(opt)
		case .tests:
			ok = build_tests(opt)
		case .demo:
			ok = build_demo(opt)
		case .hot:
			ok = build_hot(opt)
		case .all:
			ok = build_all(opt)
	}

	if !ok {
		os.exit(1)
	}
}

do_clean :: proc(opt: Options) -> bool {
	if !os.exists(opt.out) {
		return true
	}
	fmt.printfln("clean: removing %s", opt.out)
	if err := os.remove_all(opt.out); err != nil {
		fmt.eprintfln("could not remove %s: %v", opt.out, err)
		return false
	}
	return true
}

build_lib :: proc(opt: Options) -> bool {
	fmt.println("lib: checking", LIB_DIR)
	args := make([dynamic]string, context.temp_allocator)
	append(&args, "odin", "check", LIB_DIR, "-no-entry-point")
	append_vet(&args, opt)
	if !cmd(opt, ..args[:]) {
		return false
	}
	return lint_globals(LIB_DIR)
}

build_tests :: proc(opt: Options) -> bool {
	if !build_lib(opt) {
		return false
	}
	if !os.exists(TESTS_DIR) {
		fmt.eprintfln("tests: skipping, %s is not present", TESTS_DIR)
		return true
	}
	fmt.println("tests: running", TESTS_DIR)
	out := join(opt.out, fmt.tprintf("tests%s", EXE))
	args := make([dynamic]string, context.temp_allocator)
	append(&args, "odin", "test", TESTS_DIR, fmt.tprintf("-out:%s", out), "-define:ODIN_TEST_THREADS=1")
	append_common(&args, opt)
	return cmd(opt, ..args[:])
}

build_demo :: proc(opt: Options) -> bool {
	if opt.backend == .all {
		built := 0
		for b in BACKENDS {
			if !available(b) {
				report_skip(b)
				continue
			}
			if !build_demo_for(opt, b) {
				return false
			}
			built += 1
		}
		if built == 0 {
			fmt.eprintln("demo: no backend is available here yet")
		}
		return true
	}

	for b in BACKENDS {
		if b.kind != opt.backend {
			continue
		}
		if !available(b) {
			report_skip(b)
			return true
		}
		return build_demo_for(opt, b)
	}
	return true
}

build_demo_for :: proc(opt: Options, b: Backend_Info) -> bool {
	fmt.printfln("demo: building %s", b.name)
	suffix := "_release" if opt.mode == .release else ""
	name := fmt.tprintf("demo_%s%s%s", b.name, suffix, EXE)
	out := join(opt.out, name)

	args := make([dynamic]string, context.temp_allocator)
	append(&args, "odin", "build", b.demo_dir, fmt.tprintf("-out:%s", out))
	append(&args, fmt.tprintf("-define:LOOM_BACKEND=%s", b.name))
	append_common(&args, opt)
	if !cmd(opt, ..args[:]) {
		return false
	}
	if opt.run {
		return exec_built(opt, name)
	}
	return true
}

build_hot :: proc(opt: Options) -> bool {
	if !os.exists(HOST_DIR) || !os.exists(PLUGIN_DIR) {
		fmt.eprintfln("hot: skipping, %s and %s are not both present", HOST_DIR, PLUGIN_DIR)
		return true
	}

	fmt.println("hot: building plugin")
	plugin := fmt.tprintf("plugin%s", DLL)
	pargs := make([dynamic]string, context.temp_allocator)
	append(&pargs, "odin", "build", PLUGIN_DIR, "-build-mode:dll")
	append(&pargs, fmt.tprintf("-out:%s", join(opt.out, plugin)))
	append_common(&pargs, opt)
	if !cmd(opt, ..pargs[:]) {
		return false
	}

	fmt.println("hot: building host")
	host := fmt.tprintf("host%s", EXE)
	hargs := make([dynamic]string, context.temp_allocator)
	append(&hargs, "odin", "build", HOST_DIR)
	append(&hargs, fmt.tprintf("-out:%s", join(opt.out, host)))
	append_common(&hargs, opt)
	if !cmd(opt, ..hargs[:]) {
		return false
	}

	if opt.run {
		return exec_built(opt, host)
	}
	return true
}

build_all :: proc(opt: Options) -> bool {
	if !build_tests(opt) {
		return false
	}
	o := opt
	o.backend = .all
	o.run = false
	return build_demo(o)
}

available :: proc(b: Backend_Info) -> bool {
	return ODIN_OS in b.platforms && os.exists(b.lib_dir) && os.exists(b.demo_dir)
}

report_skip :: proc(b: Backend_Info) {
	if ODIN_OS not_in b.platforms {
		fmt.printfln("skipping %s: not supported on %v, it needs %s", b.name, ODIN_OS, b.needs)
		return
	}
	if !os.exists(b.lib_dir) {
		fmt.printfln("skipping %s: %s is not present", b.name, b.lib_dir)
		return
	}
	fmt.printfln("skipping %s: %s is not present", b.name, b.demo_dir)
}

append_common :: proc(args: ^[dynamic]string, opt: Options) {
	switch opt.mode {
	case .debug:
		append(args, "-debug")
	case .release:
		append(args, "-o:speed", "-no-bounds-check")
	}
	append_vet(args, opt)
}

append_vet :: proc(args: ^[dynamic]string, opt: Options) {
	if opt.vet {
		append(args, "-vet", "-strict-style", "-warnings-as-errors")
	}
}

exec_built :: proc(opt: Options, name: string) -> bool {
	exe := join(opt.out, name)
	if opt.verbose {
		fmt.printfln("$ (cd %s) %s", opt.out, exe)
	}
	desc := os.Process_Desc{
		working_dir = opt.out,
		command = []string{exe},
		stdout = os.stdout,
		stderr = os.stderr,
		stdin = os.stdin,
	}
	return wait_ok(desc, name)
}

cmd :: proc(opt: Options, parts: ..string) -> bool {
	if opt.verbose {
		fmt.printfln("$ %s", strings.join(parts, " ", context.temp_allocator))
	}
	desc := os.Process_Desc{command = parts, stdout = os.stdout, stderr = os.stderr, stdin = os.stdin}
	return wait_ok(desc, parts[0])
}

wait_ok :: proc(desc: os.Process_Desc, what: string) -> bool {
	p, err := os.process_start(desc)
	if err != nil {
		fmt.eprintfln("could not start %s: %v", what, err)
		return false
	}
	state, werr := os.process_wait(p)
	if werr != nil {
		fmt.eprintfln("could not wait on %s: %v", what, werr)
		return false
	}
	if state.exit_code != 0 {
		fmt.eprintfln("%s exited with %d", what, state.exit_code)
		return false
	}
	return true
}

ALLOWED_GLOBAL :: "g"

lint_globals :: proc(dir: string) -> bool {
	entries, err := os.read_directory_by_path(dir, -1, context.temp_allocator)
	if err != nil {
		fmt.eprintfln("lint: could not read %s: %v", dir, err)
		return false
	}

	ok := true
	for e in entries {
		if e.type == .Directory || !strings.has_suffix(e.name, ".odin") {
			continue
		}
		data, rerr := os.read_entire_file(e.fullpath, context.temp_allocator)
		if rerr != nil {
			fmt.eprintfln("lint: could not read %s: %v", e.fullpath, rerr)
			ok = false
			continue
		}
		for line, i in strings.split_lines(string(data), context.temp_allocator) {
			name, is_global := global_decl_name(line)
			if !is_global || name == ALLOWED_GLOBAL {
				continue
			}
			fmt.eprintfln(
				"lint: %s:%d: mutable package-level variable %q, only %q is allowed",
				e.fullpath,
				i + 1,
				name,
				ALLOWED_GLOBAL,
			)
			ok = false
		}
	}

	if ok {
		fmt.printfln("lint: %s has no mutable package globals other than %q", dir, ALLOWED_GLOBAL)
	}
	return ok
}

global_decl_name :: proc(line: string) -> (name: string, is_global: bool) {
	if len(line) == 0 {
		return "", false
	}
	switch line[0] {


		case ' ', '\t', '/', '@', '#', ')', '}', ']':
			return "", false
	}

	i := 0
	for i < len(line) && is_ident_byte(line[i]) {
		i += 1
	}
	if i == 0 {
		return "", false
	}
	name = line[:i]

	for i < len(line) && line[i] == ' ' {
		i += 1
	}
	if i >= len(line) || line[i] != ':' {
		return "", false
	}
	i += 1
	if i < len(line) && line[i] == ':' {
		return "", false
	}
	return name, true
}

join :: proc(parts: ..string) -> string {
	s, err := filepath.join(parts, context.temp_allocator)
	if err != nil {
		return strings.concatenate(parts, context.temp_allocator)
	}
	return s
}

is_ident_byte :: proc(c: byte) -> bool {
	return c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
}
