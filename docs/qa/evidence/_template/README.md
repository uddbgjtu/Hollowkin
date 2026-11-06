# PC 帧预算基线与证据模板（ADR-6 / Wave 2b）

> **状态**：模板就位，**零测量值**；R1 / R3 仍为 **CONCERNS**。
> **依据**：`docs/architecture/adr-006-pc-first.md`（Windows Desktop 单平台、移动端彻底放弃）。
> **历史参考**：`docs/qa/archive/r1r3-device-test-plan.md` 已归档，仅保留插桩方法学与统计口径，**不作为现行判据**。
> **采集工具**：`src/qa/probe_runner.tscn` + `tools/qa/r1r3_probe.gd`；导出预设 `export_presets.cfg`（Windows Desktop）。

---

## 0. 定位与诚实性约束

- 本目录用于 **PC 窗口 / 全屏基线**：目标 60fps，30fps 为下限档。每行数据均属【PC 基线 · 非移动端真机】，**不得回填到已归档的移动端真机表**。
- `measurement_template.csv` 共 **19 列 × 10 行**，数值栏全部为占位 `【PC 基线待实测】` 或 `—`；`target` 列是**目标预算（判据）不是测量值**。
- 严禁把 GUT tick 数、Python 仿真、headless 自检输出换算成设备 ms 耗时；严禁抄目标预算充当实测值。
- **R1 / R3 CONCERNS 不因平台变更、模板就位或归档自动翻转**（`architecture-doc.md §6`）；翻转须 PC 实测数据 + 核验签字 + 主理人独立审批。

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
| `evidence_path` | 原始证据相对路径 | 手工 / 脚本 |
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
| `r1_render_mean` / `r1_render_p95_spike` | **blocked** | `BLOCKED-BY-SCENE`：`TileMapLayer` 未落地（Wave 3） |
| `r3_entity_render` / `r3_particles` | **blocked** | `BLOCKED-BY-SCENE`：无场景 / MultiMesh / 屏外剔除 / 粒子层 |
| `r3_total_frame_share` | **blocked** | 分项缺失时**只能给部分和，不得判 `pass`** |

因 5 项渲染 / 粒子 / 合计占帧比仍缺前置依赖，**当前即使数据齐备也无法把 R1 / R3 翻成 PASS**。

## 3. 样本量下限与统计口径（沿用归档方法学）

- R1 生成逻辑 ≥ **100 层**；保底切换 ≥ **10 次**注入；降密度高 / 低档各 ≥ **30 次**。
- R3 输入仲裁 ≥ **100 帧**；AI tick ≥ **200 tick**；窗口与全屏、60fps 与 30fps 各单独一轮。
- 每轮启动后预热 ≥ 5s（着色器编译 / 资源导入），预热帧**不计入统计**。
- `mean` = 算术均值；`p95` = 升序第 `ceil(0.95N)` 个样本；保留原始样本 CSV 作为证据。

## 4. 证据目录与命名

```
docs/qa/evidence/<device_id>/<build_sha>/<metric>.csv
docs/qa/evidence/<device_id>/<build_sha>/metrics_raw.csv
```

一次提交只对应**一个 `device_id` + 一个 `build_sha` + 一种 `build_type`**。目录下 `.gdignore` 阻止 Godot 把 `.csv` 当翻译资源导入。

## 5. 核验规则（数据到齐后由主理人执行）

1. 机器规格与 `os_version` / `gpu_backend` 一致，且属于约定的 PC 基线档位；
2. `build_sha` 与被测构建一致、`godot_version=4.3.stable`、debug/release 未混算；
3. 单位统一 ms，`samples` 达 §3 下限，mean / p95 与原始样本可复算；
4. `verdict` 与数值及 `target` 一致，`blocked` 项数值栏为空；
5. `evidence_path` 指向真实存在的原始证据文件，轮次可对应；
6. 无任何臆造值；任何【PC 基线待实测】占位残留即退回。

核验通过后**先报主理人审批**才写入汇总；`architecture-doc.md §6` CONCERNS → PASS 是**独立审批动作**。

## 6. 已知会污染数据的偏差（未修）

`simulation_clock.gd::_adapt()` 以 `delta > 1/60` 判「超预算」，PC 掉帧至 30fps 时每帧必然命中、连续 30 帧后误降 5Hz，会污染 `r3_ai_tick`。Godot 4.3 headless 实跑已记录该偏差（30fps 600 帧得 104 tick，Python 记账基准期望 200），修复属生产代码改动，**须单独授权**；未修前请在提交中标注「构建未含 `_adapt` 修复」，按受限数据处理。

---

*本目录为 Wave 2b 产物：移动端 runbook 已归档、Android 导出预设已替换为 Windows Desktop 骨架。零新增测量数字、未翻转任何 CONCERNS、未执行 git commit。*
