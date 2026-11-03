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

*本拆分为 Phase 5 排期依据；工作量占位为 Lean 估算，正式排期在 Phase 5 kickoff 敲定。未 git commit。*
