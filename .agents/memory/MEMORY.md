# NanoFlowVision

用 [nanoui](https://github.com/justrach/nanoui)（Zig 0.17）重写的图片浏览器，
参照对象是 macOS 上的 [netdcy/FlowVision](https://github.com/netdcy/FlowVision)（Swift/AppKit，GPL）。

## 方向（用户确认）
纯 Zig 原生 UI · v1 只做最小可用闭环 · Windows 优先，但代码保持平台无关。

## 两条不可动摇的技术决定
1. **图片走 `ui.texture` 自己的 BGRA 像素，不走 `ui.image` 的图集。**
   `ui.image` 的图集 2048²、最长边截到 1024 → 大图看不了；图集满了会清空重排 → 滚动卡顿。
   像素格式：**BGRA，预乘**（nanoui 的 `gpu.Pixels` / `gpu.Texture.bgra` 都是这个约定）。
2. **布局解析化。** 只读文件头拿宽高比（`decode.probeSize`：PNG IHDR / GIF / BMP / JPEG SOF），
   不解码像素就能算出瀑布流位置 → 视口外的照片一个都不构建。
   `ui.list` 是等高行的 uniform_list，做不到变高瀑布流，必须自己写。

## 布局与浏览（阶段 1 已定）
- **先量尺寸再布局**：只读文件头量完所有宽高比才开始布局，布局只做一次（宽度变了才重排）。
  量完前显示 "measuring N of M…"。这样画廊不会在测量陆续到达时跳动。
- **缩略图按滚动方向预取**：往前 2 屏、往后 0.5 屏。
- **缓存按最近使用淘汰**，可见的受保护；切文件夹时整个缓存清空（按世代号丢弃迟到的旧结果）。

## 硬约定
- 每文件 ≤600 行（沿用 nanoui 的规矩）。当前总量约 2200 行（阶段 3 后）。
- 开发时不弹真实窗口：用 `--nanoui-snapshot` / `ui.Tester` 离屏验证。
  **快照慢解码要加 `--nanoui-script=live:1`**（settle 是模拟时间，见 2026-10-24.md）。
- 图片解码用 [zigimg](https://github.com/zigimg/zigimg)（纯 Zig，同样要 Zig 0.17.0）兜底；
  Windows 走 WIC（`src/wic.zig`）、macOS 走 ImageIO（`src/imageio.zig`），大图不再整幅进内存。
- 缓存 key 与文件路径必须分开（大图用 `"L:" ++ path` 做 key，曾因此让 worker 崩溃）。

## Zig 0.17 的坑
- 互斥量在 `std.Io`：`std.Io.Mutex.lockUncancelable(io)`、`std.Io.Condition.waitUncancelable(io, &m)`。
- 睡眠用 `std.Io.sleep(io, .fromMilliseconds(n), .awake)`（Clock 成员是 real/awake/boot）。
- Windows 上参数解析用 `std.process.Args.iterateAllocator(args, gpa)`。
- `std.StringHashMap` 不复制 key、也没有 `.empty` → 用 `StringHashMapUnmanaged` 自己持有 key。
- nanoui 侧：`c.scroll.put(...)` 可写滚动偏移；`c.rects` 跨帧保留但 `c.node(i).rect` 在 view 里读不到；
  `ui.Shortcut.escape` 要写全名；`ui.Tester.scroll` **负 dy 才是往下滚**。

## 验证方式
`zig build test`（23 个测试）、`zig-out/bin/nanoflowvision.exe <目录> --nanoui-snapshot=out.png --nanoui-wait=1 --nanoui-script=live:1`。
截图存在 `docs/`。详细调研与踩坑记录见 `.workbuddy/memory/2026-10-23.md` 和 `2026-10-24.md`。
