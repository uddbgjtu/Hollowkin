# 《深窟兽语 / Hollowkin》主架构文档（Architecture）

> **作者**：程基岩（Cheng Jiyan）· 工程负责人 / 引擎架构
> **引擎**：Godot 4.3（**目标平台 Windows Desktop / PC 单平台**；移动端 iOS / Android 已彻底放弃，见 ADR-6；次版本已签字冻结，见 `CLAUDE.md` §2）
> **平台契约**：`docs/architecture/adr-006-pc-first.md`（ADR-6 · 2026-11-06 用户批准）
> **版本**：v1.1 · 2026-11-06 按 ADR-6 更新平台口径；架构模块 / ADR×5 / C1 / 自评审结论保持不变
> **阶段**：Phase 3 技术搭建（基于 Phase 2 技术可行性评审 `feasibility-review.md` 的 ADR×5 落地）
> **输入文档**：`feasibility-review.md`（ADR×5）、`concept-doc.md`、`combat-system-gdd.md`、`spirit-pouch-gdd.md`、`spirit-vein-gdd.md`、`mvp-spirit-bestiary.md` v1.2、`art-bible.md` v0.2、`accessibility-requirements.md` v1.0
> **定位**：本文是 Phase 3 实现的**顶层架构真源**，定义模块边界、依赖、运行时数据流，并把每条 ADR 落到具体模块/文件。所有实现须以本文为纲。

---

## 0. 设计原则（架构红线）

1. **RNG 单一出口**——任何随机性（生成、掉落、战斗方差）一律经 `RNGService` 派生的种子化实例，禁绝 `randf()`/`randi()` 全局随机（ADR-5）。这是 ADR-1 存档可重建的硬前提。
2. **仿真与表现解耦**——输入帧末队列结算（ADR-2）、AI 固定 10Hz tick（ADR-3）、移动/动画逐帧插值；三者互不抢占，30/60fps 行为一致。
3. **StatBlock 单一真源**——`FinalStat = (Base + ΣVeinAdd) × ΠRuneMult`（C1 契约），灵脉加算聚合、符文独立乘区，run 起始算一次基底、符文变动重算乘区，每击 O(1)。
4. **存档极小 + 层间硬存档**——仅存 `run_seed + floor + 事件日志`；层内中断=放弃本层（E-A 已拍板，见 §6）；永久进度激活即存（灵脉 GDD §5）。
5. **资产离线脚本唯一出口**——AI→像素化→≤16 色索引→描边→抖动全由脚本完成，Godot 导入预设关 filter/mipmap，防偏色（ADR-4）。
6. **PC 键鼠可达优先（ADR-6）**——所有可点元素点击区域 ≥24×24px 且全功能键盘可达 / 键位可重映射（a11y §3.2 已重订）；形状+颜色双编码（a11y §3.1）**不变**。原「单手触屏 / ≥48px 触控命中区」红线已废止。

---

## 1. 模块划分

> 8 个业务模块 + 2 个跨切核心服务。括号内为**规划路径**（Phase 3 实现落点，本文为首次引入，非既有文件）；"关联 ADR"标注该模块承载的架构决策。

### 1.1 地窟生成（DungeonGen）`src/core/dungeon_gen/`
- **职责**：按 `(run_seed, floor_index)` 确定性重建地窟布局——房间拼接（`room_stitcher`）、敌人模板挑选、掉落表抽取。**不含瓦片渲染状态**（渲染交 Godot `TileMapLayer`，生成只产出逻辑网格+实体放置表）。
- **关键文件（实）**：`dungeon_generator.gd`（入口，调 `RNGService.floor_rng`）、`room_stitcher.gd`（确定性核心）、`floor_cache.gd`（同 run 内 (seed,floor) 布局缓存）、`fallback_template.gd`（保底安全层）。
- **关键约束**：
  - 全随机源走本层 `RandomNumberGenerator` 实例（ADR-5）。
  - **分步生成 + `await get_tree().process_frame` 让帧**（R1 缓解 1），按房间/区域分片跨帧写入，避免单帧尖峰。
  - 生成超时/异常 → 切 `fallback_template`，不阻断流程（战斗 GDD §6 边界 2）。
  - 低端机依档位下调房间数/敌人上限（R1 缓解 5）。
- **关联 ADR**：ADR-5（种子化）、ADR-1（布局重建）。

### 1.2 战斗（Combat）`src/gameplay/combat/`
- **职责**：地窟内实时战斗仿真——自动普攻、`CombatDirector.step_simulation(TICK_DT)` 锁敌/伤害结算、技能运行时（点按/滑动）、灵兽协战调用、死亡/元进度结算。
- **关键文件（拟）**：`combat_director.gd`（每 tick 调一次）、`damage_calc.gd`（伤害公式）、`skill_runtime.gd`、`death_settlement.gd`（coin_temp→ember_eternal，C3：转化率 30%、任何 run 结束均触发）。
- **关键约束**：
  - 伤害公式 `Final = clamp(Mitigated × CritMult × RuneMult × Variance, 1, 99999)`（战斗 GDD §3.5）。
  - 战斗方差（Variance ∈ [0.90,1.10]）取**本层 RNG**（ADR-5，瞬时结果不进存档）。
  - `step_simulation` 由 SimulationClock 在 10Hz tick 内调用（ADR-3），非每帧。
  - 读 `StatBlock.final_stat()` 取每击最终值（O(1)）。
- **关联 ADR**：ADR-5（战斗方差）、ADR-3（tick 驱动）、C1（RuneMult）。

### 1.3 灵囊（Pouch）`src/gameplay/pouch/`
- **职责**：三栏（灵兽/符文/物资）自动分拣、符文镶嵌（提供乘区因子）、队伍编制（party_slots=3）、货币（coin_temp/ember_eternal）。持有本局符文集，喂给 `StatBlock` 的乘区。
- **关键文件（实）**：`pouch.gd`、`spirit_entry.gd`、`rune_entry.gd`（字段 `mult:{stat:factor}`，对齐 C1）、`party_manager.gd`、`bestiary.gd`（图鉴解锁，Epic D 已落）。
- **关键约束**：
  - 符文条目字段 **`mult:{stat:factor}`**（乘算，**非** `mods:{stat:delta}` 加算）——已与 C1 对齐（灵囊 GDD §3 已修订）。
  - 重复灵兽蛋：同 species 标记 +1 计数（设计侧拍板默认，见 §6）。
  - 镶嵌/卸下时触发 `StatBlock.recompute_rune_mult()`。
  - 灵兽 slug 唯一映射取自 bestiary v1.2：`mossback/emberhorn/frostling/voltsprite`（+ 主角 `tamer`）。
- **关联 ADR**：C1（乘区契约）。

### 1.4 灵脉图谱（SpiritVein）`src/gameplay/spirit_vein/`
- **职责**：永久元进度 DAG——节点激活（MODIFY_STAT/UNLOCK_SKILL/GRANT_START）、`ember_eternal` 消耗、run 起始属性快照（Base+ΣVeinAdd 算一次）、激活即时持久化。
- **关键文件（实）**：`vein_graph.gd`（DAG 静态校验、构建期断言无环）、`vein_node.gd`、`run_snapshot.gd`（run 起始聚合基底，Epic D 已落）。
- **关键约束**：
  - 节点激活即时写 `save_meta.cfg`（灵脉 GDD §5，即时存档点）。
  - `run_snapshot` 在进地窟时把灵脉修正后的基础属性喂给 `StatBlock.build_run_base()`。
  - DAG 构建期断言（R4 缓解，无热点）。
- **关联 ADR**：ADR-1（永久快照独立）、C1（加算基底）。

### 1.5 存档（Save）`src/core/save/`
- **职责**：`save_run.cfg`（种子+层号+事件日志）、`save_meta.cfg`（ember+节点激活）。仅层间硬存档点写入（E-A）；`NOTIFICATION_APPLICATION_PAUSED` 同步落盘；损坏→回退庇护所（永久进度独立）。
- **关键文件（实）**：`src/core/save/save_service.gd`（承载 ADR-1；层间落盘 `user://save_run.cfg` / `user://save_meta.cfg`）。事件日志以 `Array` 内嵌于 `save_run.cfg`（`event_log` 字段），预留将来升为独立 append-only 命令日志的空间。
- **关键约束**：
  - run 存档体积极小（种子+层号+短日志 ≈ 数百字节）；永久快照 ≈ 数 KB。
  - 读档异常 → 丢弃 run、回庇护所（ADR-1 损坏回退）。
  - 须结合 `NOTIFICATION_WM_CLOSE_REQUEST` 双保险（R2 知识缺口：PC 进程被强杀 / 断电时 `paused` 未必触发；ADR-6 已把原 iOS 后台强杀风险改述为 PC 等价场景）。
- **关联 ADR**：ADR-1（核心落地）、ADR-5（重建依赖）。

### 1.6 输入仲裁（InputArbiter）`src/gameplay/input/`
- **职责**：`InputQueue`（RefCounted 单例）收集**所有输入事件的同构字典** `{"position": Vector2, "touch_id": int}`，**帧末结算**；`HitZone` 热区注册表（固定热区独立命中、去重、cd 下限 0.5s）。
- **关键文件（拟）**：`input_queue.gd`、`hit_zone.gd`、`joystick_pointer.gd`；PC 侧新增 `pc_input_adapter.gd`（键盘 / 鼠标事件 → 同构字典，属 Wave 3）。
- **关键约束**：
  - 所有输入入队，不立即改仿真（ADR-2）——**队列语义不变**。
  - 键盘方向 / 鼠标左键 / 技能键位各自映射到固定热区 id，互不抢占；原「浮杆独占单一 `touch_id`」在 PC 下退化为键位状态，逻辑保留。
  - 每 tick 消费一次队列、按热区归并、技能去重（战斗 GDD §6.4）。
  - `touch_id` 字段保留为**兼容标识**（PC 恒为 0），不再承担 iOS/Android 指序仲裁职责。
- **关联 ADR**：ADR-2（核心落地）、ADR-6（平台适配层）。

### 1.7 灵兽 AI（SpiritAI）`src/gameplay/ai/`
- **职责**：`SimulationClock`（10Hz 累加器时钟、MAX_CATCHUP=3）驱动 `tick()`——锁敌/寻路/技能释放/协战决策/伤害结算；移动/动画逐帧插值（读 AI 给出的目标/方向）；省电自适应（连续超预算降 5Hz、后台暂停）。
- **关键文件（拟）**：`simulation_clock.gd`、`spirit_ai.gd`（灵兽协战）、`enemy_ai.gd`（杂兵/精英/Boss）、`offscreen_culler.gd`（VisibleOnScreenNotifier2D 停用屏外 AI）。
- **关键约束**：
  - tick 内消费输入队列（与 ADR-2 联动），再调 `CombatDirector.step_simulation`。
  - 10Hz 判定延迟 ~100ms 对低 APM 桌面设计可接受；若手感偏钝，仅玩家主动技能走即时通道（ADR-3 风险备注；ADR-6 仅改述措辞，约束不变）。
  - 对象池化普攻弹幕/特效，禁每击 `instance()`（R3 缓解 3）。
- **关联 ADR**：ADR-3（核心落地）、ADR-2（队列联动）。

### 1.8 资产管线（AssetPipeline）`src/core/asset_pipeline/`
- **职责**：离线后处理脚本（Python+Pillow）产出 PNG-8 索引色 + `asset-manifest.csv`；Godot 目录导入预设（Lossless/Uncompressed + filter=false + gen_mipmaps=false，见 `docs/engine-reference/godot/pixel_texture.import.tpl`）；`PaletteValidator`（SceneTree 脚本，godot --headless -s 调用）校验 ≤16 色且取自母库；批绘制同帧敌人（`MultiMeshInstance2D`）。
- **关键文件（实）**：`src/core/asset_pipeline/pixel_pipeline.py`（全链路·Pillow，单一来源 `palette_source.json`）、`src/core/asset_pipeline/palette_source.json`（调色板唯一真源）、`src/core/asset_pipeline/palette_validator.gd`（R1–R6）、`src/core/asset_pipeline/asset_manifest.csv`（14 行资产登记 + 14 列表头）、`docs/engine-reference/godot/pixel_texture.import.tpl`（ADR-4 导入预设）。
- **关键约束**：
  - 脚本为唯一出口，禁人工绕过（美术圣经 §6.1 强制链路，CLAUDE.md 禁止项）。
  - 16 色由离线脚本+manifest 校验保证，非引擎格式要求（ADR-4）。
  - 帧动画用预烘焙 `AnimatedSprite2D`，MVP 不做运行时调色板查表。
- **关联 ADR**：ADR-4（核心落地）。

### 1.9 跨切核心服务（Cross-cutting Core）—— 不属上述任一业务模块，被全局依赖
- **RNGService** `src/core/rng/rng_service.gd`：单一随机出口。`floor_seed=hash_mix(run_seed, floor_index)`；`new_floor_rng(seed)` 返回种子化 `RandomNumberGenerator`，`floor_rng(run_seed, floor_index)` 由 `derive_seed` 派生层 RNG（§3.1）；提供全局 lint 钩子禁 `randf()/randi()`。**承载 ADR-5**。
- **StatBlock** `src/core/stats/stat_block.gd`：Resource 单一真源，`FinalStat = (Base + ΣVeinAdd) × ΠRuneMult`（C1 契约）。`build_run_base()`（灵脉注入）、`recompute_rune_mult()`（符文变动）、`final_stat()`（每击 O(1)）；Epic D 扩展 `add_vein_add()`/`set_base_stat()`/`reset()` 增量 API。**承载 C1**。

---

## 2. 模块依赖图

```
                         ┌─────────────────────────────┐
                         │   RNGService (跨切·ADR-5)    │◄── 被所有随机源依赖
                         └───────────────┬─────────────┘
                                         │ new_floor_rng()
                                         ▼
  灵脉图谱(SpiritVein) ──run_snapshot──► StatBlock(跨切·C1) ◄── pouch.recompute_rune_mult
        │ 基底(Base+ΣVeinAdd)                ▲                      (乘区 ΠRuneMult)
        │                                    │ final_stat()
        ▼                                    │
  存档(Save)──seed/floor──► 地窟生成(DungeonGen)──布局+实体表──► 战斗(Combat)
        │                      ▲                                  │ step_simulation
        │                      │ (确定性重建, ADR-1/5)             │
        │                      └──────────────────────────────────┘
        │
  输入仲裁(InputArbiter)──InputQueue──► 灵兽AI(SpiritAI·SimulationClock 10Hz)
        │ 帧末结算(ADR-2)                  │ tick()→消费队列→驱动战斗
        │                                 │ 自适应降频(ADR-3)
        ▼
  资产管线(AssetPipeline·ADR-4)──导入预设+校验──► 全部视觉模块(Godot 渲染)
```

**依赖方向（DAG，无循环）**：
- `RNGService` 是叶子（被依赖，不自依赖任何业务模块）。
- `StatBlock` 被 Combat/Pouch/SpiritVein 读写，自身只依赖纯数据。
- `DungeonGen` 依赖 `RNGService` + `Save`（取 seed）；产出布局给 `Combat`。
- `Combat` 依赖 `StatBlock` + `DungeonGen` 布局 + `SpiritAI` 调度。
- `SpiritAI` 依赖 `InputArbiter`(队列) + `Combat`(结算) + `RNGService`。
- `Save` 依赖 `RNGService` 间接（日志确定性）；被 SpiritVein（永久）/DungeonGen（run）读写。
- `AssetPipeline` 仅构建/导入期参与，运行期不进入热路径（零运行时成本，ADR-4 后果）。

---

## 3. 运行时数据流（三个重点）

### 3.1 RNG 单一出口
```
任意模块需要随机
   → RNGService.floor_rng(run_seed, floor_index)  # 返回种子化 RandomNumberGenerator（等价 new_floor_rng(derive_seed([run_seed,floor_index]))）
   → 全程只用该实例的 .randi()/.randf()/.randf_range()
   ✗ 禁止 randomize() / randf() / randi() 全局调用（CI lint 阻断）
```
- 地窟布局、敌人模板、掉落表、战斗 Variance 全部同源；同一 (seed,floor) → 同一结果，保证 ADR-1 重建与事件日志不错位。

### 3.2 输入队列 → AI tick（仿真主循环）
```
每帧 _input():  PC 键鼠事件 → 适配层转同构 dict → InputQueue.push(e)   # 不立即改仿真(ADR-2；touch_id 恒为 0)
   │
SimulationClock._process(delta):  _accum += delta
   │   while _accum >= 0.1 (10Hz) and n < 3 (MAX_CATCHUP):
   │       tick(); _accum -= 0.1; n++
   │
tick():  InputQueue.consume_into(self)   # 帧末结算: 热区归并+去重+cd钳0.5s(ADR-2)
         CombatDirector.step_simulation(0.1)  # 锁敌/寻路/协战决策/伤害结算(ADR-3)
   │
移动/动画: 每帧逐帧 lerp 朝向/位置(读 AI 给出的目标, 不重算决策)  # 视觉平滑
```
- 解耦要点：输入不即时生效、AI 不每帧决策、移动插值独立于决策——30/60fps 行为一致，低端机省电。
- 自适应：连续 N 帧超帧预算 → AI 降 5Hz + 降同屏敌人/粒子（无感降级，R3 缓解 4）。

### 3.3 StatBlock 注入链（属性契约 C1）
```
run 起始:
   SpiritVein.run_snapshot  →  StatBlock.build_run_base()
        = { stat: Base + ΣVeinAdd }            # 灵脉加算聚合, 仅算一次(缓存)
   镶嵌/卸符文:
   Pouch → StatBlock.recompute_rune_mult(runes)
        = { stat: Π mult[stat] }               # 符文独立乘区, 变动时重算(缓存)
每击:
   Combat.damage_calc → StatBlock.final_stat(stat, run_base)
        = run_base[stat] × rune_mult[stat]      # O(1), 无热点(R4)
```
- 加算基底 + 独立乘区 = 凸增长，天然鼓励两系统并用，防"全堆灵脉或全堆符文"主导（R4 设计正确性）。

---

## 4. ADR ↔ 架构映射表

| ADR | 标题 | 落地模块 | 关键文件（拟） | 完成判据（摘要） |
|---|---|---|---|---|
| **ADR-1** | 可恢复存档架构 | Save + DungeonGen + EventLog | `save_service.gd` / `dungeon_generator.gd`（Epic B） | 层间硬存档点写 seed+floor+log；paused 同步落盘；损坏回退庇护所；同 (seed,floor) 重建一致 |
| **ADR-2** | 输入事件并发仲裁 | InputArbiter | `input_queue.gd` / `hit_zone.gd` / `joystick_pointer.gd` | 输入入队、帧末结算、去重、cd 下限 0.5s；30/60fps 行为一致（ADR-6 不改队列语义） |
| **ADR-3** | AI 定步长 10Hz | SpiritAI | `simulation_clock.gd` / `enemy_ai.gd` / `spirit_ai.gd` | 10Hz tick、MAX_CATCHUP=3、移动插值、自适应降 5Hz |
| **ADR-4** | 像素资产后处理 | AssetPipeline | `src/core/asset_pipeline/pixel_pipeline.py` / `palette_validator.gd`（SceneTree + headless -s）/ `palette_source.json` / `docs/engine-reference/godot/pixel_texture.import.tpl` | PNG-8 索引、导入预设关 filter/mipmap、headless -s 实跑 R1–R6（2026-11-07 对 14 资产 0 失败 0 警告） |
| **ADR-5** | RNG 种子化 | RNGService（跨切）+ 全部随机源 | `rng_service.gd` + 各模块 | 单一出口、floor_seed 派生、lint 禁全局随机、重建一致 |
| **C1（契约）** | StatBlock 乘算 | StatBlock（跨切）+ Pouch + SpiritVein | `stat_block.gd`（完整 D1）/ `rune_entry.gd` / `run_snapshot.gd` / `vein_graph.gd`（无环断言）/ `pouch.gd`（+1 堆叠） | `FinalStat=(Base+ΣVeinAdd)×ΠRuneMult`，每击 O(1) |
| **ADR-6** | 平台定位：PC 单平台 | 跨切（输入 / 布局 / QA） | `adr-006-pc-first.md` / `CLAUDE.md §1` / UX 规格 / a11y | 移动端彻底放弃；横屏 1280×720 整数缩放；R1/R3 改 PC 基线；不自动翻转 CONCERNS |

---

## 5. 跨文档一致性自检

| # | 检查点 | 依据文档 | 本文落实情况 | 结论 |
|---|---|---|---|---|
| 1 | 灵兽命名/路径 | bestiary v1.2 §0.1 | slug 唯一映射 `mossback/emberhorn/frostling/voltsprite`(+`tamer`) 用于 Pouch/Combat/资产命名 | ✅ 一致 |
| 2 | 符文乘算契约 C1 | 灵囊 GDD §3 / 战斗 GDD §3.5 | Pouch 字段 `mult:{stat:factor}`（非 `mods` 加算）；StatBlock 落地 `ΠRuneMult` | ✅ 一致 |
| 3 | 伤害公式 | 战斗 GDD §3.5 | `Final=clamp(Mitigated×CritMult×RuneMult×Variance,1,99999)`，clamp 齐备 | ✅ 一致 |
| 4 | 属性注入契约 | 灵脉 GDD §9 V1 / 冲突 C1 | `Base+ΣVeinAdd` 加算、`ΠRuneMult` 独立乘区，run 起始算基底 | ✅ 一致 |
| 5 | C3 经济 | 任务拍板 | 转化率 30%、任何 run 结束均触发（`death_settlement` 统一路径） | ✅ 已闭环 |
| 6 | E-A 中断策略 | 任务拍板 | 层内中断=放弃本层，仅层间硬存档点落盘（Save 模块） | ✅ 已闭环 |
| 7 | 键鼠可操作目标（ADR-6 重订） | a11y §3.2 / ADR-6 | InputArbiter 热区点击区域 ≥24×24px + 键盘可达；原触控 ≥48px 已废止 | ✅ 一致（Wave 3 落地后复核） |
| 8 | ADR-4 导入预设 | ADR-4 / CLAUDE.md | Lossless(0)/Uncompressed(1)+filter=false+gen_mipmaps=false | ✅ 一致 |
| 9 | 形状+颜色双编码 | a11y §3.1 / bestiary §3 | 灵兽靠三角特征（耳/角/尾）识别，不依赖配色 | ✅ 一致 |

---

## 6. 架构自评审

### 6.1 评审结论表
| ID | 检查项 | 结论 | 依据 | 残留风险 |
|---|---|---|---|---|
| A-1 | 模块边界清晰、依赖无环 | **PASS** | §2 DAG 依赖图 | — |
| A-2 | RNG 单一出口纪律可执行 | **PASS（条件）** | RNGService + CI lint 禁全局随机（CLAUDE.md） | 依赖 lint 实际落地，否则易被绕过 |
| A-3 | StatBlock 契约 C1 落地 | **PASS** | §3.3 注入链 + §5 一致性 2/4 | — |
| A-4 | 输入→AI→战斗 解耦 | **PASS** | ADR-2/3 + §3.2 | 10Hz 判定延迟 ~100ms 手感待 PC 实机验证 |
| A-5 | 存档 ADR-1 完整落地 | **PASS** | E-A 已拍板，仅层间落盘 | R2：PC 进程被强杀 / 断电时 `paused` 未必触发（ADR-6 改述） |
| R1 | 地窟生成帧预算 | **CONCERNS** | `prototype-r1r3-report.md` 算法级基准 + 步进让帧设计 | ADR-6：PC 基线表已就位、导出链路已实跑；Wave 3b 已接入 `TileMapLayer.set_cell` + 屏外剔除，但纹理为 `DEBUG_PLACEHOLDER`（E1 原图缺），窗口模式渲染尖峰仍未实测 |
| R3 | 输入 + AI 同帧预算 | **CONCERNS** | `prototype-r1r3-report.md` 预算对照表 + 10Hz 自适应 | ADR-6：PC 基线表已就位；`MultiMesh` ≤12 + 剔除 / 粒子层已就位但为 debug 占位；`_adapt` 30fps 误降频已修复；输入/AI/渲染/粒子分项仍待窗口模式实测 |
| ADR-4 | 像素资产防偏色 | **CONCERNS** | 预设+PaletteValidator | PNG-8 在部分工具链被重新量化（须脚本唯一出口） |
| 总判定 | — | **PASS（带 3 项 CONCERNS）** | 架构可行、ADR 体系完备 | R1/R3 须 PC 基线实测闭环；R2/ADR-4 须实测/纪律 |

> **ADR-6 状态注（2026-11-06，2026-11-07 补充）**：目标平台改为 Windows Desktop 单平台、移动端彻底放弃后，R1/R3 的「低端 iOS/Android 真机」判据失去适用前提，须改由 PC 窗口 / 全屏基线测量（见 `adr-006-pc-first.md §3`）。**本表 CONCERNS 状态不因平台变更自动翻转**；翻转仍须实测数据 + 独立审批。移动端 runbook 已于 Wave 2b 归档至 `docs/qa/archive/r1r3-device-test-plan.md`，证据模板已重定位为 PC 基线。Wave 3b 渲染层技术接入、Wave 4 Windows exe 实导出 / 启动、`_adapt` 30fps 误降频修复均已完成（headless 实跑），但 E1 真实像素资产与窗口 60/30fps 帧预算实测仍缺；headless smoke 数据不充当基线。R1 / R3 **仍为 CONCERNS**。2026-11-07 E1 真实资产已提交 `f1c79c2`（CI 双绿），b 核验审批包已备（`r1r3-verification-approval.md`）：R1/R3 翻转须 G1（a 渲染集成实测）+ G2（核验签字）+ G3（独立审批）三件套齐备，治理动作不替代实测数据。

### 6.2 残留风险说明
- **R1 / R3（高优先）**：本环境可跑 Godot 4.3 headless，但**无渲染 / 设备帧时间采集链**，无法实测渲染 / AI 运行时帧时间。已交付"原型代码 + 测量方法学 + 预算对照表 + 算法级基准"，**PC 基线测量为开放项**，不编造数据（见报告 §1/§4、ADR-6 §4）。
- **R2（中）**：Godot `NOTIFICATION_APPLICATION_PAUSED` 在 PC 进程被强杀 / 断电时不一定触发，须结合 `NOTIFICATION_WM_CLOSE_REQUEST` 与"层间/进庇护所即存"双保险——须在 PC 实机验证边界（ADR-6 等价改述，机制不变）。
- **ADR-4（中）**：PNG-8 工具链若二次量化会破坏 16 色；必须以离线脚本为唯一出口、CI `PaletteValidator` 阻断偏色资产（CLAUDE.md 禁止人工绕过）。
- **A-2（低·条件）**：RNG 纪律依赖 CI lint 落地（grep/正则禁 `randf()/randi()` 全局调用），否则新增随机源易绕开种子。

### 6.3 相对 Phase 2 可行性评审的变化
- Phase 2 总判定为 **CONCERNS**，主因 E-A/C3/C4 未拍板 + R1/R3 未验证。
- 本次（Phase 3 启动）**E-A/C3/C4/C1 均已拍板**（见任务书与 §5），故 ADR-1 由"拟采纳(依赖 E-A)"升级为**可完整实现**；C1 契约已写入 StatBlock 设计。
- 剩余 CONCERNS 仅来自 R1/R3 真机性能与 R2/ADR-4 工程纪律，**不构成架构阻断**。

---

## 7. 待主理人 / 用户拍板项

| # | 项 | 类型 | 影响 | 本文建议 |
|---|---|---|---|---|
| **ENG-1** | Godot 4.x 次版本钉定 | 工程 | 全工程兼容基线 | 建议最新稳定版（如 4.3/4.4），CLAUDE.md 已标注"**待用户签字确认**" |
| **ENG-2** | 重复灵兽蛋 "+1 计数" vs "独立格" | 设计侧（**已裁定 +1 计数**） | 序列化/UI 结构 | 已裁定采纳 +1 计数（见 `design/gdd/decisions/eng2-duplicate-egg-counting.md`），降栏位压力（灵囊 GDD §6.4） |
| **ENG-3** | R1/R3 帧预算测量排期 | 工程（**计划已出，待按 ADR-6 重定位**） | 关闭 2 项 CONCERNS | 原移动端真机计划已归档（见 `docs/qa/archive/r1r3-device-test-plan.md`）；ADR-6 后判据改由 PC 窗口 / 全屏基线表实测（Wave 4），CONCERNS 不自动翻转 |
| **ENG-4** | CI lint 禁全局随机 | 工程（**lint 已落地**） | 加固 A-2 | lint 已落地并实跑通过（见 `tools/ci/lint_no_global_random.py`），待接入 CI 运行 |
| **ENG-5** | 光照方向终审 | 设计（**终审已通过**） | 资产管线一致性 | 终审 PASS（见 `docs/art-bible/lighting-direction-audit.md`），附录 B #3 已闭合 |

---

*本文 v1.1（2026-11-06 按 ADR-6 更新平台口径，模块 / ADR×5 / C1 / 自评审结论不变）为 Phase 3 主架构真源，覆盖 8 业务模块 + 2 跨切服务。未执行 git commit。*
