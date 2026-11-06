# ADR-6 · 平台定位变更：PC（Windows Desktop）单平台，彻底放弃移动端

> **决策日期**：2026-11-06
> **决策者**：用户（项目主理人）拍板「C · 转向 PC 优先」+「移动端彻底放弃」
> **状态**：✅ 已批准；Wave 1（真源层）已落地，Wave 2–4 待分批报批
> **依据**：`CLAUDE.md §8.1`（破坏性改动须先更本文档 + 主理人审批）
> **关联**：`CLAUDE.md §1/§5/§8.1`、`architecture-doc.md §0/§1.6/§6`、`feasibility-review.md`、`docs/qa/archive/r1r3-device-test-plan.md`（Wave 2b 已归档）

---

## 1. 上下文

- Phase 1–4 全部文档把「移动端 iOS / Android，触屏单手」写进项目身份与设计契约：`CLAUDE.md §1`、`concept-doc.md §1/P1/§6.2`、`ux-spec.md`、`combat-system-gdd.md §1`、`architecture-doc.md §0 第 6 条 / §1.6`、`accessibility-requirements.md §0/§3.2`。由此派生：竖屏 720×1280、拇指热区、≥48px 触控命中区、单局 5–10 分钟碎片、低端 iOS/Android 真机性能指标（R1/R3）。
- 实际阻塞：本环境无 `adb`、无 iOS/Android 真机、无 Android SDK / 导出模板 / keystore，G4 真机测量无法闭环；仓库只有空 `src/main.tscn`，无四主屏 `*.tscn`、无 `TileMapLayer`、无粒子层，R1/R3 的渲染分项标 `BLOCKED-BY-SCENE`。
- 可运行条件：本机 Windows + Godot 4.3 headless 已可实跑（7 scripts / 54 tests / 11468 asserts），CI 为 `windows-latest` 双绿；Windows Desktop 导出不需要 Android SDK / keystore / 额外模板。
- 用户裁决（2026-11-06）：选择 **C · PC 优先**，并明确 **移动端彻底放弃**。

## 2. 决策

**目标平台改为 Windows Desktop（PC）单平台；iOS / Android 彻底放弃**——不再是目标平台，不再作为「后续可选移植」，不保留兼容承诺、不保留移动端设备矩阵与专有验收项。

### 2.1 解除的红线（自本 ADR 生效日起不再作为约束）

| # | 被废止条款 | 原出处 |
|---|---|---|
| 1 | 目标平台 iOS / Android | `CLAUDE.md §1`、概念头部、架构头部等 |
| 2 | 触屏单手 / 拇指热区 / 左右手握持布局 | 概念 §1/P1/§6.2、UX 规格 §0/§1/§7 |
| 3 | 竖屏 720×1280 逻辑基准与竖屏 HUD | UX 规格 §1、`project.godot`、战斗 GDD §4 |
| 4 | ≥48px 触控命中区（Apple HIT / Android dp 依据） | a11y §0/§2 #4/§3.2/§4、UX 规格 §3–§5、美术圣经 §4 |
| 5 | DPR 2~3 / 移动端省电 / iOS 后台强杀专属风险 | a11y §0/§3.5、feasibility R2、ADR-1 风险栏 |
| 6 | 单局 5–10 分钟碎片、通勤 / 睡前场景 | 概念 §1/§4.1/§6.2、战斗 GDD §1 |
| 7 | 低端 iOS/Android 真机为 R1/R3 关闭硬证据 | `docs/qa/archive/r1r3-device-test-plan.md §0/§1/§8`（已归档）、架构 §6 |

### 2.2 保持不变（不得借平台变更顺带推翻）

- Godot **4.3 冻结**（`CLAUDE.md §2`，已签字）。
- ADR-1 层间硬存档 / ADR-2 输入帧末队列结算 / ADR-3 10Hz tick + `MAX_CATCHUP=3` / ADR-4 像素资产离线管线 + 导入预设 / ADR-5 RNG 单一出口；C1 `StatBlock` 乘算契约。
- Basic 级非触控项：形状 + 颜色双编码、色盲安全配色、非色彩提示、字号 ≥14px、CVD 模拟验收。
- 诚实性纪律：零臆造测量数字、CONCERNS 翻转属独立审批。

## 3. 新平台契约

| 项 | 新口径 |
|---|---|
| 目标平台 | Windows Desktop（PC）单平台；如需其他桌面系统须另立 ADR |
| 逻辑分辨率 | 横屏 **1280×720 @1x**，整数倍缩放（2×→2560×1440）护 ADR-4 `filter=false` 像素资产；窗口可缩放但须整数倍 |
| 输入 | 键盘（WASD / 方向键移动）+ 鼠标（左键点击 / 拖拽）+ 技能键位 → 统一转 `{"position": Vector2, "touch_id": 0}` 同构字典入 `InputQueue`；ADR-2 帧末结算、热区去重、0.5s cd 钳不变 |
| 节奏 | 单局 **10–20 分钟**桌面会话；层间硬存档点仍为唯一存档点 |
| 可访问性 | 「键鼠可操作目标」取代触控 48px：主操作点击区域 ≥24×24px 且**全功能键盘可达 / 键位可重映射**；Basic 其余四项不变 |
| 性能基线 | R1/R3 改 PC 窗口 / 全屏基线（目标 60fps，30fps 为下限档），独立 QA 表；每行标注【PC 基线 · 非移动端真机】 |
| 存档 | ADR-1 不变；R2 风险改述为「PC 进程被强杀 / 断电时层间存档一致性」，`NOTIFICATION_WM_CLOSE_REQUEST` 仍为双保险 |

## 4. 影响面与风险（只读核验已确认）

1. **布局硬编码**：5 个 `.gd` 共 6 处硬编码 `720×1280`（`overview_screen.gd`、`battle_screen.gd`、`pouch_screen.gd`、`spirit_vein_screen.gd`、`test_ui.gd` 两处 `Rect2(0,1232,720,48)`）。改横屏前须抽 `LayoutConfig` 单一真源、测试改读配置，否则 Epic F 热区与 54 个 GUT 用例会失效。
2. **G4 失去适用前提**：`docs/qa/archive/r1r3-device-test-plan.md`（Wave 2b 已归档）的设备矩阵（Redmi 9A / Pixel 6a / iPhone SE）与 §8「目标最低档 iOS/Android 真机」硬证据不再成立；`export_presets.cfg` 的 Android 预设骨架已于 Wave 2b 删除，`src/qa/probe_runner.tscn` 已重定位为 PC 基线。**本 ADR 不自动关闭 R1 / R3 CONCERNS**——仍需 PC 实测数据 + 独立审批，禁止拿 PC 数字冒充原真机判据。
3. **`_adapt` 偏差仍在**：`simulation_clock.gd::_adapt()` 以 `delta > 1/60` 判超预算，PC 掉帧至 30fps 同样会误降 5Hz，污染 R3 测量；修复属生产代码改动，需单独授权。
4. **审计链**：已签字文档采用「版本升级 + 顶部废止横幅 + 规范句替换」，不静默删除历史原文；git 变更记录保留完整差异。

## 5. 分批执行与闸门

| Wave | 范围 | 状态 |
|---|---|---|
| **1** | 新增本 ADR + 改 `CLAUDE.md`、`concept-doc.md`、`ux-spec.md`、`combat-system-gdd.md`、`architecture-doc.md`、`adr-control-checklist.md`、`accessibility-requirements.md`、`plan.md`（共 9 个文件） | ✅ 本次批准并落地 |
| **2** | 约 12 份下游文档对齐（✅ 已落地）：`spirit-pouch-gdd.md`、`spirit-vein-gdd.md`、`art-bible.md`、`asset-production-spec.md`、`pixel-asset-pipeline.md`、`lighting-direction-audit.md`、`VERSION.md`、`feasibility-review.md`、`prototype-r1r3-report.md`、`epic-breakdown.md`、`tests/README.md`、`eng2-duplicate-egg-counting.md` | ✅ 本次批准并落地 |
| **2b** | 归档移动端 runbook v1.1 → `docs/qa/archive/r1r3-device-test-plan.md`、删除 / 替换 `export_presets.cfg` 的 Android `[preset.0]` 为 Windows Desktop 骨架、`docs/qa/evidence/` 证据模板重定位为 PC 基线 | ✅ 本次批准并落地 |
| **3** | `LayoutConfig` 抽真源、`project.godot` 横屏、Windows Desktop 导出预设、键鼠适配层、四主屏 `*.tscn` + `TileMapLayer` / 粒子层 | ⏸ 待报批 |
| **4** | 回归：GUT 全量、ADR-5 lint、文档一致性、导出 exe 启动、PC 帧预算基线 | ⏸ 待报批 |

## 6. 质量门

**CONCERNS（平台变更未回归）**：Wave 1 只改文档口径；Wave 2/2b 只改文档口径、归档与导出预设骨架，仍不改生产代码、不改测试断言、不翻转任何 CONCERNS、不写入任何性能测量数字。R1 / R3 仍为 **CONCERNS**；`architecture-doc.md §6` 状态列保持原判据，仅把「目标设备」描述改注为「PC 基线待建」。

## 7. 审批记录

| 时间 | 动作 | 结果 |
|---|---|---|
| 2026-11-06 | 用户选择 C（PC 优先） | 已拍板 |
| 2026-11-06 | 用户明确「移动端彻底放弃」+「批准 Wave 1」 | 已批准 |
| 2026-11-06 | Wave 1 落地（9 个文件） | 已完成 |
| 2026-11-06 | 用户批准「Wave 2 + 2b」 | 已批准 |
| 2026-11-06 | Wave 2 + 2b 落地（12 份文档对齐 + 归档 + 预设 / 证据模板重定位） | 本次 |

---

*本 ADR 为平台定位的唯一新真源；与其冲突的 Phase 1–4 历史条款以本文件为准。未执行 git commit。*
