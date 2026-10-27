# 05 · 实施与验证

原则：**每一期结束时应用都必须是可运行、可发布的完整状态**，不合并半成品。
P0 只做「骨架 + 修正」，不足以称之为新设计；P1 才让新交互成立。

## 分期总览

| 期 | 主题 | 规模 | 用户可感知的变化 |
|---|---|---|---|
| **P0** | 骨架与修正：色板、外壳、命令栏、状态条、密度、失败态、toast、设置 sheet | L | 应用看起来完全不同，且现状 6 个缺陷被修掉 |
| **P1** | 选择与键盘：选择模型、游标、框选、批量动作、菜单升级、大图 HUD 与胶片条 | L | 「挑拣」这件事第一次变得可能 |
| **P2** | 增强：星级/标签筛选、历史、全屏、撤销、拖放、键盘一览 | M | 从「能用」到「顺手」 |

---

## P0 · 骨架与修正

| # | 工作项 | 文件 | 验收 |
|---|---|---|---|
| 0.1 | 新色板与对比度：`Colors` 换为 03 §1 的全部令牌；填满 `Theme` 槽位（`accent = 反相强调`） | `theme.zig` | 新增 `test "每个文字令牌都过对比度线"` 通过 |
| 0.2 | 拆 `app.zig`：把 rail / 命令栏 / 状态条搬到 `shell.zig`，设置搬到 `settings.zig` | `app.zig` `shell.zig`（新）`settings.zig`（新） | `wc -l` 全部 ≤ 600（现状 686 必须下降） |
| 0.3 | 命令栏重做：面包屑（`kit.breadcrumb`，`min_w=120`）+ 计数自适应 + 搜索 + 密度 + 排序图标钮 | `shell.zig` | 700pt 宽窗口下面包屑仍可见（测试断言 rect 宽 ≥ 80） |
| 0.4 | 排序改 `kit.menu`（✓ 当前键 + 升/降序两项）；密度 `kit.menu` 三档 | `shell.zig` | 菜单里能读到「升序」「降序」「大」等文字 |
| 0.5 | 密度生效：`masonry.compute` 的列数由目标行高推得；`thumbs` 的 `Kind` 带档位、缓存键含档位 | `shell.zig` `thumbs.zig` `masonry.zig` | 三档下第一行图块高度分别接近 128/256/512 |
| 0.6 | 图块：圆角 4、角标出现条件（悬停/游标/选中）、失败态与等待态分开、新增 `s.test_tiles` | `tile.zig`（新，从 `gallery.zig` 拆） | 「无法读取」在坏文件上出现；等待态没有该文字 |
| 0.7 | 状态条：选中数/总数/大小、监视圆点与时间、测量进度线 | `statusbar.zig`（新） | 三种文案都能在快照里看到 |
| 0.8 | toast：`State.toaster` + 全部 `ops` 结果回声（删除/粘贴/复制/重命名失败/写入失败） | `app.zig` `menu.zig` | 删除一张后 `t.hasText("已移到回收站")` |
| 0.9 | 空态/无匹配/不可读：`kit.empty` + 出口按钮；`kit.alert` 处理打不开的目录 | `gallery.zig` | 空目录与无匹配各有一张快照 |
| 0.10 | 设置 sheet：`kit.sheet` 取代居中弹窗（遮罩由 kit 提供，修掉现状 P2）+ 外观/密度/减少动效/导航栏宽度 | `settings.zig`（新） `config.zig` | 面板打开时背景变暗（截图）；新键往返测试通过 |
| 0.11 | 窗口标题带进度：测量时 `Window.setTitle("正在测量 42% · NanoFlowVision")`，结束还原 | `app.zig` | 单元断言字符串拼装函数即可 |
| 0.12 | 跟随系统外观：启动用 `nanoui.isDark()`；auto 模式每分钟读一次，变了换主题 | `main.zig` `app.zig` `theme.zig` | 设置选「跟随系统」后 `state.dark == nanoui.isDark()` |

**P0 不做**：选择模型、键盘游标、框选、胶片条、筛选、历史。
（但 0.6 已经把 `.test_tiles` 与角标条件准备好，P1 直接用。）

---

## P1 · 选择与键盘

| # | 工作项 | 文件 | 验收 |
|---|---|---|---|
| 1.1 | `select.zig`：选中集合（按路径键）、锚点、游标索引、框选状态机；换文件夹清空、重命名跟随、重新扫描保留存活的 | `select.zig`（新） | 单元测试：加选/连选/框选/重命名跟随/换目录清空 |
| 1.2 | 图块点击语义：单击/⌘加选/⇧连选/双击/点 ⋯；未选中压暗（设置可关） | `tile.zig` | 「已选 2 / 共 12」出现 |
| 1.3 | 网格键盘：方向键（左右跨列、上下同列）、Home/End/PageUp/PageDown、Space/Enter、0–5、⌫、F2、⌘C、⌘⇧R、⌘↩ | `gallery.zig` | 每条键在测试里按一次并断言可见后果 |
| 1.4 | 游标视觉：1px 内描边；与选中环同屏可辨（快照） | `tile.zig` | 快照 `selection-light.png` 两种状态同框 |
| 1.5 | 批量动作：评分（复用 `large.rate` 的写文件路径）、删除（>1 走确认）、复制；菜单在多选下只留两项 | `menu.zig` `select.zig` | 多选删除先出确认框；取消后文件仍在 |
| 1.6 | 菜单升级：`kit.menu` + `shortcut` 文案 + `separator` + `danger` + `disabled` | `menu.zig` | 菜单里能读到「⌘⌫」「移到回收站」 |
| 1.7 | 重命名框：`kit.dialog` + 内联错误、失败不关闭 | `menu.zig` | 同名重命名 → 「这个名字已经存在」且对话框仍在 |
| 1.8 | ⌘V 的粘贴目标改为「选中项所在文件夹」（无选择时 = 当前文件夹） | `menu.zig` | 测试断言文件落点 |
| 1.9 | 大图顶部条：序号「3 / 12」、文件名、可点星级 | `large.zig` | `t.hasText("3 / 12")` |
| 1.10 | 大图胶片条（窗口式 15 张），点击跳转，滚轮在条上 = 前后翻 | `filmstrip.zig`（新） | 点第 5 张 → `hasText("5 / 12")` |
| 1.11 | 信息块：收起/展开（`I`），面板卡片样式，替代常驻黑纱 | `large.zig` | 收起时只有一行；展开有 EXIF |
| 1.12 | 缩放控件：适应 ⇄ 100% 可点，`Z` 同效，百分比 mono | `large.zig` | `t.hasText("100%")` |
| 1.13 | Esc 层级：输入框 → 浮层 → 大图 → 选择 | `shell.zig` `gallery.zig` `large.zig` | 单元/集成各一层 |
| 1.14 | 导航栏键盘（↑↓←→ Enter Tab）+ 焦点顺序（搜索 → 筛选 → 排序 → 树 → 网格） | `shell.zig` `gallery.zig` | Tab 三次后方向键作用于树 |

---

## P2 · 增强（按需，不阻塞发布）

1. **星级筛选**（命令栏 ★≥N chip）：`shared.measuredOf(path).rating` 过滤 `shown`；
   新增「筛选后隐藏的选中项」状态文案。
2. **标签筛选**（P2）：标签在 `exif.Meta` 里已有，需要把 meta 提前到测量阶段填充
   （`thumbs` 的 `measure` 已读 EXIF，只需把 tags 也放进 `Measured`）。
3. **文件夹历史**：`⌥←/⌥→`，环形缓冲 20 条，放在 `State.history`。
4. **列表视图**：`ui.list`（虚拟化，行高 28）显示文件名/尺寸/星级，密度钮旁加切换；
   图标用 `list.bullet` / `square.grid.2x2`。
5. **全屏看片**：依赖 nanoui 加 `Window.setFullscreen`（02 §11 的缺口 #3）。
6. **撤销删除**：依赖 `ops.restore`（从回收站还原，平台相关；Windows 需要 Shell API）。
7. **拖出到资源管理器**：依赖 nanoui 的拖放 API（缺口 #7）。
8. **键盘一览**：`⌘/` 打开一张全屏对照表，内容就是 02 §5 的键盘地图。
9. **扩展名保护**：重命名时只选中主名，依赖文本框初始选区 API。
10. **监视暂停状态**：`watch.zig` 暴露错误状态，状态条变黄点 + F5 提示。

## 文件映射与行数预算

现状 `wc -l src/*.zig`（关键几行）：`app.zig` **686**、`tests.zig` **631**（两个都超线）、
`large.zig` 405、`gallery.zig` 289、`menu.zig` 167、`theme.zig` 105。

| 文件 | 现状 | 目标 | 说明 |
|---|---|---|---|
| `theme.zig` | 105 | ~180 | 新色板 + 对比度测试 + `icons_used` 允许清单 |
| `app.zig` | 686 | ~330 | 只留 State、帧编排、浮层调度、toaster |
| `shell.zig` | — | ~340 | rail + 命令栏 + 断点折叠 |
| `statusbar.zig` | — | ~110 | 状态条 + 进度线 |
| `settings.zig` | — | ~180 | 设置 sheet |
| `tile.zig` | — | ~230 | 图块与全部角标 |
| `select.zig` | — | ~240 | 选择/游标/框选 |
| `gallery.zig` | 289 | ~240 | 网格循环、空态、滚动指示、键盘 |
| `large.zig` | 405 | ~330 | 房间、顶部条、信息块、缩放 |
| `filmstrip.zig` | — | ~140 | 窗口式胶片条 |
| `menu.zig` | 167 | ~150 | kit.menu + 对话框 + 批量动作 |
| `i18n.zig` | 216 | ~380 | 见下（若超 600 就拆 `i18n_en.zig` / `i18n_zh.zig`） |
| `tests.zig` | 631 | ~250 | 拆分：`tests_shell.zig` / `tests_select.zig` / `tests_lightbox.zig` |
| `thumbs.zig` | 483 | ~500 | `Kind` 带档位、缓存键含档位、tags 进 `Measured`（P2） |

**不要动的**：`decode.zig`、`wic.zig`、`imageio.zig`、`exif.zig`、`xmp.zig`、
`scan.zig`、`ops.zig`、`masonry.zig`（除列数来源）、`win.zig`、`model.zig`。

## i18n 新增键（全部双语，格式串沿用 `{d}` / `{s}`）

| 键 | 中文 | English |
|---|---|---|
| `rail_library` | 资料库 | Library |
| `rail_no_subfolders` | 此文件夹没有子文件夹 | No subfolders here |
| `selected_of` | 已选 {d} / 共 {d} | {d} selected of {d} |
| `total_meta` | 共 {d} · {s} | {d} · {s} |
| `cursor_position` | 第 {d} 张 | #{d} |
| `hidden_by_filter` | 另有 {d} 张被筛选隐藏 | {d} more hidden by filters |
| `clear_filter` / `clear_search` | 清除筛选 / 清除搜索 | Clear filters / Clear search |
| `filter_min_stars` | ★≥{d} | ★≥{d} |
| `density` / `density_small` / `density_medium` / `density_large` | 网格密度 / 小 / 中 / 大 | Grid density / Small / Medium / Large |
| `sort_by` / `sort_ascending` / `sort_descending` | 排序 / 升序 / 降序 | Sort by / Ascending / Descending |
| `select_all` / `clear_selection` | 选择全部 / 清除选择 | Select all / Clear selection |
| `rescan` | 重新扫描 | Rescan |
| `appearance` / `appearance_auto` / `appearance_light` / `appearance_dark` | 外观 / 跟随系统 / 亮 / 暗 | Appearance / System / Light / Dark |
| `reduce_motion` | 减少动效 | Reduce motion |
| `dim_unselected` | 挑拣时压暗未选中 | Dim unselected while culling |
| `rail_reset` | 复位宽度 | Reset width |
| `reveal_in_files` | 在文件夹中显示 | Reveal in File Manager |
| `open_with_system` | 用系统打开 | Open with system app |
| `copy_file` | 复制文件 | Copy file |
| `trash_selection` | 移到回收站 | Move to Recycle Bin |
| `trash_confirm_title` | 删除 {d} 张图片？ | Delete {d} pictures? |
| `trash_confirm_body` | 首张 {s} · 末张 {s}。可在系统回收站中恢复。 | First {s} · last {s}. They can be restored from the system bin. |
| `trashed` / `pasted` / `copied` | 已移到回收站 / 已粘贴 {d} 个文件 / 已复制到剪贴板 | Moved to Recycle Bin / Pasted {d} files / Copied to clipboard |
| `rename_taken` | 这个名字已经存在 | That name is taken |
| `rate_failed` | 评分未写入文件 | Rating wasn't written to the file |
| `measuring_progress` | 正在测量 {d}% | Measuring {d}% |
| `decode_failed` | 无法读取 | Can't read |
| `folder_unreadable` / `choose_other_folder` | 无法打开这个文件夹 / 打开其他目录 | Can't open this folder / Open another folder |
| `formats_hint` | 支持 JPG、PNG、HEIC、WebP、AVIF 等 | Supports JPG, PNG, HEIC, WebP, AVIF … |
| `info` / `actual_size` | 信息 / 100% | Info / 100% |
| `prev_picture` / `next_picture` | 上一张 / 下一张 | Previous / Next |
| `watching_paused` | 监视已暂停 · F5 重新扫描 | Watching paused · F5 to rescan |
| `filter_empty` | 没有 ★≥{d} 的图片 | No pictures rated ★≥{d} |

现有可能要改口径的两条：`reveal`（「在资源管理器中显示」是 Windows 专属说法，
Windows 上是 Explorer、macOS 上是 Finder —— 改成中性的「在文件夹中显示」）、
`keys_hint`（大图的键位提示，P1 后由键盘一览承担，可删）。

## config 新增键（`config.zig` 的 `key = value`）

```
appearance = auto | light | dark      # 默认 auto
density = small | medium | large      # 默认 medium
reduce_motion = 0|1                   # 默认 0
dim_unselected = 0|1                  # 默认 1
rail_w = 240                          # 200–360
rail_open = 1
```
`config.zig` 现有的往返测试扩展这几行即可（读回一致、越界钳制）。

## 测试计划（行为 → 断言）

框架给的工具就够：`t.click` / `t.doubleClick` / `t.drag` / `t.scroll` / `t.key` /
`t.shortcut` / `t.typeText` / `t.resize` / `t.findText`（带 rect）/ `t.hasText` /
`t.screenshot`。**凡是能画错、裁掉、盖住的，断言 rect 或留快照**（AGENTS.md 的要求），
`hasText` 只用于「存在性」。

| # | 行为 | 测试写法 |
|---|---|---|
| T1 | 窄窗口不吞标题 | `t.resize(700, 760)` → `findText("album").?.w >= 80` |
| T2 | 计数在窄窗口迁到状态条 | `hasText("共 12")`（命令栏里已不存在） |
| T3 | 排序菜单生效 | 点排序钮 → `hasText("降序")` → 点「日期」→ 首图矩形或 `s.shown[0]` 变 |
| T4 | 密度三档 | 点密度 → 点「大」→ `s.layout.placements[0].h > 400` |
| T5 | 单击选中 | 点 `s.test_tiles[1]` 中心 → `hasText("已选 1 / 共 12")` |
| T6 | ⌘ 加选 | ⌘ 点第 3 块 → 「已选 2 / 共 12」 |
| T7 | ⇧ 连选 | 点第 1 块，⇧ 点第 4 块 → 「已选 4 / 共 12」 |
| T8 | 全选 / 清除 | `t.shortcut(.{.key='a',.ctrl=true})` → 「已选 12 / 共 12」；`t.key(.escape)` → 「共 12」 |
| T9 | 框选 | `t.drag` 覆盖前两行 → 选中数 = 落进框里的图块数 |
| T10 | 键盘游标 | `t.key(.down)` → 状态条「第 2 张」；`t.key(.right)` → 换列（矩形 x 变大） |
| T11 | 键盘评分 | 选 2 张 → `t.typeText("4")` → 两文件字节里出现 rating（照 `tests_meta.zig` 的做法） |
| T12 | 单张删除 | 选 1 → `⌘⌫` → 文件不在 + `hasText("已移到回收站")` |
| T13 | 多张删除要确认 | 选 2 → `⌘⌫` → `hasText("删除 2 张图片？")`；点取消 → 文件还在 |
| T14 | 失败态与等待态可分 | 坏文件 → `hasText("无法读取")`；正常未解码文件 → 无此文字且矩形一致 |
| T15 | 大图序号与文件名 | 双击 → `hasText("1 / 12")` 与文件名 |
| T16 | 胶片条跳转 | 点 `s.test_filmstrip[4]` → `hasText("5 / 12")` |
| T17 | Esc 回到原图块 | 大图 Esc → 状态条「第 3 张」仍是原来那张 |
| T18 | 信息块展开/收起 | `t.typeText("i")` → `hasText("ISO")`；再按 → 消失 |
| T19 | 缩放控件 | `t.typeText("z")` → `hasText("100%")` |
| T20 | 密度 toast | 菜单切档 → `hasText("网格密度：中")` |
| T21 | 设置面板有遮罩 | 打开设置 → 遮罩 leaf 矩形 = 窗口尺寸（读 `s.test_scrim` 或截图） |
| T22 | 设置改主题 | 点「暗」→ `s.dark == true` + 截图两张（亮/暗） |
| T23 | 对比度 | 纯单元测试：`theme.zig` 内按 WCAG 公式断言 03 §1 的每一对 |
| T24 | 图标名存在 | 纯单元测试：视图用到的图标名 ∈ 允许清单；允许清单与图集人工核对（见下「依赖」） |
| T25 | config 新键往返 | 扩展 `config.zig` 现有往返测试 |
| T26 | 目录不可读 | 指向一个无权限/不存在的目录 → `hasText("无法打开这个文件夹")` |
| T27 | 空目录 / 无匹配 | 各一张快照 + 出口按钮可点（`clickText("清除搜索")` 后恢复） |

## 快照计划（`nui snapshot` 产出，人眼核对）

放 `docs/redesign/shots/`，1280×800 与 760×800 两种宽度，中英各一套关键屏：

```
grid-light.png        网格 · 亮房 · 有选择（3 张，含游标与 ⋯ chip）
grid-dark.png         网格 · 暗房 · 无选择
grid-narrow.png       760 宽：面包屑仍在、计数已迁到状态条
lightbox.png          大图：顶部条 + 胶片条 + 信息块收起
lightbox-zoom.png     大图放大 240% + 信息块展开
settings.png          设置 sheet（背景已压暗）
empty.png             空目录空态      no-match.png  无匹配空态
failed.png            一个失败图块 vs 一个等待图块（必须可分）
rail-collapsed.png    导航栏折叠
```

现状 `docs/*.png`（app-dark / app-light / settings-open / …）在 P0 落地后**重拍**，
因为它们记录的是旧设计；旧图不删，移到 `docs/redesign/before/` 作为对照。

## 风险与缓解

| 风险 | 缓解 |
|---|---|
| 图块角标让每帧实例数上升（一墙几十块 × 5 个角标） | 角标只在需要时构建（现状的纪律），保留 `s.built` 计数断言，P0 后用 `nui snapshot` 对比帧时 |
| 密度分档导致缓存分裂（`budget = 192 MB`） | 只三档；缓存键含档位；切档只解码可见区（现有 prefetch 逻辑不变） |
| 测量完成后重排「跳一下」 | 布局锁定前画 1:1 骨架而**不画真照片**，锁定后整块 120ms 淡入（03 §8 已定） |
| 拆 `app.zig` 时把状态所有权弄乱 | 只搬视图函数与它们的只读参数；`State` 字段与生命周期完全不动 |
| `i18n.zig` 膨胀越 600 行 | 超了就按语言拆两个文件，`strings(lang)` 仍是唯一入口 |
| kit 组件（菜单/对话框/sheet/toast）与自绘部分风格不一致 | kit 只负责浮层（它本来就带层与动效），网格、rail、状态条自绘；色板统一走 `theme.zig`，kit 读的是同一份 `Theme` |
| 测试钩子与视图耦合 | 钩子一律是「每帧写出的矩形」，只读、不参与布局决策 |
| 选择集合按路径键，重命名/重扫后失配 | `select.rename(old,new)` 与重扫后按路径存活重建，单元测试覆盖（1.1） |

## 依赖（需要 nanoui 侧配合的，先记在 ROADMAP）

1. `ui.icons` 未导出 → 图标守卫测试只能先用「允许清单常量」；给 nanoui 加一行
   `pub const icons = @import("icons.zig");` 后测试可直接比对图集。
2. `Window.setFullscreen`（缺口 #3）、`Style.scroll_x`（缺口 #2）、`Input` 的按键位（缺口 #1）、
   拖放 API（缺口 #7）、系统减弱动效（缺口 #6）、a11y 桥（缺口 #4）。

## 验收定义（每一期的 DoD）

- [ ] `zig build test` 全绿（含 T23/T24/T25 三条纯单元测试）。
- [ ] `wc -l src/*.zig` 全部 ≤ 600。
- [ ] 03 §1 表格里的每一对色值都有测试盯着（T23）。
- [ ] 02 §5 键盘地图的每一行，人工按一遍都能对得上；写成一张 checklist 附在 PR 里。
- [ ] 快照清单里每一张都拍出来并人工核对过：悬停、游标、选中三者同屏可辨。
- [ ] 六种状态（空 / 无匹配 / 测量中 / 解码失败 / 目录不可读 / 选择被隐藏）各有一张快照。
- [ ] 每一个新行为在 `tests_*.zig` 里有一条测试，且**断言坐标或留快照**，不是只看 `hasText`。
- [ ] `docs/design.md` 里被本方案取代的段落已同步删除或改写（不留两份事实）。

## 需要你确认的三件事

1. **中性无色方向**（D1/D2）：chrome 完全不上色、选中用反相环。若想保留品牌色，
   改 `03-visual.md` §1 的 `accent` 一行即可，结构不用动。
2. **密度三档**（D3/D5）：受缩略图尺寸分级约束；想要五档或连续滑块需要先改缓存键策略。
3. **不做右键菜单**（D7）：这是 nanoui 当前的硬边界；若必须有，先做缺口 #1 的框架改动，
   再回来加一节 `04-components.md` 的「上下文菜单」。
