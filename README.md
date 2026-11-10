# 《燎原》Godot 客户端工程

本工程已从本次开发记录中的完整文件快照恢复；字体、音效和图标从保留下来的原版 APK 恢复。使用 Godot 4.6.3，Compatibility 渲染器。

当前源码是磁盘恢复后留存的最新完整快照（更晚的两个源码目录已丢失）。仓库不含安装包、Godot 缓存、构建产物或签名材料。

## 运行

用 Godot 导入本目录中的 `project.godot`，运行 `scenes/main.tscn`。命令行也可运行：

```sh
godot --path .
```

玩法、存档和五关内容没有因恢复而重写。恢复后重新编译的五个核心脚本与原版 APK 中的编译脚本逐字节相同。

## 恢复后验证

- 模拟测试：126,427 通过，0 失败。
- GUI 实际点击/按键测试：377 通过，0 失败。
- 持久化核心测试：480 通过，0 失败。损坏 JSON 用例会输出预期的解析错误日志。
- Windows 和 Linux 客户端已重建；Windows 没有在 Windows 系统上执行验证。
- 安卓安装包是保留下来的原版，文件 SHA-256 和签名证书均核验一致；未新增安卓真机验证。

```sh
godot --headless --path . --script res://scripts/test_sim.gd
```

## 文件

- `scripts/main.gd`：原生 Control 界面、输入、引导、结算和存档。
- `scripts/sim.gd`：确定性火势模拟、五关和评分。
- `scripts/board.gd`：地图绘制和格子交互。
- `scripts/save_store.gd`：存档读取、备份和原子写入。
- `scripts/game_audio.gd`：音效和环境循环。
- `tests/`：GUI、持久化测试与合法关卡解法。
- `tools/make_audio.py`：程序化音频生成器。
- `docs/BALANCE.md`：规则和平衡说明。

## 从源码运行与测试

```sh
git clone git@github.com:xiaolanawaqaq/liaoyuan.git liaoyuan
cd liaoyuan
godot --headless --editor --path . --import
```

自动化测试（先执行上面的资源导入）：

```sh
godot --headless --path . --script res://scripts/test_sim.gd
godot --headless --path . --script res://tests/test_challenge.gd
godot --headless --path . --script res://tests/test_store_v030.gd -- --evidence=/tmp/liaoyuan-qa/store-<唯一id>
godot --headless --path . --script res://tests/test_persistence.gd -- --evidence=/tmp/liaoyuan-qa/persistence-<唯一id> --mode=core
godot --headless --path . --script res://tests/test_ui.gd -- --save-path=/tmp/liaoyuan-qa/ui-<唯一id>/save.json
godot --headless --path . --script res://tests/test_ui_v030.gd -- --save-path=/tmp/liaoyuan-qa/ui-v030-<唯一id>/save.json
```

`test_store_v030` 和 `test_persistence` 是带证据目录的审计型测试：`--evidence` 必须是工程外、不存在的绝对路径，测试结果 JSON 写入该目录。`test_persistence` 还支持 `--mode=reload`（跨进程重载核验）、`--mode=denied`（权限拒绝注入）等审计模式。两个 UI 测试用 `--save-path` 指定隔离的测试存档，绝不读写玩家真实存档；`--shots=<目录>` 可选保存界面截图。

`tests/solutions.json` 保存五关的合法解法序列，`test_challenge.gd` 等用它回放验证。

## Android 签名与导出

原来的安卓私有签名密钥没有找到，旧 APK 仍被保留。现在使用独立生成的新发布密钥；新密钥和密码放在工程目录之外，不进入源码和发行压缩包。

导出命令（凭据通过仓库外的 JSON 文件提供，`JAVA_HOME`/`ANDROID_HOME` 等本机路径在 `tools/export_android.py` 中，换机器时需要调整）：

```sh
python3 tools/export_android.py \
  --credentials /path/to/credentials.json \
  --output /path/to/新的输出文件名.apk \
  --log /path/to/私有日志.log
```

脚本只在导出进程中设置 Godot 官方签名环境变量，密码不会写入 `export_presets.cfg`。每次输出使用新文件名，避免覆盖已发布安装包。Android `versionCode` 后续更新应递增，签名必须持续使用这把新密钥。

**新签名不能覆盖更新旧签名的安装。** 同一包名的旧安装需要先卸载，再装新包；卸载可能丢失本地存档。首次安装用户没有此冲突。
