# Credits

gai-pi 的界面层直接复用了 [gai](https://github.com/godot-fun/gai)（MIT）的资产。
大脑是 [pi](https://github.com/earendil-works/pi)（`@earendil-works/pi-coding-agent`），
通过官方 RPC 模式接入，未修改其源码。

## gai / zfoo

```
MIT License

Copyright (c) 2026 godot-fun

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### 复制清单

| 路径 | 来源 | 改动 |
| --- | --- | --- |
| `zfoo/` | gai `zfoo/` | 未改动 |
| `app/visuals/` | gai `agent/ui/visuals/` | 47 个脚本的资源路径 `res://agent/ui/visuals/` → `res://app/visuals/`；5 处 `BubbleContainer` 类型判断 → `ChatBubble`；`VisualControl.gd` 重写为 `app/ui/VisualStage.gd`；`ChatEntryCursor.gd` 重写数据源；`ToolVisualDisplay.gd` 重写工具映射；删除 `VisualControl.gd`、原 `ChatEntryCursor.gd` |
| `app/markdown/MarkdownParser.gd`、`MarkdownParseResult.gd` | gai `agent/markdown/` | 未改动 |
| `app/bridge/ChatEntry.gd` | gai `agent/manager/session/ChatEntry.gd` | 增加 `id/tool_name/tool_call_id/is_error/running` 字段；移除依赖 gai 弹窗的 `open_full_view` 实现 |
| `app/bridge/AgentToolResult.gd` | gai `agent/tools/AgentToolResult.gd` | 未改动 |
| `app/locale/zh.json`、`en.json` | gai `agent/config/locale/` | 未改动 |
| `zfoo/ui/font/*.woff2` | gai（随 zfoo） | 未改动；字体授权见 `zfoo/ui/font/OFL.txt` |

兼容壳（`AgentLayout`、`AgentSetting`、`ToolHelper`、`LlamaHelper`、`VLMServer`、`SessionRow`）
是为让 gai 的效果脚本在本工程编译而写的轻量同名类，不含 gai 的业务实现。
