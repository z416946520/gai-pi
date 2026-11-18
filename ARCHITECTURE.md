# gai-pi 架构

pi 的桌面端。外壳是 Godot 4.6 场景（沿用 gai 的视觉语言），大脑是 `pi --mode rpc` 子进程。
本文记录为什么这样切、边界在哪、每个协议字段落到哪个界面元素、以及还没做的部分。

---

## 一、gai 是怎么设计的（读代码得出，不是读 README）

gai（`godot-fun/gai`，MIT）把「AI 编程代理」整个搬进游戏引擎：

- **单体 Godot 场景**：`agent/Agent.tscn` 就是全部 UI。没有 Web 层，界面元素用 `Control` 和
  `_draw`/shader 画出来，因此可以做 GPU 级动效。
- **自己的框架**：`zfoo/`（可直接同步进任意 Godot 4.6 工程），提供主题色板、字体、UI 缩放、
  OpenAI 兼容客户端、WebSocket、音频、异步资源加载。
- **自己的 agent 循环**：`agent/loop/AgentLoop.gd`，约 90 行。取消息 → 流式请求 → 有 tool_calls
  就逐个执行 → 追加 tool 结果 → 再请求，直到无工具调用或超过最大轮数。
- **自己的工具层**：`agent/tools/` 18 个工具（bash/read/write/edit/delete/grep/glob/list_dir/
  web_fetch/web_search/browser_open|observe|act/read_image/audio_to_text + MCP）。
- **自己的会话与记忆**：会话是 `ChatEntry` 数组（`kind/title/body/details`），存 JSON；
  `.memory/` 是纯 Markdown，由后台记忆代理在压缩时整理。
- **自己的事件总线**：`agent/AgentEvents.gd`。这是关键发现——它的信号命名已经和 pi 的会话事件
  一一对应：

  ```
  agent_start → turn_start → message_update → message_complete
             → tool_execution_start → tool_execution_end → turn_end → agent_end
  ```

  也就是说 gai 的前端是「按 pi 的事件模型写的事件驱动 UI」，只是它自己实现了一个循环。
- **60 个视觉场景**：`agent/ui/visuals/<name>/<Name>.gd`，每个都是 `VisualEffect` 子类，
  实现同一组钩子（`on_agent_start/on_turn_start/on_message_update/on_tool_execution_end/...`），
  由工具调用驱动：矩阵雨、推理树、记忆河流、乐器、天体……
- **其余外壳**：编辑器（文件树/标签/Markdown 预览）、Git 检查点与 diff、语音、36 个资产技能、
  Node+Playwright 浏览器服务、llama.cpp + MiniCPM-V 本地视觉。

结论：gai 的**界面契约**是可复用的，**大脑**是可替换的。这正是 gai-pi 的切口。

---

## 二、pi 已经提供了什么

pi（`@earendil-works/pi-coding-agent`，1.5.2）作为独立进程提供：

| 能力 | 形式 |
| --- | --- |
| 代理循环 | 进程内，`prompt` 后自跑，直到 `agent_settled` |
| 工具 | `read` `write` `edit` `bash` `powershell` `grep` `find` `ls` + 扩展（MCP/codemode/子代理） |
| 会话 | `~/.pi/agent/sessions/--<cwd>--/<ts>_<uuid>.jsonl`，v3 树形，可 fork/clone/switch |
| 上下文 | `AGENTS.md`、skills、prompt templates、compaction（阈值/溢出/手动） |
| 模型 | provider/model 目录、thinking level、虚拟模型、重试 |
| 事件 | JSONL 事件流：消息增量、工具生命周期、队列、压缩、重试、扩展 UI |
| 编辑可视化 | `edit` 工具结果自带 `details.diff` 与 `details.patch` |

pi 不在桌面端提供的：布局、主题、动效、会话侧栏、编辑器、图片拖拽、快捷键。
**这就是桌面端要写的全部。**

---

## 三、总体结构

```
┌──────────────────────────── Godot 4.6 进程 ────────────────────────────┐
│  app/ui/Main.gd            工具栏 / 侧栏 / 对话流 / 输入框              │
│  app/ui/ChatBubble.gd      ChatEntry → 气泡（markdown、diff、折叠）     │
│  app/ui/VisualStage.gd     60 个 shader 场景，事件驱动                  │
│  app/bridge/*              协议层                                       │
│      PiPaths               找 node + pi bundle + 会话目录               │
│      PiProcess             OS.execute_with_pipe，JSONL 分帧            │
│      PiClient              请求 id 关联、超时、扩展 UI                  │
│      PiWorkspace           一个工作目录 = 一个 pi 进程                  │
│      PiSession             事件 → ChatEntry，持久条目 → ChatEntry       │
│      PiSessionIndex        扫 JSONL，喂侧栏                             │
│      PiEvents              应用内事件总线（与 gai 同名同参）             │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ cmd.exe /c launch.cmd（先 cd，再 node cli.js --mode rpc）
                                    │ stdin/stdout: JSONL
┌───────────────────────────────────▼────────────────────────────────────┐
│                            pi 子进程                                    │
│  loop / tools / sessions / compaction / models / extensions / skills    │
└─────────────────────────────────────────────────────────────────────────┘
```

### 为什么是子进程而不是 SDK

SDK 只能在 Node/Bun 里内嵌，Godot 是 GDScript。RPC 模式是 pi 官方给的「自定义 UI」通道，
协议稳定、语言无关、进程隔离（模型崩溃不会带走窗口）。代价是多一个进程和一个 JSONL 编解码层，
这层只值 ~600 行。

### 为什么不用 Electron/Tauri

用户的诉求是「喜欢 gai 的设计」。那套设计的核心是 shader 动效、逐帧绘制的场景、GPU 合成，
换成 DOM 就不是同一个东西了。而 pi 的 RPC 让「引擎壳 + 原大脑」成为可能。

### 为什么不直接 fork gai

fork 会连带一整套 GDScript 版 agent（循环、18 个工具、MCP、VLM、记忆代理、压缩）——全部是
死代码，还会和 pi 抢会话与记忆的真相。gai-pi 只挑**可移植的界面资产**：

- `zfoo/`（框架，gai 明确说可同步到任意工程）
- `app/visuals/`（60 个效果 + `VisualEffect/VisualColor/ToolVisualDisplay`）
- `MarkdownParser`（markdown → BBCode）
- `ChatEntry` / `AgentToolResult`（界面数据契约）
- 语言包（`app/locale/*.json`）

需要桥接的兼容壳只有 5 个，且都在明处：`ChatEntryCursor`、`AgentLayout`、`AgentSetting`、
`ToolHelper`、`LlamaHelper`/`VLMServer` 空实现。

---

## 四、进程与会话模型

- **一个会话一个 pi 进程**。pi 的会话工作目录在创建时固定，一个进程同时只装一个会话；
  要并行跑多个会话，就得给每个会话各自一个进程。`Main._hosts` 是 `路径 -> PiWorkspace` 的池，
  每个 host 用 `pi --mode rpc --session <文件>` 启动，后台运行时互不影响。侧栏每个运行中的
  会话前面加 `●`，切过去只是换显示，原来的进程还在跑。
- **启动时切换工作目录**：`OS.execute_with_pipe` 不能设置子进程 cwd。每个 host 写一个
  `user://runtime/launch-<local_id>.cmd`（Windows）或 `.sh`，内容是 `cd /d <工作目录>` + 启动 node，
  再用 `cmd.exe /c <脚本>` 拉起。文件名按 host 的 local id 区分，多个进程不会互相覆盖。
- **切换会话不再走 `switch_session`**：命中已有 host 就 `activate_session`（换显示 + 从内存
  entries 重放窗口，约 300ms）；没有 host 才起一个进程，启动同时读会话文件而非 `get_entries`。
- **新会话的 key 会变**：新 host 用 `new:<n>` 占位，第一条消息落盘后 `rekey_host()` 把它挪到
  文件路径下，侧栏随之出现这一行。
- **上限与淘汰**：池子最多 4 个进程，超出时按 LRU 停掉「非当前 + 非运行中」的 host；
  每个进程约占 100–200MB。
- **本地 id**：pi 用 UUID，视觉层与 gai 的钩子用 `int`。每个 host 从 shell 拿一个全局递增的
  `local_id`，这样多会话的视觉事件不会串台。
- **本地 id**：pi 用 UUID，视觉层与 gai 的钩子用 `int`。`PiSession.local_id` 做一次映射，
  这样 60 个效果一行都不用改。
- **目录编码**：去掉前导分隔符，把 `/`、`\`、`:` 换成 `-`，两侧加 `--`。
  `D:\BuildProject\gai-pi` → `--D--BuildProject-gai-pi--`，与 pi 自身一致。

---

## 五、协议映射

### 会话事件 → 对话流

| pi 事件 | 处理 |
| --- | --- |
| `agent_start` | 置运行态，`RuntimeManager.begin`，视觉层出现 |
| `turn_start/turn_end` | 透传给视觉层 |
| `message_start`(assistant) | 新回合，准备文本/思考条目 |
| `message_update.text_delta` | 追加到 agent 条目，节流刷新（80ms） |
| `message_update.thinking_delta` | 追加到 thinking 条目，标为推理流 |
| `message_update.toolcall_start/end` | 建工具条目（id = toolCallId），记参数摘要 |
| `tool_execution_start` | 工具气泡进入 running，参数体填充 |
| `tool_execution_update` | 覆盖部分输出 |
| `tool_execution_end` | 输出入体、`isError`、`details.diff/patch` 直接做内联 diff |
| `message_end` | 用权威消息校正文本/思考，更新 usage |
| `compaction_start/end` | 生成「Context Summary」条目 |
| `auto_retry_*` | 错误条目（重试中/最终失败） |
| `queue_update` | 记录 steer / follow-up 队列 |
| `session_info_changed` | 侧栏标题 |
| `agent_settled` | 结束运行态，视觉层淡出 |

`get_entries` 重建走同一套 `ChatEntry` 模型：`message.user/assistant/toolResult` → 对应用户、
助手、思考、工具条目；`compaction`/`branch_summary` → 上下文条目。

### pi 命令 → 界面

| 界面动作 | 命令 |
| --- | --- |
| 发送 / 打断中发送 | `prompt`（streaming 时带 `streamingBehavior: steer|followUp`） |
| 停止 | `abort` |
| 新会话 | `new_session` → `get_state` → `get_entries` |
| 切换会话 | `switch_session` → `get_state` → `get_entries` |
| 模型 / thinking | `get_available_models` / `set_model` / `set_thinking_level` |
| 压缩上下文 | `compact` |
| 启动握手 | `get_state`（失败则 3s 重试） |

### 工具名 → 视觉语言

pi 的 8 个内置工具与 gai 的 18 个不是一一对应，映射集中在 `ToolVisualDisplay`：

| pi | gai 对应 | 气泡类型 | 字形 |
| --- | --- | --- | --- |
| `read` | `read` | file_tool | R |
| `write` | `write` | file_tool | W |
| `edit` | `edit` | file_tool | E |
| `bash` | `bash` | tool | `>_` |
| `powershell` | — | tool | `>_` |
| `grep` | `grep` | explorer_tool | ? |
| `find` | `glob` | explorer_tool | * |
| `ls` | `list_dir` | explorer_tool | / |
| 其他（MCP/扩展） | — | tool | 名称前两位 |
| `web_*` / `browser_*` | 同名 | web_tool | @ |

---

## 六、复用的界面资产，以及它们需要的壳

60 个效果都是 `VisualEffect` 子类，钩子签名固定：`session_id: int`、`args: Dictionary[String, Variant]`、
`result: AgentToolResult`、`usage: OpenAiUsage`、`entry: ChatEntry`。`PiEvents` 与 `VisualStage`
按这个签名投喂，所以效果文件本身**零改动**。

为让它们编译，补了这些同名兼容类（不带 gai 的业务逻辑）：

| 类 | 位置 | 作用 |
| --- | --- | --- |
| `ChatEntryCursor` | `app/visuals/` | 句子级转录游标，数据源改为 `RuntimeManager` 里的 `PiSession` |
| `AgentLayout` | `app/ui/` | 只保留 `toolbar_height` |
| `AgentSetting` | `app/bridge/` | 只保留 `DEFAULT_MAX_TURNS` / `get_max_turns()` |
| `ToolHelper` | `app/bridge/` | 文件/网络/浏览类工具判定 |
| `LlamaHelper` / `VLMServer` | `app/bridge/` | 本地视觉服务空实现（健康检查恒 false，回退本地分词） |
| `SessionRow` | `app/ui/` | 侧栏行标记类型（部分效果按类型扫描 UI 树） |

把效果里的 `BubbleContainer` 类型判断改成了 `ChatBubble`（5 处），并把 47 个脚本里写死的
`res://agent/ui/visuals/...` 预加载路径改成 `res://app/visuals/...`。这是唯一的批量改动。

---

## 七、界面语言

界面文字只有两个来源：

1. **gai 的现成词条**：`agent.visuals.*`、`agent.toolbar.visual_*` 等，60 个视觉场景与视觉选择器
   直接用，`app/locale/zh.json` / `en.json` 原样保留。
2. **gai-pi 自己的词条**：全部放在两份语言文件的 `gai_pi.*` 下（`app/locale/*.json`，嵌套 JSON，
   `LocaleData` 会拍平成点号键）。`app/ui/T.gd` 负责查表与 `{}` 占位符替换，缺词条时回退成键名，
   不会静默变空。

切换流程：

```
点右上角 中/EN
  → I18n.set_locale("res://app/locale/<code>.json")   // 加载词典、set_locale、写 Setting
  → gdf.events.locale_changed
  → Main.apply_locale()
       顶栏 tooltip / 语言按钮 / 发送与停止按钮 / 输入框占位 / 快捷键提示
       视觉选择器重建（60 项走 VisualStage.localized_name）
       侧栏重建（未命名会话用 gai_pi.sidebar.untitled）
       空状态重建
       所有气泡 refresh()（标题按 kind 现算，不存英文常量）
       打开中的扩展弹窗 rebuild()
```

设计上的取舍：

- **气泡标题在渲染时翻译**：`ChatEntry.title` 建于事件发生那一刻，若直接显示会冻结语言；
  `ChatBubble.localized_title()` 按 `kind` 现查词条，只有工具名（`read`/`bash`/`edit`…）保留原文，
  因为它们是 pi 的工具标识。
- **pi 的输出不翻译**：模型文本、工具输出、pi 报的原始错误都是数据；只有桥接层自己生成的
  提示（启动失败、切换失败、重试中…）走词条。
- **持久化交给 zfoo**：`I18n.set_locale` 把 locale 写进 `Setting`，下次启动 `_init_i18n()` 读回，
  没有第二份配置。
- **热切换的代价**：一次切换会重建侧栏、重排全部气泡（400 条会话约 1 秒）。可接受，因为切换是
  低频动作；滚动位置由 `watch_scroll_extent` + 跟随窗口保持在底部，不会被重建打断。

## 八、性能与卡顿处理

会话切换原先是「`switch_session` → `get_entries` → 全量建气泡」，500 条以上的会话要
6s + 2s + 1.2s，界面直接冻住。现在分三层拆开：

1. **历史不从 RPC 拉**：`PiSessionIndex.load_branch_entries()` 直接读会话 JSONL，按
   `parentId` 从叶子回溯出活动分支（565 条 / 5.9MB ≈ 120ms）。`get_entries` 只用于启动时的
   空会话。
2. **只建首屏窗口**：默认渲染最后 50 条，其余靠顶部「载入更早」分批前插，前插后按高度差
   补滚动位置。回放时按 8ms/帧的时间预算推进，不按条数，保证单帧不超时。
3. **长内容降采样**：思考块默认只留标题（展开才解析 markdown）；助手正文默认截 80 行；
   侧栏元数据按 mtime+size 缓存；侧栏只在签名变化时重建；语言切换按 24 条/帧重排。

## 九、检查点（整轮回滚）

pi 没有检查点概念，用用户自己的仓库会往里塞 commit。gai-pi 的做法是**影子 Git 仓库**：

- 仓库放在 `user://checkpoints/<workspace>-<hash>/`，每条命令都带
  `--git-dir=<影子> --work-tree=<工作目录>`，用户的 `.git` 从不被写。
- `.git/info/exclude` 排除 `.godot/`、`.dependency/`、`node_modules/`、`.verify/`、`build/`
  等生成目录，快照只存源码量级的数据。
- 每回合两枚提交：发消息前 `turn N start`，`agent_settled` 后 `turn N end`；
  「本轮改了哪些文件」= 两个提交的 `diff --name-only`。
- 回滚 = 先 `git add -A`（把本回合新文件纳入索引）再 `git reset --hard <start>`。
  新增的文件被删掉、改过的文件回到原样，没动过的文件不受影响。
- 检查点元数据（session / turn / commit / summary / timestamp / reverted）写在影子仓库旁的
  `turns.json`：重放会话时按时间戳把「检查点」气泡插回正确位置，已回滚的保持「已回滚」。
- Git 调用走 `AsyncProcess`（`OS.execute_with_pipe` + 帧循环轮询），`git add -A` 再慢也不冻界面。

## 十、文件浏览器

右上角「文件」打开右侧面板：

- **文件树**：排除 `.git`/`.godot`/`.dependency`/`node_modules` 等目录与 `*.import`/`*.uid`，
  最多 4000 个节点，超出截断。
- **预览**：打开的文件进 `TabBar`，每个标签带关闭按钮，切标签只换右侧内容。图片走
  `Image`/`ImageTexture`；Markdown 走 gai 的 `MarkdownParser` 转 BBCode（README 里的 HTML
  标签先剥掉）；其余按文本用只读 `CodeEdit` 显示，超过 2MB 只给提示。
- **语法高亮**：直接复用 gai 的 `agent/manager/git/code/` 全套（`CommonHighlighter.create(path)`
  按后缀分派 GDScript/JSON/Markdown/Windows/通用，`CodeColors` 随主题切换），只在
  `MarkdownHighlighter` 里把 `@mention` 扫描换成同逻辑的 `MentionScan`。
- **引用**：点「引用」把 `@相对路径` 追加到输入框，交给 pi 的 `@path` 展开。
- **Diff**：标题栏 `Δ` 把当前文件与「本会话最近一次检查点的开局提交」做 `git diff`，
  按行着色；没有记录时退回仓库 baseline，再没有就提示「还没有检查点」。

只读是刻意的：写文件归 pi，外壳不跟它抢，避免同一份文件两个写入者。

## 十一、图片输入与扩展状态

**图片**进 `pi` 只有一条路：`prompt` 的 `images` 字段（`{type, data, mimeType}`，data 是 base64）。
外壳做三件事：

- `Ctrl+V` 在输入框里粘贴：`DisplayServer.clipboard_has_image()` 为真且剪贴板没有文本时，
  取图、最大边缩到 1600px、转 PNG、base64 入队，并接管按键（不让文本控件再插一次）。
- 拖拽：`Window.files_dropped` 里挑图片后缀，其余忽略。
- 发送：附件以 `ImageContent` 交给 `prompt`；只有图没有字时用一句本地化默认提示。
  用户气泡右上角标 `XX N`。

**扩展状态**：`setStatus` / `setWidget` 是终端语义的推送，外壳把它们变成输入框上方的一条细带：

- `setStatus {statusKey, statusText}` 按 key 维护，空文本即删除；所有状态拼成一行，超出省略，
  tooltip 给全文。
- `setWidget {widgetKey, widgetLines}` 按 key 维护，最多 4 行、每行 120 字，所有挂件按 key
  插入顺序拼起来。
- 两者都先过 `TextSanitize.strip_ansi()`（CSI/OSC 转义、回车）再接一行，否则 powerline 类扩展
  的彩色控制符会直接显示成乱码。

## 十二、聊天记录搜索

`ChatSearch.find_matches()` 是纯函数：大小写不敏感的子串匹配，命中 `body` 也算命中 `title`，
每条结果给一段以命中点为中心、换行压平的摘录（`SNIPPET_RADIUS = 44`，最多 60 条）。
`test/search_test.gd` 直接对它跑断言，不依赖 UI。

界面是右上角 `⌕` / `Ctrl+F` 打开的浮层：输入即搜，结果按“类型 · 摘录”列出，回车跳第一条。
跳转分两种情况：

- 命中在当前窗口（最后 50 条）里：直接滚到气泡居中，并用 1.1 秒的高亮 tween 标出来。
- 命中在窗口之外：`start_transcript_window(index - 8, index - 8 + 50)` 重建一个以命中点为中心的
  窗口，再滚动高亮。这样不会为了看一条旧记录把整段历史都建出来，也不会只剩孤零零一条气泡。

只搜当前会话；不做正则、不跨会话。跳转后点击侧栏当前会话即可回到最新尾部。

## 十三、主题

调色板有两层：`zfoo` 的 `ThemeColor` 已经带深/浅两套派生色（标题、正文、卡片、强调），
外壳又加了一层 `app/ui/AppTheme.gd`——它把背景、顶栏、侧栏、输入框、容器、描边这些
“外壳色”统一映射到 `Colors.DARK_*` / `Colors.LIGHT_*`，并提供一个 `ink()` 把为深色画布
设计的霓虹色（工具头、diff 的加/删行、错误红、检查点黄）在浅色下压暗 42%。

主题切换的做法是**重建整个界面**：面板样式在构造时就把颜色写进了 `StyleBoxFlat`，逐处回写
不如重建干净。重建时保留 `workspace_host` / `session`（pi 进程不重启）、输入框草稿、附件、
编辑器开合状态与当前文件、滚动跟随，然后用 `start_transcript_build()` 把转录重放回来。
实测从点击到新主题完整出现约一帧，首屏 50 条气泡重建 ~300ms。

一个坑：重建会重新填充视觉选择器，某些构建下 `add_item` / `selected` 会触发 `item_selected`，
于是看起来像“用户选了一个特效”。`_suppress_visual_signal` 在重建期间屏蔽该信号。

## 十四、打包

`tools/package.ps1` 不依赖 Godot 导出模板（那一套要另下 700MB 模板）：它把**引擎二进制、工程源、
`.godot/` 导入缓存**拷到一个目录，再打 zip。包内保持仓库目录形状，所以 `gai-pi.cmd` 不用改。
实测：180MB 目录 / 90MB 压缩包，749 个文件，包内引擎 headless 启动能拿到 pi 会话，窗口也能渲染。

Node.js 与 pi 故意不打进包：它们用用户自己的安装、自己的 provider 凭据，这也符合整个项目的边界。

## 十五、已验证的事实（可复跑）

```bash
# 1. GoDot 能驱动 pi 的 RPC（协议往返）
.dependency/godot/Godot_v4.6.3-stable_win64_console.exe --headless --path . --script test/bridge_smoke.gd
# 期望：PASS ready model=... / PASS settled assistant="gai-pi bridge ok"

# 2. 不调用模型，只验证启动与会话加载
GAI_PI_SMOKE_PROMPT=0 ... --script test/bridge_smoke.gd

# 3. 两种语言 + 热切换（自检钩子）
GAI_PI_LOCALE=zh GAI_PI_SWITCH_LOCALE=en GAI_PI_SCREENSHOT=.verify/lang.png   .dependency/godot/Godot_v4.6.3-stable_win64_console.exe --path .

# 4. 界面截图（自检钩子）
GAI_PI_VISUAL=4 GAI_PI_SCREENSHOT=.verify/run.png GAI_PI_SCREENSHOT_DELAY=45000 \
  .dependency/godot/Godot_v4.6.3-stable_win64_console.exe --path .
```

读代码/探针得到的、容易踩的点：

1. `OS.execute_with_pipe` 返回的 `FileAccess` 在**没有数据可读时会报 `ERR_FILE_EOF(14)`**。
   把它当结束信号会导致读到第一帧就以为进程退出。判活只看 `OS.is_process_running(pid)`。
2. 自己拼引号传给 `cmd.exe /c` 会把 `""path""` 传给 cmd 并报「不是内部或外部命令」。
   把路径原样作为一个参数传，让 Godot 去加引号。
3. `cmd.exe` 自己输出的错误是 GBK，按 UTF-8 解会刷一堆替换字符。启动脚本里 `chcp 65001` 压掉；
   node 自身输出本来就是 UTF-8。
4. 未类型化的 `Dictionary` 不能直接传给 `Dictionary[String, Variant]` 形参，必须 `.assign()`。
   这在 `PiEvents → VisualStage → VisualEffect` 的边界上各出现一次。
5. Godot 4.6 默认把「Variant 类型推断」当错误。所有 `var x = dict.get(...)` 都要显式标类型。
6. `super._gui_input(event)` 对内置虚函数不可用。回车发送要在 `_input` 阶段拦截并
   `set_input_as_handled()`，否则 `TextEdit` 仍会插入换行。

---

## 十六、边界与已知不足

明确没做，避免误以为已经具备：

- **弹窗队列**：`select/confirm/input/editor` 已能渲染并回写，但一次只显示一个，其余排队；
  带 `timeout` 的请求到点自动按 `cancelled` 关闭（与 pi 的默认行为一致）。
- **并发的代价**：每个会话一个 node 进程（约 100–200MB），池子上限 4；超出后按 LRU 淘汰
  非当前且空闲的 host，再切回去会重新启动。
- **状态细带的容量**：状态拼成一行、挂件最多 4 行，超出的扩展输出会被截断。
- **检查点的范围**：影子仓库排除了生成目录，所以回滚不会恢复 `.godot/`、`node_modules/`
  里的内容；`turns.json` 还没有清理策略。
- **图片输入的边界**：只接图片，不接音频/视频；剪贴板里同时有文字和图片时优先进文字。
- **聊天记录搜索**：只搜当前会话的正文/标题，没有正则、没有跨会话、没有结果内高亮。
- **编辑器**：只读预览（标签页与语法高亮已有），没有写操作、没有 diff 视图、没有搜索。
- **主题切换的代价**：重建界面会丢掉未提交的瞬时状态（正在预览的特效、未发送的弹窗）；
  主题选择本身持久化在 `Setting` 里。
- **附件/图片、粘贴截图**：已支持图片，尚无文件附件与音频。
- **编辑器面板、语音、资产技能面板、演练场（workflow）**：只补了文件浏览与只读预览，其余未移植。
- **审批/安全模式**：`confirm` 已能弹窗回写，但还没有配置界面去开关或编排扩展的审批策略。

---

## 十七、路线图（每步带验收）

1. **协议稳固**（已完成）：启动/握手/流式/工具/结算，`test/bridge_smoke.gd` 通过。
2. **性能基线**（已完成）：切换 565 条会话 = pi 的 `switch_session` ~0.5s + 读文件重建
   ~0.12s + 首屏 50 条气泡 ~0.3s。此前为 `get_entries` 6s + 全量重建 2s + 1200ms。
   并发会话后，已打开过的 host 切回来不再起进程，只重放窗口（~0.3s）。
3. **扩展弹窗**（已完成）：`confirm/select/input/editor` 渲染为居中卡片，回写
   `extension_ui_response`；`notify` 进顶栏。验收：`GAI_PI_FAKE_DIALOG=confirm|select|input`
   起的假弹窗可渲染并回写（真扩展审批待补一个用例）。
4. **会话管理**（大部分已完成）：搜索、置顶、重命名、删除已接；fork / 拖拽排序待做。
5. **检查点增强**（基础已完成）：`bash` 改动也在快照里；回滚后自动刷新编辑器预览。
6. **图片输入**（已完成）：粘贴/拖拽 → base64 → `prompt.images`，`GAI_PI_ATTACH_IMAGE`
   验收钩子能直接挂图并发给模型。
7. **打包**（已完成）：`tools/package.ps1` 产出便携目录与 zip，包内引擎可启动、可截图。
8. **主题**（已完成）：`AppTheme` 映射外壳色，右上角深/浅切换，重建界面但保留会话与草稿。
9. **聊天内容搜索**（已完成）：纯函数匹配 + 浮层结果 + 跳转高亮，远端命中重建窗口。
10. **编辑器增强**（部分完成）：标签页、语法高亮、diff 视图已接；写操作、文件内搜索待做。
11. **并发会话**（已完成）：一会话一进程，`test/concurrency_test.gd` 同时跑两个 prompt
    都能拿到各自回答；侧栏 `●` 标运行中，池子上限 4。
12. **导出单文件 exe**：装 Godot 导出模板后加 `export_presets.cfg`。

---

## 十八、目录

```
app/
  bridge/      pi 协议、会话映射、兼容壳
  ui/          Main / ChatBubble / VisualStage / SessionRow
  visuals/     60 个效果 + VisualEffect + ChatEntryCursor（来自 gai，MIT）
  markdown/    MarkdownParser → BBCode（来自 gai，MIT）
  locale/      zh/en 语言包（来自 gai，MIT）
zfoo/          框架（来自 gai，MIT）
test/          bridge_smoke.gd（headless 验证）
.dependency/   Godot 4.6.3（不入库）
```
