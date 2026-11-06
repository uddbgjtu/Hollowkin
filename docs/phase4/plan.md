# Phase 4 预制作总纲 / Pre-Production Plan

> **文档类型**：Phase 4 总纲（Studio 主理人签发，Lean 口径）
> **上游锚点**：Phase 3 已冻结（架构 `docs/architecture/architecture-doc.md`、ADR×5 + C1、`docs/architecture/prototype-r1r3-report.md`、CLAUDE.md、ADR-4 像素资产后处理链路）。
> **下游出口**：Phase 5 生产实现（按本总纲 Epic 拆分进入）。
> **版本**：v1.2 · 2026-11-06 按 ADR-6 重订平台口径（PC / Windows Desktop 单平台，移动端彻底放弃）；v1.1 已回填 Phase 5 实跑进展与出口判据状态。

> ⚠️ **ADR-6 废止声明**：本总纲中的「单手触屏 / 触控 ≥48px / 移动端真机」表述已废止，改按 `docs/architecture/adr-006-pc-first.md` 执行；**出口判据勾选状态、GUT 实跑数字、ADR-1/2/3/4/5 与 C1 契约全部不变**。

---

## 0. 一句话定位

Phase 3 把"该做什么、怎么约束"钉死了（架构/ADR/原型/资产链路）。**Phase 4 不做实现**，只搭四块脚手架，把设计语言转成"工程可直接拆工单、美术可直接排产、QA 可直接写用例"的蓝图。

## 1. Phase 4 范围（四块脚手架）

| # | 脚手架 | 交付物 | 主理人落点 |
|---|---|---|---|
| P4-1 | **总纲** | 本文件 | 进入 Phase 5 的出口判据 |
| P4-2 | **UX 规格** | `design/gdd/ux-spec.md` | PC 键鼠交互模型 + 界面流 + 状态机（ADR-6 重订） |
| P4-3 | **资产规格** | `docs/art-bible/asset-production-spec.md` | 基于 ADR-4 的 MVP 像素资产清单与闭环排产 |
| P4-4 | **Epic 拆分** | `docs/phase4/epic-breakdown.md` | MVP → Epic A–G，含验收/依赖/ADR 映射 |
| P4-5 | **测试脚手架** | `tests/README.md` + `tests/unit/*` + `.github/workflows/test.yml` | GUT 接入 + 确定性测试清单 + CI |

## 2. 设计约束（Phase 4 全文须遵守）

- **引擎**：Godot 4.3（已签字冻结，见 `docs/engine-reference/godot/VERSION.md`）。
- **随机性纪律**：唯一出口 `src/core/rng/rng_service.gd`（ADR-5）；全局 `randf/randi/randomize` 由 `tools/ci/lint_no_global_random.py` 拦截。
- **像素资产红线**：AI 原图 → `src/core/asset_pipeline/pixel_pipeline.py` 离线后处理 → `palette_validator.gd` 校验（R1–R6）→ Godot 导入预设（ADR-4）。人工不得跳过。
- **可访问性 Basic 红线**（Lean 强制，见 `docs/accessibility-requirements.md`，ADR-6 重订第 4 项）：键鼠可操作目标 ≥24×24px + 全功能键盘可达 / 键位可重映射、形状+颜色双编码、色盲安全配色、最小字号 ≥14px。
- **存档一致性**：种子化可恢复存档，层间落盘（ADR-1）。

## 3. 与 Phase 1–3 的衔接

- **架构模块**（Phase 3 已定）：DungeonGen / Combat / Pouch / SpiritVein / Save / InputArbiter / SpiritAI / AssetPipeline + 跨切 RNGService / StatBlock。
- **GDD 已存在**：`combat-system-gdd.md` / `spirit-pouch-gdd.md` / `spirit-vein-gdd.md` / `mvp-spirit-bestiary.md`（v1.3）。Phase 4 的 UX/资产/Epic 须引用而非重写这些口径。
- **设计裁定已落**：ENG-2 重复灵兽蛋 = +1 堆叠计数（`design/gdd/decisions/eng2-duplicate-egg-counting.md`）。
- **待实测（ADR-6 重定位中）**：R1/R3 帧预算指标原移动端真机判据失效，须改由 PC 窗口 / 全屏基线表测量（Wave 2b/4）；`docs/qa/archive/r1r3-device-test-plan.md` 已于 Wave 2b 归档，标【需实测】不臆造。

## 4. 进入 Phase 5 的出口判据（Exit Criteria）

满足全部方可进入生产：

1. [ ] UX 规格经主理人签字，全功能键盘可达性核验与四主屏线框被认可（ADR-6 重订判据）。**（F1–F5 代码与 `test_ui.gd` 已在 Godot 4.3 实跑；签字/线框认可无凭据，保持未勾选）**
2. [ ] 资产规格的 MVP 资产清单、尺寸档、场景子集归属、manifest 字段被美术负责人签批。**（规格已定稿入库，manifest 字段已对齐 canonical 14 列；签批无凭据，保持未勾选）**
3. [ ] Epic 拆分 A–G 的故事与验收标准被三角色（工程/美术/设计）确认，依赖图无环。**（依赖图无环已复核；三角色确认无凭据，保持未勾选）**
4. [x] 测试脚手架的 GUT 可在目标机跑通 smoke，CI 同时挂 lint + test 两条绿线。**（2026-11-05：本机 Windows 与 GitHub Actions `windows-latest` 实跑 6 scripts / 50 tests / 50 passing / 11452 asserts；test run `42045291457`、Lint run `42045291552` 均 success，sha `0a19159`。2026-11-06 本地基线已增至 7 scripts / 54 tests，见 `epic-breakdown.md §12`）**
5. [x] `src/core/rng/rng_service.gd` 已创建并通过"种子确定性"单测（ADR-5 落地前置）。**（`test_rng_service.gd` 在 Godot 4.3 headless 实跑通过；ADR-5 lint 扫描 39 个 `.gd` 零违规）**

> **回填口径（2026-11-05，ADR-6 后仍适用）**：仅勾选有可核验运行证据的判据 4/5；1–3 属签字 / 确认类，
> 无签批凭据不臆造勾选。帧预算实测指标仍未回填，**不因 CI 全绿或平台变更视为完成**；ADR-6 未自动翻转 R1/R3 CONCERNS。
> 实跑明细与 Epic 逐项状态见 `docs/phase4/epic-breakdown.md §12`、`tests/README.md §6`。

## 5. 风险与遗留

- **rng_service.gd（已闭环）**：Epic A1 已创建 `src/core/rng/rng_service.gd`，`test_rng_service.gd` 在 Godot 4.3 headless 实跑通过；ADR-5 全局随机禁令由 `lint.yml` 在 CI 复验（0 违规）。
- **帧预算实测未到位（ADR-6 重定位中）**：R1/R3 的 60fps/30fps 预算须改由 PC 窗口 / 全屏基线回填；原移动端真机 runbook 已归档（Wave 2b），Phase 3 报告中【需真机实测】标注按 ADR-6 改注为【PC 基线待建】，零臆造数字。
- **ADR-6 平台变更（Wave 1/2/2b 已落地）**：目标平台改为 Windows Desktop 单平台、移动端彻底放弃；下游 12 份文档已对齐、移动端 runbook 已归档、Android 导出预设已替换为 Windows Desktop 骨架；Wave 3 布局/输入适配/四主屏、Wave 4 回归与 PC 帧预算基线仍待分批报批；平台变更本身**不视为 Phase 4 出口判据已满足**。
- **CI 平台范围**：2026-11-05 决定暂时只在 `windows-latest` 跑 test/lint，Linux 侧验证暂缓；恢复多平台矩阵为开放项。
- **资产与场景集成**：E1 真实 AI 原图、Godot `.import`/Import Preset 固化、四主屏 `*.tscn` 场景尚未落地；当前测试覆盖的是 GDScript 逻辑层，不等于可玩画面已集成。
- **MVP 灵兽 4 只 + boss + sanctuary**：Phase 2 扩 5–8 只时须复用 bestiary §6 审计模板维持剪影唯一性。

---

*本总纲 v1.2（2026-11-06 按 ADR-6 重订平台口径，出口判据勾选状态不变）为 Phase 4 总入口，四块脚手架独立成册。Phase 5 实施进展与实跑结论见 `docs/phase4/epic-breakdown.md §12`、`tests/README.md §6`。*
