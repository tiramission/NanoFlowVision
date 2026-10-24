# AGENTS.md

NanoFlowVision is a picture browser: a tree of folders on the left, a gallery
of pictures in columns on the right. It is made with
[nanoui](https://github.com/justrach/nanoui) in Zig 0.17: native UI drawn by
nanoui itself (Metal on macOS, its own CPU renderer on Linux and Windows),
from one codebase.

## Commands

```sh
nui build                       # compile (zig build)
nui test                        # the tests: views rendered offscreen with ui.Tester
nui snapshot --out shot.png     # build, then render the app to a PNG, no window
nui snapshot --out shot.png --script "click:Increment;click:Increment"
nui run                         # open the app's window (for people, not agents)
nui doctor                      # check Zig and the platform
```

Every command takes `--json` for output a program can read.

Without `nui` on the PATH, the same thing works:

```sh
zig build                      # the app
zig build test                 # the tests
zig-out/bin/nanoflowvision.exe --nanoui-snapshot=shot.png --nanoui-wait=2
```

The app shows the folder named on the command line, or the folder of the
last visit, or the user's Pictures, or the folder it was started in.

## Rules

- **Never open windows while working.** Check what the app looks like with
  `nui snapshot` (open the PNG), and what it does with tests through
  `ui.Tester` (`src/tests.zig`). `nui run` is for people.
- **A view is a function of the state.** `State.view` in `src/app.zig` draws
  everything each frame; widgets report input as they're drawn
  (`if (ui.button(c, "Save", .{}).clicked) …`).
- **Every behavior gets a test** in `src/tests.zig`: `t.clickText`,
  `t.doubleClick`, `t.hasText`, `t.screenshot("/tmp/x.png")`. `hasText`
  proves a node exists, not that it is visible — for anything that can be
  painted over, clipped, or laid out wrong, assert the rect or keep a
  screenshot.
- **No file is over 600 lines**, as in nanoui itself.
- **A modal dialog never opens inside a frame's build.** Clicks only set a
  flag and schedule `nanoui.App.after(0, …)`; the dialog opens from that
  callback, outside any build, and the choice waits at the top of the next
  frame (see `openFolderDialog` in `src/app.zig`).
- **Prefer a mature library over a new wheel.** Folder dialogs are
  [nfd-zig](https://github.com/fabioarnold/nfd-zig); platform glue lives in
  `src/win.zig`. If a hand-written vtable or extern is ever needed, count
  its slots against the mingw headers shipped with zig
  (`lib/libc/include/any-windows-any/*.h`) before trusting it.

## Layout

```
build.zig       the app, `run` and `test` steps
build.zig.zon   nanoui, zigimg and nfd, pinned
src/main.zig    the window, and the folder to show
src/app.zig     the state and its view: tree, the overlays, the settings
src/gallery.zig the gallery: toolbar, the grid of pictures, their menu corner
src/model.zig   what a folder holds: folders, pictures
src/scan.zig    reading folders and files
src/decode.zig   pictures as pixels: BGRA, premultiplied; the per-platform dispatch
src/wic.zig      Windows' decoder: WIC scales while it decodes, from disk
src/imageio.zig  macOS' decoder: ImageIO, the same way
src/exif.zig     what a picture says about itself: EXIF and XMP, from the bytes measurement holds
src/xmp.zig      the stars and tags, written back into the picture file
src/large.zig    the picture large, with its exif in the corner
src/menu.zig     the picture's menu: open, reveal, copy, rename, the bin
src/ops.zig      the file operations: the bin and the clipboard where nanoui is silent
src/config.zig   the settings: how the window sat, dark, subfolders
src/theme.zig    the look: two themes, amber on paper and on charcoal (docs/design.md)
src/i18n.zig     the interface's words, in English and Chinese
src/watch.zig    the folder watched, so the disk's changes arrive by themselves
src/masonry.zig  where each picture sits: columns of pictures
src/thumbs.zig   the cache and the workers that fill it
src/win.zig      Windows glue: the window's icon, whether it is maximized
src/tests.zig    the view, drawn offscreen, and the pictures it decodes
src/tests_meta.zig  the tests for what goes into the picture files
```

## How the gallery works

- The pictures of the folder are listed by `scan.list`, then each one's size
  is read from its header alone (`decode.probeSize`): no pixels are decoded
  to lay the gallery out.
- `masonry.compute` places them: each picture goes in the column that ends
  highest, at its own height. The layout is analytic, so a picture's place is
  known without building it.
- Only the pictures in view are built, and each is drawn with `ui.texture`
  from the pixels the workers decoded — not through nanoui's picture atlas,
  which would cap a picture at 1024 pixels on a side.
- The workers (`thumbs.Pool`) read the files in the background and leave the
  answer in a cache both they and the view share. The view never waits: a
  picture that is not ready is drawn as a placeholder.
- Decoding goes through `decode.decodeFile`: on Windows the picture is scaled
  while it is decoded by WIC (`src/wic.zig`), on macOS by ImageIO
  (`src/imageio.zig`), so a 24 MP photograph never sits whole in memory;
  elsewhere — and wherever the system decoder cannot read a picture — the
  whole file is read and zigimg makes the thumbnail.
- While pictures are still on their way, the view asks for another frame
  (`c.animationFrame()`), so what is drawn follows the state as it arrives.
