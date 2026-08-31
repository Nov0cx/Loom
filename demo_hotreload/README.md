# Hot reload demo

The same demo as `demo/`, with the panel code in a DLL that reloads while the window stays open. The executable owns the window, the Vulkan 1.3 backend, `demo.App`, the `ui.Context` and `ui.Globals`; the DLL owns nothing at all and only builds the tree.

This is the acceptance test for `set_globals` / `make_current`, and it is the case that breaks the moment anyone adds a mutable package global anywhere in `loom/` or a backend.

```
link/link.odin      package hot_link — the Link struct both images share
panels/panels.odin  package panels   — the four exports, calling demo.root
host/main.odin      package main     — window, backend, context, loop
host/reload.odin    package main     — the mtime watcher
```

## The edit loop

```
odin run build.odin -file -- -target:hot_demo -run     # once, builds both and runs
odin run build.odin -file -- -target:hot_panels        # after every edit
```

Edit anything in `demo/`, run the second command, and the running window updates within a quarter second with the tree, scroll positions and text carets intact. `-target:hot_panels` is sugar for:

```
odin build demo_hotreload/panels -build-mode:dll -out:build/panels.dll -debug
```

`-target:hot_demo` ignores `-backend`: `host/main.odin` imports `vulkan_1_3` directly. Building a hot host per backend would mean a `host/backends/<name>/` tree mirroring `demo/backends/`; there is no reason to until someone wants it.

`odin build -debug` cannot rewrite `panels.pdb` while a debugger has it open. If you are debugging, add `-pdb-name:build/panels_2.pdb` (any fresh name) to your rebuild.

## What the DLL exports

```odin
@(export) panels_version :: proc "c" () -> int
@(export) panels_load    :: proc "c" (l: ^hot_link.Link)
@(export) panels_frame   :: proc "c" (l: ^hot_link.Link)
@(export) panels_unload  :: proc "c" (l: ^hot_link.Link)
```

`panels_load` is the whole contract, and it must run before any UI call:

```odin
context = l.odin_ctx
ui.set_globals(l.ui_globals)
ui.make_current(l.ui_ctx)
```

A reload zeroes the DLL's own globals, so this re-adopts every time — that is why it is an explicit entry point rather than lazy initialisation.

Two version gates, one per layer. `panels_version` guards the `Link` struct's layout and is checked *before* `panels_load` is called. `ui.set_globals` guards `loom` itself: it asserts on `VERSION`, `size_of(Context)` and `size_of(Node)`, which turns a stale DLL into an assert at load time instead of a crash somewhere later. Adding a field to `Theme` or to the ini state changes `size_of(Context)`, so host and panels must be rebuilt together; that assert firing is the system working.

`panels_unload` deliberately does nothing. It must **not** call `ui.make_current(nil)` — that mutates a thread-keyed map inside the *host's* `Globals` and would leave the host with no current context.

The DLL must never call `ui.init` or `ui.destroy`. `globals_release` would decrement the host's refcount and free `Globals` out from under it.

The host keeps `ui.begin_frame` and `ui.end_frame` on its own side, so a frame where the DLL is momentarily unloadable still produces a valid empty frame rather than a crash.

## Why the host owns `App`

`demo.App.tracks` is assigned `demo.TRACKS`, an `@(rodata)` slice, and `demo.App.playing` is a string literal. The `demo` package is compiled into both images, so both have a copy of that data — and whichever module runs `init_app` is the module whose read-only section those pointers land in. The host runs it, so everything reachable from `App` points into the executable, which is never unloaded.

The rule that follows, and the one to keep in mind when writing panels:

> The panels DLL may read `App` freely, but may only ever store into it strings that came out of `App` itself or out of `loom`.

`tracks_panel`'s `app.playing = track.id` satisfies this, because `track` came out of `app.tracks`, which the host owns.

## Loaded modules are never unloaded

This looks like a leak and is not negotiable.

`loom/input_text.odin` registers `input_state_free` as a destructor on a node's `State_Block`. `loom` is statically linked into both images, so when the DLL calls `ui.input(...)`, the function pointer recorded on that node points into **the DLL's** code segment. `free_states` calls it on node prune and again from `ui.destroy` at exit. Unload the DLL and process shutdown becomes an access violation — long after the reload that appeared to work.

The same reasoning covers a hazard that is easier to spot: `Element.key` and `Element.text` are borrowed, so a node named by a DLL string literal has an unmapped name the instant that module goes away.

So every loaded module stays mapped for the process lifetime, and at exit the host runs `ui.destroy` **first**, then unloads everything. The cost is one mapped module and one `panels_hot_<n>.dll` on disk per reload within a single run; stale copies from previous runs are swept at startup. The "unload generation N-2, never N-1" scheme people reach for is not safe — it crashes less often, which is worse.

## State that survives, and state that does not

Anything on the host-owned `App` survives a reload unconditionally.

Per-node state taken with `ui.state(T)` usually survives and is not guaranteed to. `loom/state.odin` matches state blocks on `typeid`, and a `typeid` is an index into `runtime.type_table`, which is per-image. Recompiling the DLL can renumber its table; when it does, the lookup misses, a fresh zeroed block is allocated, and scroll offsets and text carets reset. Editing only procedure bodies keeps the numbering stable, which is exactly why this appears to work right up until it doesn't.

**Durable state belongs on `App`. `ui.state` state is ephemeral across reloads.** A stable type-name hash, or an explicit `state_keyed(T, name)`, would fix this properly; that is a change to `loom`, not to this demo.

If a panel ever registers a `Settings_Handler`, that is another function pointer into the DLL: re-register it on every `panels_load`, or do not register one.

## How the reload works

Polled at the top of the loop, before `glfw.PollEvents`. An `os.stat` is microseconds, and `POLL_INTERVAL` is 0.25s rather than the demo's 1.0s so an idle app notices a rebuilt DLL promptly.

1. Compare `panels.dll`'s mtime against the last one loaded.
2. Debounce: after the first load, require the same mtime on two consecutive polls *and* a successful whole-file read. The compiler may still be writing; a sharing violation just skips this frame. A `sleep(100ms)` is the usual alternative and it stalls the UI.
3. Write those bytes to `panels_hot_<n>.dll` and load *that*. This copy is the entire reason the scheme works: Windows holds an exclusive lock on a mapped DLL, so the compiler could never overwrite `panels.dll` if it were loaded directly.
4. Resolve all four symbols and check `panels_version`. Any failure unloads the new copy and keeps the old module — never a half-loaded state.
5. Call the new `panels_load`, and only *then* swap the stored procedure pointers. Swapping after the load returns means a failed load can never leave the host calling into a module that has not adopted the globals.

No watcher thread, and no `ReadDirectoryChangesW`. `ui.Context` is thread-affine — `make_current` keys on the thread id — so a watcher thread would have to marshal back to the UI thread anyway, and a 4 Hz stat is twenty lines less code. If you ever do move the watch off-thread, `glfw.PostEmptyEvent()` is the one-liner that breaks `WaitEventsTimeout`.

The host does not invoke the compiler. Rebuilding is your job, which keeps the demo about the reload contract rather than about shelling out to a build system.

## Relationship to `tests/`

`tests/host` + `tests/plugin` + `tests/link` is the headless version of the same contract: `ui.noop_backend()`, no window, ten `load_library`/`unload_library` cycles asserting that per-node state and node ids survive. It runs anywhere, including CI with no GPU, and it is what `-target:hot` builds.

This demo is the windowed counterpart. It is deliberately a separate target: `-target:hot` must stay runnable on a headless machine, and this one needs the Vulkan SDK.
