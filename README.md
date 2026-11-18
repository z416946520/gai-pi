<p align="center">
  <img src="icon.svg" width="112" alt="gai-pi logo">
</p>

<h1 align="center">gai-pi</h1>

<p align="center"><b>pi 的桌面端。</b></p>

 外壳是一个 Godot 4.6 场景（沿用 [gai](https://github.com/godot-fun/gai) 的视觉语言：
GPU 绘制的界面、shader 动效、随工具调用起伏的 60 个场景），大脑是官方 `pi --mode rpc` 子进程。

```
工具栏   gai-pi · 工作目录 ······ ctx 3.2k · 模型 · thinking · 视觉场景
┌──────────────┬─────────────────────────────────────────────────────┐
│ ＋ 新会话     │  > 你: 把这个模块的轮询改成事件驱动                    │
│              │  # Edit  src/poller.ts            -18 +42           │
│ 会话列表      │    [内联 diff，逐行着色]                              │
│ (来自 pi)     │  AI Agent: 改完了，测试通过……                          │
│              │─────────────────────────────────────────────────────│
│              │  [ 输入框                              ] 发送 / 停止  │
└──────────────┴─────────────────────────────────────────────────────┘
```

| 中文 | English |
| --- | --- |
| ![中文界面](docs/screenshot-edit.png) | ![English UI](docs/screenshot-en.png) |

## 为什么这么做

- **pi 负责大脑**：循环、工具、会话、压缩、模型、skills、扩展，全在 pi 里，
  桌面端不重复实现，也不和它抢真相。
- **gai 负责身体**：60 个 `VisualEffect` 场景原样复用（MIT）。gai 的事件总线本来就和 pi 的
  会话事件同形，所以效果文件零改动。
- **进程边界**：`pi --mode rpc` 是官方给自定义 UI 的通道，JSONL 进出。模型崩了不带崩窗口。

## 环境要求

- Windows 10/11（Linux/macOS 的启动脚本也已写好，未实测）
- **Node.js 20+**
- **pi 已安装**：`npm i -g @earendil-works/pi-coding-agent`，并已配置好 provider（`pi` 能直接跑）
- 仓库内自带 Godot：`.dependency/godot/Godot_v4.6.3-stable_win64_console.exe`

gai-pi 不安装、不修改 pi。它读 `PI_CODING_AGENT_DIR`（默认 `~/.pi/agent`）里的配置和会话，
用的是你现有的模型和凭据。

## 运行

```bash
# 双击 gai-pi.cmd，或：
.dependency/godot/Godot_v4.6.3-stable_win64_console.exe --path .

# 无窗口自检：启动 pi → 握手 → 发一句话 → 等结算
.dependency/godot/Godot_v4.6.3-stable_win64_console.exe --headless --path . --script test/bridge_smoke.gd

# 截图自检
GAI_PI_VISUAL=4 GAI_PI_SCREENSHOT=.verify/run.png GAI_PI_SCREENSHOT_DELAY=45000 \
  .dependency/godot/Godot_v4.6.3-stable_win64_console.exe --path .
```

首次打开会在右上角显示当前模型；点工作目录切换项目。工作目录会记住（`user://gai-pi.cfg`）。

## 操作

| 操作 | 键/入口 |
| --- | --- |
| 发送 | `Enter` |
| 换行 | `Shift+Enter` |
| 运行中插话 | 直接发送：默认 `steer`（本回合工具跑完后插入），可在设置里改成 `followUp` |
| 停止 | 输入框右侧「停止」 |
| 切换/新建会话 | 左侧栏；每个会话独立进程，后台继续运行（`●` 标运行中） |
| 置顶 / 重命名 / 删除会话 | 右键会话行（重命名只对当前会话，删除会二次确认） |
| 复制 / 放回输入框 | 鼠标悬停气泡，右上角 ⧉ 与 ↩ |
| 撤销一次文件修改 | `edit`/`write` 气泡下方的「↶ 撤销这次文件修改」 |
| 回滚整轮 | 每个回合顶部的「检查点」气泡，点「↶ 撤销本轮」并确认 |
| 浏览工作目录 | 右上角「文件」：文件树 + 多标签预览（文本带语法高亮、Markdown、图片），`Δ` 对比上个检查点，`引用` 把 `@路径` 塞进输入框 |
| 贴图 | 输入框里 `Ctrl+V` 粘贴截图，或把图片拖到窗口上；发送前可移除 |
| 看扩展状态 | 输入框上方的细条：`setStatus` 一行汇总，`setWidget` 最多 4 行 |
| 搜索聊天记录 | `Ctrl+F` 或右上角 `⌕`，点结果跳转并高亮 |
| 选模型 / thinking | 右上角 |
| 切换界面语言 | 右上角 `中` / `EN`，立即生效并记住 |
| 切换主题 | 右上角 `☀` / `☾`，深色与浅色互换并记住 |
| 换视觉场景 | 右上角下拉（60 个） |
| 展开长输出 / diff | 点气泡头部 |

## 自检钩子（环境变量）

| 变量 | 作用 |
| --- | --- |
| `GAI_PI_VISUAL` | 启动时强制视觉场景序号 |
| `GAI_PI_AUTOPROMPT` | 启动后自动发送这句话（录制/验收用） |
| `GAI_PI_SCREENSHOT` / `GAI_PI_SCREENSHOT_DELAY` | 到点截图并退出 |
| `GAI_PI_SMOKE_PROMPT=0` | 只验证启动，不调用模型 |
| `GAI_PI_NODE` / `GAI_PI_CLI` | 覆盖 node / pi bundle 路径 |
| `GAI_PI_SESSION` | 启动后打开指定会话（uuid 或 jsonl 路径） |
| `GAI_PI_FAKE_DIALOG` | 起一个假扩展弹窗（`confirm`/`select`/`input`/`editor`），用于检查样式 |
| `GAI_PI_EDITOR` / `GAI_PI_EDITOR_FILE` | 启动即打开文件浏览器，并预览指定文件 |
| `GAI_PI_ATTACH_IMAGE` | 启动时就把指定图片挂到输入框（验收图片输入） |
| `GAI_PI_LOCALE` | 强制界面语言（`zh` / `en`），用于截图与验收 |
| `GAI_PI_SWITCH_LOCALE` | 启动 2.5 秒后自动切到另一种语言，用于验证热切换 |
| `GAI_PI_THEME` / `GAI_PI_SWITCH_THEME` | 强制深/浅色；后者在指定秒数后切一次，用于验证主题重建 |
| `GAI_PI_SEARCH` / `GAI_PI_SEARCH_JUMP` | 启动后自动打开搜索并填入关键词；JUMP=1 时自动跳第一条结果 |

## 现在能做什么，不能做什么

已完成：启动握手、流式文本与思考、工具气泡（含 `edit` 内联 diff）、运行/停止、
steer 队列、会话搜索/置顶/重命名/删除、模型与 thinking 切换、上下文压缩事件、扩展弹窗
（`confirm`/`select`/`input`/`editor`）与 `notify`、扩展状态条与挂件、单文件修改撤销、
每轮检查点与整轮回滚（影子 Git，不碰用户仓库）、文件浏览器（树 + 文本/Markdown/图片预览 + `@引用`）、
图片粘贴与拖拽、深色/浅色主题切换、聊天记录搜索（跳转+高亮）、并发会话（一会话一进程）、
60 个视觉场景（切换即预览）、多工作目录、
中英双语与运行时切换、便携打包。

未完成（详见 [ARCHITECTURE.md](ARCHITECTURE.md#十六边界与已知不足)）：编辑器写操作与 diff 视图、
导出为单文件 exe。

## 打包

```bash
pwsh -File tools/package.ps1          # dist/gai-pi-portable/ + dist/gai-pi-portable.zip
pwsh -File tools/package.ps1 -NoZip   # 只要目录，方便先试跑
```

包里是「引擎 + 工程 + 导入缓存」：180MB 目录，压完 90MB。不改用 Godot 导出模板，所以不需要
下载那 700MB 模板；`gai-pi.cmd` 布局不变，双击即可。Node.js 与 pi 故意不打进去——它们用你机器上
已经装好、已经配好凭据的那套。

## 与原版的功能对照

| gai | gai-pi |
| --- | --- |
| agent 循环 / 18 个工具 | ✅ 交给 pi（内置 read/write/edit/bash/grep/find/ls + 扩展工具） |
| 每轮检查点、单文件恢复、整轮回滚 | ✅ 影子 Git + 单文件快照撤销 |
| 会话 pin / 重命名 / 删除 / 搜索 | ✅（拖拽排序未做） |
| 内置编辑器：文件树 / 标签 / 图片 / Markdown | ✅ 另加语法高亮与 diff 视图 |
| 60 个动效场景 | ✅ 全部移植，切换即预览 |
| 图片进对话 | ✅ 粘贴/拖拽 → pi 的 ImageContent |
| 多语言、深浅主题、MCP、技能 | ✅ 语言与主题自带；MCP/技能走 pi 扩展 |
| 语音输入 | ❌ 未做 |
| `.memory/` 后台记忆整理 | ❌ 未做（pi 用 AGENTS.md/skills/压缩） |
| 36 个资产技能 + 工作流画布 | ❌ 未做 |
| 本地 MiniCPM-V 读图 | ❌ 未做（走 provider 的视觉能力） |
| 安全模式（工作区限制/命令守卫） | ❌ 未做（依赖扩展的 confirm 弹窗） |
| Git Bash 窗口 / 单文件 exe | ❌ 未做（有便携包） |

## 文档

- [ARCHITECTURE.md](ARCHITECTURE.md)：gai 的拆解、pi 的能力边界、协议映射表、踩过的坑
- [CREDITS.md](CREDITS.md)：gai / zfoo 的 MIT 授权与复制清单

## 授权

MIT。界面资产来自 gai（`Copyright (c) 2026 godot-fun`，MIT），见 CREDITS。
