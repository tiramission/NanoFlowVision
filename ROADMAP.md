# ROADMAP

界面的规格见 [docs/design.md](docs/design.md)；这里只记**还没做的事**与**不能越过的边界**。
已完成的事看 `git log`（每个阶段一个提交）与 [docs/redesign/04-history.md](docs/redesign/04-history.md)。

## 现状（2026-10-23 实测，Windows / ReleaseFast / 1280×800）

| 场景 | 峰值内存 | 备注 |
|---|---|---|
| 空文件夹 | 75 MB | 应用基线（CPU 渲染器双缓冲 + 字形图集） |
| 200 张 1.4 MP | 108 MB | 多出来的是预取缩略图（一屏半） |
| 8 张 24 MP | 80 MB | WIC 边解码边缩放；此前整幅解码要 450 MB |

启动到首帧约 250 ms；200 张照片的目录，视口内 0.5 秒内解码完毕。
结论：文件数量不是问题，照片尺寸才是——所以解码走系统缩略图器（WIC / ImageIO），
24 MP 的照片从不整幅进内存。

## 还没做的

| 事项 | 依赖 / 说明 |
|---|---|
| **视频**（播放 + 抽帧缩略图） | nanoui 没有视频控件；要接 ffmpeg 或 Media Foundation，用 `ui.texture` 逐帧上传 |
| **justified / grid 两种布局** | 现在只有瀑布流；`masonry.zig` 的两个兄弟算法，密度钮旁加切换 |
| **标签筛选** | `exif.Meta` 已有 tags；需把 tags 放进 `thumbs.Measured` 再过滤 |
| **列表视图** | `ui.list` 虚拟化，行高 28：文件名/尺寸/星级；密度钮旁切换 |
| **⌘+滚轮改密度** | 设计草稿里有，没落地；网格滚轮目前只滚动 |
| **监视暂停态** | `watch.zig` 的读错误目前被当作“没有变化”；要暴露状态给状态条（黄点 + F5） |
| **非 JPEG 的评分写回** | `xmp.zig` 只会重建 JPEG 段；PNG/HEIC 的容器写法另列 |
| **撤销删除** | 依赖 `ops.restore`（Windows 的 Shell API），当前只承诺“可在回收站恢复” |
| **拖出到资源管理器** | 依赖 nanoui 的拖放 API（目前没有） |
| **a11y 树** | 依赖 nanoui 的平台无障碍桥；当前用键盘全可达 + 焦点可见替代 |

## 平台债

- **macOS**：`src/imageio.zig` 编译过声明、未上机实测；目录监听要 FSEvents；
  `ops.zig` 的文件剪贴板（CF_HDROP 的 mac 等价物）是 TODO。
- **Linux**：目录监听要 inotify；解码是 zigimg 兜底（接受它的内存）；
  全屏看图退化为最大化（nanoui 没有 X11/Wayland 全屏 API）。

## 造轮子清单（能用库的地方不用库）

| 手写的 | 为什么 | 换库的路径 |
|---|---|---|
| `src/win.zig`（窗口图标、最大化） | 三个 extern，不值得引依赖 | 长大了迁 zig-win32 |
| `src/watch.zig`（ReadDirectoryChangesW） | Zig 生态没有成熟的跨平台 watcher | macOS/Linux 实现时评估 notify 类库 |
| `src/wic.zig`（WIC 的 COM 调用） | 现路径经过 1280 次解码压测 | 迁 zig-win32 的接口绑定，消掉手数槽位的风险 |
| `src/exif.zig` / `src/xmp.zig` | 没有成熟的 Zig 读写库；写回要“重建段、原子替换” | 暂无；libexif/exiv2 集成成本高 |
| `src/masonry.zig` / `src/thumbs.zig` | 本项目的核心，不是轮子 | — |
| `src/config.zig`（key = value） | 刻意人选可读可改 | — |

## 明确不做的

- **RAW 格式**：解码器成本极高，收益低。
- **HEIC**：除非走系统解码器（Windows 的 WIC 新版本支持 HEIF），否则不做。
- **色管理 / HDR**：CPU 渲染器不做色彩管理。
- **跨设备同步**：这是本地浏览器，不是照片管理服务。
- **右键菜单 / 多窗口**：nanoui 不暴露右键；单窗口是这个应用的形状。⋯ 角标是替代。

## 相关

- 设计规格与快照：[docs/design.md](docs/design.md)、[docs/redesign/](docs/redesign/README.md)
- 编码规则：[AGENTS.md](AGENTS.md)
- 调研与踩坑记录：`.agents/memory/MEMORY.md`（长期约定）、`.agents/memory/2026-10-24.md`（WIC / nanoui 快照等细节）
