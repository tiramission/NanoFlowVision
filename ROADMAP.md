# ROADMAP

这份文档记的不是"想要哪些功能"，而是**接下来按什么顺序做，以及每一步要解决哪个还不确定的技術问题**。
功能清单在下面那张表里；为什么是这个顺序，在这里。

每一步都带一个**验收标准**——能测的，不是"感觉快了"。

## 现状（2026-10-23 实测，Windows / ReleaseFast / 1280×800）

| 场景 | 峰值内存 | 备注 |
|---|---|---|
| 空文件夹 | **75 MB** | 应用自身基线（CPU 渲染器 2560×1600 双缓冲 + 字形图集） |
| 200 张 1.4 MP | **108 MB** | 阶段 1 之后：多出来的是预取的缩略图（多解了约一屏半） |
| 8 张 24 MP | 450 MB → **80 MB**（阶段 3） | 之前：解码整幅图再缩小，4 个 worker 各吃一张全尺寸 |

启动到首帧约 250 ms；200 张照片的目录，0.5 秒内视口内全部解码完毕。

**结论**：文件数量不是问题，**照片的尺寸才是**。阶段 3 之前 `decode.decode` 先把整张图解成
RGBA 再做 box 降采样，一张 24 MP 的照片瞬间就是 96 MB，而 zigimg 的 JPEG 解码器没有
libjpeg 那种 DCT 缩放，纯 Zig 路线躲不掉；阶段 3 换成系统解码器（Windows 的 WIC）
之后，内存跟着**输出的缩略图**走，这张表上真正的风险已经解掉。

## 阶段

**顺序调整**：阶段 3 的调研做完后，结论是**先做阶段 3**——它把每个 worker 的内存开销
降到 1/4，而且 macOS 那条路已经在 nanoui 里被验证过；做完它，阶段 4（EXIF）也能
顺便一起拿到元数据。阶段 3 已于 2026-10-24 落地（WIC 路线，见下），
阶段 2（排序与搜索）随之在同日完成。

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

### 阶段 2 · 排序与搜索 ✅

日常翻相册用得最多，不引入新依赖。**已实现**（2026-10-24，`feat/stage2`）。

- **排序**：Name / Date / Size / Pixels（分段控件）+ 方向（↑↓）。Date 和 Size 来自量尺寸阶段
  顺带的 `stat`（一次读头时一起拿到），Pixels 来自文件头——**切排序不读文件、不重新解码**，
  缩略图按路径缓存，与顺序无关（测试断言排序前后解码缓冲指针不变）。
- **搜索**：文件名子串、忽略大小写，即时过滤（纯内存，远快于 100 ms 的验收线）。
  过滤时计数显示"1 of 3 pictures"；换文件夹自动清空，排序保持。
- **实现**：`State.shown`——指向当前文件夹图片的指针列表，先过滤再排序（`orderFold` 忽略大小写；
  同键并列按名字 A→Z）。布局、预取、点按大图都走 `shown`；`showLarge` 改收图片指针，不再依赖序号。
- 工具栏用了 nanoui 的 `ui.segmented` 和 `ui.textField`。

**验收**：切排序不触发任何重新解码 ✅（测试）；搜索结果即时出现 ✅（同步内存过滤）。
23 个测试全绿，新增 4 个（排序翻转不重解码、按像素数排序、搜索收窄与清空、换文件夹重置搜索）。

### 阶段 3 · 换掉缩略图解码路径 ✅

解决 450 MB 那个问题。**已实现并实测**（2026-10-24，`feat/stage3`）。

**落地的东西**：

- `src/wic.zig` —— Windows 的 WIC，COM vtable 直接声明（约 200 行）。文件留在磁盘上由 WIC 自己读，
  缩放走在解码里，输出 `32bppPBGRA`（预乘 BGRA，nanoui 纹理零转换）。COM 对象按创建逆序 Release；
  `CoInitializeEx` 每线程一次（threadlocal）。链接 `ole32` + `windowscodecs`。
- `src/imageio.zig` —— macOS 的 ImageIO，照 nanoui 自己的 `decodeFit` 写的（约 120 行），走文件 URL，
  `CGImageSourceCreateThumbnailAtIndex` 边解码边缩放。**只在 macOS 上编译过声明，未实测**——上 Mac 时先跑一遍。
- `src/decode.zig` 的 `decodeFile` —— 按平台分派：Windows 走 WIC，macOS 走 ImageIO，
  其余平台（和系统解码器读不了的图）读整文件走 zigimg 兜底。
- `src/app.zig` —— 视图在还有缩略图没就绪时调用 `c.animationFrame()`（量尺寸阶段和大图加载同理）：
  状态在路上，帧就得继续来。这是"视图是状态的函数"的一部分。
- 顺带发现并绕过：nanoui 离屏快照的 `settle` 用的是**模拟时间**（dt=1/60 × 帧数），2 秒预算实际只给
  几十毫秒真实时间，慢解码赶不上截图。给快照加 `--nanoui-script=live:1`（真实时间泵事件循环+画帧）即可。

**实测（Windows / ReleaseFast / 8 张 24 MP PNG / 离屏快照）**：

| 场景 | 之前（zigimg 全图解码） | 现在（WIC） |
|---|---|---|
| 8 张 24 MP 的峰值内存 | **450 MB** | **80.0 MB**（应用基线 75 MB） |
| 单张 24 MP 缩略图解码 | ~103 ms / 100 MB | ~30 ms / ~9 MB |

验收标准"24 MP 峰值 < 150 MB"达标。另做了两个专项验证：4 线程并发锤击 1280 次 WIC 解码零失败；
`std.Io.Mutex` 五线程百万次进出无一计数错（排查快照伪影时顺手做的）。

**踩过的坑（写代码时一定会遇到）**：

- Zig 自带的 mingw 头文件（`lib/libc/include/any-windows-any/wincodec.h`）**和真正的 DLL 对不上**：
  - `CreateDecoderFromFilename` 头文件写 4 个参数，DLL 实际要 5 个
    （`filename, vendor, dwDesiredAccess, riid, out`）——按头文件写会崩。
  - `CreateBitmapScaler` / `CreateFormatConverter` 头文件写 1 个参数（只有 out），
    这个**是对的**——按 COM 惯例多传一个 riid 也会崩。
  - 接口名是 `IWICFormatConverter`，不是 `IWICBitmapFormatConverter`。
- **vtable 结构体必须声明到要调用的最后一个槽位**，中间的方法一个不能省
  （`IWICImagingFactory` 继承 IUnknown(3)：`CreateDecoderFromFilename`=3、`CreateFormatConverter`=10、
  `CreateBitmapScaler`=11；`IWICBitmapSource`(8)；Scaler/Converter 的 `Initialize`=8）。
  声明截断了就会调到错误的槽位——按头文件顺序写全即可。
- `CoInitializeEx(null, COINIT_MULTITHREADED)` 之后才能用 COM；路径要转 UTF-16 **带结尾 0**
  （`std.unicode.utf8ToUtf16LeAllocZ`）；COM 对象要按创建的逆序 `Release`（worker 常驻，不释放就是真泄漏）。
- 探针 `tools/wicprobe/` 留在仓库里，改动解码路径时可以再跑一遍对比。

**各平台怎么走**：

| 平台 | 办法 | 状态 |
|---|---|---|
| Windows | WIC：`CreateDecoderFromFilename` → `GetFrame` → `IWICBitmapScaler` → `IWICFormatConverter` | ✅ |
| macOS | ImageIO 的 `CGImageSourceCreateThumbnailAtIndex` + `kCGImageSourceThumbnailMaxPixelSize` | 代码就绪，待上机验证 |
| Linux | 没有系统缩略图器 | zigimg 兜底，接受它的内存 |

（调研阶段的原始实测数据表保留在 git 历史里；探针可随时重跑。）

### 阶段 4 · 元数据 ✅

EXIF 已实现（2026-10-24，`feat/stage4`）：

- **`src/exif.zig`** —— 纯 Zig 的 EXIF 解析（约 250 行）：JPEG 的 APP1 段（跳过 XMP 等别的 APP1）、
  TIFF 自带头；TIFF 字节序 II/MM 都支持。取 Make/Model、DateTimeOriginal、曝光、光圈、ISO、焦距、方向。
  字符串放进结构体自带的定长缓冲（量尺寸的缓冲是 worker 复用的，不能引用）；每个读取都有边界检查。
- **零额外读盘**：EXIF 就在量尺寸阶段读的那 64KB 头部里，`measure` 任务顺路解析入缓存
  （`Shared.metaOf(path)`）。符合"EXIF 和缩略图一次读取拿到"的依赖要求。
- **信息面板**：大图视图左上角两行——"Canon EOS R5" 和 "2024-01-02 03:04 · f/2.8 · 1/250 s · ISO 200 · 24 mm"，
  只显示有的字段；大图没加载完也照常显示（`src/large.zig`）。
- 单元测试覆盖两种字节序、JPEG 包装、XMP 段跳过、畸形输入；集成测试手工构造 JPEG 全链路
  （量尺寸 → 缓存 → 大图面板），测试全绿。
- PNG/GIF/BMP 不解析（PNG 的 eXIf 块很罕见，先不做）；EXIF 方向（orientation 6/8 的竖拍照片）
  目前只读取不旋转——显示旋转要做像素变换，另列。

**评分与标签**（用户拍板：写回照片文件，标准 XMP）：

- **`src/xmp.zig`** —— XMP 包的构建与读取（`xmp:Rating` 属性 + `dc:subject` 标签袋，
  Lightroom 等软件读同一标准），以及 JPEG 的段级重建：原段保留（丢掉旧的 XMP 段），我们的
  XMP 段插在 SOI 之后，SOS 起的图像数据原样到末尾。
- **原子写**：先写临时文件再 `File.Atomic.replace` 落位，崩溃不会毁照片；写完恢复原 mtime，
  评分不会把照片在 Date 排序里挪位。
- **UI**（大图视图）：数字键 1-5 评分、0 清除、`t` 加标签（Enter 提交）、点标签上的 ✕ 删除；
  面板显示 ★★★★☆ 和标签 chips；排序菜单加 "Stars"（未评分排最后）。只对 JPEG 开放
  （其他格式的容器写法另列）。写失败时缓存不更新——面板显示的与文件一致。
- **验收达成**：评分写进文件、重启后仍在（测试直接重读磁盘断言）；标签同理。

### 阶段 5 · 视频

**最大的未知，可能推后。** nanoui 没有视频控件，只有 `ui.texture` 能塞一帧画面进去。

- 要自己接解码器：ffmpeg（纯 Zig 绑定不存在，Windows 上有现成的 ffmpeg.dll）或者 Windows 的 Media Foundation。
- 缩略图用 ffmpeg 抽帧，播放用 `ui.texture` 逐帧上传。
- **验收**：能播 mp4，能抽帧当缩略图。

### 阶段 6 · 文件操作与右键手势 ✅（设置面板除外）

已实现（2026-10-24，`feat/stage6`）：

- **`src/ops.zig`** —— 文件操作层：nanoui 的 shell（open / reveal）各平台都有就用它；
  Windows 的回收站 nanoui 是空壳，这里用 SHFileOperationW（FOF_ALLOWUNDO → 可撤销）自己实现；
  文件剪贴板用 CF_HDROP 读写（资源管理器互认）。重命名走 renameAbsolute，重名拒绝。
- **悬停菜单**：nanoui 不暴露右键，缩略图悬停时右上角出现 "⋯"，点开菜单：
  Open large / Open in system / Reveal in Explorer / Copy / Rename… / Move to Recycle Bin；
  点空白处或 Esc 关闭。Ctrl+V 把剪贴板里的文件粘到当前文件夹（名字冲突自动 " - Copy"）。
- **重命名**：弹窗输入，提交后文件改名，树/画廊/缓存三处同步——缓存的 key 随路径迁移
  （`Shared.renameKey`），缩略图不重新解码。
- **递归浏览**：树栏的 "Subfolders" 复选框，勾上后画廊列出子文件夹（逐层，跳过点开头目录）的
  全部照片；重列后测量照常，缓存按路径复用。
- 回收站与粘贴后目录重列（relist），测量照旧、已缓存的不重解。
- **验收**：重命名/回收站/复制粘贴/递归各有测试，全绿。
- **没做的**：设置面板（暂无可配置项）；Finder 标签（macOS 专属——阶段 4 的 XMP 标签即跨平台等价物）；
  右键拖拽手势（nanoui 不暴露右键，列回阶段 7 的交互打磨）。

### 阶段 7 · 交互打磨 ✅（多窗口与手势除外）

已实现（2026-10-24，`feat/stage7`）：

- **暗色模式**：Ctrl+D 随处切换（大图里也生效），窗口 surface 的主题直接换（Windows 的 surface
  默认永远亮色，这里通过 `theme_override` 接管）；启动读回上次的偏好。
- **窗口状态记忆**：位置和尺寸在关闭时存入数据目录的 `settings.txt`（nanoui 的 `desktop.path(.data)`），
  启动恢复；写入直接截断重写（几行键值对，不值得原子仪式）。
- **大图快捷键**：← → 在画廊里前后走（到头即停）；Delete 把照片送进回收站并自动跳到下一张。
- **目录监听**：`src/watch.zig` —— ReadDirectoryChangesW 独立线程（本文件夹，文件名/目录名/改写），
  变化经 `App.onMain` 回主线程重列；换文件夹重挂，退出 CancelIoEx 立即收线程。
  回收站/粘贴后的重列与它共用同一条路（relist），已缓存的图片不重解。
- **递归偏好记忆**：Subfolders 勾选状态随设置存取。
- **没做的**：多窗口（单窗口是这个应用的形状，FlowVision 也是）；右键拖拽手势（nanoui 不暴露右键，
  悬停菜单已是替代）；Linux/macOS 的目录监听（inotify/FSEvents 另列）。
- 测试 33 全绿；暗色快照 `docs/app-dark.png`。

## 界面设计

界面仿照 **nanomon**（nanoui 同作者的参考应用，2026-10-24 重设计）：Harness 的 Codegraff
色板——暖炭 `#16140f` 或奶油 `#faf8f3` 底、琥珀选中、暖白文字，Geist/JetBrains Mono 字体；
侧栏 214px（图标 chip + 等宽尾数 + 底部 Watching 状态）、页头 52px。文档在 `docs/design.md`，
实现是 `src/theme.zig`（色板从 nanomon 移植，MIT）。改视觉只动这两处。

## 阶段 8 · 观片的正确与深度（2026-10-24 修订时新增）

- **EXIF 方向旋转**。竖拍照片（orientation 6/8，手机照的大多数）现在在 Windows 上横躺着——
  这是正确性 bug。`exif.zig` 已解析方向；macOS 的 ImageIO 已带 transform（✓）；Windows 的 WIC
  在 scaler 之后插 `IWICBitmapFlipRotator`（5/7 两个横竖变换链两个 rotator），仍是解码内变换、
  零额外内存。**测量的宽高比要跟着换**（orientation 5-8 交换 w/h），否则布局也是躺着的。
- **递归模式下的目录监听**。`watch.zig` 的 ReadDirectoryChangesW 传了 `subtree=0`——勾了
  Subfolders 后子文件夹的增删不会自动刷新。修一个参数。
- **大图 1:1 缩放与平移**。现在只有 fit-view；像素级查看是照片浏览器的核心用途（FlowVision 有）。
  滚轮缩放、拖拽平移、双击在 fit 与 1:1 之间切换；Esc 语义不变。
- **验收（2026-10-24 达成）**：竖拍 JPEG 立着显示、布局也是竖的（宽高比断言 + 真 JPEG
  端到端像素断言）；滚轮缩放、双击回 fit（测试驱动真实滚轮事件）。测试 38 全绿。

## 阶段 9 · 布局与选择（2026-10-24 修订时新增）

- **justified / grid 布局补做**。功能差距表曾把这项误标为 ✅——实际只有瀑布流。justified
  （行式自适应）和 grid（均匀网格）是 `masonry.zig` 的两个兄弟算法，排序页头加个切换。
- **画廊键盘导航与选中**。方向键只在
 大图里生效；画廊没有选中模型，纯键盘无法浏览。
  选中 + 方向移动 + Enter 开大图 + Delete 进回收站。
- **缩略图大小档位**。固定 256px；FlowVision 可调（小/中/大），缓存按路径键仍复用（尺寸进 key）。
- **验收**：三种布局同一数据切换不重解码；纯键盘完成浏览→开图→评分→关闭。

## 功能差距表

FlowVision 有、我们还没有的，以及它落在哪个阶段：

| 功能 | 阶段 |
|---|---|
| 瀑布流布局 | 1 ✅ |
| justified / grid 布局 | 9（此前误标为 1 ✅，实际未做） |
| 排序（名字/大小/时间/EXIF/评分/标签） | 2 ✅（名字/时间/大小/像素数；EXIF/评分在阶段 4） |
| 搜索 | 2 ✅ |
| 缩略图解码路径换掉 | 3 ✅ |
| EXIF 信息面板 | 4 ✅ |
| 星级评分 | 4 ✅（JPEG 写回 XMP） |
| 标签 | 4 ✅（JPEG 写回 XMP） |
| EXIF 方向旋转 | 8 ✅（Windows WIC；ImageIO 已带 transform） |
| 大图 1:1 缩放平移 | 8 ✅ |
| 递归模式下的目录监听 | 8 ✅ |
| 视频播放 | 5 |
| 视频缩略图 | 5 |
| 重命名 / 删除 / 回收站 | 6 ✅ |
| 复制粘贴 | 6 ✅ |
| 递归浏览 | 6 ✅ |
| 设置面板 | 已关闭：设置（暗色/递归/窗口状态）都在界面里就地切换并持久化 |
| 右键手势 | 已关闭：nanoui 不暴露右键，悬停菜单是替代 |
| 窗口管理 / 多窗口 | 已关闭：单窗口是这个应用的形状 |
| 画廊键盘导航与选中 | 9 |
| 缩略图大小档位 | 9 |
| 目录监听自动刷新 | 7 ✅（Windows；inotify/FSEvents 见平台债） |
| 暗色模式 | 7 ✅ |

FlowVision 还有 `justified`（自适应行）和 `grid`（网格）两种布局——归入阶段 9，不再算阶段 1 的欠账。

## 平台债（等硬件，单列）

- **macOS**：`src/imageio.zig` 编译过声明未上机实测；目录监听要 FSEvents；ops.zig 的
  文件剪贴板（CF_HDROP 的 mac 等价物）是 TODO。
- **Linux**：目录监听要 inotify；解码仍是 zigimg 兜底（接受它的内存）。

## 明确不做的

- **RAW 格式**。解码器成本极高，收益低。
- **HEIC**。除非走阶段 3 的系统解码器（Windows 的 WIC 新版本支持 HEIF），否则不做。
- **色管理 / HDR**。nanoui 的 CPU 渲染器不做色彩管理；Metal 那条路以后再说。
- **跨设备同步**。这是本地浏览器，不是照片管理服务。

## 相关

- 详细的调研记录和踩坑（Zig 0.17 的 API 变化、nanoui 的内部约定）见 `.workbuddy/memory/2026-10-23.md`。
- 长期有效的技术决定见 `.workbuddy/memory/MEMORY.md`。
