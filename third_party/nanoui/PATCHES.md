# nanoui, vendored — and why

`third_party/nanoui` is nanoui **v0.9.2**'s `src/` (plus its LICENSE and
notices), with three fixes this app needs and upstream does not have yet.
The build here is only the module: examples, `nui`, the reels are
upstream's and not ours.

When these land upstream, drop the directory and point `build.zig.zon`
back at the release.

## 1. `ui.texture` on the GPU (the white pictures)

**Symptom.** After v0.9.2, every photograph was a white rectangle: the
gallery, the large view, the filmstrip. The chrome drew fine.

**Cause.** Every picture here goes through `ui.texture` — not nanoui's
picture atlas, because the atlas caps a picture at 1024 px on a side.
That kind is `gpu.Kind.texture` (`kind == 8`). `shader.metal` has a
branch for it; **`shader.hlsl` (Direct3D 11) and `shader.glsl` (OpenGL)
did not**, so the instance fell through to the plain-quad branch and
painted its fill — white — over the picture. The CPU renderer
(`raster.zig`) has the branch, which is why the offscreen snapshots and
the `NANOUI_NO_D3D=1` path looked right, and only the real window was
white.

**Fix.**
- `src/ui/shader.hlsl`: `app_texture` on `t5`, `sampler_app_texture` on
  `s5`, and the `kind == 8` branch, as `shader.metal`'s.
- `src/ui/shader.glsl`: the same branch (BGRA swapped for GL ES, as the
  atlas branch already does).
- `src/ui/d3d11.zig` and `src/ui/opengl.zig`: the renderers bind **one**
  texture a draw, where Metal names a slot per instance, so a run of
  instances is split at each `kind == 8` and drawn with that texture.
  `Renderer.draw` takes the frame's `textures` (`ctx.textures`) for this.
- `src/windows/surface_gpu.zig`, `src/linux/surface.zig`,
  `src/android/surface.zig`, `src/ui/tests_d3d11.zig`,
  `src/ui/tests_opengl.zig`: pass `ctx.textures.items`.
- `src/ui/ui.zig`: exports `ui.d3d11` and `ui.gpu`, so an app can hold the
  GPU renderer to the CPU one for the kinds it draws.

`src/tests_gpu.zig` in the app is the regression test: it draws a red
`ui.texture` square on a blue clear through Direct3D 11 and asserts the
middle pixel is red. It fails on unpatched v0.9.2 (white) and skips only
when there is no device.

## 2. A CJK fallback drawn heavier than the Latin beside it

**Symptom.** Chinese labels came out bolder than the Latin text next to
them —「资料库」at `semibold` looked like the weight of a heading, while
「NanoFlowVision」beside it was normal.

**Cause.** `fontdb.family()` picks the face of a family nearest the asked
weight by **absolute difference**. Microsoft YaHei UI ships 400 and 700;
asked for 600 it took 700 (100 away) over 400 (200 away), then
`text_tt.zig` did not thicken it further — but the face was already a
full step heavy. Latin faces have 600, so the two strings disagreed.

**Fix.** `src/ui/tt/fontdb.zig`: a face **heavier than asked** costs
`1000` extra, so 400 wins for a 600 request, and `text_tt.zig`'s existing
`embolden` thickens it by 3% — the same synthetic semibold the Latin
path uses when a family has no 600.

## 3. `ui.d3d11` / `ui.gpu` exports

Small, but it is what makes the regression test above possible without
patching a second time: the renderer was reachable only from inside
nanoui's own tests.
