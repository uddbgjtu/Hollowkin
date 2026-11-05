# 测试脚手架 / Test Scaffolding

> **文档类型**：测试策略 + GUT 接入 + 确定性测试清单（Phase 4 脚手架，Lean）
> **归属**：engineering-lead 起草，主理人签发
> **引用**：`docs/architecture/adr-control-checklist.md`（ADR-1/2/3/5）、`tools/ci/lint_no_global_random.py`、`docs/qa/r1r3-device-test-plan.md`
> **版本**：v1.1 · 随 Epic G 提交（2026-11-05 · 主理人静态 API 对账 + CI 硬化）。
> **环境注**：本沙箱无 Godot，以下为可落地脚手架与执行说明；GUT 实际跑通待目标机安装 Godot 4.3。

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
    smoke_test.gd                # 冒烟：验证 GUT  harness 可达
    rng_service_test.gd          # ADR-5：种子确定性（Epic A1）
    dungeon_gen_test.gd          # ADR-1/R1：同 seed 同布局（Epic B3）
    combat_test.gd               # DamageCalc/Clock/Input/Joystick/Death/C1/CombatDirector（Epic C）
    pouch_vein_test.gd           # C1/ENG-2/DAG/activate/Save 重建/Bestiary（Epic D）
  templates/
    rng_service_test.gd          # 模板（不被 GUT 扫描，供参考填充）
```

> `tests/templates/` 不放入 GUT 扫描路径，避免引用尚未创建的类导致解析失败。

## 2. GUT 安装与运行

1. 在 Godot 4.3 编辑器 → AssetLib 安装 **GUT**（Godot Unit Test）。
2. 项目设置 → 插件启用 GUT。
3. GUT 配置：测试目录指向 `res://tests/unit/`，勾选"在运行时扫描"。
4. 命令行（CI / 本地无头）：
   ```
   godot --headless --path . --quit res://addons/gut/gut_cmdln.gd \
     -gdir=res://tests/unit/ -gexit
   ```
5. 预期：smoke_test 通过即 harness 正常；其余测试随模块落地逐步启用。

## 3. 确定性测试清单（与模块/ADR 映射）

| 测试文件 | 目标模块 | 断言要点 | ADR/原型 |
|---|---|---|---|
| `rng_service_test.gd` | RNGService | 同 seed 序列逐字节一致；异 seed 分叉；`floor_rng` 确定性；调用时序无关 | ADR-5 |
| `dungeon_gen_test.gd` | DungeonGen | 同 (seed,floor,tier) JSON 逐字节一致；异 floor 分叉；非法 floor 切保底 | ADR-1 / R1 |
| `combat_test.gd` | Combat/Input/AI | DamageCalc 确定性/钳制/Variance/Crit、Clock 10Hz 稳态/追帧钳 3/自适应 5Hz、InputQueue 去重+0.5s 钳、Joystick 8 向+死区、Death 30%、StatBlock C1、CombatDirector 确定性+无敌人 idle | ADR-3 / C1 |
| `pouch_vein_test.gd` | Pouch/SpiritVein/Save | C1 公式、负 atk/def 钳 0、D1 增量 API、ENG-2 +1 堆叠、满栏拒绝不静默丢、`{slug:count}` 往返、RuneEntry 格式、PartyManager slots、DAG 无环正反例、activate/ember 扣减、`ΣVeinAdd` 聚合、RunSnapshot 注入、Bestiary 解锁+联动、存档重建一致 | C1 / ENG-2 / ADR-1 |

> 设备级帧预算（60/30fps 实测）仍标【需真机实测】，沙箱不臆造；见 `docs/qa/r1r3-device-test-plan.md`。

## 4. 与 CI 的衔接

- **lint 线**：`tools/ci/lint_no_global_random.py --root .`（已有 `.github/workflows/lint.yml`）。
- **test 线**：`.github/workflows/test.yml` 安装 Godot 4.3 → 跑 GUT headless。
- 两条线均绿方可合并（见 ADR-5 完成判据）。

## 5. 冒烟测试示例（`tests/unit/smoke_test.gd`）

```gdscript
extends GutTest

func test_harness_runs():
    assert_eq(1, 1, "GUT harness reachable")
```

## 6. CI 与本地运行（Epic G 接入）

- **CI**：`.github/workflows/test.yml`（push 到 main / PR 触发）安装 Godot 4.3 + GUT 9.x，以
  `godot --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit/ -gexit`
  无头实跑全部 GUT 用例；`-gexit` 使全绿退出码 0、任一失败非 0（CI 据此判红）。
  全局随机 lint 由 `.github/workflows/lint.yml`（ADR-5）单独覆盖。
- **本地**：`bash tools/ci/run_gut_tests.sh`（需 PATH 含 `godot` 4.3，且已通过编辑器 AssetLib 安装 `addons/gut`）。

> **Epic G 状态（2026-11-05）**：5 个 GUT 测试文件已全部按 GUT 9.x 规范书写，且主理人对其中引用的
> 17 个生产类的全部方法/属性/签名做了**静态 API 对账（逐一读真实源码）**，100% 吻合，可高置信度预期
> 在 Godot 环境一次跑通。受本沙箱无 Godot 限制，**实际编译与运行时执行尚未进行**——属环境阻断，非测试缺陷。
> 待目标机/CI 安装 Godot 4.3 后，上述流水线即会真实执行并反馈绿/红。

---

*本脚手架随 Epic A–G 模块落地填充，Epic G 完成 CI 接入与静态对账（2026-11-05 提交）。*
