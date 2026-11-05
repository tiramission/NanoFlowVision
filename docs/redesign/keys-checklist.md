# 键盘地图 checklist（02-ux.md §5 的验收对照）

每行一条，`✅` = 已实现且有测试盯着；`⚠️` = 已实现、靠人工按一遍核对
（快照/手动验证，无自动化断言）；`🚧` = 留待后续（依赖框架缺口）。
应用内的同一张表：`Ctrl+/`（`src/i18n.zig` 的 `keys_map`）。

## 全局

| 键 | 动作 | 状态 | 证据 |
|---|---|---|---|
| `⌘O` | 打开目录（原生对话框） | ✅ | `shell.askForFolder`；对话框在帧外打开（AGENTS.md 规则） |
| `⌘,` | 设置面板 | ✅ | `app.view` 绑定 `⌘,` → `settings_open` |
| `⌘B` | 显示 / 隐藏导航栏 | ✅ | `app.zig` `rail_visible`；`rail-collapsed.png` |
| `⌘F` | 聚焦搜索框 | ✅ | `app.view` 置 `focus_search`；`shell` 在框前 `c.focus = c.peekId(null)`；`tests_shell` 搜索测试 |
| `⌘/` | 键盘一览 | ✅ | `app.view` 绑定 `⌘/` → `keys_open`；设置面板页脚另有入口 |
| `⌘D` | 外观循环 | ✅ | `toggleDark`；`tests_shell` 设置面板测试 |
| `⌘↑` | 上级目录 | ✅ | `app.view` 绑定 `⌘↑` → `shell.goUp` |
| `F5` | 重新扫描当前目录 | ✅ | `app.view` 绑定 `F5` → `relist_pending` |
| `Esc` | 逐层关闭：输入框 → 浮层 → 大图 → 选择 | ✅ | `app.view` 的分层守卫 + kit 覆盖层各自处理；`tests_select` |

## 网格

| 键 | 动作 | 状态 | 证据 |
|---|---|---|---|
| `←` `→` | 相邻列里垂直中心最近的一张 | ✅ | `neighborOf`；`tests_select` 键盘行走 |
| `↑` `↓` | 同列上一张 / 下一张 | ✅ | 同上 |
| `Home` `End` | 第一张 / 最后一张 | ✅ | `jumpCursor`；`tests_select` |
| `PageUp` `PageDown` | 上 / 下一屏（保持列位置） | ✅ | `pageCursor` |
| `Space` `Enter` | 打开游标那张的大图 | ✅ | `gridKeys` `.enter`；Space 走字符路径 |
| `0`–`5` | 给选择（或游标）打分 | ✅ | `large.rateBatch`；`tests_select` 评分写文件 |
| `⌫` / `Delete` | 移入回收站（多张先确认） | ✅ | `dialogs.askTrash` + 确认对话框；`tests_select` |
| `F2` | 重命名（单张） | ✅ | 重命名对话框；`tests_select` |
| `⌘C` | 复制文件到剪贴板 | ✅ | `ops.copyFilesToClipboard`（CF_HDROP 多文件） |
| `⌘⇧R` | 在文件夹中显示 | ✅ | `ops.reveal` |
| `⌘↩` | 用系统默认程序打开 | ✅ | `ops.open` |
| `T` | 打开大图并进入标签输入 | ✅ | `gridKeys` 字符路径 + `large.view` 标签字段 |
| `⌘V` | 粘贴到当前文件夹 | ✅ | `menu.paste`；`tests_meta` |
| `⌘A` | 全选 | ✅ | `select.all`；`tests_select` |
| `Tab` | 树 ⇄ 网格焦点 | ✅ | `shell.treeKeys`；`tests_view` 树键盘 |

## 大图

| 键 | 动作 | 状态 | 证据 |
|---|---|---|---|
| `←` `→` | 上一张 / 下一张 | ✅ | `neighbor`；`tests.zig` 大图测试 |
| `Space` `Esc` | 关闭，回到原来那张 | ✅ | `close` + 游标跟随（`show` 记 cursor）；`tests_view` |
| `0`–`5` | 打分 | ✅ | `rate` → `xmp.rewriteFile`；`tests_meta` |
| `T` | 标签输入 | ✅ | `tag_editing`；`tests_meta` |
| `Z` | 适应 ⇄ 1:1 | ✅ | `toggleZoom`；`tests_view` 缩放测试 |
| `I` | 信息块展开 / 收起 | ✅ | `info_open`；`tests_view` |
| `⌫` | 移入回收站并前进 | ✅ | `large.view` delete 路径 |
| 滚轮 / 拖动 | 缩放（锚定指针）/ 平移 | ✅ | `large.view` wheel/panning；`tests.zig` |
| 滚轮（条上） | 胶片条逐张 | ✅ | wheel 让位胶片条；`tests_view` 胶片条跳转 |

## 导航栏（树有焦点时）

| 键 | 动作 | 状态 | 证据 |
|---|---|---|---|
| `↑` `↓` | 移动高亮行（可见行） | ✅ | `visibleFolders` + `treeKeys`；`tests_view` |
| `→` | 展开；已展开则进入第一个子项 | ✅ | `treeKeys` `.right`；`tests_view` |
| `←` | 折叠；已折叠则回到父项 | ✅ | `treeKeys` `.left` |
| `Enter` | 打开高亮的文件夹 | ✅ | `treeKeys` `.enter`；`tests_view` |
| `Tab` | 把焦点交给网格 | ✅ | 同上 |

## 未绑定项的归宿

已无未绑定的组合键。`⌘F` 在 2026-11 的打磨里接上了：`c.focus` 接一个稳定的搜索框 id
（`c.next_key = "search"` + `c.peekId`）就够，不需要新 API（见 06-polish.md）。

## 导航栏的指针动作

| 手势 | 动作 | 状态 | 证据 |
|---|---|---|---|
| 拖右缘 4pt | 改宽 200–360（松手写 config） | ✅ | `rail.zig` 的 handle；`tests_shell` 拖宽/复位 |
| 双击右缘 | 复位 240 | ✅ | 同上 |
| 单击 chevron | 只折叠 / 展开，不打开 | ✅ | `folderRow`；`tests_view` |
| 单击根行 | 回到根目录 | ✅ | `folderRow(s, &s.tree)` |
