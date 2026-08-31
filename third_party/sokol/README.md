# sokol-odin, vendored

Bindings and prebuilt static libraries for [sokol](https://github.com/floooh/sokol), used only by
`example_backends/sokol` and `demo/backends/sokol`.

- Upstream: https://github.com/floooh/sokol-odin
- Pinned commit: `02cab874a7d712532cf21fb9229afe1b57b2a0ad`
- Licence: zlib/libpng, see `LICENSE` (unchanged from upstream, and it covers sokol itself too)

## Why this is checked in

sokol is the one backend dependency Odin does not ship in `vendor:`. Everything else the six
backends need — raylib, GLFW, OpenGL, Vulkan, D3D11, stb — comes with the compiler. Rather than make
`-backend:sokol` depend on a clone-and-build step that fails differently on every machine, the
bindings and the four libraries they need are committed. That is about 2.7 MB.

**The commit is pinned, and that matters.** Upstream is on the unified `sg.View` API (`Bindings.views`,
`sg.make_view`) rather than the older `Bindings.fs.images`. A backend written against an unpinned
master breaks the next time someone re-clones.

## What is here

```
sokol/app/    app.odin  + sokol_app_windows_x64_d3d11_release.lib
sokol/gfx/    gfx.odin  + sokol_gfx_windows_x64_d3d11_release.lib
sokol/glue/   glue.odin + sokol_glue_windows_x64_d3d11_release.lib
sokol/log/    log.odin  + sokol_log_windows_x64_d3d11_release.lib
sokol/c/      the four headers and their .c stubs, so the libs can be rebuilt
sokol/build_clibs_{windows.cmd,linux.sh,macos.sh}
```

Upstream's `audio`, `debugtext`, `shape`, `gl`, `framebuffer`, `helpers`, `letterbox` and `time`
packages, its `examples/` tree and its CI config are not vendored — Loom uses none of them.

**Release libraries only.** `gfx.odin` picks its library filename from
`#config(SOKOL_GFX_DEBUG, SOKOL_DEBUG)`, where `SOKOL_DEBUG` defaults to `ODIN_DEBUG`. Since
`build.odin` passes `-debug` in debug mode, Odin would otherwise go looking for a `..._debug.lib`
that is not here. The sokol row in `BACKENDS` therefore carries `define: "SOKOL_DEBUG=false"`, which
`build_demo_for` turns into `-define:SOKOL_DEBUG=false`. That pins the release libraries in both
build modes, halves what is committed, and costs only C-level debug symbols inside sokol — which is
not what you want to step through anyway.

If you build the sokol demo by hand rather than through `build.odin`, pass that define yourself.

## Rebuilding the libraries

The committed libraries are Windows x64 / D3D11. On another platform, or after bumping the pin, run
the matching upstream script from this directory's `sokol/`:

```
build_clibs_windows.cmd     # from a Visual Studio developer prompt, needs cl and lib
./build_clibs_linux.sh
./build_clibs_macos.sh
```

Those scripts build all nine upstream packages across every configuration; keep only the four
`log` / `app` / `gfx` / `glue` release libraries for the platform you are on. To build just those on
Windows:

```
cl /nologo /c /O2 /DNDEBUG /DIMPL /DSOKOL_D3D11 c\sokol_<pkg>.c
lib /nologo /OUT:<pkg>\sokol_<pkg>_windows_x64_d3d11_release.lib sokol_<pkg>.obj
```

## Imports

There is no `-collection` flag for this, deliberately. Upstream's own `glue.odin` imports `gfx` with
a relative path, and the `foreign import` inside each binding is relative to that file's own
directory — so preserving the `app/` `gfx/` `glue/` `log/` shape is all that linking needs.

```odin
import sapp "../../third_party/sokol/sokol/app"
import sg   "../../third_party/sokol/sokol/gfx"
```

A collection would have to be repeated on every `odin check` an editor runs, for no gain.

## `.gitignore`

The repository ignores `bin`, `build/` and `*.exe`, none of which match anything here. If a broad
`third_party` or `*.obj` rule is ever added, exclude this directory or the libraries silently stop
being committed and `-backend:sokol` fails to link on a fresh clone.
