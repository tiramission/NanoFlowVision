# NanoFlowVision 设计系统

界面的设计语言**仿照 nanomon**（justrach/nanomon，nanoui 同作者的参考应用，MIT）：
Harness 的 Codegraff 色板——**暖炭或奶油底、琥珀选中、暖白文字**，文字用 Geist、
数字用 JetBrains Mono（未安装则回退系统字体）。本文档是界面视觉的事实来源；
代码里的事实是 `src/theme.zig`（色板从 nanomon 移植）。

## 设计原则

1. **暖底，不是冷灰。** 暗色是暖炭 `#16140f`（带一点黄褐），亮色是奶油 `#faf8f3`——
   照片在暖底上比在冷灰上更接近纸上观感。
2. **侧栏与内容分层。** 侧栏比页面亮/深半步（`sidebar`），内容区即页面色（`page`）；
   卡片再进一步（`card`）。
3. **琥珀选中。** 选中行是一整条琥珀药丸，选中态文字用页面色（深字在琥珀上）；
   图标 chip 用强调色 16% 底 + 强调色图标。
4. **数字用等宽。** 计数、尺寸、速率一律 `mono`（JetBrains Mono），像终端一样对齐。
5. **页头即工具栏。** 52px：左侧大标题 + 路径副标题，右侧搜索与排序；
   内容区 `px(20) pb(20)`，卡片 `p(16) rounded(10) border`。
6. **状态在侧栏底部。** 绿点 + "Watching"——目录监听活着。

## 色彩

`src/theme.zig` 的 `Colors` 结构（暗/亮各一套，从 nanomon 移植）：

| 令牌 | 暗色 | 亮色 |
|---|---|---|
| `page` | `#16140f` | `#faf8f3` |
| `sidebar` | `#1b1914` | `#f3efe6` |
| `card` | `#1f1c16` | `#f0ece3` |
| `text` | `#edeae2` | `#1a1813` |
| `secondary` | `#9a9384` | `#6b6557` |
| `tertiary` | `#5c564b` | `#a8a090` |
| `picked`（琥珀） | `#e8a33d` | `#c77d20` |
| `on_picked` | `#16140f` | `#fffdf8` |
| `border` | page ⊕ 白 9% | page ⊕ 黑 9% |
| `well` | `#191712` | `#e9e3d6` |

nanoui Theme 槽位的映射照 nanomon 的 `ui()`：`background=page`、`surface=control_on`、
`surface_hover=control`、`accent=amber`、`accent_text=on_picked`、`track=control`。

## 布局令牌

| 令牌 | 值 |
|---|---|
| 侧栏宽 | 214 |
| 页头高 | 52 |
| 侧栏行高 / 圆角 | 30 / 7 |
| 图标 chip | 20，圆角 6，强调色 16% 底 |
| 内容区边距 | px(20) pb(20) |
| 缩略图间隙 / 网格边距 | 8 / 20 |
| 卡片 | p(16) rounded(10) border |
| 字号 | 侧栏名 13 bold · 页标题 15 bold · 副标题 11 · 正文 13 · 尾数 11 mono |

## 图标语言

图标统一走 nanoui 的线稿图集（`ui.icon`，Lucide 风格、SF Symbols 命名、24 网格圆头
笔画），**名字必须先对过图集**——不存在的名字静默画空。尺寸 10–14；侧栏/菜单用
secondary 或 accent，chip 底为强调色 16%。两处例外：照片的 ⋯ 角标是黑 55% 白字
（任何照片上都读得清），大图的星级是内容本身（★☆ 文本）。

## 组件规格

- **侧栏**：品牌行（22 琥珀圆角角标内嵌 photo 图标 + 名称 13 bold）→ 分组标签（11
  semibold tertiary）→ 文件夹行（折叠 chevron 10 tertiary + 图标 chip + 名字 + 等宽
  计数；chevron 自占 16 宽的可点区，点击只折叠不打开）→ 打开目录行（folder chip）→
  Subfolders 复选框 → 状态行（绿点 + Watching）→ 设置行（slider.horizontal.3 chip）。
- **页头**：`↑ 上级`（图标 + 文字）+ 标题/路径列（吃剩余空间并裁剪）+ 搜索框
  （well 底 + 边框 + 放大镜 + bare 输入域，基准 189 最宽 206）+ 排序分段 + 方向
  （chevron.up/down 图标钮）+ 计数（66 定宽裁剪盒）。
- **大图面板**：黑 45% scrim、圆角 10、白系文字——照片可明可暗，面板自己负责可读性。
  右下角一枚同款纱底的缩放 chip **常驻**：适应窗口时明说，缩放后显示百分比；锚定窗口
  不随图走（与照片框分开绘制）。
- **照片角标**：右上 ⋯ 黑 55% chip，悬停出现，绘制在像素之后（像素会盖住先画的）。
- **空状态**：34 的 photo 图标 + 居中 secondary 文案；量尺寸中/加载中是
  circle.dotted + 文字。
