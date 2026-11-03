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
| **状态** | 进行中（Epic A2 已落地 `save_service.gd` 骨架；待与 DungeonGen 联测重建一致 + 真机 R2 双保险） |
| **落地文件（实）** | `src/core/save/save_service.gd`（层间落盘 + 暂停同步 + 损坏回退，承载 ADR-1）；`src/core/dungeon_gen/dungeon_generator.gd`、`src/core/dungeon_gen/fallback_template.gd`（Epic B 待落）；event_log 以内嵌 `Array` 存于 `save_run.cfg` |
| **关联模块** | Save + DungeonGen（见 architecture-doc.md §1.1/§1.5、§4） |
| **验证点** | ① 层间硬存档点写入 `user://save_run.cfg`（seed+floor+log）；② `NOTIFICATION_APPLICATION_PAUSED` 同步落盘；③ 读档损坏 → 回退庇护所且永久进度不受影响；④ 同 (run_seed, floor_index) 重建布局与事件日志重放一致 |
| **负责人** | engineering-lead |
| **风险** | R2：iOS 后台强杀时 `paused` 不一定触发 → 须结合 `NOTIFICATION_WM_CLOSE_REQUEST` + "层间/进庇护所即存"双保险（**真机实测边界**）；战斗随机性若遗漏任一随机源则重建与日志错位（靠 ADR-5 统一出口兜底） |
| **完成判据** | 1) 仅层间落盘且量极小（数百字节）；2) 损坏回退路径有断言/测试；3) 重建一致性有确定性测试（同种子→同布局）；4) R2 双保险在真机验证 |

---

## ADR-2 · 触屏输入并发仲裁

| 字段 | 内容 |
|---|---|
| **状态** | 进行中 |
| **落地文件（拟）** | `src/gameplay/input/input_queue.gd`、`src/gameplay/input/hit_zone.gd`、`src/gameplay/input/joystick_pointer.gd` |
| **关联模块** | InputArbiter（见 architecture-doc.md §1.6、§4） |
| **验证点** | ① 所有 `InputEventScreenTouch/Drag` 入队、不立即改仿真；② 帧末单次结算、按热区归并；③ 技能重复触发去重；④ cd 下限钳 0.5s（战斗 GDD §6.4）；⑤ 浮杆独占单一 `touch_id`，与技能热区互不抢占；⑥ 30/60fps 设备行为一致 |
| **负责人** | engineering-lead |
| **风险** | 低。注意 iOS 多指 `index` 与 Godot `touch_id` 映射、Android 指序变化——已统一以 `touch_id` 仲裁规避 |
| **完成判据** | 1) 输入队列单测覆盖去重/归并；2) 摇杆+2 按钮+滑动并发无抢占；3) 跨帧率行为一致有对比验证（R3 同帧预算内） |

---

## ADR-3 · 自动战斗 / 灵兽协战 AI 定步长

| 字段 | 内容 |
|---|---|
| **状态** | 进行中 |
| **落地文件（拟）** | `src/gameplay/ai/simulation_clock.gd`、`src/gameplay/ai/enemy_ai.gd`、`src/gameplay/ai/spirit_ai.gd`、`src/gameplay/ai/offscreen_culler.gd` |
| **关联模块** | SpiritAI（见 architecture-doc.md §1.7、§4） |
| **验证点** | ① `SimulationClock` 累加器每满 0.1s（10Hz）跑 `tick()`，MAX_CATCHUP=3；② tick 内消费输入队列→`CombatDirector.step_simulation`；③ 移动/动画逐帧 lerp 读 AI 目标（不重算决策）；④ 连续超帧预算降 5Hz、后台暂停；⑤ 屏外实体经 `VisibleOnScreenNotifier2D` 停用 AI/动画 |
| **负责人** | engineering-lead |
| **风险** | 低。10Hz 下技能响应最大 ~100ms，对休闲单手可接受；若手感偏钝，仅玩家主动技能走即时通道（备注方案） |
| **完成判据** | 1) 10Hz tick 计数/追帧断言；2) 自适应降频触发逻辑有单测；3) 同屏 ≤12 敌人渲染 <4ms、粒子 <3ms 在真机达标（R3） |

---

## ADR-4 · 像素资产后处理链路接入 Godot 导入管线

| 字段 | 内容 |
|---|---|
| **状态** | **实现完成 + 待真机/签字闭环**（引擎已签字 Godot 4.3；实现已落地；仅剩 Godot 环境接 CI headless 实跑） |
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
| **状态** | 进行中（CI lint 已落地；RNGService + `floor_rng` 已落 + 单测已落 `tests/unit/rng_service_test.gd`；待与 ADR-1 联测重建一致） |
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
| **状态** | 已闭环（设计层面；实现随 Pouch/SpiritVein 落地） |
| **落地文件（拟）** | `src/core/stats/stat_block.gd`、`src/gameplay/pouch/rune_entry.gd`、`src/gameplay/spirit_vein/run_snapshot.gd` |
| **关联模块** | StatBlock（跨切）+ Pouch + SpiritVein（见 architecture-doc.md §1.3/§1.4/§1.9、§4） |
| **验证点** | ① `FinalStat = (Base + ΣVeinAdd) × ΠRuneMult`；② 灵脉加算聚合 run 起始算一次缓存；③ 符文乘区变动时重算缓存；④ 每击 O(1) 取最终值；⑤ 符文字段为 `mult:{stat:factor}`（非 `mods` 加算） |
| **负责人** | engineering-lead（+ 设计侧已对齐字段命名） |
| **风险** | 低。纯命名/语义对齐，已写入灵囊 GDD §3 与战斗 GDD §3.5 |
| **完成判据** | 1) StatBlock 单测覆盖加算/乘区/每击；2) 灵囊 GDD 字段命名一致；3) 伤害公式调用一致无溢出 |

---

## 汇总看板

| ADR | 状态 | 主要阻塞/风险 | 闭环前置 |
|---|---|---|---|
| ADR-1 | 进行中 | R2 iOS 后台强杀边界 | save_service.gd 已落；真机双保险实测 + DungeonGen 联测 |
| ADR-2 | 进行中 | 低 | R3 同帧预算验证 |
| ADR-3 | 进行中 | 低 | R3 真机达标 |
| ADR-4 | 实现完成 + 待真机/签字闭环 | PNG-8 人工绕过风险 | 脚本唯一出口 + CI 校验 + Python selftest 已通过（含 boss/sanctuary R3 严格） |
| ADR-5 | 进行中 | 待与 ADR-1 联测 | RNGService+单测已落；全局随机调用拦截（lint 已落地） |
| C1 | 已闭环（设计） | 低 | 随模块实现落地 |

> **总评**：6 项决策均"技术可落地、无 FAIL"。ADR-1 因 E-A 拍板由拟采纳升级为可完整实现；**ADR-4 已实现完成（引擎 4.3 签字、Python `--selftest` 实跑通过含 boss/sanctuary R3 严格硬阻断）**，仅待 Godot 环境接 CI headless 实跑；剩余开放项集中在 **R1/R3 真机测量** 与 **R2/ADR-5 的工程纪律（CI 校验/lint）**，不构成架构阻断。

---

*本清单为 ADR 落地追踪真源，与 `architecture-doc.md` 映射表互锁。未修改 `design/` 与 `docs/architecture/` 之外目录，未执行 git commit。*
