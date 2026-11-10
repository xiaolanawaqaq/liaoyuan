# AI 与第三方资源披露（TapTap 聚光灯 GameJam 2026 申报用）

赛事规则要求：作品中使用 AI 生成内容必须如实披露，否则取消评奖资格；AI 生成美术占比超过 50% 不得参与美术奖项评选。

## 本作 AI 使用情况

| 环节 | 是否使用 AI | 说明 |
|---|---|---|
| 游戏策划 / 规则设计 | 部分 | 玩法方向、规则参数与关卡结构由 AI 助手（ZCode）参与设计讨论并生成草案，人工确定最终数值与规则 |
| 程序代码 | 主要 | 全部 GDScript 源码由 AI 助手编写与迭代，人工测试与验收 |
| 美术资源 | 未使用 AI 生成图像 | 图标 `assets/icon.svg` 为手工编写的矢量图形；界面为引擎原生控件样式，无位图美术 |
| 字体 | 未使用 AI | 使用 DejaVu Sans（自由字体，许可证随发行包附带 `DEJAVU-NOTICE.txt`） |
| 音频 | 未使用 AI 生成 | `tools/make_audio.py` 以代码程序化合成的简单波形音效，非 AI 模型产物 |
| 文案 | 部分 | 游戏内中文文案与说明由 AI 助手起草，人工修改定稿 |

按上述口径：本作**未使用 AI 生成美术资产**（图像类资产为零），不涉及美术奖项的 50% 红线；代码与文案属 AI 辅助，已如实披露。

## 第三方资源清单

| 资源 | 来源 | 许可证 |
|---|---|---|
| Godot Engine 4.6.3 运行时与导出模板 | godotengine.org | MIT（`licenses/GODOT-LICENSE.txt`） |
| Godot 内置第三方组件 | 见 Godot 官方第三方清单 | `licenses/GODOT-THIRD-PARTY-NOTICES.txt` |
| DejaVu Sans 字体 | dejavu-fonts.github.io | 自有许可证（`licenses/DEJAVU-NOTICE.txt`、`licenses/FONT-NOTICE.txt`） |

无其它外部美术、音频、字体或代码库。
