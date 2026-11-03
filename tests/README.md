# 测试脚手架 / Test Scaffolding

> **文档类型**：测试策略 + GUT 接入 + 确定性测试清单（Phase 4 脚手架，Lean）
> **归属**：engineering-lead 起草，主理人签发
> **引用**：`docs/architecture/adr-control-checklist.md`（ADR-1/2/3/5）、`tools/ci/lint_no_global_random.py`、`docs/qa/r1r3-device-test-plan.md`
> **版本**：v1.0 · 未 git commit。
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
    rng_service_test.gd          # ADR-5：种子确定性（Epic A 落地后启用）
    dungeon_gen_test.gd          # ADR-1/R1：同 seed 同布局
    save_rebuild_test.gd         # ADR-1：层间落盘重建一致
    combat_tick_test.gd          # ADR-3：tick 预算与追帧上限
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
| `rng_service_test.gd` | RNGService | 同 seed 产出序列逐字节一致；`new_floor_rng()` 独立 | ADR-5 |
| `dungeon_gen_test.gd` | DungeonGen | 同 (seed,floor) 布局哈希一致 | ADR-1 / R1 |
| `save_rebuild_test.gd` | Save | 落盘→重建与事件日志对齐 | ADR-1 |
| `combat_tick_test.gd` | Combat/SpiritAI | 60fps→99tick/10s、30fps→200tick/20s、MAX_CATCHUP=3 断言 | ADR-3 / R3 |

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

---

*本脚手架为 Phase 4 交付；实际测试逻辑随 Epic A–G 模块落地填充。未 git commit。*
