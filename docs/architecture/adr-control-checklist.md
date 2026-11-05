# ADR 控制清单（ADR Control Checklist）

> **作者**：程基岩（Cheng Jiyan）· 工程负责人
> **引擎**：Godot 4（iOS / Android，触屏单手）
> **阶段**：Phase 3 技术搭建
> **来源**：`feasibility-review.md` 的 ADR×5 + 任务书拍板的 C1 契约；与 `architecture-doc.md` 的 ADR↔架构映射表互锁
> **用途**：将每条 ADR 转为**可追踪闭环**——状态 / 落地文件 / 验证点 / 负责人 / 风险 / 完成判据。架构评审（PASS/CONCERNS/FAIL）结论见 `architecture-doc.md` §6。

---

## 使用说明
- **状态枚举**：`待启动` / `进行中` / `待验证` / `已闭环` / `阻塞`
- **负责人**：`engineering-lead`（程基岩）为技术落地主责；标注 `设计侧` 的项需文策渊/林绘澄协同。
- **验证点**：须有可观测证据（CI 检查 / 真机测量 / 单元断言），**不接受口头声明**。
- **完成判据**：全部达成方可勾 `已闭环`。

---

## ADR-1 · 程序生成地窟的可恢复存档架构

| 字段 | 内容 |
|---|---|
| **状态** | 进行中（Epic A2 `save_service.gd` + Epic B `dungeon_generator.gd`/`room_stitcher.gd`/`floor_cache.gd`/`fallback_template.gd` 已落；待 DungeonGen↔Save 重建联测一致 + 真机 R2 双保险） |
| **落地文件（实）** | `src/core/save/save_service.gd`（层间落盘 + 暂停同步 + 损坏回退，承载 ADR-1）；`src/core/dungeon_gen/dungeon_generator.gd`（入口）、`src/core/dungeon_gen/room_stitcher.gd`（确定性核心）、`src/core/dungeon_gen/floor_cache.gd`（布局缓存）、`src/core/dungeon_gen/fallback_template.gd`（保底，Epic B 已落）；event_log 以内嵌 `Array` 存于 `save_run.cfg`；Epic D 扩展 `save_pouch`/`load_pouch`（run 级·存灵囊）/ `save_permanent`/`load_permanent`（meta 级·存 bestiary+vein+ember），load-first 增量写互不覆写（ADR-1 语义保持） |
| **关联模块** | Save + DungeonGen（见 architecture-doc.md §1.1/§1.5、§4） |
| **验证点** | ① 层间硬存档点写入 `user://save_run.cfg`（seed+floor+log）；② `NOTIFICATION_APPLICATION_PAUSED` 同步落盘；③ 读档损坏 → 回退庇护所且永久进度不受影响；④ 同 (run_seed, floor_index) 重建布局与事件日志重放一致 |
| **负责人** | engineering-lead |
| **风险** | R2：iOS 后台强杀时 `paused` 不一定触发 → 须结合 `NOTIFICATION_WM_CLOSE_REQUEST` + "层间/进庇护所即存"双保险（**真机实测边界**）；战斗随机性若遗漏任一随机源则重建与日志错位（靠 ADR-5 统一出口兜底） |
| **完成判据** | 1) 仅层间落盘且量极小（数百字节）；2) 损坏回退路径有断言/测试；3) 重建一致性有确定性测试（同种子→同布局）；4) R2 双保险在真机验证 |

---

## ADR-2 · 触屏输入并发仲裁

| 字段 | 内容 |
|---|---|
| **状态** | 进行中（生产模块已落 + 单测已落；待真机 R3 测量 / GUT CI 实跑） |
| **落地文件（实）** | `src/gameplay/input/input_queue.gd`、`src/gameplay/input/hit_zone.gd`、`src/gameplay/input/joystick_pointer.gd`（由 R3 原型晋升；InputArbiter 集成层节点——把 `InputEventScreenTouch/Drag` 抽 dict→push、浮杆/按钮 touch 仲裁——留 Epic-C 后续桩） |
| **关联模块** | InputArbiter（见 architecture-doc.md §1.6、§4） |
| **验证点** | ① 所有 `InputEventScreenTouch/Drag` 入队、不立即改仿真；② 帧末单次结算、按热区归并；③ 技能重复触发去重；④ cd 下限钳 0.5s（战斗 GDD §6.4）；⑤ 浮杆独占单一 `touch_id`，与技能热区互不抢占；⑥ 30/60fps 设备行为一致 |
| **负责人** | engineering-lead |
| **风险** | 低。注意 iOS 多指 `index` 与 Godot `touch_id` 映射、Android 指序变化——已统一以 `touch_id` 仲裁规避 |
| **完成判据** | 1) 输入队列单测覆盖去重/归并（`test_input_queue_dedupe_same_zone`）；2) 摇杆+按钮并发无抢占（浮杆独占 `touch_id` 已由 `test_joystick_8_direction_and_deadzone` 演练）；3) 跨帧率行为一致有对比验证（R3 同帧预算内，**待真机测量**）。去重/归并/0.5s cd 钳/浮杆独占已由 `tests/unit/combat_test.gd` 覆盖 |

---

## ADR-3 · 自动战斗 / 灵兽协战 AI 定步长

| 字段 | 内容 |
|---|---|
| **状态** | 进行中（SimulationClock + CombatDirector 已落 + 单测已落；enemy_ai/spirit_ai/offscreen_culler 留 Epic-C 后续桩；待真机 R3 测量） |
| **落地文件（实）** | `src/gameplay/ai/simulation_clock.gd`（由 R3 原型晋升：10Hz / MAX_CATCHUP=3 / 自适应 5Hz）、`src/gameplay/combat/combat_director.gd`（step_simulation 在 tick 内调用）、`src/gameplay/input/input_queue.gd`（tick 内消费）；`enemy_ai.gd`/`spirit_ai.gd`/`offscreen_culler.gd` 留 Epic-C 后续桩 |
| **关联模块** | SpiritAI（见 architecture-doc.md §1.7、§4） |
| **验证点** | ① `SimulationClock` 累加器每满 0.1s（10Hz）跑 `tick()`，MAX_CATCHUP=3；② tick 内消费输入队列→`CombatDirector.step_simulation`；③ 移动/动画逐帧 lerp 读 AI 目标（不重算决策）；④ 连续超帧预算降 5Hz、后台暂停；⑤ 屏外实体经 `VisibleOnScreenNotifier2D` 停用 AI/动画（留桩） |
| **负责人** | engineering-lead |
| **风险** | 低。10Hz 下技能响应最大 ~100ms，对休闲单手可接受；若手感偏钝，仅玩家主动技能走即时通道（备注方案） |
| **完成判据** | 1) 10Hz tick 计数/追帧断言（`test_clock_steady_state_10hz` / `test_clock_stall_capped_at_max_catchup`）；2) 自适应降频触发逻辑有单测（`test_clock_adaptive_5hz_after_over_budget`）；3) 同屏 ≤12 敌人渲染 <4ms、粒子 <3ms 在真机达标（R3，**待真机测量**）。① ② 已由 `tests/unit/combat_test.gd` 覆盖 |

---

## ADR-4 · 像素资产后处理链路接入 Godot 导入管线

| 字段 | 内容 |
|---|---|
| **状态** | **已闭环（工具链 verified · 2026-11-04 主理人独立实跑 `pixel_pipeline.py --selftest` → PASS / exit 0；引擎已签字 Godot 4.3）**；开放项：① E1 真实资产产出（art-director，AI 原图→pipeline→manifest）② Godot 侧 `.import`/Import Preset 固化 + `palette_validator` headless CI 实跑 —— 二者均非架构阻断 |
| **落地文件（实）** | `src/core/asset_pipeline/pixel_pipeline.py`（全链路·Pillow）、`src/core/asset_pipeline/palette_source.json`（调色板单一来源）、`src/core/asset_pipeline/palette_validator.gd`（R1–R6）、`src/core/asset_pipeline/asset_manifest.csv`（14 列表头）、`docs/engine-reference/godot/pixel_texture.import.tpl`（ADR-4 导入预设）、`docs/engine-reference/godot/VERSION.md`（引擎 4.3 签字版） |
| **关联模块** | AssetPipeline（见 architecture-doc.md §1.8、§4） |
| **验证点** | ① 离线脚本输出 PNG-8 索引色 + 登记 manifest（seed/提示词/色数/校验）；② 目录 `.import` 覆写 `compress/mode=0或1`、`filter=false`、`gen_mipmaps=false`、`detect_3d/compress_to=0`；③ `PaletteValidator` 断言每资产 ≤16 色且取自母库，否则阻断导入；④ CI headless 接口就绪；**⑤ Python `--selftest` 已实跑通过（upper=9 色 / mid=7 色，R1–R4 绿），与 bestiary §4（9/16、7/16）吻合** |
| **负责人** | engineering-lead（脚本/预设/校验）+ art-director（母库/风格锁） |
| **风险** | 中（已缓解）。PNG-8 在部分工具链被重新量化 → 以脚本为唯一出口、禁人工绕过（CLAUDE.md 禁止项）；Godot 默认 Compress(BPTC) 必须显式改预设否则偏色/渗色（已钉预设）。**boss/sanctuary 场景子集已由 bestiary §4（v1.2）正式定义**（boss 10 色 / sanctuary 9 色，均 ≤16），已回填 `palette_source.json` 并接入 `palette_validator.gd` 完整 R3 硬阻断（与 upper/mid 同对待，降级分支已删除）。引擎已签字 4.3（≥4.1），`Image.load_from_file()` 可用，兼容分支为更早 4.x 兜底 |
| **完成判据** | 1) 导入预设已钉进 `docs/engine-reference/godot/`（4.3 签字版）；2) `PaletteValidator` 已实现 R1–R6（GDScript，EditorPlugin + CI headless 接口就绪）；3) Python `--selftest` 实跑通过（upper=9/mid=7/boss=10/sanctuary=9，R1–R4 绿）；4) **boss/sanctuary 子集已由 bestiary §4 回填，R3 严格硬阻断已实现（降级分支删除）**，仅待 Godot 环境接 CI headless 实跑 |

---

## ADR-5 · 程序生成 RNG 种子化

| 字段 | 内容 |
|---|---|
| **状态** | 进行中（CI lint 已落地；RNGService + `floor_rng` 已落 + 单测已落 `tests/unit/rng_service_test.gd`；DungeonGen 经 `floor_rng` 接入完成（Epic B）；待 DungeonGen↔Save 联测重建一致） |
| **落地文件（拟）** | `src/core/rng/rng_service.gd`（跨切）+ 各随机源模块 |
| **关联模块** | RNGService（见 architecture-doc.md §1.9、§4） |
| **验证点** | ① `floor_seed = hash_mix(run_seed, floor_index)`，每层独立 `RandomNumberGenerator.seed`；② 生成/掉落/战斗方差全走本层 RNG；③ 禁 `randf()/randi()` 全局随机（CI lint 阻断）；④ 同 (seed,floor) → 同布局（与 ADR-1 联测） |
| **负责人** | engineering-lead |
| **风险** | 低，但纪律性要求高——任一随机源绕开种子即破坏 ADR-1；建议 CI 加正则检查全局随机调用 |
| **完成判据** | 1) RNGService 单一出口单测；2) `tools/ci/lint_no_global_random.py` 实跑拦截 `randf()/randi()` 全局调用（已落地，见 ENG-4）；3) 与 ADR-1 联测重建一致 |

---

## C1（契约）· StatBlock 乘算注入

| 字段 | 内容 |
|---|---|
| **状态** | 已闭环（实现随 Epic D 落地：`stat_block.gd` 完整版 + `rune_entry.gd` + `run_snapshot.gd` + Pouch/SpiritVein 生产模块 + 单测已落） |
| **落地文件（实）** | `src/core/stats/stat_block.gd`（完整 D1）、`src/gameplay/pouch/rune_entry.gd`、`src/gameplay/spirit_vein/run_snapshot.gd`、`src/gameplay/pouch/pouch.gd`、`src/gameplay/pouch/spirit_entry.gd`、`src/gameplay/pouch/party_manager.gd`、`src/gameplay/pouch/bestiary.gd`、`src/gameplay/spirit_vein/vein_graph.gd`、`src/gameplay/spirit_vein/vein_node.gd`（Epic D 已落） |
| **关联模块** | StatBlock（跨切）+ Pouch + SpiritVein（见 architecture-doc.md §1.3/§1.4/§1.9、§4） |
| **验证点** | ① `FinalStat = (Base + ΣVeinAdd) × ΠRuneMult`；② 灵脉加算聚合 run 起始算一次缓存；③ 符文乘区变动时重算缓存；④ 每击 O(1) 取最终值；⑤ 符文字段为 `mult:{stat:factor}`（非 `mods` 加算）；⑥ C1 公式单测（`tests/unit/pouch_vein_test.gd`：atk=(10+5)×(2.0×1.5)=45、def=(5+3)×1.5=12、负 atk/def 钳 0、每击 O(1) 一致）；⑦ ENG-2 +1 堆叠 + `{slug:count}` 序列化往返一致 |
| **负责人** | engineering-lead（+ 设计侧已对齐字段命名） |
| **风险** | 低。纯命名/语义对齐，已写入灵囊 GDD §3 与战斗 GDD §3.5 |
| **完成判据** | 1) StatBlock 单测覆盖加算/乘区/每击（已达成）；2) 灵囊 GDD 字段命名一致；3) 伤害公式调用一致无溢出（Combat `damage_calc` 取 `StatBlock.final_stat`，Epic C 已落）；4) ENG-2 +1 堆叠 + 序列化单测（已达成） |

---

## 汇总看板

| ADR | 状态 | 主要阻塞/风险 | 闭环前置 |
|---|---|---|---|
| ADR-1 | 进行中 | R2 iOS 后台强杀边界 | save_service.gd + dungeon_generator.gd/room_stitcher.gd/floor_cache.gd/fallback_template.gd 均已落（Epic A2/B）；剩余 DungeonGen↔Save 重建联测 + R2 真机双保险实测 |
| ADR-2 | 进行中（生产模块+单测已落） | 低 | R3 同帧预算验证（真机） |
| ADR-3 | 进行中（生产模块+单测已落） | 低 | R3 真机达标（同屏≤12敌人<4ms等） |
| ADR-4 | 已闭环（工具链 verified 2026-11-04；selftest 实跑 PASS） | E1 资产产出 / Godot 应用待办（非架构阻断） | 脚本唯一出口 + CI 校验 + Python selftest 实跑 PASS（upper=9/mid=7/boss=10/sanctuary=9） |
| ADR-5 | 进行中（GUT 单测已接线 CI） | 待与 ADR-1 联测；GUT 实跑待 Godot 环境 | RNGService+单测已落；全局随机调用拦截（lint 已落地）；`rng_service_test.gd` 等 5 件套经 `.github/workflows/test.yml` 接 Godot 4.3 headless（Epic G 接线，主理人已做静态 API 对账，待实跑） |
| C1 | 已闭环（Epic D 实现已落） | 低 | 单测覆盖加算/乘区/堆叠（`pouch_vein_test.gd`） |

> **总评**：6 项决策均"技术可落地、无 FAIL"。ADR-1 因 E-A 拍板由拟采纳升级为可完整实现；**ADR-4 已实现完成（引擎 4.3 签字、Python `--selftest` 实跑通过含 boss/sanctuary R3 严格硬阻断）**，仅待 Godot 环境接 CI headless 实跑；剩余开放项集中在 **R1/R3 真机测量** 与 **R2/ADR-5 的工程纪律（CI 校验/lint）**，不构成架构阻断。

---

*本清单为 ADR 落地追踪真源，与 `architecture-doc.md` 映射表互锁。未修改 `design/` 与 `docs/architecture/` 之外目录，未执行 git commit。*
