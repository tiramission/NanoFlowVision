# nanoui: our fork

`build.zig.zon` pins **`tiramission/nanoui`**, branch `nanoflowvision-fixes`,
at commit `bb038a6` — nanoui v0.9.2 plus four fixes this app needs. It is
pinned to a commit, not to the branch: a branch would move under a build.

Upstream: `justrach/nanoui`. When these land there, drop the fork and point
`build.zig.zon` back at the release.

## The four commits

| commit | what |
|---|---|
| `284e0a3` | **shaders: draw `ui.texture` (kind 8)** on Direct3D 11 and OpenGL |
| `88c05f6` | d3d11: bind the frame's textures, one draw at a time |
| `f1c59de` | opengl: bind the frame's textures, one draw at a time |
| `ea00d7e` | fontdb: never pick a face heavier than the weight asked |
| `bb038a6` | ui: export `d3d11` and `gpu` |

## Why: the white photographs

Every picture in this app goes through `ui.texture` — nanoui's picture atlas
caps a picture at 1024 px on a side, which a photograph cannot live with.
That is `gpu.Kind.texture`, kind 8. `shader.metal` and the CPU renderer
(`raster.zig`) have a branch for it; **`shader.hlsl` and `shader.glsl` did
not**, so the instance fell through to the plain-quad branch and painted its
fill — white — over the picture.

It was invisible in testing because the offscreen snapshots are drawn by the
CPU renderer. Only a real window showed it.

The fix is two parts: the shader branch (Metal's, exactly), and the binding
— Direct3D and OpenGL take **one** texture a draw, where Metal names a slot
per instance, so a run of instances is split at each kind 8 and drawn with
its texture.

`src/tests_gpu.zig` here is the regression test: a red `ui.texture` on a
blue clear through Direct3D 11, its middle pixel asserted red. It fails on
unpatched v0.9.2 and skips only when there is no device.

## Why: the CJK text a step too heavy

`fontdb.family()` chose the face nearest the asked weight by absolute
difference. Microsoft YaHei UI ships 400 and 700; asked for 600 it took 700
(100 away) over 400 (200 away), and `text_tt.zig` does not thicken a face
that is already heavier — so 「资料库」came out a full step bolder than the
Latin text beside it, whose families have a 600.

A face heavier than asked now costs 1000 extra: 600 lands on 400, and
`text_tt.zig`'s existing 3% embolden makes it the same synthetic semibold
the Latin path uses when a family has no 600.

## Maintaining it

```sh
git clone https://github.com/tiramission/nanoui
cd nanoui
git remote add upstream https://github.com/justrach/nanoui
git fetch upstream --tags
git rebase v0.10.0            # or whatever the next release is
zig build test                # nanoui's own tests, including the D3D11 parity ones
```

Then bump the commit and the hash in `build.zig.zon` (`zig build` prints the
hash it expects when one is wrong). The four commits touch 11 files and add
about 190 lines, so a rebase is small — but it is a rebase, and conflicts
would be in the two renderers' draw loops.

## Upstream

Both fixes are worth sending upstream: the kind 8 gap is a bug any app
drawing a `ui.texture` hits on Windows and Linux, and the CJK weight affects
every app with Chinese or Japanese text. The commits are already separated so
they can be cherry-picked or opened as a PR against `justrach/nanoui:main`.
