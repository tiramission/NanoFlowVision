# 04 · 组件规格

每个组件给四样东西：**结构**（盒子怎么套）、**尺寸**（数字来自 03）、**状态**（每个状态
画什么）、**映射**（用哪些 nanoui API、落在哪个文件）。层号按 03 §5；图中 `⎯` 表示
1px `line` 描边。

---

## 1. 应用外壳 Shell

**结构**（一个 `ui.row`，高满）：

```
row (w=fill, h=fill)
├── Rail          宽 s.rail_w（折叠时 0，不构建）
└── column (grow)
    ├── CommandBar   高 44
    ├── ProgressLine 高 2（只在测量中）
    ├── Grid         高 fill（唯一滚动容器）
    └── StatusBar    高 28
```

**断点规则**（窗口宽，按可用宽度而不是窗口宽判断更稳，这里用窗口宽）：

| 宽度 | 变化 |
|---|---|
| ≥ 1180 | 全量命令栏：面包屑 · 计数 · 搜索(240) · 星级筛选 · 排序 · 密度 · 导航栏 · ⋯ |
| 960–1180 | 计数移到状态条；搜索收窄到 180 |
| 760–960 | 星级筛选折叠进 ⋯；排序按钮只留图标（文字进 tooltip） |
| < 820 | 导航栏自动折叠（用户手动展开后不再自动收） |
| < 760 | 命令栏 = [☰] [面包屑末段] [🔍] [⋯]；搜索点开为全宽 popover |

**硬规则**：面包屑有 `min_width = 120`，任何断点下都不得为 0 —— 这是对现状 P1 的修复。
计数与搜索在放不下时**先折叠自己**，不是挤掉面包屑。

**映射**：`src/shell.zig`（新），`src/app.zig` 只保留 `State.view` 的编排与浮层。
折叠状态在 `State.rail_open` / `State.rail_w`。

---

## 2. 导航栏 Rail

```
column (w=rail_w, bg=rail, px=10, gap=2)  ⎯→ 右侧 1px line 分隔 + 4pt 拖动热区
├── 品牌行   h=52, px=6, gap=8：22×22 圆角 5 的 photo 图标（ink 底、page 字）+ 名称 13 bold
├── 分组标签 「资料库」11 semibold ink3, px=8, pt=14, pb=4
├── 树（滚动，grow）
│   └── 行 h=30, 圆角 6, 缩进 7+depth*12
│       ├── chevron 热区 16×24（有子项才画）
│       ├── folder 图标 chip 20×20（圆角 5，accent 16% 底）
│       ├── 名称 13（选中 semibold / 否则 regular）
│       ├── spacer
│       └── 计数 11 mono ink2（>0 才画）
├── 空态行（无子文件夹时）「此文件夹没有子文件夹」12 ink3, px=8, py=6
└── 底部行 h=30：⚙ 设置 13 + 右侧 ⌘, 提示 11 ink3（mono）
```

**状态矩阵**

| 状态 | 画法 |
|---|---|
| 默认 | 透明底 |
| 悬停 | `hover` 提亮，圆角 6 |
| 当前文件夹 | `accent` 底 + `on_accent` 字（反相整行，不是色块） |
| 焦点（树有键盘焦点） | 当前行加 1px `ink3` 内描边（与网格游标同一语言） |
| 折叠 | chevron = `chevron.right`，子行不构建 |
| 展开 | chevron = `chevron.down` |
| 有子项但未读 | 计数留空，chevron 照画（现状的「一层预读」保留） |

**交互**：单击行 → 打开；单击 chevron → 只折叠（现状保留，两个热区不重叠：chevron 16 宽、
行整体另一个热区）；拖右缘 4pt 热区 → 200–360 改宽（`c.cursor = .resize_left_right`），
双击热区复位 240；⌘B 折叠。

**映射**：`src/shell.zig` `viewRail`；折叠标志 `s.rail_open`，宽度 `s.rail_w`（写进 config）。
拖动用 `c.input.pressed` + 鼠标 x，无需新 API。

---

## 3. 命令栏 CommandBar

```
row (h=44, px=16, gap=6, items=center)  ⎯ 底边 1px line
├── [☰] sidebar.left 图标钮 28×28（只在 rail 折叠时出现）
├── 面包屑 grow, min_w=120, clip
│   根 ▸ 2024 ▸ 杭州          15 bold（末段）/ 13 ink2（祖先，可点）
├── 含子文件夹 chip（只在 recursive 打开时）22 高：folder 11 + 文字 12 + xmark 11
├── spacer
├── 计数 12 mono ink2，自适应宽（min 44, max 160）— <1180 时移到状态条
├── 搜索框 30 高, 180–240 宽, rounded 8, bg=control, ⎯line
│   ├── magnifyingglass 12 ink3
│   ├── 输入域（bare）13, placeholder「搜索文件名…」
│   └── xmark 12 热区（有输入时）
├── ★≥N 筛选 chip 22 高（star.fill 11 grade + 文字 12 ink2）
├── 排序钮 28×28：chevron.up.chevron.down 14
├── 密度钮 28×28：square.grid.2x2 14
└── ⋯ 钮 28×28：ellipsis.circle 14
```

**按钮的三种画法**：图标钮 = 28×28、圆角 6、悬停 `hover` 底、`kit.tooltip` 说明；
chip = 22 高、`control` 底、圆角 5；有筛选生效时 chip 用 `accent` 底 + `on_accent` 字。

**汉堡位的折叠**：`rail_open == false` 时 `[☰]` 一定在，否则不画（省下的宽度给面包屑）。

**三个菜单**（都用 `kit.menu`，锚点 = 触发按钮的 `interaction.rect`）：

| 菜单 | 项（含 ✓、快捷键文案） |
|---|---|
| 排序 | 名称 / 日期 / 大小 / 像素 / 星级（`checked` 标当前键）+ 分隔线 + 「升序 ✓ / 降序」 |
| 密度 | 小 / 中 / 大（`checked`） |
| ⋯ | 选择全部 ⌘A · 清除选择 Esc · 分隔线 · 含子文件夹（`checked`）· 重新扫描 F5 · 分隔线 · 设置 ⌘, |

**映射**：`src/shell.zig` `viewCommandBar`；排序/密度状态在 `State.sort` /
`State.sort_ascending` / `State.density`；`kit.menu(c, "sort", &s.sort_menu_open, rect, items, .{})`
返回选中下标，与现状的 `s.orderChanged()` 接上。

---

## 4. 状态条 StatusBar

```
row (h=28, px=16, gap=10, items=center)  ⎯ 顶边 1px line, bg=page
├── 左：已选 3 / 共 128 · 24.6 MB        13/12 mono ink2
│       无选择时：「共 128 · 84.2 MB」
│       有游标时追加：「第 3 张」mono
├── 中（有筛选时）：另有 3 张被筛选隐藏 [清除筛选]
└── 右：● 正在监视 · 12:04                12 ink2（点 = ok 色 8pt 圆点；暂停时 danger）
```

进度线（测量中）：命令栏下方 2pt 高、`accent` 色、宽度 = 已测量/总数，
与状态条左端文字「正在测量 42%」同时出现。画完 `c.animationFrame()` 让帧继续。

**映射**：`src/statusbar.zig`（新）；测量进度现有 `s.shared.measuredCount()` 直接用。

---

## 5. 网格 Grid 与滚动指示

**结构**：`c.open({ .direction = .column, .scroll = true, .clip = true })`（现状保留），
内容高度 = `s.layout.height`，再在其上：

1. **滚动指示**：绝对定位在内容区右缘 4pt 处，宽 3pt、圆角 1.5，颜色 `ink3` 40%；
   长度 = `可用高 * (可用高 / 内容高)`（最小 24），位置按 `offset / (内容高 - 可用高)` 换算。
   滚动时出现（`c.scrollMoved(id)` 或 offset 变化），静止 1.2s 后淡出。
2. **框选层**：绝对定位 1pt `ink3` 边 + `ink` 6% 填充的矩形，画在内容区最上层，
   但**在浮层之下**（层 0 即可）。
3. **⋮ 悬停位置**：图块角标（见 §6）。

**映射**：`src/gallery.zig`（网格循环保留，加入 §1/§2 两个自绘）+ 新的
`src/select.zig`（选择/游标/框选状态机）。

---

## 6. 图块 Tile

```
div (absolute, offset=place, w, h, 圆角 4, clip)
├── 照片（ui.texture, fill×fill） 或 well 骨架
├── 失败态：well + exclamationmark.triangle 14 + 「无法读取」12 ink2（居中）
├── 星级（有评分时）左下 6,6：★×5，12 grade，黑 45% 纱底圆角 4，padding 4×2
├── 文件名条（悬停/游标/选中时）底部 0：26 高，黑 45% 纱底，13 ink（白）
│    文件名（clip）+ 尺寸 11 mono（白 70%）
├── ⋯ chip（悬停/游标/选中时）右上 6,6：24×24 圆角 5，黑 55% 底，⋯ 13 白
└── 勾章（选中时）左上 6,6：20×20 圆角 5，accent 底 + checkmark 12 on_accent
```

**状态矩阵**（可叠加，任意两者叠在同一块上都要可辨）

| 状态 | 视觉 |
|---|---|
| 默认 | 圆角 4 的照片 |
| 悬停 | 1px `line2` 外描边 + 提亮 4% |
| 游标 | 1px `ink3` **内**描边 |
| 选中 | 2px `accent` **外**环（外扩 2pt，圆角 6）+ 勾章 |
| 选中（多选时其他块） | 整块 `opacity 0.55`（设置可关） |
| 等待解码 | `well` 底（不呼吸；一墙同时呼吸会闪） |
| 解码失败 | 见上「失败态」，与等待必须可分 |
| 已评分 | 左下星级 |
| 菜单开着 | ⋯ chip 保持可见 |

**点击语义**（对应 02 §4）：单击 = 选择 + 游标；⌘ = 加选；⇧ = 连选；
双击 = 大图；点 ⋯ = 打开菜单（锚点 = chip 的 rect，`kit.menu` 自己负责贴边翻转）。

**映射**：`src/tile.zig`（新，从 `gallery.zig` 拆出 `viewPicture` 的全部角标）；
`first_picture` 的测试钩子保留，并新增 `s.test_tiles: []ui.Rect`（每帧写出可见图块矩形），
让测试能点到「第 3 张」而不是碰运气。

---

## 7. ⋯ 菜单与上下文动作

`kit.menu` 的一次调用，`MenuItem` 列表：

| 项 | icon | shortcut 文案 | danger |
|---|---|---|---|
| 打开大图 | `photo` | Space | |
| 用系统打开 | `arrow.right.square` | ⌘↩ | |
| 在文件夹中显示 | `folder` | ⌘⇧R | |
| 复制文件 | `doc.on.doc` | ⌘C | |
| 重命名… | `pencil` | F2 | |
| —— 分隔线 —— | | | |
| 移到回收站 | `trash` | ⌘⌫ | ✔ |

**规则**：多选时菜单只留「复制文件 / 移到回收站」两项（其余是单张动作），
标题行显示「已选 12 张」。禁用项（多选下的 F2）用 `disabled = true`，
不要静默去掉 —— 让人知道它存在但此刻不行。

**映射**：`src/menu.zig` 重写为对 `kit.menu` 的一次调用；动作仍在 `ops.zig`。

---

## 8. 大图 Lightbox

层号 **5**（低于 kit 的 10/11/20/30/40，否则确认框会被照片盖住）。

```
div (fixed, sizeFull, bg=page)          ← 房间随主题：暗房 #0E0F11 / 亮房 #F7F7F4
├── 照片框（absolute 居中 + 平移，w/h = 图片像素 × zoom，亮房 1px line2 + shadowMd）
├── 顶部条 h=40（指针动时出现）
│   左：3 / 12（12 mono ink2）+ 文件名（13 ink）
│   右：★★★★★（可点的星行，16，未评 = ink3、已评 = grade）+ info.circle 28×28 + xmark 28×28
├── 胶片条 h=76（与顶部条同生共死）
│   窗口式：当前居中，左右各 7 张；缩略 48 高（宽度 = 48×aspect，44–96）
│   当前项：2px accent 环 + 不透明；其他：opacity 0.7；不足 15 张则只画有的
│   悬停某张 → 该张 1px line2；点击 → 跳转；滚轮停在胶片条上 → 上一张/下一张
├── 信息块（左下；胶片条可见时让位到 76+12，否则 16）
│   收起：一行 = 文件名 · 尺寸 · 大小（13 ink）
│   展开（I）：+ 相机/镜头行（13）· EXIF 行（12 mono ink2）· 星级 · 标签 chips + 添加
│   底：panel + 1px line + 阴影 —— 唯一不透明卡片，因为它可能压住照片任意部分
└── 缩放控件（右下 16,16）
    32 高圆角 8：arrow.up.left.and.arrow.down.right 12 + 文字（「适应窗口」/「100%」/「240%」）
    点击在「适应窗口 ⇄ 100%」之间切换；Z 同效；百分比用 mono
```

**状态**：加载中 → 房间保持上一张（不清空）+ 右下角 `circle.dotted` + 「加载中…」，
避免「黑屏一闪」；失败 → 居中 `exclamationmark.triangle` + 「无法读取」+ 路径（12 mono）；
到达新图 → 120ms 淡入（`motion.present`），照片本体不做缩放动画。

**映射**：`src/large.zig`（房间、照片框、缩放保留）+ `src/filmstrip.zig`（新）+ 顶部条与
信息块在 `large.zig` 内。胶片条需要 `s.shown` 与 `s.shared` 现状即可，不需要新的解码种类
（用 `.picture` 的 256 缩略图）。

---

## 9. 空态 / 无匹配 / 目录不可读

| 场景 | 结构 | 文案 |
|---|---|---|
| 空目录 | `kit.empty`（图标 `photo`，标题 + 说明）+ 「打开其他目录」主按钮 | 「这里没有图片」/「支持 JPG、PNG、HEIC、WebP、AVIF 等」 |
| 无匹配 | 图标 `magnifyingglass` + 「清除搜索」按钮 | 「没有匹配"杭州"的图片」 |
| 筛选后为空 | 同上 + 「清除筛选」 | 「没有 ★≥4 的图片」 |
| 目录不可读 | 内容区顶部 `kit.alert`（danger，可关）+ 面包屑保留 | 「无法打开这个文件夹」+ 路径 |
| 测量中 | 骨架墙（`well` 块按 1:1 铺）+ 状态条进度 + 标题栏百分比 | 「正在测量 42%」 |

空态整体居中于内容区**可用高度的 45%**（不是正中：视觉上正中偏低才像居中）。

**映射**：`kit.display.empty` / `kit.display.alert` / `kit.display.skeleton`；
`src/gallery.zig` 的空分支改写。

---

## 10. Toast（操作回声）

`State.toaster: kit.Toaster`，每帧最后 `s.toaster.view(c)`（层 40 由 kit 负责）。

| 事件 | status | 标题 | 说明 |
|---|---|---|---|
| 移到回收站 | neutral | 已移到回收站 | 单张显示文件名；多张「12 张图片」 |
| 粘贴完成 | neutral | 已粘贴 12 个文件 | 失败时 success/danger 分开报 |
| 复制文件 | neutral | 已复制到剪贴板 | |
| 重命名失败 | danger | 这个名字已经存在 | 输入框保留原值 |
| 评分写入失败 | danger | 评分未写入文件 | 图片保持原样 |
| 密度切换 | neutral | 网格密度：中 | 1.2s 短提示，避免占三次操作 |

**注意**：`Toaster.push` 会复制字符串（`std.mem.concat`），所以可以直接把帧内
`c.print` 的结果推进去，不用担心 arena 生命期。

---

## 11. 确认对话框

只用于「一次影响多个文件」。用 `kit.dialog`（自带压暗层与进出动效）：

```zig
if (kit.dialog(c, "trash", &s.trash_confirm, .{
    .title = tr.trash_confirm_title,     // 「删除 12 张图片？」
    .description = tr.trash_confirm_body, // 「首张 A.jpg · 末张 Z.jpg，可以在回收站恢复」
    .ok = tr.to_bin, .cancel = tr.cancel,
    .ok_variant = .danger,
})) |d| { if (d.end() == .ok) menu.trashSelection(s); }
```

**映射**：`src/menu.zig`（对话框）+ `State.trash_confirm`；`kit.dialog` 的层是
`kit.dialog.layer_backdrop = 10` / `layer_panel = 11`（框架定值，不要自造）。

---

## 12. 重命名框

`kit.dialog` 的一次调用，body 里一个 `ui.textField`（预填全名）+ 一行内联错误（12 danger）：

- 打开：`F2`（或菜单）；关闭：Esc / 取消 / 点遮罩。
- 回车提交；重名 → 对话框**不关**，错误行显示「这个名字已经存在」，输入保留。
- 成功 → 图块文件名、选择集合、缓存键、状态条同步（`shared.renameKey` + `select.rename`）。
- 扩展名保护（只选中主名）依赖 nanoui 文本框的初始选区 API，P2 做；
  P0 的做法是预填全名并把光标放末尾。

---

## 13. 设置面板（右侧 sheet）

`kit.sheet(c, "settings", &s.settings_open, .{ .side = .right, .size = 320, .title = tr.settings })`
—— 自带压暗层与滑入动效，天然修掉现状 P2（没有遮罩）。分组与控件：

| 分组 | 行 |
|---|---|
| 外观 | 跟随系统 / 亮 / 暗（`ui.segmented`，图标 + 文字）· 挑拣时压暗未选中（`ui.checkbox`）· 减少动效（`ui.checkbox`） |
| 语言 | English / 中文（`ui.segmented`，各写各的语言） |
| 浏览 | 包含子文件夹（`ui.checkbox`）· 网格密度（`ui.segmented` 三档） |
| 窗口 | 记住窗口位置（`ui.checkbox`）· 导航栏宽度「复位」按钮 |
| 页脚 | 版本号 + 「键盘一览」（P2） |

改动立即生效并立即写 config（现状保留：`saveSettings()`）。

---

## 14. 目录对话框（原生）

保持不变：`⌘O` / 空态按钮 → `State.openFolderDialog()` → `nanoui.App.after(0, …)` →
`nfd.openFolderDialog` → `queueReroot` → 下一帧 `reroot`。
**不许**在帧内直接开原生模态（AGENTS.md 的硬规则）。

---

## 15. 组件 ↔ 文件 ↔ 测试钩子

| 组件 | 文件 | 测试钩子 |
|---|---|---|
| Shell / Rail / CommandBar / StatusBar | `src/shell.zig`（新，拆分自 `app.zig`） | `s.test_rail_rows: []ui.Rect` |
| 网格 + 滚动指示 + 框选 | `src/gallery.zig` | 现状 `s.first_picture` + 新增 `s.test_tiles` |
| 图块与角标 | `src/tile.zig`（新） | `s.test_tiles` |
| 选择 / 游标 / 框选状态机 | `src/select.zig`（新） | `s.selected.count()`（测试可直接读） |
| 大图 + 顶部条 + 信息块 | `src/large.zig` | `s.test_filmstrip: []ui.Rect` |
| 胶片条 | `src/filmstrip.zig`（新） | 同上 |
| 菜单 / 重命名 / 确认框 | `src/menu.zig` | —— |
| toast | `src/app.zig`（`State.toaster`） | 断言 `t.hasText("已移到回收站")` |
| 设置 | `src/shell.zig` 或 `src/settings.zig`（新） | 现状测试保留 |
| 状态文案 | `src/i18n.zig` | 现有「两种语言都有全部字符串」测试扩展 |

所有测试钩子都是「每帧写出的矩形」，与现状 `s.first_picture` 同一手法：
测试点击真实坐标，而不是在文本里猜位置。
