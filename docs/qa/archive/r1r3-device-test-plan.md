# R1 / R3 真机测量计划与执行 Runbook（ENG-3）
> 🗄️ **归档声明（2026-11-06 · ADR-6 Wave 2b）**：本文件为 ENG-3 「iOS / Android 真机测量 runbook v1.1」，因用户裁决「移动端彻底放弃」（见 `docs/architecture/adr-006-pc-first.md`）而**停止执行、移入归档**。
> - 文中设备矩阵（Redmi 9A / Pixel 6a / iPhone SE）、§8「目标最低档 iOS/Android 真机」硬证据、§2/§3 的移动端判据**全部失效**，不再作为验收依据。
> - 保留全文（含插桩方法学、19 列回填模板、CONCERNS 关闭判据与 §7 的 `_adapt` 偏差记录）仅作**历史方法学参考**；文中所有数值仍为原值，未改写、未新增。
> - **R1 / R3 仍为 CONCERNS**（`docs/architecture/architecture-doc.md §6`）。ADR-6 后须改由 **PC 窗口 / 全屏基线**采集，独立 QA 表 + 实测数据 + 独立审批；**CONCERNS 不因归档或平台变更自动翻转**。
> - 现行证据模板见 `docs/qa/evidence/_template/`；采集工具见 `src/qa/probe_runner.tscn` 与 `tools/qa/r1r3_probe.gd`（已重定位为 PC 基线口径）。

---

> **项目**：《深窟兽语 / Hollowkin》（Godot 4.3，iOS / Android 触屏单手）
> **负责人**：程基岩（工程）+ 主理人
> **版本**：v1.1 · 已入库（2026-11-06 升级为可执行 runbook + 数据回填接口）
> **关联**：`docs/architecture/prototype-r1r3-report.md`（算法 / 记账级基准）、`docs/architecture/architecture-doc.md §6`（R1 / R3 CONCERNS）、`tests/unit/test_frame_budget.gd`（记账级断言）
> **当前状态**：真机数据**未到**；R1 / R3 保持 **CONCERNS**，未关闭。

---

## 0. 目的与性质声明

关闭架构自评审的 **R1 / R3 两项 CONCERNS**。v1.0 交付了「目标设备 + 指标 + 排期占位」；v1.1 把它升级为**可直接执行的 runbook**：每条指标补插桩点、采集字段、样本量、判定阈值、复现步骤与失败降级，并给出数据回填模板与核验规则。

- **本文件不含任何真机实测帧时间数字**。文中出现的数字只有两类：① feasibility 的**目标预算**（判据，非测量值）；② `prototype-r1r3-report.md` 中已由 Python 跑出的**算法级 / 记账级真实基准**（引用，非设备耗时）。
- 所有待采集项一律标【需真机实测】或【前置依赖未满足】；实测前禁止写入具体帧时间。
- 关闭 CONCERNS 的硬证据 = 目标最低档机型 + Godot 4.3 编辑器 / 导出构建实测报告（见 §6 / §8）。

### 0.1 v1.1 相对 v1.0 的新增边界

| 新增 | 内容 | 不改变 |
|---|---|---|
| §2 / §3 执行列 | 插桩点（真实生产函数）、采集字段·单位、样本量与统计口径、复现步骤、失败降级 | 目标预算数值、沙箱基准数值 |
| §4 | 步骤化 runbook（环境→构建→插桩→预热→采集→记录→复测→归档） | 排期占位仍为「待定 W1–W4」，不虚构日期 |
| §5 / §6 | 数据回填表模板、提交格式与核验规则（G4-03 数据接口） | 不代填任何数字 |
| §7 | 记账级实跑发现与前置依赖（渲染层 / `_adapt` 偏差） | 不擅自修生产代码 |
| §8 | CONCERNS 关闭判据与审批点 | 不自动翻转架构文档 §6 |

---

## 1. 目标设备清单与必填环境字段

| 档位 | 参考机型 | OS | 用途 |
|---|---|---|---|
| 低端 Android | Redmi 9A / Go 版设备 | Android 11+ | R1 渲染尖峰、R3 同帧预算下限 |
| 中端 Android | Pixel 6a | Android 13+ | 常规目标，对照低端差异 |
| 低端 iPhone | iPhone SE（2022，A15） | iOS 16+ | iOS 侧渲染 / 帧时间基线 |
| （可选）老旧 iPhone | iPhone 8 | iOS 15+ | iOS 低端边界 |

**每次采集必须随数据记录以下环境字段**（缺失任一 → 核验不通过，见 §6）：

| 字段 | 说明 |
|---|---|
| `device_id` | 机型 + 设备编号（如 `redmi9a_01`） |
| `os_version` / `gpu_backend` | 系统版本、渲染后端（Vulkan / GLES3） |
| `build_sha` | 被测构建的 git SHA，须与 `git rev-parse HEAD` 一致 |
| `godot_version` / `build_type` | 固定 `4.3.stable`；`debug` 或 `release`（两者不得混算） |
| `thermal_state` / `battery_pct` | 温控状态、电量；连续采集须记录首尾值 |
| `background_policy` | 后台应用清理 / 省电模式 / 网络状态，避免干扰 |

---

## 2. R1 指标执行表（地窟生成帧预算）

| 指标 | 目标预算 | 插桩点（生产模块真实函数） | 采集字段 / 单位 | 样本量与统计口径 | 复现步骤 | 失败降级与记录 |
|---|---|---|---|---|---|---|
| 单层生成逻辑耗时 | ≤ 1ms | `dungeon_generator.gd::generate_sync`、`room_stitcher.gd::build_rooms/build_corridors/build_enemies/build_loot` | `elapsed_us`（`Time.get_ticks_usec()` 差值）/ ms | ≥100 层，取均值与 P95（排序第 `ceil(0.95*N)`） | 固定 `(run_seed, floor_index, tier)` 连续进层，清 `floor_cache.gd` 缓存避免命中短路 | 超预算 → 记录分层耗时，检查是否缓存命中；不修改目标值 |
| 单层渲染（`set_cell` 批量）均摊 | ≤ 16.6ms | **【前置依赖未满足】** `TileMapLayer.set_cell` 尚未落地；`dungeon_generator.gd` 明确「不含瓦片渲染态」 | 帧时间 / ms（Profiler） | ≥30 次进层，每次 ≥100 帧，排除预热帧但记录不删除 | 对照「不分步 vs `generate_floor` 四段 `await process_frame` 让帧」 | 先标记 BLOCKED-BY-SCENE，待 `*.tscn` 场景集成后重测 |
| 渲染尖峰 | < 50ms（P95） | 同上（依赖场景层） | 进层峰值帧 / ms | ≥30 次进层取 P95 | 同上，记录峰值帧索引 | 超阈值 → 启用分步让帧 / 保底模板后复测并留证 |
| 保底模板切换 | 不阻断流程 | `fallback_template.gd::build`、`dungeon_generator.gd::generate_sync` 的非法 floor 分支 | 是否回退、耗时、有无卡死 / bool + ms | ≥10 次注入（floor <0 或 >9999） | 注入异常 / 越界 floor，观察回退与后续帧 | 卡死即 FAIL，附复现日志 |
| 低端机降密度生效 | 房间 / 敌人上限下调 | `room_stitcher.gd` 常量 `MAX_ROOMS_HIGH/LOW = 14/8`、`MAX_ENEMIES_HIGH/LOW = 24/12` | 房间数、敌人数、帧时间对比 / 个 + ms | 高 / 低档各 ≥30 次 | `OS.get_model_name()` 分支指定档位，同 seed 对比 | 低档未降载 → FAIL，记录分支判定依据 |
| 同 (seed, floor) 重建一致 | True | `dungeon_generator.gd::generate_sync` / `generate_floor` | 布局 JSON 逐字节比对 / bool | 已有 GUT 用例覆盖（沙箱已实测 True） | 复跑重建比对 | 不一致即阻断（ADR-1） |

> **既有真实基准（引用，非本次采集）**：`prototype-r1r3-report.md §2.3` 的 Python 算法级实测 HIGH `0.0786ms` / LOW `0.0631ms` 单层、重建一致 True。它是**纯逻辑**耗时，不含 Godot 渲染开销；不得当作上表渲染项的实测值。

---

## 3. R3 指标执行表（触屏 + AI 同帧预算）

| 子系统 | 60fps / 30fps 目标预算 | 插桩点（生产模块真实函数） | 采集字段 / 单位 | 样本量与统计口径 | 复现步骤 | 失败降级与记录 |
|---|---|---|---|---|---|---|
| 输入仲裁（ADR-2 队列） | < 0.5ms / < 1.0ms | `input_queue.gd::consume_into`，配合 `hit_zone.gd::resolve` | `elapsed_us` / ms；队列事件数 | ≥100 帧连续，取均值与 P95 | 同热区多事件 + 跨 tick 重触发（0.5s cd 钳） | 超预算 → 检查去重 / cd 分支是否重复结算 |
| AI tick（ADR-3 10Hz） | ~1.66ms / ~3.3ms | `simulation_clock.gd::_tick`（含 `advance_time` + `consume_into`）、`combat_director.gd::step_simulation` | 单 tick `elapsed_us` / ms；当前 `is_slow()` 状态 | ≥200 tick，分别统计 10Hz / 5Hz 态 | 稳态 60fps 与 30fps 各跑 10s，再注入连续超预算帧触发降频 | 超预算 → 核对 §7 的 `_adapt` 已知偏差，避免把误降频当成有效缓解 |
| 实体渲染（同屏 ≤12） | < 4ms / < 8ms | **【前置依赖未满足】** 场景 / MultiMesh / `VisibleOnScreenNotifier2D` 尚未落地 | draw call 数、GPU 时间 / ms | ≥100 帧，同屏 12 敌人 | 压到 12 上限，对比屏外剔除开关 | 标记 BLOCKED-BY-SCENE |
| 粒子 / 特效 | < 3ms / < 6ms | **【前置依赖未满足】** 粒子系统尚未落地 | 粒子数、开销 / ms | ≥100 帧 | 低档降密度对照 | 标记 BLOCKED-BY-SCENE |
| 合计占帧比（60fps） | < 9.16ms（55%） | 各分项求和 | 分项求和 / ms | 与上述同批次 | 同批次数据求和，不得跨设备 / 跨构建拼接 | 超标 → 记录最大贡献项，交工程整改后复测 |

> **既有真实基准（引用，非本次采集）**：Python 记账级仿真曾给出「60fps→99 tick/10s、30fps→200 tick/20s」并称跨帧率一致。**2026-11-06 的 Godot headless 实跑证明该结论不适用于 GDScript 实现**，详见 §7；不得把 tick 数换算成 ms 预算结论。

---

## 4. 执行 Runbook（步骤化，真机现场按序执行）

1. **环境准备**：借调 §1 设备；安装 Godot 4.3 编辑器 + 对应导出模板；记录全部环境字段与 `build_sha`。
2. **构建**：同一 SHA 分别导出 `debug`（便于 Profiler 插桩）与 `release`（性能判定以 release 为准），两套数据分开归档，禁止混算。
3. **插桩**：按 §2 / §3 的插桩点，在入口 / 出口取 `Time.get_ticks_usec()` 差值；渲染 / GPU 项用 Godot Profiler。插桩代码**不得**留在最终发布构建中（单独分支或编译期开关）。
4. **预热**：启动后预热 ≥5s，完成着色器编译与资源导入；预热帧单独标记，不纳入统计但保留原始记录。
5. **采集**：按各指标样本量连续采集；同批次固定 seed / floor / 同屏实体数；记录导热与电量首尾值。
6. **记录**：逐样本写入 CSV（表头见 §5），同步保存 Profiler 截图 / 日志到证据路径；异常帧保留原值并标注，不删除。
7. **复测**：每个档位至少复测 1 轮（不同时间 / 不同设备实例）；两轮差异显著时追加第 3 轮并说明。
8. **归档与提交**：按 §6 命名证据文件，填好核验清单后提交给主理人；**未经核验与审批不得写入 §5 回填表或翻转架构文档 §6**。

---

## 5. 数据回填表模板（数值栏保持空）

**CSV 表头**（每条指标一行；数值字段一律留空并标 `【需真机实测】`）：

```csv
device_id,os_version,gpu_backend,build_sha,godot_version,build_type,thermal_state,battery_pct,background_policy,metric,unit,samples,mean,p95,target,verdict,evidence_path,measured_at,operator
```

**回填表（当前为空模板，禁止代填）**：

| metric | unit | samples | mean | p95 | target | verdict | evidence_path | device_id / build_sha |
|---|---|---|---|---|---|---|---|---|
| r1_logic_elapsed | ms | 【需真机实测】 | 【需真机实测】 | 【需真机实测】 | ≤ 1 | 【需真机实测】 | 【需真机实测】 | 【需真机实测】 |
| r1_render_mean | ms | 【需真机实测】 | 【需真机实测】 | 【需真机实测】 | ≤ 16.6 | 【前置依赖未满足】 | — | — |
| r1_render_p95_spike | ms | 【需真机实测】 | 【需真机实测】 | 【需真机实测】 | < 50 | 【前置依赖未满足】 | — | — |
| r1_fallback_switch | bool + ms | 【需真机实测】 | 【需真机实测】 | — | 不阻断流程 | 【需真机实测】 | 【需真机实测】 | 【需真机实测】 |
| r1_low_tier_density | 个 + ms | 【需真机实测】 | 【需真机实测】 | — | 上限下调 | 【需真机实测】 | 【需真机实测】 | 【需真机实测】 |
| r3_input_arbitration | ms | 【需真机实测】 | 【需真机实测】 | 【需真机实测】 | < 0.5 / < 1.0 | 【需真机实测】 | 【需真机实测】 | 【需真机实测】 |
| r3_ai_tick | ms | 【需真机实测】 | 【需真机实测】 | 【需真机实测】 | ~1.66 / ~3.3 | 【需真机实测】 | 【需真机实测】 | 【需真机实测】 |
| r3_entity_render | ms | 【需真机实测】 | 【需真机实测】 | 【需真机实测】 | < 4 / < 8 | 【前置依赖未满足】 | — | — |
| r3_particles | ms | 【需真机实测】 | 【需真机实测】 | 【需真机实测】 | < 3 / < 6 | 【前置依赖未满足】 | — | — |
| r3_total_frame_share | ms | 【需真机实测】 | 【需真机实测】 | — | < 9.16（55%） | 【需真机实测】 | 【需真机实测】 | 【需真机实测】 |

> `verdict` 只允许 `pass` / `fail` / `blocked`；`blocked` 须在备注写明前置依赖（如场景层未落地）。

---

## 6. 数据接收与核验规则（G4-03 接口）

**提交格式**：§5 的 CSV（每行一指标）+ 原始 Profiler / 日志证据 + 环境字段清单；一次提交对应一个 `device_id` 与一个 `build_sha`。

**证据路径约定**：`docs/qa/evidence/<device_id>/<build_sha>/<metric>.csv`（或 `.log` / `.png`），文件须可读、可追溯到采集轮次。

**核验清单（任一不通过 → 退回，不回填）**：
1. 机型在 §1 清单内，或附等价性说明（CPU/GPU/OS 对照）。
2. `build_sha` 与被测构建一致；`godot_version` = 4.3；`build_type` 明确且未跨类型混算。
3. 单位统一为 ms（微秒原始值须换算并保留原始列）；`mean` / `p95` 齐全，`samples` 达 §2 / §3 下限。
4. `verdict` 与数值一致；`pass` 必须与 `target` 比较得出，`blocked` 须注明依赖。
5. 证据文件存在且与表格行数 / 轮次对应；异常帧保留原值并有标注。
6. **禁止**：把目标预算抄进 `mean` / `p95`；把 Python 仿真或 GUT 记账值冒充设备耗时；无证据的 `pass`。

**回填流程**：核验人按上述清单签字 → 主理人审批 → 才写入 §5 表与 `architecture-doc.md §6`。**CONCERNS 翻转是独立审批动作，本文件不自动执行。**

---

## 7. 记账级实跑发现与前置依赖（2026-11-06，质量门记录）

> 本节记录的是**本地 headless 真实实跑**结论，属【记账级】，不是真机帧时间；用于提示真机测量前的阻塞项。

1. **`simulation_clock.gd::_adapt()` 跨帧率误判（待修，需另行审批）**：实现以 `delta > 1/60` 判「超预算」，30fps 每帧 `1/30` 必然命中，连续 30 帧后误降 5Hz（`TICK_DT_SLOW=0.2`）。Godot 4.3 headless 实跑：30fps 600 帧（20s）得 **104 tick**，而 Python 记账基准期望 200；10s 墙钟对比 60fps **99 tick** vs 30fps **54 tick**。仿真步长总量仍近似守恒，但 tick 频率不守恒。影响：低端 30fps 设备（R3 目标档）被误判降载。已在 `tests/unit/test_frame_budget.gd` 用「已知偏差探测」用例如实锁定当前行为，未把缺陷写成期望。建议修复方向：以插桩的真实单帧耗时判超预算，区分「帧间隔长」与「单帧计算超时」；修复后把两个用例断言改回 200 tick / 跨帧率相等，再执行 §3 的 AI tick 真机测量，否则降频态会污染数据。
2. **渲染 / 粒子层未落地**：`dungeon_generator.gd` 只产逻辑网格 + 实体表，明确不含瓦片渲染态；`*.tscn` 场景、MultiMesh、屏外剔除、粒子系统尚未实现（见 `epic-breakdown.md §12.6` 开放项 3）。因此 §2 / §3 中标记【前置依赖未满足】的项目当前**不可测**，须待可玩 MVP 集成后重排期。
3. **可立即测的分项**：R1 生成逻辑耗时、保底切换、降密度分支；R3 输入仲裁、AI tick 耗时——这些插桩点已在生产模块存在，只差目标真机与 Godot 编辑器 / 导出构建。

---

## 8. CONCERNS 关闭判据（质量门）

| 判定 | 条件 | 当前 |
|---|---|---|
| **PASS** | §2 的 R1 全部硬指标（含渲染尖峰 / 均摊 / 保底 / 降密度）与 §3 的 R3 全部分项均有合格数据、`verdict=pass`、证据齐全、核验签字完成 | 否 |
| **CONCERNS** | 数据未齐 / 场景层前置依赖未满足 / §7 的 `_adapt` 偏差未裁定 | **是（当前状态）** |
| **FAIL** | 任一硬指标超预算且缓解措施复测无效 → 交工程整改并重新走 §4 | 否 |

- 翻转动作：由主理人 / 用户审批后修改 `architecture-doc.md §6` 与 `epic-breakdown.md §12`；**本文件不代为执行**。
- 排期仍为占位「待定 W1–W4」（v1.0 原表），不虚构具体日期；设备到位后再落实际日期。

---

## 9. 诚实性约束（强制）

- 本文件**零新增真机帧时间数字**；所有数值列为目标预算或已引用的沙箱算法 / 记账级基准。
- 所有【需真机实测】项在实测前禁止写入具体帧时间；所有【前置依赖未满足】项禁止标 `pass`。
- 不把 tick 计数、Python 仿真或 GUT 断言换算成设备 ms 耗时；不因 CI 全绿而视为 R1 / R3 已闭环。
- 沙箱已实测值见 `prototype-r1r3-report.md §4` 分层标注，本计划引用而非重测。
- 生产代码修复（§7 第 1 条）与 CONCERNS 翻转均为独立审批动作，不在本次文档升级范围内。

---

*本文件为 ENG-3 真机测量计划 v1.1（可执行 runbook + 数据回填接口），已入库。真机数据未到，R1 / R3 保持 CONCERNS；未编造任何设备测量数据。*
