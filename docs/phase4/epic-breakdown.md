# Epic 拆分与验收标准 / Epic Breakdown
> ⚠️ **ADR-6 状态声明（2026-11-06 · Wave 2）**：本文件为Phase 5 排期依据（§12 为当前有效状态，§5–§11 为当时交付的历史记录；其中 §5–§11 的 ≥48px / 竖屏 / 触屏实现数值**反映当时代码现状**，不因本声明改写，待 Wave 3 抽 LayoutConfig 后一并重订）。原「移动端 iOS / Android、触屏单手、竖屏 720×1280、≥48px 触控命中区、低端机真机判据」条款**已由 `docs/architecture/adr-006-pc-first.md` 废止**；现行契约为 **Windows Desktop 单平台（横屏 1280×720、键鼠输入、单局 10–20 分钟）**。下文保留的移动端表述均为当时的评审 / 测量 / 裁定原文，仅作历史记录，不得据此推导现行设计；R1 / R3 仍为 **CONCERNS**，PC 基线待 Wave 4 建立，CONCERNS 不自动翻转。历史原文保留于 git 变更记录，未静默删除。

> **文档类型**：MVP → 开发 Epic 拆分（Canonical for Phase 5 排期）
> **归属**：主理人签发，三角色（工程/美术/设计）确认
> **引用**：`docs/architecture/architecture-doc.md`（模块+DAG）、`docs/phase4/plan.md`、`design/gdd/*.md`、ADR×5 + C1
> **版本**：v1.2 · 2026-11-06 按 ADR-6 重订平台口径（PC 单平台）；v1.1 追加 §12「实跑回填与出口状态」。§5–§11 保留为各 Epic 交付当时的进度记录。

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
| **F** | PC 键鼠 UX 实现 | InputArbiter / UI / 可访问性 | UX 规格 / 可访问性 Basic | L |
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
- **验收**：生成耗时待 PC 基线回填（Wave 4；历史 runbook 见 `docs/qa/archive/r1r3-device-test-plan.md`）；确定性单测绿。
- **依赖**：A1。
- **映射**：ADR-1、R1 原型。

### Epic C — 战斗系统
- **目标**：实现战斗状态机、定步长 AI、帧末输入队列。
- **子故事**：
  - C1 Combat 状态机（回合开始→输入→AI tick→结算→结束）。【M】
  - C2 SpiritAI 定步长 10Hz tick，MAX_CATCHUP=3（ADR-3）。【M】
  - C3 InputArbiter 帧末输入队列（ADR-2）。【M】
  - C4 伤害公式/技能（对齐 `combat-system-gdd.md` §3.5）。【M】
- **验收**：60fps/30fps/自适应降频预算断言（ADR-6 后由 PC 窗口 / 全屏基线回填，Wave 4）；确定性 tick 可复现。
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

### Epic F — PC 键鼠 UX 实现
- **目标**：按 `ux-spec.md` v1.1 落地四主屏 + 横屏 Tab + 可访问性 Basic（键鼠口径，ADR-6）。
- **子故事**：
  - F1 横屏 Tab 栏（总览/灵囊/灵脉/地图），点击区域 ≥24×24px + 键盘可达。【M】
  - F2 战斗屏布局 + 技能键热区 + 状态双编码。【M】
  - F3 灵囊屏三栏 + 灵兽格 +1 角标（ENG-2）。【M】
  - F4 灵脉图谱屏节点点击区域 ≥24×24px + 键盘可达 + 缩放。【M】
  - F5 可访问性 Basic 验收（CVD 模拟、字号、非色彩提示）。【M】
- **验收**：全功能键盘可达 + 键鼠热区 100% 覆盖（ADR-6）；§5 五项 CVD 不丢信息。
- **依赖**：C3（InputArbiter）、D2、D3。
- **映射**：ux-spec.md、accessibility-requirements.md。

### Epic G — 测试与质量门
- **目标**：GUT 接入 + 确定性测试清单 + 设备测试 + CI 双绿。
- **子故事**：
  - G1 `tests/` 脚手架 + GUT 安装 + smoke 通过（见 `tests/README.md`）。【S】
  - G2 确定性测试：RNGService / DungeonGen / Save 重建。【M】
  - G3 战斗预算测试（60/30fps + MAX_CATCHUP）。【M】
  - G4 PC 窗口 / 全屏帧预算基线回填（ADR-6；原移动端 runbook 已归档，见 `docs/qa/archive/r1r3-device-test-plan.md`）。【M】
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
- **E3（Godot 导入预设·模板就位 + 应用待 Godot）**：`docs/engine-reference/godot/pixel_texture.import.tpl` 已固化覆写（compress/mode=0或1、filter=false、gen_mipmaps=false、detect_3d/compress_to=0、fix_alpha_border=true）；`palette_validator.gd` 的 EditorPlugin + `godot --headless --script` 入口已写。**真实 `.import` / Import Preset 文件待在 Godot 编辑器内一次性固化并提交**（VERSION.md §2.2 已更新：headless 已可运行，但编辑器导入预设仍未固化）。
- **工具链 ↔ 规格交叉核对（一致）**：manifest 14 列 = pixel-asset-pipeline §2（canonical）；MASTER(19)/SCENE(upper9/mid7/boss10/sanctuary9) = palette_source.json；VALID_SIZES(16/24/32/48)、描边 1–2px、alpha_cutoff=128、Bayer `[[0,2],[3,1]]/4` 与规格逐字对齐；CLAUDE.md §3 导入预设、§6 资产红线、§8.2 禁止项（人工绕过脚本即违规）齐备。
- **文档不一致（2026-11-05 已闭环）**：`asset-production-spec.md §3` 曾另列一套 14 列 manifest schema（`src_md5/validator_pass/import_preset/palette_version/author/note`），与 canonical 14 列（pixel-asset-pipeline §2 = 代码实现）字段语义冲突。v1.1 已把 §3 对齐 canonical 14 列、列出废弃字段并指向 `MANIFEST_COLUMNS` / `asset_manifest.csv` 表头（本轮文档闭环已完成）。
- **质量门**：主理人独立复验（读全部 6 个文件 + 实跑 selftest PASS + 规格交叉核对），非仅信文档声明。
- **待办 / 开放项（非臆造）**：① E1 真实资产产出（art-director，AI 原图 → 跑 pipeline → 登记 manifest）；② Godot 侧 `.import`/Import Preset 固化 + `palette_validator` headless CI 实跑；③ R5/R6 与真实导入校验依赖编辑器导入流程（预设未固化），至今未跑；Godot 4.3 headless 虽已可用（见 §12），不等于导入链路已闭环。

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

## 10. Epic G 执行进度（2026-11-05 · 主理人静态 API 对账 + CI 硬化）

> **状态提示**：本节为当日**上午**静态阶段的进度记录；此处「无 Godot / 仅静态对账 / 实跑待 Godot 环境」已于当日下午被真实实跑取代。**当前有效结论以 §12 为准**，原文保留作审计轨迹。

> **核心事实**：Epic G 目标为「GUT 接入 Godot CI 实跑」。本沙箱**无 Godot**（已 `which godot` 验证：NO_GODOT_ON_PATH），故真实边界是**接线 + 静态审计**，而非运行时实跑；此属环境阻断，非测试缺陷。

- **G1（CI 接入·硬化）**：`.github/workflows/test.yml` 重写——移除与 `lint.yml` 重复的 lint job，仅保留 `gut` job；修正 GUT 调用为 canonical 形式 `godot --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit/ -gexit`（原稿的 `--quit` 位置非标准），`-gexit` 使全绿退出码 0、任一失败非 0（CI 据此判红）；GUT 解包逻辑加固（兼容 `addons/gut/` 与根目录 `gut/` 两种发布布局，异常即 `exit 1` 并 `ls -R` 暴露结构）。GUT 版本固定 `9.3.0`，注释提示团队首跑核对与 Godot 4.3 兼容性。
- **G2（本地运行脚本）**：新增 `tools/ci/run_gut_tests.sh`，镜像 CI 的 gut 步骤；前置校验 `godot` 4.3 在 PATH、`addons/gut` 已安装，否则给出明确报错退出。
- **G3（静态 API 对账·质量门核心）**：主理人对 `tests/unit/` 下 **5 个 GUT 文件**引用的 **17 个生产类**逐一读真实源码核验方法/属性/签名：
  - `simulation_clock`（tick_count/is_slow/advance/combat_director/input_queue）、`combat_director`（setup/step_simulation/on_action/player.hp/enemy_count/coin_temp/is_player_dead）、`damage_calc`（compute 7 参 / compute_from_stats 4 参）、`input_queue`（set_hit_zone/push/advance_time/consume_into）、`hit_zone`（register_rect/resolve）、`joystick_pointer`（max_radius/press/move/get_direction/release 8 向+15% 死区）、`stat_block`（build_run_base/recompute_rune_mult/final_stat/set_base_stat/get_base/add_vein_add/reset）、`save_service`（save_pouch(dict)/load_pouch/save_permanent/load_permanent）、`rng_service`（new_floor_rng/floor_rng/seed_from_string/derive_seed）、`dungeon_generator`（generate_sync 3 参）、`fallback_template`（build→{seed:-1,floor:-1,fallback:true}）、`pouch`（CAP_RUNE/CAP_MATERIAL=24、add_spirit_egg/get_spirit_count/add_rune 满栏 false/equip_rune/tamer_runes/recompute_stat_block/to_dict/from_dict）、`rune_entry`（mult_dict/to_dict/from_dict）、`party_manager`（PARTY_SLOTS=3/recruit 满 false/remove/get_party）、`bestiary`（unlock 幂等/is_discovered/to_dict/from_dict）、`vein_graph`（register_node/assert_acyclic/can_activate/activate 返回剩余 ember/-1/get_activated_modify_stats 加算+pct/get_activated_node_ids）、`vein_node`、`run_snapshot`（apply_to）。
  - **结果：17/17 类全部吻合，0 处签名/方法名偏差**。可高置信度预期在 Godot 环境一次跑通（唯一未覆盖的是编译与运行时执行本身）。
- **G4（文档漂移修正）**：`tests/README.md` §1/§3 实际清单（smoke/rng_service/dungeon_gen/combat/pouch_vein 五件）替换原稿对 `save_rebuild_test.gd`/`combat_tick_test.gd` 的计划清单；新增 §6「CI 与本地运行」与 Epic G 状态注记；版本 v1.0→v1.1。
- **质量门**：主理人独立读盘核验（17 个生产类源码 + 5 个测试文件 + CI 脚本 + README 修正），非仅信文档声明；`tools/ci/lint_no_global_random.py` 不在 G 范围（已由 lint.yml 覆盖，ADR-5 通过）。
- **待真机/后续（环境阻断·非缺陷）**：① CI 在装有 Godot 4.3 的 runner 上**真实执行** `test.yml` 并反馈绿/红（当前沙箱无 Godot，无法本地验证 CI 绿）；② `save_service` 真实 `ConfigFile` 往返（pouch_vein_test 的 `save_reconstruction`）在 Godot 下验证文件 IO 一致；③ 若实跑暴露 GUT 9.x 版本/布局差异，按脚本内注释回写 `GUT_VER`。

## 11. Epic F 执行进度（2026-11-05 · 主理人直接落地 + 质量门核验）

> **状态提示**：本节「`ui_test.gd` 未执行 / 待 CI 真跑」为交付当时状态，现已被 §12 的真实实跑结论取代；`*.tscn` 场景与像素资产集成仍是开放项。原文保留作审计轨迹。

> **关键事实**：Epic F 半成品曾备份于 `C:/tmp/hollowkin_epicF_backup_20261104/`（6 文件，2026-11-04 因 429 限流中断）。本次 kickoff 不复用半成品的空 DTO，而是基于已落地（D2/D3/C3）的**真实 Pouch/VeinGraph/CombatDirector API** 重建，使 UI 真正绑定领域层（质量门"报告不跑在代码前"）。

- **F1（底部 Tab 栏 + 总览）**：`bottom_tab_bar.gd` 四槽 [总览/灵囊/灵脉/地图]，每槽 56×56px、间距 ≥8px（a11y §3.2），文字标签优先（弱图标·政务式，ux-spec §0.2）；`overview_screen.gd` 顶部资源文字标签 + 进入地牢主按钮（≥64px，热区偏下）+ 底部 Tab。
- **F2（战斗屏）**：`battle_screen.gd` 下半屏技能键（≥56px，拇指热区）+ 防御/跳过键；HUD view 暴露 hp/低血双编码(≤30%→heart+红框，a11y §3.4)/敌数/技能就绪态；zone_id 直转 `CombatDirector.on_action`（lingji/fuling），经帧末输入队列（ADR-2）。
- **F3（灵囊屏）**：`pouch_screen.gd` 三栏分段控件（≥48px）+ 物品格（≥48px）；`pouch_view_data.gd` 绑定真实 `Pouch`+`Bestiary`——灵兽按 slug 聚合、count>1→+1 堆叠角标（ENG-2）、符文 mult 乘区（C1）。
- **F4（灵脉图谱屏）**：`spirit_vein_screen.gd` 节点圆形命中区（半径 24→直径 48 ≥48px，a11y §3.2 澄清）+ 缩放按钮（重建合并热区）；`spirit_vein_view_data.gd` 绑定真实 `VeinGraph`——状态形状编码（active=星 / available=高亮 / locked=锁，ux-spec §3.3），点击经 `can_activate`→`activate` 扣 ember。
- **F5（可访问性 Basic）**：`accessibility.gd` 静态助手——`clamp_font`(≥14/18)、`is_cvd_safe`（危险红须配形状、禁纯红绿对立）、`dual_code`（形状+色相矩阵）；CVD 母库子集、低血/禁用形状提示齐备。
- **路由/架构**：`ui_screen.gd`（屏基类，RefCounted 可无头单测）+ `screen_router.gd`（复用 Epic C 的 InputQueue/HitZone 做帧末结算 ADR-2；**战斗中隐藏 Tab 防误触**）+ `ui_context.gd`（领域依赖注入容器）。
- **测试**：`tests/unit/ui_test.gd`（GUT）6 例，绑定真实 Pouch/VeinGraph/CombatDirector——tab 布局 / 路由派发 / 战斗中 Tab 禁用 / 可访问性钳制与双编码 / +1 角标 / 节点状态分类 / 战斗技能热区。
- **质量门**：主理人独立复验 `lint_no_global_random.py` → 退出码 0、扫描 38 个 .gd、ADR-5 通过；12 个 UI 文件 + 1 测试逐一读盘，绑定 API 与 D2/D3/C3 源码逐一对账（关键调用全吻合）。
- **待真机/后续（环境阻断·非缺陷）**：① 本沙箱无 Godot，`ui_test.gd` 未执行，仅按规范书写，待 CI（`test.yml`）真跑；② 真实 Godot Control 场景文件（`*.tscn`）与像素资产（ADR-4）为 UI 集成层，不在本 Epic 代码范围；③ 灵兽格长按/拖拽装备、防御/跳过语义为后续交互增强。

## 12. Epic G / F 实跑回填与 Phase 4 出口状态（2026-11-05 · 主理人直接验收）

> **本节为当前有效状态**：§5–§11 为各 Epic 交付当时的进度记录，凡「本沙箱无 Godot /
> GUT 未实跑 / 待 CI 真跑」表述均由本节取代。Epic G（GUT 接入 CI）与本次 Epic F
> （触屏 UI 测试）已从「静态 API 对账」升级为「本地 + 远端 Windows CI 真实实跑」。

### 12.1 环境与范围

| 项 | 结论 |
|---|---|
| 引擎 / 插件 | Godot `4.3.stable.official.77dcf97d8` + GUT `9.3.0`（tag `v9.3.0`） |
| 本地 | Windows，`*_console.exe` headless；干净 checkout 等价流程 |
| 远端 | GitHub Actions `windows-latest`；test run `42045291457`、Lint run `42045291552`（sha `0a19159`）均 **success** |
| 平台范围 | 2026-11-05 决策：暂时只在 Windows 运行，不做 Linux 侧验证 |
| 提交链 | `c33ba49`（实跑闭环）→ `9c33a9d`（Windows-only）→ `d3a2513`（Lint UTF-8 + GUT 超时）→ `0a19159`（挂起修复） |

### 12.2 验证结果（可复现）

- **本地 Windows 端到端等价验证**：GUT **6 scripts / 50 tests / 50 passing / 11452 asserts / `GUT_EXIT=0`**；ADR-5 lint 扫描 **39 个 `.gd`、0 违规**；两个 workflow YAML 解析 PASS。
- **远端 `windows-latest`（sha `0a19159`）**：`Generate global script class cache` 输出 `wrote 40 global classes`，`Run GUT headless` 约 **2 秒**完成，输出同为 6/50/50/11452；Lint success。
- 首轮无超时的悬挂 test run `42038019907`（sha `9c33a9d`）已通过 Actions API 取消（`completed / cancelled`），近期 run 无 `in_progress`。
- 残留**非致命**告警：GUT 自带字体未导入引起的 fontdata / ObjectDB leak 提示，本地与 CI 同样存在，不影响结果。

### 12.3 实跑暴露并修复的问题（静态审计无法发现）

1. `joystick_pointer.gd` 的 `_snap_8` 混入 Tab 缩进 → GDScript 4.x 拒绝解析，`test_combat.gd` 整份无法加载、其中用例全部漏计。
2. `DirAccess.make_dir_recursive()` / `remove()` 为实例方法，禁止静态调用。
3. **Epic F 真实逻辑缺陷**：`InputQueue` 的 0.5s 技能 CD 被误施加于底部 Tab 导航；新增 `set_cooldown_exempt()`，由 `ScreenRouter.build()` 注册 tab 豁免，CD 回归「仅技能防抖」本意。
4. 其余：8 处类型推断失败、UI 子类漏 `super._init()` 致 `hit_zone=null`、`FloorCache.get` 与 `Object.get` 冲突改名 `fetch`、autoload 键名、`main.gd` 静态调用、GUT `test_*.gd` 前缀、joystick 浮点噪声吸附。
5. **CI 挂起根因**：项目根 `gut_tmp/` 下的 GUT 副本被 `gen_global_class_cache.gd` 扫描（45 类 vs 本地 40 类）→ `Class "GutMain" hides a global script class` → GUT 主类加载失败 → `run_tests` 等不到完成信号、挂起至超时。修法：归档改在项目外 `$env:RUNNER_TEMP` 解压并即时清理；生成器加 `SKIP_DIR_NAMES` 与同名 `class_name` 去重（`res://addons/` 优先）。字体错误经日志比对证伪为非根因。
6. Windows runner 的 Lint 中文输出在 cp1252 下抛 `UnicodeEncodeError` → 脚本入口强制 UTF-8 + workflow 设 `PYTHONIOENCODING: utf-8`。

### 12.4 Epic 逐项状态（以可核验证据为准）

| Epic | 状态 | 证据 / 剩余 |
|---|---|---|
| A 工程基线 | ✅ 代码 + 单测实跑 | RNGService / Save 确定性用例通过；ADR-5 lint 0 违规 |
| B 地牢生成 | ✅ 代码 + 单测实跑 | 同 (seed,floor) 布局一致用例通过；R1 渲染尖峰待 PC 基线实测（Wave 4） |
| C 战斗系统 | ✅ 代码 + 单测实跑 | 解析修复后 `test_combat.gd` 恢复加载、用例全通过；EnemyAI/SpiritAI 独立文件与 InputArbiter 集成层仍为桩 |
| D 灵兽灵囊 | ✅ 代码 + 单测实跑 | C1 / ENG-2 / DAG / Save 重建用例通过；`equipped_runes` 为运行时叠加层不持久化 |
| E 资产管线 | ⚠️ 工具链 selftest PASS，资产未产出 | `pixel_pipeline.py selftest` exit 0、R1–R4 绿；E1 真实 AI 原图 / `.import` 预设固化 / R5–R6 实跑仍开放 |
| F PC 键鼠 UX（当时为触屏逻辑层） | ✅ 逻辑层 + `test_ui.gd` 实跑 | 四主屏 / Tab / a11y 用例通过；`*.tscn` 场景与像素资产集成未做 |
| G 测试质量门 | ✅ GUT 接入 + 本地/远端 CI 双绿 | 见 §12.2；G4 已重定位为 PC 帧预算基线（Wave 4），R1 / R3 仍 CONCERNS |

### 12.5 Phase 4 出口判据对照

- `docs/phase4/plan.md §4` 判据 **4 / 5 已勾选**（有运行证据）；判据 **1 / 2 / 3 保持未勾选**（签字 / 三角色确认无凭据，不臆造）。
- 所有待测项继续有效；ADR-6 后判据改由 **PC 窗口 / 全屏基线**采集（Wave 4），**CI 全绿不替代帧预算实测**；R1 / R3 仍为 CONCERNS、不自动翻转。Phase 3 报告中的「本沙箱无 Godot、无低端机」为当时环境陈述，其真机数据结论未被本节推翻。

### 12.6 开放项清单（编号，供排期）

1. **G4 PC 基线（ADR-6 重定位）**：60/30fps 预算改由 PC 窗口 / 全屏采集；单手可达性热力图已废止，改「全功能键盘可达」；R2 改 PC 进程强杀 / 断电双保险。原移动端 runbook 已归档。
2. **Epic E**：E1 原图 → pipeline → manifest；`.import` / Import Preset 固化；`palette_validator` headless CI 与 R5/R6。
3. **Epic F 集成**：四主屏 `*.tscn` 场景 + 像素资产接入，形成可玩画面。
4. **集成层**：InputArbiter 接入 PC 键鼠事件（Wave 3 适配层）、`enemy_ai.gd` / `spirit_ai.gd` 独立文件、DungeonGen↔Save 重建联测。
5. **CI 硬化（本轮已完成）**：两条 workflow 补齐 job 级超时（lint 10 / gut 15 分钟）；`addons/gut/` 明确忽略；本地 `run_gut_tests.sh` 与 CI 对齐生成全局类缓存。**Linux runner 恢复暂缓**。

---

*本拆分为 Phase 5 排期依据；§12 记录的 50/50 为 Wave 3 之前的历史基线，Wave 3 后 GUT 基线为 8/60/60/11511 且 PC 主场景 headless 自检 `WAVE3_SELFTEST_OK`。§5–§11 保留为各 Epic 交付当时的审计记录；平台口径以 ADR-6 为准。*
