# ROADMAP

这份文档记的不是"想要哪些功能"，而是**接下来按什么顺序做，以及每一步要解决哪个还不确定的技術问题**。
功能清单在下面那张表里；为什么是这个顺序，在这里。

每一步都带一个**验收标准**——能测的，不是"感觉快了"。

## 现状（2026-10-23 实测，Windows / ReleaseFast / 1280×800）

| 场景 | 峰值内存 | 备注 |
|---|---|---|
| 空文件夹 | **75 MB** | 应用自身基线（CPU 渲染器 2560×1600 双缓冲 + 字形图集） |
| 200 张 1.4 MP | **108 MB** | 阶段 1 之后：多出来的是预取的缩略图（多解了约一屏半） |
| 8 张 24 MP | **450 MB** | ⚠️ 解码整幅图再缩小，4 个 worker 各吃一张全尺寸 |

启动到首帧约 250 ms；200 张照片的目录，0.5 秒内视口内全部解码完毕。

**结论**：文件数量不是问题，**照片的尺寸才是**。现在 `decode.decode` 先把整张图解成 RGBA 再做 box 降采样，
一张 24 MP 的照片瞬间就是 96 MB。zigimg 的 JPEG 解码器没有 libjpeg 那种 DCT 缩放（1/2、1/4、1/8），
所以纯 Zig 路线下这个开销躲不掉——除非换解码器，或按尺寸限制并发。

## 阶段

**顺序调整**：阶段 3 的调研做完后，结论是**先做阶段 3**——它把每个 worker 的内存开销
降到 1/4，而且 macOS 那条路已经在 nanoui 里被验证过；做完它，阶段 4（EXIF）也能
顺便一起拿到元数据。阶段 2（排序与搜索）不依赖任何新东西，随时可以插进来做。

### 阶段 1 · 把浏览做扎实 ✅

不加任何依赖，先把已有的东西做到"能天天用"。

- **布局稳定**。宽高比改为**先全部量完再布局**：只读文件头的量尺寸阶段跑完前，画廊显示
  "measuring N of M…"，量完之后布局**只做一次**，之后只有窗口宽度变了才重排。
  画廊不再在测量陆续到达时跳动，滚动位置也不再漂。
  代价是打开文件夹时有一次短暂的等待（只读文件头，2000 张约 200 ms）。
- **按滚动方向预取**。缩略图不再只解码视口内的：往前预取 2 屏、往后 0.5 屏，
  方向随滚动方向反过来。向上滚不会看到一片空白。
- **缓存淘汰**。改为**按最近使用**（LRU）而不是按生成时间淘汰，并且可见的缩略图受保护。
  之前来回快速滚动会反复重解码，现在不会。
- **顺带修的**：缓存跟着文件夹走（切文件夹时清空，迟到的旧结果按世代丢弃）；
  淘汰挪到建纹理之前（之前会用到已释放的像素）；任务队列改成 O(1) 出队（一次要排几千个测量任务）。

**验收**：17 个测试全绿，覆盖"尺寸量完前不布局""布局做好后不再移动""视口外也预取"
"缓存会放弃不用的缩略图""滚动后布局不动""双击开大图"。

### 阶段 2 · 排序与搜索

日常翻相册用得最多，而且不引入新依赖。

- 排序 key 照 FlowVision 的思路设计（名字、扩展名、大小、创建/修改/添加时间、EXIF 拍摄时间、像素数、评分）。
  排序结果一变，布局要重算，但**不能重新解码**——缩略图按路径缓存，与顺序无关。
- 搜索按文件名子串匹配即可，先不上索引（一个目录几千个文件时线性扫足够快）。
- **验收**：切排序不触发任何重新解码；搜索结果 < 100 ms 出现。

### 阶段 3 · 换掉缩略图解码路径 ✅ 已调研

解决 450 MB 那个问题。这是本项目最大的技术未知。**已经用探针实测过了**。

探针在 `tools/wicprobe/`（自己一个包，`cd tools/wicprobe && zig build -Doptimize=ReleaseFast`），
它用 WIC 和用 zigimg 各解一遍同一张图，打印尺寸、耗时、进程峰值内存和第一个像素。

**实测（Windows，ReleaseFast，缩略图 256px，中位数，5 次）**：

| 文件 | 路径 | 耗时 | 峰值内存 |
|---|---|---|---|
| JPEG 1 MP | WIC | **16 ms** | **11.8 MB** |
| JPEG 1 MP | zigimg | 17 ms | 20.4 MB |
| JPEG 6 MP | WIC | **82 ms** | **26.2 MB** |
| JPEG 6 MP | zigimg | 112 ms | 93.5 MB |
| PNG 24 MP | WIC | **32 ms** | **9.1 MB** |
| PNG 24 MP | zigimg | 103 ms | 100.2 MB |

**结论**：

- WIC 完胜。24 MP 的图：**100.2 MB → 9.1 MB（11 倍）**，耗时也快 3 倍。
  它的内存跟着**输出**走，不跟着**输入**走。
- 两个格式的机制不同：WIC 的 PNG 解码器是一行一行给的，所以 24 MP 也只占 9 MB；
  WIC 的 JPEG 解码器还是先解出整幅（6 MP 占 26 MB），但比 zigimg 少得多
  （zigimg 要 4 字节/像素的 RGBA，WIC 要 3 字节/像素的 RGB）。
- WIC 直接**从磁盘读文件**，连"把整个文件读进内存"这一步都省了。
- 输出格式是 `GUID_WICPixelFormat32bppPBGRA` —— **预乘 BGRA**，和 nanoui 要的
  `gpu.Texture.bgra` 一模一样，**一次转换都不用做**。
- 试过"先缩到 1/2、1/4、1/8 再缩到位"的两步法（用 JPEG 的 DCT 缩放）：**没用**，
  WIC 的 JPEG 解码器没有走那条路，内存一样。所以不用搞复杂。

**各平台怎么走**：

| 平台 | 办法 | 代价 |
|---|---|---|
| Windows | WIC：`CreateDecoderFromFilename` → `GetFrame` → `IWICBitmapScaler` → `IWICFormatConverter` | 约 250 行 COM vtable 声明；`ole32` + `windowscodecs` |
| macOS | ImageIO 的 `CGImageSourceCreateThumbnailAtIndex` + `kCGImageSourceThumbnailMaxPixelSize` | 约 50 行。**nanoui 已经这么做了**（`src/ui/image.zig` 的 `decodeFit`，注释明写 "ImageIO scales while it decodes: no full-size copy is made"），但没有从 `nanoui.ui` 导出，得自己写一遍 |
| Linux | 没有系统缩略图器 | 只能继续用 zigimg，接受它的内存；或者限制并发 |

**踩过的坑（写代码时一定会遇到）**：

- Zig 自带的 mingw 头文件（`lib/libc/include/any-windows-any/wincodec.h`）**和真正的 DLL 对不上**：
  - `CreateDecoderFromFilename` 头文件写 4 个参数，DLL 实际要 5 个
    （`filename, vendor, dwDesiredAccess, riid, out`）——按头文件写会崩。
  - `CreateBitmapScaler` / `CreateFormatConverter` 头文件写 1 个参数（只有 out），
    这个**是对的**——按 COM 惯例多传一个 riid 也会崩。
  - 接口名是 `IWICFormatConverter`，不是 `IWICBitmapFormatConverter`。
  - 头文件在 `ZIGLIB/lib/libc/include/any-windows-any/wincodec.h`，不用另外找。
- COM 的 vtable 序号 = 基类的方法数 + 自己的方法序号（每个方法 8 字节）。
  `IWICImagingFactory` 继承 `IUnknown`（3 个），所以 `CreateDecoderFromFilename` 是第 3 个，
  `CreateFormatConverter` 第 10 个，`CreateBitmapScaler` 第 11 个。
- `CoInitializeEx(null, COINIT_MULTITHREADED)` 之后才能用 COM；
  路径要转成 UTF-16 **并带结尾的 0**（`std.unicode.utf8ToUtf16LeAllocZ`）。
- Zig 0.17 没有 `std.time.Timer` 了，用
  `std.os.windows.ntdll.RtlQueryPerformanceCounter` / `RtlQueryPerformanceFrequency`。

- **验收**：24 MP 照片的缩略图，峰值内存 < 150 MB（实测 WIC 是 9 MB），解码耗时降到 1/5。
  顺带：`tools/wicprobe` 留在仓库里，改动解码路径时可以再跑一遍对比。

### 阶段 4 · 元数据

EXIF（拍摄时间、相机、光圈快门）、评分、标签。

- 依赖阶段 3：EXIF 和缩略图应该在同一次文件读取里拿到，别读两遍。
- 纯 Zig 读 EXIF 意味着解析 TIFF 结构，可行但要写。
- 评分和标签写回文件（XMP / sidecar），跨平台的写法要定。
- **验收**：信息面板显示拍摄参数；评分和标签重启后还在。

### 阶段 5 · 视频

**最大的未知，可能推后。** nanoui 没有视频控件，只有 `ui.texture` 能塞一帧画面进去。

- 要自己接解码器：ffmpeg（纯 Zig 绑定不存在，Windows 上有现成的 ffmpeg.dll）或者 Windows 的 Media Foundation。
- 缩略图用 ffmpeg 抽帧，播放用 `ui.texture` 逐帧上传。
- **验收**：能播 mp4，能抽帧当缩略图。

### 阶段 6 · 文件操作与右键手势

重命名、删除（回收站）、复制粘贴、Finder 标签、搜索、递归浏览、设置面板。
nanoui 的 `desktop.zig` 已经有 open / reveal / trash / clipboard，这些是往上搭。

### 阶段 7 · 交互打磨

右键手势（FlowVision 的方向手势）、更多快捷键、窗口管理、多窗口、暗色模式、目录监听（外部改动自动刷新）。

## 功能差距表

FlowVision 有、我们还没有的，以及它落在哪个阶段：

| 功能 | 阶段 |
|---|---|
| 瀑布流的 `justified` / `grid` 布局 | 1 ✅ |
| 排序（名字/大小/时间/EXIF/评分/标签） | 2 |
| 搜索 | 2 |
| 缩略图解码路径换掉 | 3 |
| EXIF 信息面板 | 4 |
| 星级评分 | 4 |
| Finder 标签 | 4 |
| 视频播放 | 5 |
| 视频缩略图 | 5 |
| 重命名 / 删除 / 回收站 | 6 |
| 复制粘贴 | 6 |
| 递归浏览 | 6 |
| 设置面板 | 6 |
| 右键手势 | 7 |
| 窗口管理 / 多窗口 | 7 |
| 目录监听自动刷新 | 7 |
| 暗色模式 | 7 |

FlowVision 还有 `justified`（自适应行）和 `grid`（网格）两种布局，我们只有瀑布流——这两个便宜，
可以随手加，属于阶段 1 的范围。

## 明确不做的

- **RAW 格式**。解码器成本极高，收益低。
- **HEIC**。除非走阶段 3 的系统解码器（Windows 的 WIC 新版本支持 HEIF），否则不做。
- **色管理 / HDR**。nanoui 的 CPU 渲染器不做色彩管理；Metal 那条路以后再说。
- **跨设备同步**。这是本地浏览器，不是照片管理服务。

## 相关

- 详细的调研记录和踩坑（Zig 0.17 的 API 变化、nanoui 的内部约定）见 `.workbuddy/memory/2026-10-23.md`。
- 长期有效的技术决定见 `.workbuddy/memory/MEMORY.md`。
