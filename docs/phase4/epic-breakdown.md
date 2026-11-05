# Epic 拆分与验收标准 / Epic Breakdown

> **文档类型**：MVP → 开发 Epic 拆分（Canonical for Phase 5 排期）
> **归属**：主理人签发，三角色（工程/美术/设计）确认
> **引用**：`docs/architecture/architecture-doc.md`（模块+DAG）、`docs/phase4/plan.md`、`design/gdd/*.md`、ADR×5 + C1
> **版本**：v1.0 · 未 git commit。

---

## 0. 拆分口径

- **粒度**：Epic（主题）→ 子故事（可估算、可验收）→ 验收标准。
- **工作量占位**：S(≤2d) / M(3–5d) / L(>5d)，为 Lean 估算，非承诺。
- **ADR/模块映射**：每个 Epic 标注依赖的已冻结约束，避免 Phase 5 重开争论。

## 1. Epic 总览

| Epic | 主题 | 核心模块 | 关键 ADR | 工作量 |
|---|---|---|---|---|
| **A** | 工程基线与确定性核心 | RNGService / Save / 项目骨架 | ADR-1 / ADR-5 | M |
| **B** | 地牢生成 | DungeonGen | ADR-1 / R1原型 | M |
| **C** | 战斗系统 | Combat / SpiritAI / InputArbiter | ADR-2 / ADR-3 | L |
| **D** | 灵兽与灵囊 | Pouch / SpiritVein / StatBlock | C1 / ENG-2 | L |
| **E** | 资产管线落地 | AssetPipeline | ADR-4 | M |
| **F** | 触屏 UX 实现 | InputArbiter / UI / 可访问性 | UX 规格 / 可访问性 Basic | L |
| **G** | 测试与质量门 | 全模块 | ADR-5 / lint / 设备测试 | M |

## 2. 各 Epic 详述

### Epic A — 工程基线与确定性核心
- **目标**：搭好 Godot 4.3 工程，落定"随机唯一出口 + 种子化存档"两大基石。
- **子故事**：
  - A1 创建 `src/core/rng/rng_service.gd`（RNGService + `new_floor_rng()`），单测种子确定性。【S】
  - A2 创建 `src/core/save/save_service.gd`，层间落盘 + 重建一致（ADR-1）。【M】
  - A3 工程骨架：主场景、Autoload 注册、目录约定。【S】
  - A4 CI 挂 `lint_no_global_random.py` + 测试（见 Epic G）。【S】
- **验收**：RNGService 同 seed 产出序列逐字节一致；存档重建与事件日志无错位；CI lint 绿。
- **依赖**：无（Phase 5 第一棒）。
- **映射**：ADR-1、ADR-5、CLAUDE.md §4。

### Epic B — 地牢生成
- **目标**：把 R1 原型（`src/prototype/r1_dungeon_gen/`）升为生产模块，同 seed 同布局。
- **子故事**：
  - B1 DungeonGen 模块实现，复用原型算法。【M】
  - B2 接入 RNGService（移除原型内联 RandomNumberGenerator）。【S】
  - B3 同 (seed, floor) 布局确定性单测（比对哈希）。【S】
- **验收**：生成耗时待真机回填（见 `docs/qa/r1r3-device-test-plan.md`）；确定性单测绿。
- **依赖**：A1。
- **映射**：ADR-1、R1 原型。

### Epic C — 战斗系统
- **目标**：实现战斗状态机、定步长 AI、帧末输入队列。
- **子故事**：
  - C1 Combat 状态机（回合开始→输入→AI tick→结算→结束）。【M】
  - C2 SpiritAI 定步长 10Hz tick，MAX_CATCHUP=3（ADR-3）。【M】
  - C3 InputArbiter 帧末输入队列（ADR-2）。【M】
  - C4 伤害公式/技能（对齐 `combat-system-gdd.md` §3.5）。【M】
- **验收**：60fps/30fps/自适应降频预算断言（真机回填）；确定性 tick 可复现。
- **依赖**：A1、A3、D（StatBlock/C1）。
- **映射**：ADR-2、ADR-3、combat GDD。

### Epic D — 灵兽与灵囊
- **目标**：灵兽/背包/灵脉数据模型与交互，落实 C1 契约与 ENG-2 裁定。
- **子故事**：
  - D1 StatBlock 实现 `FinalStat=(Base+ΣVeinAdd)×ΠRuneMult`（C1）。【M】
  - D2 Pouch 数据模型：灵兽 +1 堆叠计数（ENG-2），`{slug:count}` 序列化。【M】
  - D3 SpiritVein 节点/连边数据 + 生效到 StatBlock。【M】
  - D4 灵兽图鉴解锁逻辑（对齐 bestiary）。【S】
- **验收**：C1 公式单测；重复灵兽角标 `×N`；存档含 Pouch 且重建一致。
- **依赖**：A2、A1。
- **映射**：C1、ENG-2、pouch/vein GDD、bestiary v1.3。

### Epic E — 资产管线落地
- **目标**：把 ADR-4 规格变成可排产、可入库的真实资产。
- **子故事**：
  - E1 按 `asset-production-spec.md` 产出 MVP 资产原图。【M】
  - E2 `pixel_pipeline.py` 批处理后处理 + `palette_validator.gd` 校验（R1–R6）。【S】
  - E3 Godot 导入预设应用 + `asset_manifest.csv` 登记。【S】
- **验收**：每资产 R1–R6 True；四场景子集色数 ≤16 ∈ 母库；manifest 完整。
- **依赖**：无（可与 A 并行，美术先行）。
- **映射**：ADR-4、asset-production-spec.md。

### Epic F — 触屏 UX 实现
- **目标**：按 `ux-spec.md` 落地四主屏 + 底部 Tab + 可访问性 Basic。
- **子故事**：
  - F1 底部固定 Tab 栏（总览/灵囊/灵脉/地图），命中区 ≥48px。【M】
  - F2 战斗屏布局 + 技能键热区 + 状态双编码。【M】
  - F3 灵囊屏三栏 + 灵兽格 +1 角标（ENG-2）。【M】
  - F4 灵脉图谱屏节点命中区 ≥48px + 缩放。【M】
  - F5 可访问性 Basic 验收（CVD 模拟、字号、非色彩提示）。【M】
- **验收**：单手可达性热力图 100% 热区；§5 五项 CVD 不丢信息。
- **依赖**：C3（InputArbiter）、D2、D3。
- **映射**：ux-spec.md、accessibility-requirements.md。

### Epic G — 测试与质量门
- **目标**：GUT 接入 + 确定性测试清单 + 设备测试 + CI 双绿。
- **子故事**：
  - G1 `tests/` 脚手架 + GUT 安装 + smoke 通过（见 `tests/README.md`）。【S】
  - G2 确定性测试：RNGService / DungeonGen / Save 重建。【M】
  - G3 战斗预算测试（60/30fps + MAX_CATCHUP）。【M】
  - G4 `docs/qa/r1r3-device-test-plan.md` 真机回填。【M】
  - G5 CI 串联 lint + GUT 双绿。【S】
- **验收**：CI 两条线绿；确定性测试全过；设备指标已实测（非臆造）。
- **依赖**：A/B/C/D 各模块单测随模块完成。
- **映射**：ADR-5、lint、device-test-plan。

## 3. 依赖图（无环）

```
A ──► B ──► (地牢)
A ──► C ──► F
A ──► D ──► F
A ──► D ──► C
E (美术先行, 并行 A)
G 依赖 A/B/C/D 的单测逐步补齐
```

## 4. 出口判据（与 plan.md §4 对齐）

Epic A–G 全部"验收"列勾选 + 依赖图无环 + 三角色确认，方可进入 Phase 5 收尾/正式生产迭代。

---

## 5. Epic A 执行进度（2026-11-03 · 主理人直接落地）

- **A1** `src/core/rng/rng_service.gd` 补 `floor_rng(run_seed, floor_index)`（对齐架构 §3.1）；`tests/unit/rng_service_test.gd` 落 GUT 确定性单测（同 seed 同序列 / 异 seed 分叉 / floor_rng 确定性 / 调用时序无关）。
- **A2** `src/core/save/save_service.gd`（extends Node，Autoload）落地：save_run/load_run/clear_run（回退庇护所）、save_meta/load_meta、NOTIFICATION_APPLICATION_PAUSED 同步落盘、new_run_seed() 经 RNGService 派生（禁全局随机）。承载 ADR-1。
- **A3** `project.godot`（Godot 4.3 / config_version=5 / 竖屏 720×1280 / main 场景 / SaveService Autoload）+ `src/main.tscn` + `src/main.gd`（启动读档/新 run，演示 RNGService.floor_rng 链路）。
- **A4** `.github/workflows/lint.yml` + `test.yml` 双绿流水线；test.yml 增 GUT 9.x 安装步骤（pin 版本 + 注释待团队验证布局）。
- **质量门**：`tools/ci/lint_no_global_random.py` 复跑 OK（扫描 5 个 .gd，exit 0）；新增 .gd 无误触发全局随机拦截。
- **待真机/后续**：ADR-1 与 DungeonGen 联测重建一致、R2 iOS 后台强杀双保险、GUT 在 CI 真跑（本沙箱无 Godot）。

## 6. Epic B 执行进度（2026-11-03 · 工程负责人交付，主理人质量门核验）

- **B1** `src/core/dungeon_gen/dungeon_generator.gd`（入口，`generate_sync` + 异步 `generate_floor` 分段 `await process_frame`）、`room_stitcher.gd`（确定性核心，四局部构建函数）、`floor_cache.gd`（同 (seed,floor) 缓存）、`fallback_template.gd`（保底安全层）。复用 R1 原型算法，仅产逻辑网格+实体表，不含瓦片渲染态。
- **B2** 全随机走 `RNGService.floor_rng(run_seed, floor_index)`；已删除原型内联 `RandomNumberGenerator` 与 `floor_seed` 旧哈希；零全局随机（lint 复验 OK）。
- **B3** `tests/unit/dungeon_gen_test.gd`（GUT）：同 (seed,floor,tier) 两次生成 JSON 逐字节相等、不同 floor 必分叉、非法 floor 切保底。
- **质量门**：`tools/ci/lint_no_global_random.py` 独立复验 OK（扫描 9 个 .gd，exit 0）；5 个文件主理人逐一读盘确认结构正确、抽取顺序 sync/async 一致。
- **待真机/后续**：DungeonGen↔Save 重建联测（Epic A2↔B 闭环验证 ADR-1）、R1 渲染尖峰真机测量（set_cell 批量写入）、GUT 在 CI 真跑（本沙箱无 Godot）。

## 9. Epic E 执行进度（2026-11-04 · 主理人独立核验 + selftest 实跑 + 文档闭环）

> **关键事实**：ADR-4 实现工具链（pixel_pipeline.py / palette_source.json / palette_validator.gd / asset_manifest.csv / 导入预设模板）早在 `9e32d09`（Phase 3 收口）已入库；本 kickoff 不重复造轮子，而是做**独立核验 + 真实验证 + 规格对齐 + 文档闭环**。

- **E1（资产生产规格·已定稿）**：`docs/art-bible/asset-production-spec.md` v1.0 已锁定 MVP 清单（char: tamer/mossback/emberhorn/frostling/voltsprite @24 upper、boss_deep @32–48 boss；tile/props/ui 按场景子集）。slug/尺寸/场景子集与 bestiary §0.1/§4 一致。**但真实 AI 原图尚未产出**（art-director 待办）——故 `asset_manifest.csv` 仅表头、零资产登记，属 E1 真·剩余工作，非工具链缺陷。
- **E2（后处理 + 校验·已实现 + 实跑验证）**：`src/core/asset_pipeline/pixel_pipeline.py` 全链路（最近邻降采样→≤16 色固定索引→2×2 有序 Bayer 抖动→1–2px 描边 #1A1C2C→PNG-8 + manifest 登记 sha256）；`palette_validator.gd`（R1–R6，EditorScript + CI headless 入口）。**主理人 2026-11-04 独立实跑 `python pixel_pipeline.py selftest` → 退出码 0、RESULT: PASS**：`upper=9` / `mid=7` / `upper(16)=9` / `boss=10` / `sanctuary=9`，全部 `validate=True`，与 bestiary §4 子集（9/7/10/9）逐一吻合，R1–R4 全绿。Python 端 `validate_python` 镜像 R1–R4；R5/R6 为 Godot/manifest 侧。
- **E3（Godot 导入预设·模板就位 + 应用待 Godot）**：`docs/engine-reference/godot/pixel_texture.import.tpl` 已固化覆写（compress/mode=0或1、filter=false、gen_mipmaps=false、detect_3d/compress_to=0、fix_alpha_border=true）；`palette_validator.gd` 的 EditorPlugin + `godot --headless --script` 入口已写。**真实 `.import` / Import Preset 文件待在 Godot 编辑器内一次性固化并提交**（VERSION.md 已声明本沙箱无法运行 Godot）。
- **工具链 ↔ 规格交叉核对（一致）**：manifest 14 列 = pixel-asset-pipeline §2（canonical）；MASTER(19)/SCENE(upper9/mid7/boss10/sanctuary9) = palette_source.json；VALID_SIZES(16/24/32/48)、描边 1–2px、alpha_cutoff=128、Bayer `[[0,2],[3,1]]/4` 与规格逐字对齐；CLAUDE.md §3 导入预设、§6 资产红线、§8.2 禁止项（人工绕过脚本即违规）齐备。
- **文档不一致（开放项·低优先）**：`asset-production-spec.md §3` 另列一套 14 列 manifest schema（`src_md5/validator_pass/import_preset/palette_version/author/note`），与 canonical 14 列（pixel-asset-pipeline §2 = 代码实现）字段语义冲突；建议对齐到 canonical，以免 manifest 字段歧义。
- **质量门**：主理人独立复验（读全部 6 个文件 + 实跑 selftest PASS + 规格交叉核对），非仅信文档声明。
- **待办 / 开放项（非臆造）**：① E1 真实资产产出（art-director，AI 原图 → 跑 pipeline → 登记 manifest）；② Godot 侧 `.import`/Import Preset 固化 + `palette_validator` headless CI 实跑；③ R5/R6 与真实导入校验依赖 Godot 环境，本沙箱无 Godot 故未跑。

*本拆分为 Phase 5 排期依据；A/B/C/D 已 commit（a6261a4/f078082/b666d46），E 工具链已验证闭环（E1 资产产出 + Godot 应用为开放项），F 半成品已备份，G 待接。*

## 7. Epic C 执行进度（2026-11-04 · 工程负责人交付，主理人质量门核验）

- **C1** `src/gameplay/combat/combat_director.gd`（`extends RefCounted`，`step_simulation(dt)` 由 SimulationClock 10Hz tick 调用）：锁敌最近敌人、自动普攻（APS 累加发射）、灵兽协战、技能 CD 推进、敌人薄 AI（朝主角移动+普攻，EnemyAI 接缝）、死亡结算（C3 30% 转化）；无敌人→idle（GDD §6.1）；确定性（同 `_rng` 序列+输入+dt 必一致）。
- **C2** `src/gameplay/ai/simulation_clock.gd`（`extends Node`，由 R3 原型晋升）：`advance(delta)` 累加器 + 10Hz tick（TICK_DT=0.1）+ MAX_CATCHUP=3（积压丢弃防雪崩）+ 自适应降 5Hz（TICK_DT_SLOW=0.2，连续 OVER_BUDGET_LIMIT=30 超预算帧触发）；tick 内先 `input_queue.consume_into` 再 `combat_director.step_simulation`（ADR-2+ADR-3 联动）。
- **C3** `src/gameplay/input/input_queue.gd` + `hit_zone.gd` + `joystick_pointer.gd`（均 `extends RefCounted`）：输入入队帧末结算、按热区去重、技能 0.5s cd 下限钳；热区 ≥48px a11y 警告；浮杆独占单一 `touch_id`、15% 死区、8 向吸附。
- **C4** `src/gameplay/combat/damage_calc.gd`（GDD §3.5 逐字落地：Raw=ATK×Coeff、Mitigated=Raw×100/(100+DEF×K)、K=8、CritMult(crit_dmg/100，rng.randf())、Variance∈[0.90,1.10](rng.randf_range)、RuneMult(StatBlock)、clamp(1,99999)、floor）+ `skill_runtime.gd`（灵击 tap/cd4/coeff1.6/nearest、缚灵 swipe/cd8/coeff1.0/cone）+ `death_settlement.gd`（C3 30% 转化）。
- **C 依赖 D 的前置**：`src/core/stats/stat_block.gd`（`extends Resource`，C1 最小前置版，带 MINIMAL 头注释，Epic D1 重叠）：`build_run_base`(负 atk/def 钳 0) + `recompute_rune_mult`(Π 乘区) + `final_stat`(O(1))。
- **测试** `tests/unit/combat_test.gd`（GUT）：DamageCalc 确定性/钳制/Variance/Crit、SimulationClock 10Hz 稳态/追帧钳 3/自适应 5Hz、InputQueue 去重+0.5s 钳、JoystickPointer 8 向+死区、DeathSettlement 30%、StatBlock C1、CombatDirector 确定性+无敌人 idle。**本 sandbox 无 Godot，GUT 未执行**，仅按规范书写。
- **质量门**：主理人独立复验 `tools/ci/lint_no_global_random.py` → 退出码 0、扫描 18 个 .gd、ADR-5 通过；10 个文件逐一读盘确认结构与架构/ADR/GDD 一致（R3 原型晋升路径、K=8、MAX_CATCHUP=3、cd 0.5s 钳）。
- **待真机/后续**：EnemyAI/SpiritAI 独立文件（`enemy_ai.gd`/`spirit_ai.gd`）、OffscreenCuller、InputArbiter 集成层（把 `InputEventScreenTouch/Drag` 抽 dict→push、浮杆/按钮 touch 仲裁）留 Epic-C 后续桩；R3 真机 60/30fps 预算测量、GUT 在 CI 真跑（本沙箱无 Godot）。

## 8. Epic D 执行进度（2026-11-04 · 工程负责人交付，主理人质量门核验）

- **D1** `src/core/stats/stat_block.gd`（原地扩展 Epic C 最小前置为完整版）：保留 `build_run_base`/`recompute_rune_mult`/`final_stat`，新增 `set_base_stat`/`get_base`/`add_vein_add`/`reset` 增量 API；`FinalStat=(Base+ΣVeinAdd)×ΠRuneMult`；负 atk/def 钳 0；`_init` 重分配容器规避 Godot 类级可变默认陷阱。
- **D2** `src/gameplay/pouch/`：`pouch.gd`（三栏自动分拣、容量 12/24/24、满栏拒绝不静默丢、`equip_rune`、`get_equipped_rune_mults`→`StatBlock.recompute_rune_mult`、`to_dict/from_dict` 以 `{slug:count}` 排序确定、`coin_temp`、`tamer_runes`）+ `spirit_entry.gd`（`count` 堆叠）+ `rune_entry.gd`（`mult:{stat:factor}` 乘区）+ `party_manager.gd`（`PARTY_SLOTS=3`，满返回 false）+ `bestiary.gd`（首次解锁、`KNOWN_SLUGS`）。
- **D3** `src/gameplay/spirit_vein/`：`vein_node.gd`（MODIFY_STAT/UNLOCK_SKILL/GRANT_START；effect 支持 `add` 直加 / `pct=base×frac`）+ `vein_graph.gd`（三色 DFS 无环断言、前置依赖校验、`activate` 返回剩余 ember、`get_activated_modify_stats` 聚合 `ΣVeinAdd`、`to_dict/from_dict`）+ `run_snapshot.gd`（`apply_to` 把灵脉基底喂入 `StatBlock`）。
- **存档贯通** `src/core/save/save_service.gd`（ADR-1 扩展，未破坏既有 `save_run/load_run/save_meta/load_meta` 签名）：新增 `save_pouch`/`load_pouch`（run 级·存灵囊）、`save_permanent`/`load_permanent`（meta 级·存 bestiary+vein+ember）；`_write_run`/`_write_meta` 改为 load-first 增量写，多写操作互不覆写（ADR-1 语义保持）。
- **测试** `tests/unit/pouch_vein_test.gd`（GUT）：C1 公式（atk=(10+5)×(2.0×1.5)=45、def=(5+3)×1.5=12）、负 atk/def 钳 0、D1 增量 API、ENG-2 +1 堆叠、满栏拒绝不静默丢、`{slug:count}` 序列化往返、RuneEntry 格式、PartyManager slots、DAG 无环正反例、activate/ember 扣减、`ΣVeinAdd` 聚合、run_snapshot 注入、Bestiary 解锁+联动、save 重建一致。**本 sandbox 无 Godot，GUT 未执行**，仅按规范书写。
- **质量门**：主理人独立复验 `tools/ci/lint_no_global_random.py` → 退出码 0、扫描 32 个 .gd、ADR-5 通过；11 个文件逐一读盘确认契约正确（C1 公式、ENG-2、DAG、ember 扣减、save 增量写 ADR-1 安全）。
- **待真机/后续**：`save_service` 真实 `ConfigFile` 往返 + 全部 GUT 断言待 Godot 实跑（本沙箱无 Godot）；单一灵兽 `equipped_runes` 为运行时叠加层、本 MVP 不持久化（已在 `pouch.gd` 注明边界）。
