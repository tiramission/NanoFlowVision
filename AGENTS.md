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

The app shows the folder named on the command line, or the user's Pictures,
or the folder it was started in.

## Rules

- **Never open windows while working.** Check what the app looks like with
  `nui snapshot` (open the PNG), and what it does with tests through
  `ui.Tester` (`src/tests.zig`). `nui run` is for people.
- **A view is a function of the state.** `State.view` in `src/app.zig` draws
  everything each frame; widgets report input as they're drawn
  (`if (ui.button(c, "Save", .{}).clicked) …`).
- **Every behavior gets a test** in `src/tests.zig`: `t.clickText`,
  `t.doubleClick`, `t.hasText`, `t.screenshot("/tmp/x.png")`.
- **No file is over 600 lines**, as in nanoui itself.

## Layout

```
build.zig       the app, `run` and `test` steps
build.zig.zon   nanoui and zigimg, pinned
src/main.zig    the window, and the folder to show
src/app.zig     the state and its view: tree, gallery, the large picture
src/model.zig   what a folder holds: folders, pictures
src/scan.zig    reading folders and files
src/decode.zig   pictures as pixels: BGRA, premultiplied; the per-platform dispatch
src/wic.zig      Windows' decoder: WIC scales while it decodes, from disk
src/imageio.zig  macOS' decoder: ImageIO, the same way
src/exif.zig     what a picture says about itself: EXIF, from the bytes measurement holds
src/large.zig    the picture large, with its exif in the corner
src/masonry.zig  where each picture sits: columns of pictures
src/thumbs.zig   the cache and the workers that fill it
src/tests.zig    the view, drawn offscreen, and the pictures it decodes
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
