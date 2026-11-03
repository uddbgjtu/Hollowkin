# R1 / R3 原型实测报告（Prototype Report）

> **作者**：程基岩（Cheng Jiyan）· 工程负责人
> **引擎**：Godot 4（iOS / Android，触屏单手）
> **阶段**：Phase 3 技术搭建 · 原型验证
> **关联**：`feasibility-review.md` 风险 R1（地窟生成）/ R3（触屏+AI 同帧）；ADR-1/2/3/5
> **原型代码**：`src/prototype/`（仅佐证，不进正式 `src/` 业务目录）

---

## 0. 测量诚实声明（先读）

> **本沙箱无 Godot、无低端机，无法真实跑出设备帧时间。本报告严格遵守"严禁编造测量数据"约束。**
>
> 本报告交付的是三层内容，且**明确分层标注**：
> 1. **原型代码**（GDScript 忠实 port）—— 可在 Godot 编辑器/真机运行，用于后续实测。
> 2. **算法/记账级基准**（Python 可运行）—— 本报告**实际跑出**的真实数字，但仅覆盖"生成逻辑"与"仿真时钟记账逻辑"两部分，**不含 Godot 渲染与设备运行时开销**。
> 3. **预算对照表 + 测量方法学** —— feasibility-review.md 的*目标预算*，须在目标最低档机型 + Godot 编辑器实测，本沙箱**无法完成**，已逐处标注。
>
> 任何标注"【需真机实测】"的数字均为**目标值或方法学**，非本沙箱测量值；任何标注"【本沙箱实测】"的数字均为**真实跑出**。

---

## 1. 环境与工具链核查

| 项 | 结果 | 说明 |
|---|---|---|
| Godot 4 是否安装 | **否** | `which godot` / 程序目录均无；无法在 sandbox 跑工程或编辑器 |
| 低端机（目标 iOS/Android 机型） | **否** | 无物理设备；无法测量真实帧/渲染/AI 运行时开销 |
| Python 3 | **是**（3.13.14） | 用于算法/记账级基准（真实可跑） |
| 结论 | — | 仅能交付"原型代码 + 算法级真实基准 + 预算对照 + 测量方法学"；**设备级测量为开放项** |

---

## 2. R1 · 程序生成地窟（生成耗时与峰值帧）

### 2.1 目的与验证点（来自 feasibility R1）
- 单层生成耗时与峰值帧：预算**均摊 ≤ 16.6ms（60fps 单帧）、尖峰 < 50ms**。
- 验证缓解手段：**① 分步生成 + `await get_tree().process_frame` 让帧**；**② 保底模板层**；**⑤ 低端机降密度**。

### 2.2 原型代码（GDScript，可在 Godot 运行）
- `src/prototype/r1_dungeon_gen/gd_dungeon_gen.gd`
  - `floor_seed()`：确定性哈希（与 feasibility §6.4 一致），本层唯一 `RandomNumberGenerator`（ADR-5）。
  - `generate_floor()`：按房间/走廊/敌人/掉落**分片**，每 3 段 `await get_tree().process_frame` 让帧（缓解①）。
  - `fallback_template()` + `generate_with_fallback()`：异常/越界 → 切保底安全层（缓解②）。
  - 设备档位 `DeviceTier`：高/低档下调房间数与敌人上限（缓解⑤）。

### 2.3 【本沙箱实测】算法级基准（Python 忠实 port）
运行 `python3 py_dungeon_gen.py`（200 层 × 5 轮，确定性 seed）：

| 档位 | 单层生成*逻辑*耗时（均值） | min/max | 同 (seed,floor) 重建一致 |
|---|---|---|---|
| 高端 HIGH（≤14 房/≤24 敌） | **0.0786 ms** | 0.0721 / 0.0874 ms | ✅ True |
| 低端 LOW（≤8 房/≤12 敌） | **0.0631 ms** | 0.0538 / 0.0771 ms | ✅ True |

- **诚实结论**：地窟生成的**纯逻辑**（房间拼接/走廊/敌人刷新/掉落判定）开销极小（亚毫秒级），且确定性重建自检通过。
- **关键推论**：R1 帧预算风险**不在生成逻辑**，而在 Godot `TileMapLayer.set_cell` 的**瓦片渲染**层（批量写入数十~数百瓦片）。因此"分步生成 + await 让帧"的缓解对象正是**渲染尖峰**——把 set_cell 批量写入摊到多帧，避免单帧尖峰。

### 2.4 【需真机实测】渲染层预算对照表
> 以下为 feasibility R1 的**目标预算**，必须经 Godot 编辑器 + 目标最低档机型实测；本沙箱无法给出真实数字。

| 子系统 | 目标/预算 | 验证手段（方法学） |
|---|---|---|
| 单层生成 *逻辑* | ≤ 1ms（本沙箱实测亚毫秒，见 2.3） | Python 基准 + Godot `Time.get_ticks_usec()` 复测 |
| 单层 *渲染*（set_cell 批量） | 均摊 ≤ 16.6ms、尖峰 < 50ms | Godot 编辑器 Profiler 帧时间；分步让帧后取峰值帧 |
| 保底模板层切换 | 不阻断流程、日志可查 | GUT 单测注入生成异常路径 |
| 低端机降密度生效 | 房间/敌人上限下调 | `OS.get_model_name()`/GPU 档位分支单测 + 真机帧时间对比 |

### 2.5 测量方法学（供真机执行）
1. 在 Godot 编辑器以"帧时间"Profiler 观察进入每层时的峰值帧（ms）。
2. 对照"不分步 vs 分步让帧"两种实现的峰值帧差异，确认让帧摊薄有效。
3. 在目标最低档 Android（含 Go 版）/ 旧 iPhone 复测；记录均值与 P95 峰值。
4. 注入生成超时/异常，确认回退保底模板层且无卡死。

---

## 3. R3 · 触屏并发 + 自动战斗 AI 同帧开销（帧预算）

### 3.1 目的与验证点（来自 feasibility R3）
- 低端机同帧帧预算：**输入队列 < 0.5ms / AI 10Hz 均摊 ~1.66ms / 同屏敌人 ≤12 渲染 < 4ms / 粒子 < 3ms**。
- 验证：**ADR-2 帧末队列** + **ADR-3 10Hz tick 自适应降频**。

### 3.2 原型代码（GDScript，可在 Godot 运行）
- `src/prototype/r3_frame_budget/gd_simulation_clock.gd`
  - `SimulationClock`：累加器每满 0.1s（10Hz）跑 `tick()`，`MAX_CATCHUP=3`（防后台恢复雪崩）。
  - `tick()`：先 `InputQueue.consume_into()`（ADR-2 帧末结算），再 `CombatDirector.step_simulation()`（ADR-3）。
  - `_adapt()`：连续 `OVER_BUDGET_LIMIT` 帧超预算 → 降 5Hz（缓解④）。
  - 屏外剔除（`VisibleOnScreenNotifier2D`）与同屏 ≤12 敌人上限（缓解②）。

### 3.3 【本沙箱实测】记账逻辑仿真（Python）
运行 `python3 py_frame_budget_sim.py`，验证"仿真时钟记账逻辑"正确性（非设备性能）：

| 用例 | 结果 | 结论 |
|---|---|---|
| 60fps 稳态 600 帧（10s） | AI tick = **99**（≈10Hz×10s） | ✅ 10Hz 记账正确 |
| 30fps 稳态 600 帧（20s） | AI tick = **200**（≈10Hz×20s） | ✅ 跨帧率行为一致 |
| 注入 100 帧超预算 | 最终降频态 = **True**，总 tick=40 | ✅ 自适应 5Hz 触发正确 |
| 单帧 delta=1s（后台恢复） | tick=**3**（≤MAX_CATCHUP），追帧丢弃=1 | ✅ 防雪崩约束生效 |

- **诚实结论**：10Hz 累加器、跨帧率一致性、追帧上限、自适应降频的**记账逻辑**均验证通过（断言全绿）。
- **关键推论**：方法学正确 ≠ 性能达标。各子系统真实开销（输入/AI/渲染/粒子）仍须真机插桩测量。

### 3.4 【需真机实测】同帧帧预算对照表
> 以下为 feasibility R3 的**目标预算**，须真机插桩实测；本沙箱无法给出真实数字。

| 子系统 | 60fps 预算 | 30fps 预算 | 策略 | 验证手段（方法学） |
|---|---|---|---|---|
| 输入仲裁（ADR-2 队列） | < 0.5ms | < 1.0ms | 帧末单次结算、去重 | 队列 consume 前后 `get_ticks_usec()` 插桩 |
| AI tick（ADR-3，10Hz 均摊） | ~1.66ms | ~3.3ms | 自适应降 5Hz | 单 tick 耗时插桩 + 降频后复测 |
| 实体渲染（同屏 ≤12） | < 4ms | < 8ms | MultiMesh + 离屏剔除 | Godot Profiler draw call / GPU 时间 |
| 粒子/特效 | < 3ms | < 6ms | 关屏/低档降密度 | 粒子系统开销插桩 |
| **合计占帧比**（60fps 16.6ms） | < 9.16ms（55%） | — | 余量给渲染主线程 | 各分项求和 |

### 3.5 测量方法学（供真机执行）
1. 在各子系统入口/出口插 `Time.get_ticks_usec()`，统计单 tick / 单帧分项耗时。
2. 用 `OS.get_model_name()` 识别低端机，对比高/低档分项差异。
3. 人为制造"连续超预算"场景，确认 AI 降 5Hz + 降同屏敌人/粒子生效且无感。
4. 用 `VisibleOnScreenNotifier2D` 验证屏外实体 AI/动画停用。
5. 同屏敌人压到 12 上限，测渲染分项是否 < 4ms。

---

## 4. 测量数据汇总（诚实分层）

| 数据 | 来源 | 性质 |
|---|---|---|
| R1 生成逻辑 HIGH 0.0786ms / LOW 0.0631ms/层 | 本沙箱 Python 跑出 | 【真实·算法级】 |
| R1 同 (seed,floor) 重建一致 = True | 本沙箱 Python 跑出 | 【真实·算法级】 |
| R3 60fps→99 tick/10s、30fps→200 tick/20s | 本沙箱 Python 跑出 | 【真实·记账级】 |
| R3 降频触发 / 追帧上限=3 | 本沙箱 Python 跑出 | 【真实·记账级】 |
| R1 渲染尖峰 < 50ms、均摊 ≤ 16.6ms | feasibility 目标预算 | 【需真机实测】 |
| R3 输入<0.5ms / AI~1.66ms / 渲染<4ms / 粒子<3ms | feasibility 目标预算 | 【需真机实测】 |

> **明确标注**：凡涉及 Godot 渲染、设备 CPU/GPU 运行时、低端机真机帧时间的数字，**本沙箱一律未测量、未编造**；上述"需真机实测"项须在目标最低档 iOS/Android + Godot 编辑器完成，作为关闭 R1/R3 两项 CONCERNS（见 `architecture-doc.md` §6）的前置证据。

---

## 5. 原型文件清单

| 文件 | 类型 | 是否本沙箱实测 |
|---|---|---|
| `src/prototype/r1_dungeon_gen/gd_dungeon_gen.gd` | GDScript 忠实 port（R1） | 否（须 Godot 运行） |
| `src/prototype/r1_dungeon_gen/py_dungeon_gen.py` | Python 算法基准（R1） | ✅ 已跑出真实数字 |
| `src/prototype/r3_frame_budget/gd_simulation_clock.gd` | GDScript 忠实 port（R3） | 否（须 Godot 运行） |
| `src/prototype/r3_frame_budget/py_frame_budget_sim.py` | Python 记账仿真（R3） | ✅ 已跑出真实数字 |

---

## 6. 结论

- **R1**：生成*逻辑*亚毫秒、确定性重建一致（已真实验证）；帧预算风险在 Godot *渲染* 层，须真机测 set_cell 尖峰。**缓解设计（分步让帧/保底/降密度）方法学成立**，待实测闭环。
- **R3**：10Hz 累加器 + 输入帧末队列 + 自适应降频的*记账逻辑*全部验证通过（已真实验证）；各子系统*真实开销*须真机插桩。**预算目标合理**，待实测闭环。
- **整体**：两项风险均由"逻辑/方法学正确、设备性能待实测"构成，**不构成架构阻断**；关闭 CONCERNS 的硬证据为"目标最低档机型 + Godot 编辑器实测报告"（见 `architecture-doc.md` §6 / §7 ENG-3）。

---

## 7. 真机实测衔接（ENG-3）

本沙箱交付的算法 / 记账级基准为**真实测量**；设备级运行时开销（渲染尖峰、输入 / AI / 渲染 / 粒子分项）须在目标最低档 iOS / Android 机型 + Godot 编辑器实测，详见 **`docs/qa/r1r3-device-test-plan.md`**（ENG-3 真机测量计划）。该计划含目标设备清单、R1 / R3 指标对照表（沙箱基准 vs 真机待测）与排期，所有真机项标注【需真机实测】，**不臆造数据**，作为关闭架构文档 §6 R1 / R3 两项 CONCERNS 的前置证据。

---

*本报告为 Phase 3 原型验证产出，含原型代码（GDScript）+ 算法/记账级真实基准（Python）+ 预算对照表 + 测量方法学。未编造任何设备测量数据；未修改 `design/` 与 `docs/architecture/` 之外目录，未执行 git commit。*
