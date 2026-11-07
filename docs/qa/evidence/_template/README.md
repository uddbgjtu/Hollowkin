# PC 帧预算基线与证据模板（ADR-6 / Wave 2b → Wave 4 v1.2）

> **状态**：模板就位、导出链路与采集插桩已实跑验证，**零回填测量值**；R1 / R3 仍为 **CONCERNS**。
> **v1.2（2026-11-07）**：补齐逐样本原始证据、GPU / CPU / 墙钟帧时间插桩、窗口 / 全屏 × 60 / 30fps 分轮编排，并更正「本机无窗口 / 显示器」的过时判定；详见 §7.1、§8。19 列结构未变，5 项渲染 / 粒子指标仍 `blocked`。
> **依据**：`docs/architecture/adr-006-pc-first.md`（Windows Desktop 单平台、移动端彻底放弃）。
> **历史参考**：`docs/qa/archive/r1r3-device-test-plan.md` 已归档，仅保留插桩方法学与统计口径，**不作为现行判据**。
> **采集工具**：`src/qa/probe_runner.tscn` + `tools/qa/r1r3_probe.gd`；导出预设 `export_presets.cfg`（双 Windows Desktop）。

---

## 0. 定位与诚实性约束

- 本目录用于 **PC 窗口 / 全屏基线**：目标 60fps，30fps 为下限档。每行数据均属【PC 基线 · 非移动端真机】，**不得回填到已归档的移动端真机表**。
- `measurement_template.csv` 共 **19 列 × 10 行**，数值栏全部为占位 `【PC 基线待实测】` 或 `—`；`target` 列是**目标预算（判据）不是测量值**。
- 严禁把 GUT tick 数、Python 仿真、headless 自检输出换算成设备 ms 耗时；严禁抄目标预算充当实测值。
- **R1 / R3 CONCERNS 不因平台变更、模板就位、归档或导出成功自动翻转**（`architecture-doc.md §6`）；翻转须 PC 窗口实测数据 + 核验签字 + 主理人独立审批。
- **Wave 4 头部 smoke 数据不回填本表**：在导出的 exe 上以 `--headless` 跑出的 CSV 属于 CPU 侧链路验证，无窗口 / 无 GPU 帧时间、无预热与温控口径，只能证明采集工具可执行。

## 1. 19 列填写规则（PC 口径）

| 列 | PC 下含义 | 来源 |
|---|---|---|
| `device_id` | 机器标识（如 `pc_win_01`；需附 CPU / GPU / 内存规格） | 手工 |
| `os_version` | Windows 版本与 build 号 | `OS.get_version()` + 手工核对 |
| `gpu_backend` | Vulkan / D3D12 / GLES3 | **手工核对**（脚本只给 `rendering_method` 代理值，不可当作已填） |
| `build_sha` | `git rev-parse HEAD`；若含未提交改动须显式注明 | 手工 |
| `godot_version` | `4.3.stable` | 脚本 |
| `build_type` | `debug` / `release` —— **分开归档，禁止混算** | 脚本 |
| `thermal_state` | PC 可填 `N/A`，但须注明是否降频 / 散热模式 | 手工 |
| `battery_pct` | PC 台式机填 `N/A`；笔记本填首尾电量 | 手工 |
| `background_policy` | 后台负载 / 省电策略 / 是否前台独占 | 手工 |
| `metric` | 见 §2 指标清单 | 脚本 |
| `unit` | 统一 `ms`（微秒原始值换算后仍保留原始列） | 脚本 |
| `samples` | 样本数，须达 §3 下限 | 脚本 |
| `mean` | 算术均值 | 脚本 |
| `p95` | 排序后第 `ceil(0.95N)` 个 | 脚本 |
| `target` | 目标预算（判据，非测量值） | 脚本 |
| `verdict` | `pass` / `fail` / `blocked`；脚本输出为**自动初判**，最终以核验签字为准 | 脚本 + 人工 |
| `evidence_path` | 该轮汇总 CSV 路径；逐样本长表为同轮同名的 `_raw` 文件，见 §4 | 脚本生成，归档时改仓库相对路径 |
| `measured_at` | UTC 时间 | 脚本 |
| `operator` | 采集人 | 手工 |

## 2. 指标清单与当前可测性

| metric | 状态 | 说明 |
|---|---|---|
| `r1_logic_elapsed` | 可测 | `DungeonGenerator.generate_sync()`；每次须 `clear_cache()` |
| `r1_fallback_switch` | 可测 | 非法 floor 注入，校验 `fallback=true` 标记 |
| `r1_low_tier_density` | 可测 | HIGH / LOW 两档各 30 次，比较房间数与敌人上限 |
| `r3_input_arbitration` | 可测 | `HitZone.resolve()` + `InputQueue.consume_into()` |
| `r3_ai_tick` | 可测 | `CombatDirector.step_simulation(0.1)` |
| `r1_render_mean` / `r1_render_p95_spike` | **blocked** | `BLOCKED-BY-ASSET`：Wave 3b 已接入 `TileMapLayer` + 屏外剔除，但纹理是 `DEBUG_PLACEHOLDER`，须 ADR-4 E1 原图 + PC 窗口实测 |
| `r3_entity_render` / `r3_particles` | **blocked** | `BLOCKED-BY-ASSET`：`MultiMesh` + 剔除 / `CPUParticles2D` 已就位，但实体与特效贴图仍是 debug 占位 |
| `r3_total_frame_share` | **blocked** | 分项缺失时**只能给部分和，不得判 `pass`** |

因 5 项渲染 / 粒子 / 合计占帧比仍缺正式资产与窗口实测，**当前即使数据齐备也无法把 R1 / R3 翻成 PASS**。

## 3. 样本量下限与统计口径（沿用归档方法学）

- R1 生成逻辑 ≥ **100 层**；保底切换 ≥ **10 次**注入；降密度高 / 低档各 ≥ **30 次**。
- R3 输入仲裁 ≥ **100 帧**；AI tick ≥ **200 tick**；窗口与全屏、60fps 与 30fps 各单独一轮。
- 每轮启动后预热 ≥ 5s（着色器编译 / 资源导入），预热帧**不计入统计**。
- `mean` = 算术均值；`p95` = 升序第 `ceil(0.95N)` 个样本；保留原始样本 CSV 作为证据。
- **逐样本复算（v1.2）**：`python tools/qa/verify_probe_evidence.py <summary.csv> <metrics_raw.csv>` 从长表重算 `n` / `mean` / `p95` 并与 19 列逐行比对；`blocked` 行数值栏非空、帧时间样本混入汇总行、缺样本或数值不一致均判 `FAIL`。这是 §5 第 3 条的自动化实现，**不代替**核验签字与独立审批。

## 4. 证据目录与命名

```
docs/qa/evidence/<device_id>/<build_sha>/<round_id>/metrics.csv
docs/qa/evidence/<device_id>/<build_sha>/<round_id>/metrics_raw.csv
docs/qa/evidence/<device_id>/<build_sha>/<round_id>/console.log
```

`round_id` 建议形如 `windowed_60_release` / `fullscreen_30_debug`，与采集命令的 `--round-id` 一致。采集工具在 `user://` 下按 `hollowkin_probe_metrics_<round_id>.csv` 与 `hollowkin_probe_metrics_raw_<round_id>.csv` 落盘，归档时改名为上表结构并补 `console.log`（含 `METRIC|` / `METRIC_NOTE|` / `FRAME_CAPTURE|` / `PROBE_SUMMARY|` 行）。

一次提交只对应**一个 `device_id` + 一个 `build_sha` + 一种 `build_type` + 一个 `round_id`**；窗口 / 全屏、60 / 30fps、debug / release 禁止混算。目录下 `.gdignore` 阻止 Godot 把 `.csv` 当翻译资源导入。

## 5. 核验规则（数据到齐后由主理人执行）

1. 机器规格与 `os_version` / `gpu_backend` 一致，且属于约定的 PC 基线档位；
2. `build_sha` 与被测构建一致、`godot_version=4.3.stable`、debug/release 未混算；
3. 单位统一 ms，`samples` 达 §3 下限，mean / p95 经 `tools/qa/verify_probe_evidence.py` 从逐样本长表复算一致（`RESULT: PASS`）；
4. `verdict` 与数值及 `target` 一致，`blocked` 项数值栏为空；
5. `evidence_path` 指向真实存在的原始证据文件，轮次可对应；
6. 无任何臆造值；任何【PC 基线待实测】占位残留即退回。

核验通过后**先报主理人审批**才写入汇总；`architecture-doc.md §6` CONCERNS → PASS 是**独立审批动作**。

## 6. `_adapt` 30fps 误降频偏差（2026-11-07 已修复）

旧实现以 `delta > 1/60` 判「超预算」，把帧间隔长误当单帧超时，30fps 每帧必然命中、连续 30 帧后误降 5Hz（实跑 30fps 600 帧仅 104 tick，记账基准 200），会污染 `r3_ai_tick`。

**修复**：超预算只认实测单帧耗时 `frame_cost_s`，与 `delta` 解耦；无插桩数据时保守不降频；`_process` 取 `Performance.TIME_PROCESS`（CPU 侧近似，不含 GPU），并可用 `report_frame_cost()` 注入完整 profiler 数据。实跑对照：30fps 600 帧 **200 tick / `is_slow()=false`**；31 帧实测 20ms 超预算仍触发降频。

**注意**：`TIME_PROCESS` 只覆盖 CPU 脚本耗时，不含 GPU / 渲染，属保守近似；正式 PC 帧预算结论仍须按 §7 在窗口模式实测。若使用修复前构建的旧数据，须标注「构建未含 `_adapt` 修复」并按受限数据处理。

## 7. Wave 4 导出链路（已实跑验证，2026-11-07）

| 环节 | 结果 |
|---|---|
| 导出模板 | 官方 `Godot_v4.3-stable_export_templates.tpz` 为 **1.07 GB** 全平台包；用 HTTP Range 只读 EOCD / central directory，**仅取 4 个 x86_64 模板 + `version.txt`（压缩后约 59 MB）** 装入 `AppData/Roaming/Godot/export_templates/4.3.stable/` |
| rcedit | 两个预设均设 `application/modify_resources=false`，跳过图标 / 版本信息改写，无需 rcedit 即可导出；正式发布需图标时再配 rcedit 并改回 `true` |
| 发布包瘦身 | 两个预设加 `exclude_filter="addons/gut/*"`：GUT 是 CI 期安装的开发依赖，不进发布 / 采集包；`.pck` 由 3.7 MB 降至 **约 0.18–0.19 MB**（多次导出实测 185088–192928 bytes；随打包内容、构建与时间戳浮动，采集插桩补齐后 Game 192896 / Probe 192928 bytes） |
| Game 预设 | `--export-debug "Windows Desktop Game"` → `EXIT=0`；产出的 exe 以 `--headless --wave3-selftest` 启动 → `RUN_EXIT=0` / `WAVE3_SELFTEST_OK`（5 屏 5 视图、145 可见瓦片格、6 可见实体、粒子 24） |
| Probe 预设 | 按文件头注释临时把 `run/main_scene` 指向 `probe_runner.tscn` 后导出 → `EXIT=0`，**随后已改回 `src/main.tscn`**；v1.2 后 exe 支持 `--round-id` / `--window-mode` / `--fps-cap` / `--frame-samples` 等参数，输出 19 列汇总 + 逐样本长表两份文件 |
| 数据处置 | Wave 4 当时的两次启动都是 **headless 链路 smoke**：无窗口、无 GPU 帧时间、无预热 / 温控 / 后台策略口径，CSV 只留在 `user://` 与本机临时日志，**未入仓、未回填本表、未参与任何 verdict**。v1.2 的窗口模式实跑属插桩验证（§7.1），同样不是正式基线 |

### 正式 PC 基线采集步骤（v1.2）

**本机窗口能力已核实**（2026-11-07 只读检查 + Godot 受控试跑）：console 会话活动、`DISPLAY_SERVER=Windows`、单屏 1920×1080、Vulkan 1.3.205 Forward+ / NVIDIA GeForce MX450，非 headless 可创建窗口并读到 GPU 帧时间。**无需另找 PC。** 但 E1 正式资产未产出，帧时间只作链路证据（§7.1）。

1. 标定构建：导出前把 `src/qa/probe_runner.gd` 的 `PROBE_BUILD_SHA` 填成 `git rev-parse HEAD`（或用 `--build-sha=<sha>` 覆盖；`UNSET` 会被 §5 第 2 条退回）。记录 CPU / GPU / 内存规格与 `gpu_backend`（Vulkan / D3D12 / GLES3；脚本给的 `forward_plus` 只是渲染方法代理，须人工核对）。
2. 临时把 `project.godot` 的 `run/main_scene` 指向 `res://src/qa/probe_runner.tscn`，用 `--export-release`（或 debug，两轮分开）导出 Probe exe，测完改回 `src/main.tscn`。
3. **非 headless** 启动。每轮一个 `--round-id`，窗口 / 全屏 × 60 / 30fps 共 4 轮，互不混算：

   ```
   hollowkin_probe.exe -- --probe-auto --round-id=windowed_60_release --window-mode=windowed --fps-cap=60 --frame-samples=120 --warmup-frames=30
   ```

   全屏档改 `--window-mode=fullscreen`，30fps 档改 `--fps-cap=30`，并同步改 `round_id`。预热 ≥5s 后再触发；`--warmup-frames` 在脚本内剔除预热帧，**原始值不删除**。也可不传 `--probe-auto`，在窗口里点按钮。
4. 每轮取回两份文件：`user://hollowkin_probe_metrics_<round_id>.csv`（19 列汇总）与 `user://hollowkin_probe_metrics_raw_<round_id>.csv`（逐样本长表），连同 console 日志按 §4 命名归档，手工补齐 `MANUAL_REQUIRED` 字段。
5. 先跑 `python tools/qa/verify_probe_evidence.py <summary.csv> <metrics_raw.csv>`，要求 `RESULT: PASS`；再交主理人按 §5 六条核验。
6. 5 项 `blocked` 在 E1 资产到位前保持数值栏为空；`r3_total_frame_share` 不得拼部分和判 `pass`。
7. **核验通过 ≠ 自动翻转**：`CONCERNS → PASS` 属独立审批动作。

### 7.1 帧时间插桩与占帧纪律（v1.2）

Godot 4.3 反射核实的可用接口：`RenderingServer.viewport_set_measure_render_time()`、`viewport_get_measured_render_time_cpu/gpu()`、`Performance.TIME_FPS / RENDER_TOTAL_DRAW_CALLS_IN_FRAME`、`DisplayServer.WINDOW_MODE_* / VSYNC_*`。

- `probe_runner.gd` 在非 headless 下按 `--window-mode` 与 `--fps-cap` 设置窗口与 `Engine.max_fps`，逐帧采 GPU / CPU / 墙钟时间，剔除 `--warmup-frames` 后写入逐样本长表。
- headless 自动降级：`FRAME_CAPTURE_UNAVAILABLE|headless: no window, no GPU render timing`，**不填 0、不臆造样本**，19 列渲染项仍 `blocked`。
- 帧时间样本的 `load_kind` 恒为 `DEBUG_PLACEHOLDER_FRAME_NOT_A_BASELINE`：只写逐样本长表，**不产生 19 列汇总行、不参与 verdict**。当前瓦片 / 实体 / 粒子纹理都是运行时 debug 占位，测出的耗时不能充当 ADR-4 E1 正式负载的 GPU 帧预算。
- 本机受控试跑（非 headless，640×360，60fps 档）：`FRAME_CAPTURE|samples=60`、`frame_wall_ms≈16.6667`、GPU 样本全部非零；`verify_probe_evidence.py` 判 `RESULT: PASS`。该试跑 `round_id=instrument_smoke`、`build_sha=SMOKE_NOT_A_BASELINE`，**明确不是基线数据**，也未回填本表。

## 8. 已知限制

- **本机窗口能力已核实可用**（v1.2 更正）：console 会话活动、1920×1080 单屏、Vulkan Forward+ / NVIDIA MX450；非 headless 可创建窗口并读 GPU 帧时间。v1.1 中「本机无窗口 / 显示器」的判定有误，已更正；`--headless` 下渲染项仍恒 `blocked`。
- 当前负载是 `DEBUG_PLACEHOLDER`：5 项渲染 / 粒子指标仍 `BLOCKED-BY-ASSET`，帧时间只作链路证据、不进 19 列 `verdict`；ADR-4 E1 真实像素原图未产出。
- debug 与 release 模板均已安装，但本轮只导出 debug 构建做验证。
- `PROBE_BUILD_SHA` 仍为 `UNSET`，正式采集前必须填写或用 `--build-sha` 覆盖。
- `r3_total_frame_share` 在分项缺失时只能给部分和，不得判 `pass`。
- 战斗屏技能热区待注入 `CombatDirector`，帧时间负载尚未覆盖完整战斗画面。

---

*Wave 4 v1.2（2026-11-07）：在 v1.1 基础上补齐逐样本原始证据、帧时间插桩与分轮编排，并更正本机窗口能力判定；零新增基线测量数字、未翻转任何 CONCERNS。v1.1 随 Wave 3b/4 + `_adapt` 批次提交并推送（`a5c603a`，远端 CI 双绿）；**证据模板的数值栏仍全部为空，提交与 CI 全绿或插桩链路跑通都不构成 PC 基线实测数据**。*
