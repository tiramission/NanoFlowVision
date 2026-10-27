# 01 · 现状诊断

诊断只看三样东西：**屏幕上的截图**（`docs/*.png`）、**视图代码**（`src/app.zig`、
`src/gallery.zig`、`src/large.zig`、`src/menu.zig`）、**可用的框架能力**
（nanoui 0.6.4 的 `src/ui/*` 与 `src/kit/*`）。每一条都给出证据与归属：
它由本方案的哪一部分解决。

## 一、布局与可见性

**P1 · 窄窗口下文件夹标题会被挤成 0 宽。**
`viewToolbar` 里标题列用 `.wFull().grow().clip()`，搜索框同时用 `.grow().maxW(206)`：
两者都在争剩余空间，而标题列没有最小宽度，于是可以被压到 0。
证据：`docs/settings-open.png` 的工具栏里根本没有文件夹名与路径，只有「上级 / 搜索 /
排序 / 方向 / 计数」。`docs/app-light.png`（更宽的窗口）里它们都在。
归属：`02-ux.md`「命令栏」、`04-components.md` 命令栏规格（面包屑最小宽度 + 断点折叠）。

**P2 · 设置面板没有压暗层。**
`viewSettings` 的遮罩只调用了 `.control()`。`.control()` 是「此盒子的文字不可被选择、
指针保持手形」的交互标记（`Style.control`），**不是背景色**，所以这层是全透明的：
面板浮在内容上没有背景变暗。
证据：`src/app.zig` `viewSettings`；`docs/settings-open.png`（内容亮度没有变化）。
归属：`04-components.md`「设置面板」（显式 `veil` 色 + 居中改为右侧 sheet）。

**P3 · 没有子文件夹时侧栏是一大片空白。**
根目录（截图里的 `tiramission`）没有子文件夹时，「文件夹」分组标签下面什么都没有，
而「包含子文件夹 / 打开目录 / 正在监视 / 设置」四行挤在底部，中间的 400 多像素是空的。
证据：`docs/app-light.png`、`docs/app-dark.png`。
归属：`04-components.md` 导航栏（空态行 + 监视状态迁到状态条）。

**P4 · 计数被固定宽度裁掉。**
计数被放进 `w(66).clip()`，中文「3 张图片」在更窄的窗口里显示成「1 张图」。
证据：`docs/settings-open.png` 右上角。
归属：`04-components.md` 命令栏（计数改为自适应 + 与面包屑同行右侧）。

## 二、交互能力

**P5 · 没有选择模型。**
全应用只有「一张图」的两种状态：`menu_for`（菜单对着谁）与 `large`（在看谁）。
没有选中集合、没有加选 / 连选 / 框选 / 全选，也就没有批量操作（批量评分、批量移入
回收站、批量复制）。讽刺的是框架早就准备了这件事：`Input.adding()` 的注释写着
「The key that adds to a selection with a click: Command on the Mac, Control elsewhere」。
证据：`src/app.zig` 的状态字段；`nanoui src/ui/input.zig`。
归属：`02-ux.md`「选择模型」、`04-components.md`「图块」「状态条」。

**P6 · 网格里没有键盘。**
方向键、0–5 评分、`t` 标签、Delete 全部只在大图里生效（`large.zig`）；网格没有游标、
没有焦点、不能用键盘移动、不能用键盘打开。想「用键盘快速挑 100 张」在这版里做不到。
证据：`src/gallery.zig`（无 `c.input` 处理，只有 Esc / ⌘V 两条）。
归属：`02-ux.md` 键盘地图、`04-components.md`「游标」。

**P7 · 没有滚动位置指示。**
nanoui 没有滚动条组件（`grep scrollbar src/ui` 只命中文本框内部的自绘一条），
应用也没有自己画。滚到第 300 张时，只能靠记忆判断自己在哪、还有多少。
证据：框架检索；`src/gallery.zig` 的滚动分支只有 `c.scroll.get(id)`。
归属：`04-components.md`「滚动指示」（自绘，右缘 3pt）。

**P8 · 操作没有回声。**
`ops.trash` / `ops.copyFileToClipboard` / `menu.paste` / `ops.renameFile` 都返回
成功与否，但没有任何一处把结果说给用户：移入回收站、粘贴 12 个文件、重名被拒 ——
全静默。框架其实带着清单外的答案：`kit.Toaster`。
证据：`src/menu.zig`、`src/ops.zig`（无 toast、无状态条更新）。
归属：`04-components.md`「Toast」。

**P9 · 排序的语义弱。**
排序是 5 段文字的分段控件（名称 / 日期 / 大小 / 像素 / 评分），方向只有一枚 10px 的
`chevron.up/down`：没人知道这枚箭头指的是「升序」还是「向上」。它同时是 P1 的元凶之一
（占宽最大）。
归属：`04-components.md`「排序」（改为图标按钮 + `kit.menu` 带 ✓ 与方向文案）。

**P10 · 密度不可调。**
列数硬编码 `max_columns = 6`，间隙 8。想要「一眼看 200 张」或「看清每张的脸」
都做不到，而这恰恰是照片浏览器的核心旋钮。
归属：`04-components.md`「密度控件」、`05-plan.md` P0。

## 三、大图（lightbox）

**P11 · 缺上下文与相邻导航。**
大图里没有文件名、没有「3 / 12」、没有左右按钮，也没有胶片条；`←/→` 是唯一的路。
信息块（`p(12)` 黑纱）在没有 EXIF 的图片上几乎消失（只剩星与标签），
位置固定在左上，会压到照片主体。
证据：`docs/app-rating.png`、`src/large.zig`。
归属：`04-components.md`「大图」四个部件（顶部条 / 胶片条 / 信息块 / 缩放控件）。

## 四、视觉与可读性

**P12 · tertiary 文字不达对比度。**
`tertiary #5c564b` 压 `page #16140f` 约 **2.6:1**（WCAG 计算值），而它正是分组标签
「文件夹」与所有 chevron 的颜色；正文用的 `secondary #9a9384` 约 6.2:1 尚可。
一个 2.6:1 的标签在暗房里等于没有。
证据：`src/theme.zig` 色值 + 对比度计算（见 `03-visual.md` 的方法）。
归属：`03-visual.md` 全部色板（三级文字重新定值并标注用途）。

**P13 · 失败与等待长得一模一样。**
`thumbs.Shared.setFailed` 存在，但视图把失败画成与「还没解码」相同的 `well` 底色：
用户看到的是「一直在等」，其实永远等不到。
证据：`src/gallery.zig` `viewPicture`；`src/thumbs.zig` `setFailed`。
归属：`02-ux.md` 状态表、`04-components.md`「图块 · 失败态」。

**P14 · 状态文字没有下一步动作。**
空目录与无匹配只有一枚 34px 图标加一句话，没有「打开其他目录」「清除搜索」这类出口。
归属：`04-components.md`「空态 / 无匹配」。

## 五、工程约束（会决定文件结构）

**P15 · 两个文件已经越过 600 行红线。**
`wc -l src/*.zig`：`app.zig` 686、`tests.zig` 631。本方案要往视图里加的东西
（选择、命令栏、状态条、胶片条）如果直接加进去会进一步越线，所以 P0 必须同时拆分。
证据：`wc -l`；AGENTS.md「No file is over 600 lines」。
归属：`05-plan.md`「文件映射」。

## 保留不动的东西（这一版做对的部分）

- **性能取向**：只构建视口内的图块、测量先行、布局解析可算、后台四线程解码 ——
  重新设计不碰这条路线，只在其上加表面。
- **XMP 写回**：星级与标签写进图片文件本身（`src/xmp.zig`），大图里的 0–5 与 `t`
  保留，并扩展到网格（对着选中项打分）。
- **双语**：`i18n.zig` 的双语表与 `c.print` 的用法保留，新增字符串照旧双语。
- **模态规则**：原生目录对话框只能在 `nanoui.App.after` 回调里打开 —— 保留；
  本方案新增的确认框与设置面板都是 nanoui 图层的浮层，不是原生模态，可以在帧内画。
- **线稿图标语言**：统一走 `ui.icon` 的图集，只使用图集里存在的名字（见 `03-visual.md`
  的图标表；不存在的名字在 Windows/Linux 上会静默画空）。
- **等宽数字**：计数、大小、序号、EXIF 数值继续用 mono，对齐是这类界面的安静功能。
