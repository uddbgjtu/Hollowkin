# 测试脚手架 / Test Scaffolding
> ⚠️ **ADR-6 状态声明（2026-11-06 · Wave 2）**：本文件为测试脚手架（现行测试策略）。原「移动端 iOS / Android、触屏单手、竖屏 720×1280、≥48px 触控命中区、低端机真机判据」条款**已由 `docs/architecture/adr-006-pc-first.md` 废止**；现行契约为 **Windows Desktop 单平台（横屏 1280×720、键鼠输入、单局 10–20 分钟）**。相关规范句已按 ADR-6 重订；ADR-1/2/3/4/5、C1、Godot 4.3 冻结、Basic 非触控 a11y 项与所有历史测量数字不变。历史原文保留于 git 变更记录，未静默删除。

> **文档类型**：测试策略 + GUT 接入 + 确定性测试清单（Phase 4 脚手架，Lean）
> **归属**：engineering-lead 起草，主理人签发
> **引用**：`docs/architecture/adr-control-checklist.md`（ADR-1/2/3/5）、`tools/ci/lint_no_global_random.py`、`docs/qa/archive/r1r3-device-test-plan.md`（已归档·历史方法学）、`docs/phase4/epic-breakdown.md §12`
> **版本**：v1.5 · 2026-11-07 Wave 3b / Wave 4 / `_adapt` 修复落地：新增 `test_render_layer.gd`（9 例）、`test_frame_budget.gd` 偏差探测用例还原为正确断言，GUT 基线升级为 **9 scripts / 72 tests / 72 passing / 11582 asserts**；v1.4 Wave 3、v1.3 ADR-6 PC 口径、v1.2 Godot 4.3 实跑与 Windows CI 双绿。
> **环境**：Godot `4.3.stable.official.77dcf97d8` + GUT `9.3.0`（tag `v9.3.0`）；本机 Windows 与 GitHub Actions `windows-latest` 均已 headless 实跑。
> **范围决策**：CI 暂时只在 Windows 运行，不做 Linux 侧验证（2026-11-05 主理人决定）；Linux 恢复为后续开放项。

---

## 0. 测试哲学（确定性优先）

本项目所有随机须经 `RNGService`（ADR-5）。因此**核心回归测试围绕"同输入→同输出"展开**，而非概率断言：

- 同 `(seed, floor)` → 地牢布局哈希一致（ADR-1 / R1）。
- 同 `(seed, 初始状态, 输入序列)` → 战斗 tick 序列一致（ADR-3）。
- 存档重建与事件日志无错位（ADR-1）。

## 1. 目录布局

```
tests/
  README.md                      # 本文件
  unit/                          # GUT 扫描目录（仅此目录）
    test_smoke.gd                # 冒烟：验证 GUT harness 可达
    test_rng_service.gd          # ADR-5：种子确定性（Epic A1）
    test_dungeon_gen.gd          # ADR-1/R1：同 seed 同布局（Epic B3）
    test_combat.gd               # DamageCalc/Clock/Input/Joystick/Death/C1/CombatDirector（Epic C）
    test_pouch_vein.gd           # C1/ENG-2/DAG/activate/Save 重建/Bestiary（Epic D）
    test_ui.gd                   # 四主屏 / Tab 路由 / 可访问性 / 技能热区（Epic F 逻辑层）
    test_frame_budget.gd        # 记账级帧预算断言【非设备帧时间】（G4）
    test_pc_platform.gd         # ADR-6 横屏布局真源 / 键鼠适配 / ADR-2 帧末结算（Wave 3）
    test_render_layer.gd        # Wave 3b 格映射 / 屏外剔除 / TileMapLayer / MultiMesh / 粒子 / 资产纪律
  templates/
    rng_service_test.gd          # 模板（不被 GUT 扫描，供参考填充）
```

> GUT 9.x 默认只收集 `test_*.gd` 前缀。2026-11-05 实跑已将原 `*_test.gd` 全部重命名；
> `tests/templates/` 不放入扫描路径，避免引用未落地模块导致解析失败。

## 2. GUT 安装与运行

1. **CI 安装**：`.github/workflows/test.yml` 从 GUT tag 源码归档
   `https://github.com/bitwes/Gut/archive/refs/tags/v9.3.0.zip` 下载，解压到
   `$env:RUNNER_TEMP`（**项目外**）后，仅把 `Gut-9.3.0/addons/gut` 复制进 `addons/gut`。
   GUT 9.3.0 的 Release 无独立 zip 资产（`gut_9.3.0.zip` 为 404），tag 带 `v` 前缀。
2. **本地安装**：Godot 4.3 + GUT 9.3.0 置于 `addons/gut`（不入库，见 `.gitignore`）。
3. **生成全局类缓存（headless `-s` 必需，不可省略）**：
   ```
   godot --headless --path . -s res://tools/gen_global_class_cache.gd
   ```
   Godot 4.3 的 headless `-s` 模式**不扫描注册 `class_name` 全局类**，只读取
   `.godot/global_script_class_cache.cfg`；缺缓存时 GUT 报
   `Identifier "GutUtils" not declared` 且进程挂住不退出。缓存正确格式为默认
   section（空 section 名）下的单个 `list` 数组，由上述脚本幂等生成。
4. **运行测试**：
   ```
   godot --headless --path . -s res://addons/gut/gut_cmdln.gd \
     -gdir=res://tests/unit/ -gexit
   ```
   `-gexit` 使全绿退出码 0、任一失败非 0（CI 据此判红）；Windows 用
   `Godot_v4.3-stable_win64_console.exe` 保证 stdout/stderr 完整进入日志。
5. **本地一键**：`bash tools/ci/run_gut_tests.sh`（需 `godot` 4.3 在 PATH 或用
   `GODOT=/abs/path/to/godot` 指定，且 `addons/gut` 已安装）。该脚本镜像 CI，
   会先生成全局类缓存再跑 GUT。

> **2026-11-05 远端 CI 实测教训**：GUT 归档的任何副本都**不得**落在项目根 `res://`
> 扫描范围内。否则缓存生成器会把副本中的 `class_name` 一并注册（45 类 vs 本地 40 类），
> 加载真正的 `res://addons/gut/gut.gd` 时触发
> `Class "GutMain" hides a global script class`，GUT 主类加载失败 → `run_tests`
> 等不到完成信号 → 进程挂起直到超时。修法：项目外解压 + 生成器跳过临时目录并对同名
> `class_name` 去重（`res://addons/` 优先）。详见 `docs/phase4/epic-breakdown.md §12`。

## 3. 确定性测试清单（与模块/ADR 映射）

| 测试文件 | 目标模块 | 断言要点 | ADR/原型 |
|---|---|---|---|
| `test_smoke.gd` | GUT harness | 冒烟：harness 可达 | — |
| `test_rng_service.gd` | RNGService | 同 seed 序列逐字节一致；异 seed 分叉；`floor_rng` 确定性；调用时序无关 | ADR-5 |
| `test_dungeon_gen.gd` | DungeonGen | 同 (seed,floor,tier) JSON 逐字节一致；异 floor 分叉；非法 floor 切保底 | ADR-1 / R1 |
| `test_combat.gd` | Combat/Input/AI | DamageCalc 确定性/钳制/Variance/Crit、Clock 10Hz 稳态/追帧钳 3/自适应 5Hz、InputQueue 去重+0.5s 钳、Joystick 8 向+死区、Death 30%、StatBlock C1、CombatDirector 确定性+无敌人 idle | ADR-3 / C1 |
| `test_pouch_vein.gd` | Pouch/SpiritVein/Save | C1 公式、负 atk/def 钳 0、D1 增量 API、ENG-2 +1 堆叠、满栏拒绝不静默丢、`{slug:count}` 往返、RuneEntry 格式、PartyManager slots、DAG 无环正反例、activate/ember 扣减、`ΣVeinAdd` 聚合、RunSnapshot 注入、Bestiary 解锁+联动、存档重建一致 | C1 / ENG-2 / ADR-1 |
| `test_ui.gd` | UI（Epic F 逻辑层） | Tab 布局与命中区、路由派发、战斗中 Tab 禁用、可访问性钳制与双编码、+1 堆叠角标、灵脉节点状态分类、战斗技能热区 | UX 规格 / 可访问性 Basic |
| `test_frame_budget.gd` | 记账级帧预算（G4） | `_adapt` 修复后 30fps 稳态≈200 tick / 跨帧率一致 / 不降频；实测超预算才降频、恢复；无插桩数据保守策略；`report_frame_cost` 注入链路；ADR-2 tick 内队列结算顺序；**非设备帧时间** | ADR-2 / ADR-3 / G4 |
| `test_render_layer.gd` | 渲染层（Wave 3b） | 格映射确定性、L 形走廊、屏外剔除、相机锚点、同屏实体 ≤12、`TileMapLayer.set_cell` 真实写入、`MultiMesh` 实例数、粒子低档降密度、`DEBUG_PLACEHOLDER` 资产纪律标记；**非性能耗时** | ADR-4 / R1 / R3 |
| `test_pc_platform.gd` | PC 平台契约（Wave 3） | 1280×720 布局真源与整数倍缩放、所有 UI 热区落在横屏内、Tab 条带包容、鼠标/拖拽/键盘输出同构 `{"position","touch_id":0}`、右键/抬起/echo/未绑定键不臆造事件、适配层不破坏 ADR-2 帧末结算 | ADR-6 / ADR-2 |

> 设备级帧预算仍标【需实测】，**未回填、不臆造**；ADR-6 后判据改由 PC 窗口 / 全屏基线采集（Wave 4），
> 原移动端 runbook 已归档至 `docs/qa/archive/r1r3-device-test-plan.md`（仅历史方法学参考）。
> `test_frame_budget.gd` 为【记账级 · 非设备帧时间】断言，不得换算成 ms 预算结论。

## 4. 与 CI 的衔接

- **lint 线**：`.github/workflows/lint.yml` → `tools/ci/lint_no_global_random.py --root .`（ADR-5 全局随机禁令），job 超时 10 分钟。
- **test 线**：`.github/workflows/test.yml` → 安装 Godot 4.3 + GUT 9.3.0 → 生成全局类缓存 → 跑 GUT headless，job 超时 15 分钟。
- **runner / 触发**：两条线均 `windows-latest`；test 线 push `main`/`master` + PR 触发，lint 线 push + PR 触发。
- 两条线均绿方可合并（见 ADR-5 完成判据）。

## 5. 冒烟测试示例（`tests/unit/test_smoke.gd`）

```gdscript
extends GutTest

# Phase 4 脚手架冒烟测试：仅用于验证 GUT harness 在目标机可达。
# 不依赖任何尚未创建的模块，确保 CI 在模块落地前即可跑通。
func test_harness_runs():
	assert_eq(1, 1, "GUT harness reachable")
```

## 6. 实跑验证记录（2026-11-05）

| 环境 | 结果 | 证据 |
|---|---|---|
| 本机 Windows（干净 checkout 等价验证） | **6 scripts / 50 tests / 50 passing / 11452 asserts / `GUT_EXIT=0`**；ADR-5 lint 扫描 39 个 `.gd`、0 违规 | 本地 headless 日志；`tools/ci/run_gut_tests.sh` 等价流程 |
| 本机 Windows（G4 + 采集包复跑） | **7 scripts / 54 tests / 54 passing / 11468 asserts / `GUT_EXIT=0`**；ADR-5 lint 41 个 `.gd`、0 违规 | `test_frame_budget.gd` 4 例 +16 断言；全局类缓存 40 类不变 |
| GitHub Actions `windows-latest`（sha `0a19159`） | test run `42045291457` **success**、Lint run `42045291552` **success**；缓存步骤 `wrote 40 global classes`；`Run GUT headless` 约 2 秒完成，输出同为 6/50/50/11452 | 远端 run/job 结论与归档日志 |
| 首轮无超时悬挂 run `42038019907`（sha `9c33a9d`） | 已通过 Actions API 取消：`completed / cancelled` | HTTP 202 + 复查结论 |
| 本机 Windows（Wave 3 复跑） | **8 scripts / 60 tests / 60 passing / 11511 asserts / `GUT_EXIT=0`**；PC 主场景 headless 自检 `WAVE3_SELFTEST_OK`；全局类缓存仍 40 类 | `test_pc_platform.gd` 6 例 +43 断言；`godot --headless --path . res://src/main.tscn -- --wave3-selftest` |
| 本机 Windows（Wave 3b） | **9 scripts / 69 tests / 69 passing / 11572 asserts / `GUT_EXIT=0`**；ADR-5 lint 49 个 `.gd` 0 违规；主场景自检 `tile_cells=145 visible_entities=6 particles_amount=24` | `test_render_layer.gd` 9 例；`FloorGrid` / `FloorTilemap` / `EntityLayer` / `BattleParticles` |
| 本机 Windows（Wave 4 导出） | Game / Probe 双预设 `--export-debug` 均 `EXIT=0`；导出的 exe 启动 `RUN_EXIT=0` / `WAVE3_SELFTEST_OK`；Probe exe `rows=10 err=0` | HTTP Range 只取 59MB Windows 模板；`application/modify_resources=false` 规避 rcedit；`exclude_filter=addons/gut/*` 使 `.pck` 3.7MB→约 0.18–0.19MB（多次实测 185088–192928 bytes，随打包内容浮动） |
| 本机 Windows（`_adapt` 修复后） | **9 scripts / 72 tests / 72 passing / 11582 asserts / `GUT_EXIT=0`**；30fps 600 帧 **104→200 tick**、`is_slow()=false` | `test_frame_budget.gd` 偏差探测还原为正确断言 + `test_combat.gd` 新增帧间隔长不降频用例 |
| 本机 Windows（PC 基线插桩 v1.2） | 非 headless 窗口模式实跑 `FRAME_CAPTURE\|samples=60`，GPU 样本全部非零、`frame_wall_ms≈16.6667`（60fps 档）；headless 自检 `rows=10 err=0 / raw_rows=470`；`verify_probe_evidence.py` → `RESULT: PASS` | `RenderingServer.viewport_get_measured_render_time_gpu` 反射核实可用；逐样本长表 470 / 650 行可复算 mean / p95；帧时间标 `DEBUG_PLACEHOLDER_FRAME_NOT_A_BASELINE`，不进 19 列 verdict；试跑 `round_id=instrument_smoke`、`build_sha=SMOKE_NOT_A_BASELINE`，明确非正式基线 |

- 残留**非致命**告警：GUT 自带字体未导入（headless 无编辑器导入）引起的 fontdata /
  ObjectDB leak 提示，本地与 CI 同样存在，不影响测试结果。
- 远端曾出现的 GUT 挂起已定位并修复（见 §2 教训）；字体错误与渲染驱动均非根因。

## 7. 开放项（不臆造、不勾选未验证项）

1. **G4 PC 基线（ADR-6）**：Wave 4 已打通导出 / 启动 / 采集链路；v1.2 补齐逐样本原始证据、GPU / CPU / 墙钟帧时间插桩与窗口 / 全屏 × 60 / 30fps 分轮编排，并核实**本机非 headless 窗口可用**（Vulkan Forward+ / NVIDIA MX450，1920×1080；v1.1「本机无显示器」判定已更正）。仍待：① 按 `docs/qa/evidence/_template/README.md §7` 跑完四轮正式采集并补齐 `MANUAL_REQUIRED` 字段；② ADR-4 E1 真实像素资产到位后重测 5 项渲染 / 粒子指标。单手可达性热力图与 iOS 后台强杀判据已废止，改键盘可达 / PC 进程强杀双保险。**R1 / R3 仍为 CONCERNS**，插桩跑通不自动翻转。
2. **Epic E**：E1 真实 AI 原图 → pipeline → manifest 登记；Godot `.import`/Import Preset 固化；`palette_validator` headless CI 与 R5/R6 实跑。
3. **Epic F / Wave 3b 资产层**：`TileMapLayer` / `MultiMesh` + 屏外剔除 / `CPUParticles2D` 技术层已落地并实跑；但纹理均为 `DEBUG_PLACEHOLDER`，**ADR-4 E1 真实像素原图仍未产出**（需 AI 原图 → pipeline → manifest）。5 项渲染 / 粒子 / 合计占帧比的阻塞理由由「场景未落地」改为 `BLOCKED-BY-ASSET`，数值栏保持为空。
4. **集成层**：InputArbiter 接入 PC 键鼠事件（Wave 3 适配层）、`enemy_ai.gd` / `spirit_ai.gd` 独立文件、DungeonGen↔Save 重建联测。
5. **Linux runner**：按主理人决策暂缓恢复。

---

*本脚手架随 Epic A–G 模块落地填充；Epic G 已完成 GUT 接入 + 本地与远端 Windows CI 实跑闭环（2026-11-05）。各 Epic 状态与 Phase 4 出口判据见 `docs/phase4/epic-breakdown.md §12`、`docs/phase4/plan.md §4`。*
