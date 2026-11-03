# Phase 4 预制作总纲 / Pre-Production Plan

> **文档类型**：Phase 4 总纲（Studio 主理人签发，Lean 口径）
> **上游锚点**：Phase 3 已冻结（架构 `docs/architecture/architecture-doc.md`、ADR×5 + C1、`docs/architecture/prototype-r1r3-report.md`、CLAUDE.md、ADR-4 像素资产后处理链路）。
> **下游出口**：Phase 5 生产实现（按本总纲 Epic 拆分进入）。
> **版本**：v1.0 · 未 git commit。

---

## 0. 一句话定位

Phase 3 把"该做什么、怎么约束"钉死了（架构/ADR/原型/资产链路）。**Phase 4 不做实现**，只搭四块脚手架，把设计语言转成"工程可直接拆工单、美术可直接排产、QA 可直接写用例"的蓝图。

## 1. Phase 4 范围（四块脚手架）

| # | 脚手架 | 交付物 | 主理人落点 |
|---|---|---|---|
| P4-1 | **总纲** | 本文件 | 进入 Phase 5 的出口判据 |
| P4-2 | **UX 规格** | `design/gdd/ux-spec.md` | 单手触屏交互模型 + 界面流 + 状态机 |
| P4-3 | **资产规格** | `docs/art-bible/asset-production-spec.md` | 基于 ADR-4 的 MVP 像素资产清单与闭环排产 |
| P4-4 | **Epic 拆分** | `docs/phase4/epic-breakdown.md` | MVP → Epic A–G，含验收/依赖/ADR 映射 |
| P4-5 | **测试脚手架** | `tests/README.md` + `tests/unit/*` + `.github/workflows/test.yml` | GUT 接入 + 确定性测试清单 + CI |

## 2. 设计约束（Phase 4 全文须遵守）

- **引擎**：Godot 4.3（已签字冻结，见 `docs/engine-reference/godot/VERSION.md`）。
- **随机性纪律**：唯一出口 `src/core/rng/rng_service.gd`（ADR-5）；全局 `randf/randi/randomize` 由 `tools/ci/lint_no_global_random.py` 拦截。
- **像素资产红线**：AI 原图 → `src/core/asset_pipeline/pixel_pipeline.py` 离线后处理 → `palette_validator.gd` 校验（R1–R6）→ Godot 导入预设（ADR-4）。人工不得跳过。
- **可访问性 Basic 红线**（Lean 强制，见 `docs/accessibility-requirements.md`）：触控目标 ≥48px（命中区）、形状+颜色双编码、色盲安全配色、最小字号 ≥14px。
- **存档一致性**：种子化可恢复存档，层间落盘（ADR-1）。

## 3. 与 Phase 1–3 的衔接

- **架构模块**（Phase 3 已定）：DungeonGen / Combat / Pouch / SpiritVein / Save / InputArbiter / SpiritAI / AssetPipeline + 跨切 RNGService / StatBlock。
- **GDD 已存在**：`combat-system-gdd.md` / `spirit-pouch-gdd.md` / `spirit-vein-gdd.md` / `mvp-spirit-bestiary.md`（v1.3）。Phase 4 的 UX/资产/Epic 须引用而非重写这些口径。
- **设计裁定已落**：ENG-2 重复灵兽蛋 = +1 堆叠计数（`design/gdd/decisions/eng2-duplicate-egg-counting.md`）。
- **待真机实测**：R1/R3 设备指标见 `docs/qa/r1r3-device-test-plan.md`（标【需真机实测】，不臆造）。

## 4. 进入 Phase 5 的出口判据（Exit Criteria）

满足全部方可进入生产：

1. [ ] UX 规格经主理人签字，单手可达性热力图与四主屏线框被认可。
2. [ ] 资产规格的 MVP 资产清单、尺寸档、场景子集归属、manifest 字段被美术负责人签批。
3. [ ] Epic 拆分 A–G 的故事与验收标准被三角色（工程/美术/设计）确认，依赖图无环。
4. [ ] 测试脚手架的 GUT 可在目标机跑通 smoke，CI 同时挂 lint + test 两条绿线。
5. [ ] `src/core/rng/rng_service.gd` 已创建并通过"种子确定性"单测（ADR-5 落地前置）。

## 5. 风险与遗留

- **rng_service.gd 尚未创建**：CLAUDE.md / 架构均以其为设计指定路径，lint 白名单已预留；须作为 Epic A 第一棒。
- **真机资源未到位**：R1/R3 的 60fps/30fps 预算断言仍待 `docs/qa/r1r3-device-test-plan.md` 在真机回填。
- **MVP 灵兽 4 只 + boss + sanctuary**：Phase 2 扩 5–8 只时须复用 bestiary §6 审计模板维持剪影唯一性。

---

*本总纲为 Phase 4 总入口，四块脚手架独立成册，交叉引用见各文件。未修改 `src/` 业务代码（仅 test 脚手架占位），未 git commit。*
